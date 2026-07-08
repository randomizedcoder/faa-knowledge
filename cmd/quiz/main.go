package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	dbsql "github.com/das/faa-knowledge/database"
	"github.com/das/faa-knowledge/internal/db"
	"github.com/das/faa-knowledge/internal/extractor"
	"github.com/das/faa-knowledge/internal/importer"
	"github.com/das/faa-knowledge/internal/llm"
	"github.com/das/faa-knowledge/internal/pipeline"
	"github.com/das/faa-knowledge/internal/quiz"
	"github.com/das/faa-knowledge/internal/validator"
)

// envOr returns the value of environment variable key, or def if unset/empty.
func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// envOrBool returns true if the environment variable key is set to a truthy
// value (1, true, yes, on), false if set to a falsy value, or def if unset.
func envOrBool(key string, def bool) bool {
	switch strings.ToLower(os.Getenv(key)) {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	default:
		return def
	}
}

// newLLMClient builds an LLM client with the shared model/thinking config. When
// think is set (GLM), it enables reasoning mode, allows a long timeout, and
// raises max_tokens to leave room for the chain-of-thought plus JSON answer.
func newLLMClient(url, model string, think bool, temp float64, timeout time.Duration) *llm.Client {
	c := llm.NewClient(url).WithModel(model).WithTemperature(temp)
	if think {
		if timeout < 600*time.Second {
			timeout = 600 * time.Second
		}
		c = c.WithThinking(true).WithMaxTokens(16000)
	}
	return c.WithTimeout(timeout)
}

func main() {
	initDB := flag.Bool("init", false, "Initialize database with schema and seed data")
	importFile := flag.String("import", "", "Import questions from a JSON file")
	count := flag.Int("count", 0, "Number of questions (0 = all matching)")
	category := flag.String("category", "", "Filter by category (written_exam, checkride_oral, general_knowledge)")
	source := flag.String("source", "", "Filter by source code (PHAK, AFH)")
	chapter := flag.Int("chapter", 0, "Filter by chapter number")
	difficulty := flag.Int("difficulty", 0, "Filter by difficulty (1-3)")
	dbPath := flag.String("db", db.DefaultDBPath, "Database file path")
	validate := flag.Bool("validate", false, "Validate questions using a local LLM")
	fix := flag.Bool("fix", false, "Apply LLM-suggested fixes to JSON files (requires --validate)")
	llmURL := flag.String("llm-url", envOr("FAA_LLM_URL", "http://l2:8095"), "Large LLM API base URL (MI50 on l2)")
	llmModel := flag.String("llm-model", envOr("FAA_LLM_MODEL", "local"), "Model name sent to the LLM server (e.g. /model for GLM)")
	think := flag.Bool("think", envOrBool("FAA_LLM_THINK", false), "Enable the model's reasoning mode (chat_template_kwargs.enable_thinking) for all LLM calls")
	genCap := flag.Int("gen-cap", 0, "Max questions to generate per chapter (0 = one per fact); selects hardest, distinct facts")
	file := flag.String("file", "", "Validate a specific JSON file (requires --validate)")
	addRefs := flag.Bool("add-refs", false, "Extract references from PDFs and add to JSON files")
	pdfDir := flag.String("pdf-dir", "pdfs", "Directory containing phak.pdf and afh.pdf")
	extractText := flag.Bool("extract-text", false, "Stage 1: Extract text from PDFs")
	chunkText := flag.Bool("chunk-text", false, "Stage 2: Chunk text into paragraphs")
	mine := flag.Bool("mine", false, "Stage 3: Mine knowledge items from paragraphs")
	generate := flag.Bool("generate", false, "Stage 4: Generate questions from knowledge items")
	mergeFlag := flag.Bool("merge", false, "Merge question runs with consensus filtering")
	crossCheck := flag.Bool("cross-check", false, "Stage 5: Cross-check questions with small LLM")
	smallLLMURL := flag.String("small-llm-url", envOr("FAA_SMALL_LLM_URL", "http://l2:8096"), "Small LLM API base URL for cross-check (W5700 on l2)")
	runID := flag.Int("run-id", 0, "Run ID for pipeline stages (required for --mine, --generate)")
	runs := flag.Int("runs", 10, "Number of runs for --merge")
	textDir := flag.String("text-dir", "pdfs_text", "Directory containing extracted text/paragraphs")
	pipelineFlag := flag.Bool("pipeline", false, "Run full pipeline: extract, chunk, mine, generate, merge, cross-check, validate")
	startRun := flag.Int("start-run", 1, "Start from this run number (requires --pipeline)")
	skipExtract := flag.Bool("skip-extract", false, "Skip text extraction stage (requires --pipeline)")
	skipChunk := flag.Bool("skip-chunk", false, "Skip text chunking stage (requires --pipeline)")
	chapters := flag.String("chapters", "", "Filter chapters (e.g. phak:04,afh:03)")
	force := flag.Bool("force", false, "Force regeneration of existing output files")
	dryRun := flag.Bool("dry-run", false, "Show what would be done without executing")

	flag.Parse()

	if *pipelineFlag {
		filter := pipeline.ParseChapterFilter(*chapters)
		opts := pipeline.PipelineOpts{Force: *force, DryRun: *dryRun}
		runPipeline(*pdfDir, *textDir, *llmURL, *smallLLMURL, *llmModel, *think, *genCap, *runs, *startRun, *skipExtract, *skipChunk, filter, opts)
		return
	}

	if *extractText {
		if err := pipeline.ExtractText(*pdfDir, "pdfs_text"); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		return
	}

	if *chunkText {
		if err := pipeline.ChunkText("pdfs_text"); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		return
	}

	if *mergeFlag {
		report, err := pipeline.Merge(*runs, "database/questions")
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		pipeline.PrintMergeReport(report)
		return
	}

	if *crossCheck {
		ctx := context.Background()
		client := newLLMClient(*smallLLMURL, *llmModel, *think, 0.1, 120*time.Second)
		if err := pipeline.CrossCheck(ctx, client, "database/questions"); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		return
	}

	if *mine || *generate {
		if *runID <= 0 {
			fmt.Fprintf(os.Stderr, "Error: --run-id is required for --mine/--generate\n")
			os.Exit(1)
		}
		ctx := context.Background()
		client := newLLMClient(*llmURL, *llmModel, *think, 0.7, 180*time.Second)
		filter := pipeline.ParseChapterFilter(*chapters)
		opts := pipeline.PipelineOpts{Force: *force, DryRun: *dryRun}
		if *mine {
			if err := pipeline.Mine(ctx, client, *textDir, *runID, filter, opts); err != nil {
				fmt.Fprintf(os.Stderr, "Error mining: %v\n", err)
				os.Exit(1)
			}
		}
		if *generate {
			if *smallLLMURL != "" {
				smallClient := newLLMClient(*smallLLMURL, *llmModel, *think, 0.1, 120*time.Second)
				if err := pipeline.GenerateAndCheck(ctx, client, smallClient, *runID, *genCap, filter, opts); err != nil {
					fmt.Fprintf(os.Stderr, "Error generating+checking: %v\n", err)
					os.Exit(1)
				}
			} else {
				if err := pipeline.Generate(ctx, client, *runID, *genCap); err != nil {
					fmt.Fprintf(os.Stderr, "Error generating: %v\n", err)
					os.Exit(1)
				}
			}
		}
		return
	}

	if *addRefs {
		doAddRefs(*llmURL, *llmModel, *think, *pdfDir, *file)
		return
	}

	if *validate {
		doValidate(*llmURL, *llmModel, *think, *file, *fix)
		return
	}

	if *initDB {
		doInit(*dbPath)
		return
	}

	if *importFile != "" {
		doImport(*dbPath, *importFile)
		return
	}

	// Default: run quiz
	doQuiz(*dbPath, db.Filters{
		Category:   *category,
		SourceCode: *source,
		Chapter:    *chapter,
		Difficulty: *difficulty,
		Limit:      *count,
	})
}

func doInit(dbPath string) {
	conn, err := db.Open(dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close()

	schema, err := dbsql.SQL.ReadFile("schema.sql")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading schema: %v\n", err)
		os.Exit(1)
	}

	seed, err := dbsql.SQL.ReadFile("seed.sql")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading seed: %v\n", err)
		os.Exit(1)
	}

	if err := db.Migrate(conn, string(schema), string(seed)); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	// Import all embedded question files
	entries, err := dbsql.Questions.ReadDir("questions")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading embedded questions: %v\n", err)
		os.Exit(1)
	}

	total := 0
	for _, e := range entries {
		data, err := dbsql.Questions.ReadFile("questions/" + e.Name())
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading %s: %v\n", e.Name(), err)
			os.Exit(1)
		}
		n, err := importer.ImportData(conn, data, e.Name())
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error importing %s: %v\n", e.Name(), err)
			os.Exit(1)
		}
		total += n
	}

	fmt.Printf("Database initialized with %d questions.\n", total)
}

func doImport(dbPath, path string) {
	database, err := db.Open(dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	defer database.Close()

	n, err := importer.ImportFile(database, path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Imported %d questions from %s\n", n, path)
}

func doValidate(llmURL, llmModel string, think bool, filePath string, fix bool) {
	client := validator.NewLLMClientWith(llmURL, llmModel, think)
	ctx := context.Background()

	var results map[string][]validator.QuestionResult

	if filePath != "" {
		fmt.Printf("Validating %s...\n", filePath)
		qrs, err := validator.ValidateFile(ctx, client, filePath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		results = map[string][]validator.QuestionResult{filePath: qrs}
	} else {
		fmt.Println("Validating all embedded questions...")
		var err error
		results, err = validator.ValidateAll(ctx, client, dbsql.Questions)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
	}

	validator.PrintReport(results)

	if fix {
		fmt.Println("\nApplying fixes...")
		fixPath := filePath
		if filePath == "" {
			fixPath = "database/questions"
		}
		if err := validator.ApplyFixes(results, fixPath); err != nil {
			fmt.Fprintf(os.Stderr, "Error applying fixes: %v\n", err)
			os.Exit(1)
		}
	}
}

func doAddRefs(llmURL, llmModel string, think bool, pdfDir, filePath string) {
	ctx := context.Background()
	client := newLLMClient(llmURL, llmModel, think, 0.1, 180*time.Second)

	if filePath != "" {
		fmt.Printf("Adding references to %s...\n", filePath)
		if err := extractor.AddRefsToFile(ctx, client, pdfDir, filePath); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		return
	}

	// Process all question files
	entries, err := filepath.Glob("database/questions/*.json")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	for _, path := range entries {
		fmt.Printf("\n%s\n", path)
		if err := extractor.AddRefsToFile(ctx, client, pdfDir, path); err != nil {
			fmt.Fprintf(os.Stderr, "Error processing %s: %v\n", path, err)
		}
	}
}

func runPipeline(pdfDir, textDir, llmURL, smallLLMURL, llmModel string, think bool, genCap, runs, startRun int, skipExtract, skipChunk bool, filter pipeline.ChapterFilter, opts pipeline.PipelineOpts) {
	ctx := context.Background()

	// Stage 1: Extract text from PDFs
	if !skipExtract {
		fmt.Println("=== Stage 1: Extract text ===")
		if err := pipeline.ExtractText(pdfDir, textDir); err != nil {
			fmt.Fprintf(os.Stderr, "Error extracting text: %v\n", err)
			os.Exit(1)
		}
	} else {
		fmt.Println("=== Stage 1: Extract text [skipped] ===")
	}

	// Stage 2: Chunk text into paragraphs
	if !skipChunk {
		fmt.Println("=== Stage 2: Chunk text ===")
		if err := pipeline.ChunkText(textDir); err != nil {
			fmt.Fprintf(os.Stderr, "Error chunking text: %v\n", err)
			os.Exit(1)
		}
	} else {
		fmt.Println("=== Stage 2: Chunk text [skipped] ===")
	}

	// Stage 3+4: Mine knowledge + generate questions (per run)
	largeClient := newLLMClient(llmURL, llmModel, think, 0.7, 180*time.Second)
	smallClient := newLLMClient(smallLLMURL, llmModel, think, 0.1, 120*time.Second)

	for i := startRun; i <= runs; i++ {
		fmt.Printf("=== Run %d/%d: Mine knowledge ===\n", i, runs)
		if err := pipeline.Mine(ctx, largeClient, textDir, i, filter, opts); err != nil {
			fmt.Fprintf(os.Stderr, "Error mining run %d: %v\n", i, err)
			os.Exit(1)
		}

		fmt.Printf("=== Run %d/%d: Generate + cross-check questions ===\n", i, runs)
		if err := pipeline.GenerateAndCheck(ctx, largeClient, smallClient, i, genCap, filter, opts); err != nil {
			fmt.Fprintf(os.Stderr, "Error generating run %d: %v\n", i, err)
			os.Exit(1)
		}
	}

	// Stages 5-7 make real LLM/merge passes over database/questions, so they
	// must not run under --dry-run (which only previews mine/generate).
	if opts.DryRun {
		fmt.Println("=== Stages 5-7 (merge, cross-check, validate) [dry-run: skipped] ===")
		fmt.Println("\n=== Dry run complete ===")
		return
	}

	// Stage 5: Merge with consensus filtering
	fmt.Println("=== Stage 5: Merge runs ===")
	report, err := pipeline.Merge(runs, "database/questions")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error merging: %v\n", err)
		os.Exit(1)
	}
	pipeline.PrintMergeReport(report)

	// Stage 6: Cross-check with small LLM
	fmt.Println("=== Stage 6: Cross-check ===")
	if err := pipeline.CrossCheck(ctx, smallClient, "database/questions"); err != nil {
		fmt.Fprintf(os.Stderr, "Error cross-checking: %v\n", err)
		os.Exit(1)
	}

	// Stage 7: Validate with large LLM
	fmt.Println("=== Stage 7: Validate ===")
	doValidate(llmURL, llmModel, think, "", false)

	fmt.Println("\n=== Pipeline complete ===")
}

func doQuiz(dbPath string, f db.Filters) {
	database, err := db.Open(dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	defer database.Close()

	session, err := quiz.NewSession(database, f)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	session.Run()
}
