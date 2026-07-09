package pipeline

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/das/faa-knowledge/internal/importer"
	"github.com/das/faa-knowledge/internal/llm"
)

// CrossCheckResult holds the result of cross-checking a single question.
type CrossCheckResult struct {
	Question  string   `json:"question"`
	Verdict   string   `json:"verdict"` // "pass" or "fail"
	Issues    []string `json:"issues"`
	Reasoning string   `json:"reasoning"`
}

const crossCheckSystemPrompt = `You are an FAA aviation knowledge expert independently reviewing multiple-choice questions.

For each question, verify:
1. Is the correct answer actually correct per FAA publications?
2. Is the question clear and unambiguous?
3. Are the distractors plausible but clearly wrong?
4. Is the explanation accurate?

When reference text is provided, treat it as authoritative source material.

Return JSON only:
{
  "verdict": "pass" or "fail",
  "issues": ["list of specific problems found"],
  "reasoning": "brief explanation"
}`

const crossCheckUserTemplate = `Review this aviation knowledge question:

Question: %s
Correct answer: %s
Distractors: %s
Explanation: %s

Reference text from FAA handbook:
%s`

// CheckedQuestion is a question that has been cross-checked.
type CheckedQuestion struct {
	Question    importer.SeedQuestion
	CheckResult *CrossCheckResult // nil if check was skipped
}

// CrossCheckOne reviews a single question using the small LLM.
func CrossCheckOne(ctx context.Context, client *llm.Client, sq importer.SeedQuestion) (*CrossCheckResult, error) {
	refText := ""
	if sq.Reference != nil {
		refText = sq.Reference.Text
	}

	distractors := strings.Join(sq.Distractors, ", ")
	userPrompt := fmt.Sprintf(crossCheckUserTemplate, sq.Question, sq.CorrectAnswer, distractors, sq.Explanation, refText)

	var result CrossCheckResult
	if err := client.CompleteJSON(ctx, crossCheckSystemPrompt, userPrompt, &result); err != nil {
		return nil, err
	}

	result.Question = sq.Question
	return &result, nil
}

// CrossCheck reviews merged questions using a small LLM.
func CrossCheck(ctx context.Context, client *llm.Client, questionsDir string) error {
	entries, err := filepath.Glob(filepath.Join(questionsDir, "*.json"))
	if err != nil {
		return fmt.Errorf("glob %s: %w", questionsDir, err)
	}

	allResults := make(map[string][]CrossCheckResult)

	for _, path := range entries {
		data, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("read %s: %w", path, err)
		}

		var sf importer.SeedFile
		if err := json.Unmarshal(data, &sf); err != nil {
			return fmt.Errorf("parse %s: %w", path, err)
		}

		base := filepath.Base(path)
		fmt.Printf("Cross-checking %s (%d questions)...\n", base, len(sf.Questions))

		var results []CrossCheckResult
		for i, sq := range sf.Questions {
			refText := ""
			if sq.Reference != nil {
				refText = sq.Reference.Text
			}

			distractors := strings.Join(sq.Distractors, ", ")
			userPrompt := fmt.Sprintf(crossCheckUserTemplate, sq.Question, sq.CorrectAnswer, distractors, sq.Explanation, refText)

			var result CrossCheckResult
			if err := client.CompleteJSON(ctx, crossCheckSystemPrompt, userPrompt, &result); err != nil {
				fmt.Printf("  [%d/%d] ERROR: %v\n", i+1, len(sf.Questions), err)
				results = append(results, CrossCheckResult{
					Question:  sq.Question,
					Verdict:   "error",
					Issues:    []string{err.Error()},
					Reasoning: "LLM error",
				})
				continue
			}

			result.Question = sq.Question
			results = append(results, result)

			status := "\033[32mPASS\033[0m"
			if result.Verdict != "pass" {
				status = "\033[31mFAIL\033[0m"
			}
			fmt.Printf("  [%d/%d] %s %s\n", i+1, len(sf.Questions), status, truncateStr(sq.Question, 60))
		}

		allResults[base] = results
	}

	PrintCrossCheckReport(allResults)

	// Save report
	reportData, err := json.MarshalIndent(allResults, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal report: %w", err)
	}
	reportData = append(reportData, '\n')

	reportPath := filepath.Join(questionsDir, "..", "crosscheck_report.json")
	if err := os.WriteFile(reportPath, reportData, 0644); err != nil {
		return fmt.Errorf("write report: %w", err)
	}
	fmt.Printf("\nReport saved to %s\n", reportPath)

	return nil
}

// PrintCrossCheckReport prints a colored summary.
func PrintCrossCheckReport(results map[string][]CrossCheckResult) {
	totalPass, totalFail, totalErr := 0, 0, 0

	for file, crs := range results {
		fmt.Printf("\n%s\n", file)
		fmt.Println(strings.Repeat("-", len(file)))

		for _, cr := range crs {
			short := truncateStr(cr.Question, 60)
			switch cr.Verdict {
			case "pass":
				fmt.Printf("  \033[32mPASS\033[0m  %s\n", short)
				totalPass++
			case "error":
				fmt.Printf("  \033[33mERROR\033[0m %s\n", short)
				totalErr++
			default:
				fmt.Printf("  \033[31mFAIL\033[0m  %s\n", short)
				totalFail++
				for _, issue := range cr.Issues {
					fmt.Printf("         - %s\n", issue)
				}
			}
		}
	}

	total := totalPass + totalFail + totalErr
	fmt.Printf("\nCross-check summary: %d/%d passed", totalPass, total)
	if totalFail > 0 {
		fmt.Printf(", \033[31m%d failures\033[0m", totalFail)
	}
	if totalErr > 0 {
		fmt.Printf(", \033[33m%d errors\033[0m", totalErr)
	}
	fmt.Println()
}
