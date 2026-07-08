package pipeline

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/das/faa-knowledge/internal/importer"
	"github.com/das/faa-knowledge/internal/llm"
)

// generateResult carries a generated question from the generator goroutine to the checker.
type generateResult struct {
	question importer.SeedQuestion
	source   string
	chapter  int
	index    int
	total    int
}

// GenerateAndCheck runs generation on largeClient and cross-checking on
// smallClient concurrently, using a channel pipeline.
func GenerateAndCheck(ctx context.Context, largeClient, smallClient *llm.Client, runID int, filter ChapterFilter, opts PipelineOpts) error {
	knowledgeDir := filepath.Join("runs", fmt.Sprintf("run_%02d", runID), "knowledge")
	entries, err := filepath.Glob(filepath.Join(knowledgeDir, "*.json"))
	if err != nil {
		return fmt.Errorf("glob %s: %w", knowledgeDir, err)
	}

	// Load all knowledge files upfront so we know totals.
	type chapterWork struct {
		kf   *KnowledgeFile
		path string
	}
	var chapters []chapterWork
	totalItems := 0
	for _, path := range entries {
		data, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("read %s: %w", path, err)
		}
		var kf KnowledgeFile
		if err := json.Unmarshal(data, &kf); err != nil {
			return fmt.Errorf("parse %s: %w", path, err)
		}
		if !filter.Match(kf.Source, kf.Chapter) {
			continue
		}

		outPath := filepath.Join("runs", fmt.Sprintf("run_%02d", runID), "questions",
			fmt.Sprintf("%s_ch%02d.json", strings.ToLower(kf.Source), kf.Chapter))
		if !opts.Force {
			if hasQuestions(outPath) {
				fmt.Printf("  [skip] %s (exists, use --force to regenerate)\n", outPath)
				continue
			}
		}
		if opts.DryRun {
			fmt.Printf("  [dry-run] would generate from %s ch%02d (%d items)\n", kf.Source, kf.Chapter, len(kf.Items))
			continue
		}

		chapters = append(chapters, chapterWork{kf: &kf, path: path})
		totalItems += len(kf.Items)
	}

	if totalItems == 0 {
		fmt.Println("No knowledge items to process.")
		return nil
	}

	fmt.Printf("Parallel pipeline: %d items across %d chapters\n", totalItems, len(chapters))

	ch := make(chan generateResult, 4)

	var wg sync.WaitGroup

	// --- Generator goroutine (largeClient / MI50 on l2:8095) ---
	var genErr error
	wg.Add(1)
	go func() {
		defer wg.Done()
		defer close(ch)

		globalIdx := 0
		for _, cw := range chapters {
			fmt.Printf("Generating from %s ch%02d (%d items)...\n", cw.kf.Source, cw.kf.Chapter, len(cw.kf.Items))
			for _, ki := range cw.kf.Items {
				globalIdx++
				sq, err := GenerateFromItem(ctx, largeClient, ki, cw.kf.Source, cw.kf.Chapter)
				if err != nil {
					fmt.Printf("  [gen %d/%d] ERROR: %v\n", globalIdx, totalItems, err)
					continue
				}
				fmt.Printf("  [gen %d/%d] %s\n", globalIdx, totalItems, truncateStr(sq.Question, 60))

				select {
				case ch <- generateResult{
					question: *sq,
					source:   cw.kf.Source,
					chapter:  cw.kf.Chapter,
					index:    globalIdx,
					total:    totalItems,
				}:
				case <-ctx.Done():
					genErr = ctx.Err()
					return
				}
			}
		}
	}()

	// --- Checker goroutine (smallClient / W5700 on l2:8096) ---
	// Collects results grouped by source_chapter key.
	type chapterQuestions struct {
		source  string
		chapter int
		passed  []importer.SeedQuestion
	}
	chapterMap := make(map[string]*chapterQuestions)
	var allCheckResults []CrossCheckResult
	passCount, failCount, errCount := 0, 0, 0
	checkIdx := 0

	var checkErr error
	wg.Add(1)
	go func() {
		defer wg.Done()

		for gr := range ch {
			checkIdx++
			result, err := CrossCheckOne(ctx, smallClient, gr.question)
			if err != nil {
				fmt.Printf("  [chk %d/%d] \033[33mERROR\033[0m %v\n", checkIdx, gr.total, err)
				errCount++
				allCheckResults = append(allCheckResults, CrossCheckResult{
					Question:  gr.question.Question,
					Verdict:   "error",
					Issues:    []string{err.Error()},
					Reasoning: "LLM error",
				})
				continue
			}

			allCheckResults = append(allCheckResults, *result)

			if result.Verdict == "pass" {
				passCount++
				fmt.Printf("  [chk %d/%d] \033[32mPASS\033[0m %s\n", checkIdx, gr.total, truncateStr(gr.question.Question, 60))

				key := fmt.Sprintf("%s_ch%02d", gr.source, gr.chapter)
				if chapterMap[key] == nil {
					chapterMap[key] = &chapterQuestions{source: gr.source, chapter: gr.chapter}
				}
				chapterMap[key].passed = append(chapterMap[key].passed, gr.question)
			} else {
				failCount++
				fmt.Printf("  [chk %d/%d] \033[31mFAIL\033[0m %s\n", checkIdx, gr.total, truncateStr(gr.question.Question, 60))
			}
		}
	}()

	wg.Wait()

	if genErr != nil {
		return fmt.Errorf("generator: %w", genErr)
	}
	if checkErr != nil {
		return fmt.Errorf("checker: %w", checkErr)
	}

	// --- Write output files ---
	outDir := filepath.Join("runs", fmt.Sprintf("run_%02d", runID), "questions")
	if err := os.MkdirAll(outDir, 0755); err != nil {
		return fmt.Errorf("mkdir %s: %w", outDir, err)
	}

	for key, cq := range chapterMap {
		sf := &importer.SeedFile{
			Source:    strings.ToUpper(cq.source),
			Chapter:   cq.chapter,
			Questions: cq.passed,
		}
		outPath := filepath.Join(outDir, key+".json")
		out, err := json.MarshalIndent(sf, "", "  ")
		if err != nil {
			return fmt.Errorf("marshal: %w", err)
		}
		out = append(out, '\n')
		if err := os.WriteFile(outPath, out, 0644); err != nil {
			return fmt.Errorf("write %s: %w", outPath, err)
		}
		fmt.Printf("  -> %s (%d questions)\n", outPath, len(cq.passed))
	}

	// --- Write cross-check report ---
	reportPath := filepath.Join("runs", fmt.Sprintf("run_%02d", runID), "crosscheck_report.json")
	reportData, err := json.MarshalIndent(allCheckResults, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal report: %w", err)
	}
	reportData = append(reportData, '\n')
	if err := os.WriteFile(reportPath, reportData, 0644); err != nil {
		return fmt.Errorf("write report: %w", err)
	}

	total := passCount + failCount + errCount
	fmt.Printf("\nParallel pipeline complete: %d/%d passed", passCount, total)
	if failCount > 0 {
		fmt.Printf(", \033[31m%d failures\033[0m", failCount)
	}
	if errCount > 0 {
		fmt.Printf(", \033[33m%d errors\033[0m", errCount)
	}
	fmt.Println()

	return nil
}

// hasQuestions returns true if path is a JSON file with a non-empty "questions" array.
func hasQuestions(path string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	var probe struct {
		Questions []json.RawMessage `json:"questions"`
	}
	if err := json.Unmarshal(data, &probe); err != nil {
		return false
	}
	return len(probe.Questions) > 0
}
