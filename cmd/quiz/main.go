package main

import (
	"flag"
	"fmt"
	"os"

	dbsql "github.com/das/faa-knowledge/database"
	"github.com/das/faa-knowledge/internal/db"
	"github.com/das/faa-knowledge/internal/importer"
	"github.com/das/faa-knowledge/internal/quiz"
)

func main() {
	initDB := flag.Bool("init", false, "Initialize database with schema and seed data")
	importFile := flag.String("import", "", "Import questions from a JSON file")
	count := flag.Int("count", 0, "Number of questions (0 = all matching)")
	category := flag.String("category", "", "Filter by category (written_exam, checkride_oral, general_knowledge)")
	source := flag.String("source", "", "Filter by source code (PHAK, AFH)")
	chapter := flag.Int("chapter", 0, "Filter by chapter number")
	difficulty := flag.Int("difficulty", 0, "Filter by difficulty (1-3)")
	dbPath := flag.String("db", db.DefaultDBPath, "Database file path")

	flag.Parse()

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
