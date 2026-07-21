// Copyright (c) 2026 randomizedcoder. All Rights Reserved.
// Proprietary and confidential -- see the LICENSE file in the project root.

package validator

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/das/faa-knowledge/internal/importer"
)

const (
	colorReset  = "\033[0m"
	colorRed    = "\033[31m"
	colorGreen  = "\033[32m"
	colorYellow = "\033[33m"
)

// PrintReport prints a colored summary of validation results.
func PrintReport(results map[string][]QuestionResult) {
	totalPass, totalFail, totalErr := 0, 0, 0

	for file, qrs := range results {
		fmt.Printf("\n%s\n", file)
		fmt.Println(strings.Repeat("-", len(file)))

		for _, qr := range qrs {
			short := truncate(qr.Question.Question, 60)

			if qr.Err != nil {
				fmt.Printf("  %sERROR%s %s — %v\n", colorYellow, colorReset, short, qr.Err)
				totalErr++
				continue
			}

			if qr.Review.Verdict == "pass" {
				fmt.Printf("  %sPASS%s  %s\n", colorGreen, colorReset, short)
				totalPass++
			} else {
				fmt.Printf("  %sFAIL%s  %s\n", colorRed, colorReset, short)
				totalFail++
				for _, issue := range qr.Review.Issues {
					fmt.Printf("         - %s\n", issue)
				}
				if qr.Review.Reasoning != "" {
					fmt.Printf("         Reasoning: %s\n", qr.Review.Reasoning)
				}
			}
		}
	}

	total := totalPass + totalFail + totalErr
	fmt.Printf("\nSummary: %d/%d passed", totalPass, total)
	if totalFail > 0 {
		fmt.Printf(", %s%d failures%s", colorRed, totalFail, colorReset)
	}
	if totalErr > 0 {
		fmt.Printf(", %s%d errors%s", colorYellow, totalErr, colorReset)
	}
	fmt.Println()
}

// ApplyFixes rewrites JSON files with LLM-suggested corrections.
// For --file mode, fixPath is the original file path.
// For embedded mode, fixPath is the base directory (e.g., "database/questions").
func ApplyFixes(results map[string][]QuestionResult, fixPath string) error {
	for file, qrs := range results {
		// Determine the actual file path on disk
		path := fixPath
		if len(results) > 1 {
			// Embedded mode: file key is like "questions/phak_ch05.json"
			path = strings.Replace(file, "questions/", fixPath+"/", 1)
		}

		data, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("read %s for fix: %w", path, err)
		}

		var seed importer.SeedFile
		if err := json.Unmarshal(data, &seed); err != nil {
			return fmt.Errorf("parse %s for fix: %w", path, err)
		}

		changed := false
		for _, qr := range qrs {
			if qr.Err != nil || qr.Review.Verdict == "pass" {
				continue
			}

			// Find the matching question in the seed file
			for i := range seed.Questions {
				if seed.Questions[i].Question != qr.Question.Question {
					continue
				}

				sq := &seed.Questions[i]
				if qr.Review.SuggestedQuestion != nil {
					fmt.Printf("  FIX question: %s\n", truncate(*qr.Review.SuggestedQuestion, 70))
					sq.Question = *qr.Review.SuggestedQuestion
					changed = true
				}
				if qr.Review.SuggestedAnswer != nil {
					fmt.Printf("  FIX answer:   %s\n", truncate(*qr.Review.SuggestedAnswer, 70))
					sq.CorrectAnswer = *qr.Review.SuggestedAnswer
					changed = true
				}
				if len(qr.Review.SuggestedDistractors) > 0 {
					fmt.Printf("  FIX distractors: %d replacements\n", len(qr.Review.SuggestedDistractors))
					sq.Distractors = qr.Review.SuggestedDistractors
					changed = true
				}
				if qr.Review.SuggestedExplanation != nil {
					fmt.Printf("  FIX explanation: %s\n", truncate(*qr.Review.SuggestedExplanation, 70))
					sq.Explanation = *qr.Review.SuggestedExplanation
					changed = true
				}
				break
			}
		}

		if !changed {
			continue
		}

		out, err := json.MarshalIndent(seed, "", "  ")
		if err != nil {
			return fmt.Errorf("marshal %s: %w", path, err)
		}
		out = append(out, '\n')

		if err := os.WriteFile(path, out, 0644); err != nil {
			return fmt.Errorf("write %s: %w", path, err)
		}
		fmt.Printf("  Wrote %s\n", path)
	}

	return nil
}
