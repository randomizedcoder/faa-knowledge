// Copyright (c) 2026 randomizedcoder. All Rights Reserved.
// Proprietary and confidential -- see the LICENSE file in the project root.

package validator

import (
	"context"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"

	"github.com/das/faa-knowledge/internal/importer"
)

// ReviewResult is the structured response from the LLM.
type ReviewResult struct {
	Verdict              string   `json:"verdict"`
	Issues               []string `json:"issues"`
	SuggestedQuestion    *string  `json:"suggested_question"`
	SuggestedAnswer      *string  `json:"suggested_correct_answer"`
	SuggestedDistractors []string `json:"suggested_distractors"`
	SuggestedExplanation *string  `json:"suggested_explanation"`
	Reasoning            string   `json:"reasoning"`
}

// QuestionResult pairs a question with its review.
type QuestionResult struct {
	Question importer.SeedQuestion
	Review   ReviewResult
	Err      error
}

// ValidateFile reads one JSON file from disk and reviews each question.
func ValidateFile(ctx context.Context, client *LLMClient, path string) ([]QuestionResult, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	return validateData(ctx, client, data, path)
}

// ValidateAll walks all JSON files in the embedded FS and reviews every question.
func ValidateAll(ctx context.Context, client *LLMClient, questionsFS fs.FS) (map[string][]QuestionResult, error) {
	entries, err := fs.ReadDir(questionsFS, "questions")
	if err != nil {
		return nil, fmt.Errorf("read embedded questions dir: %w", err)
	}

	results := make(map[string][]QuestionResult)
	for _, e := range entries {
		name := "questions/" + e.Name()
		data, err := fs.ReadFile(questionsFS, name)
		if err != nil {
			return nil, fmt.Errorf("read %s: %w", name, err)
		}

		qr, err := validateData(ctx, client, data, name)
		if err != nil {
			return nil, fmt.Errorf("validate %s: %w", name, err)
		}
		results[name] = qr
	}

	return results, nil
}

func validateData(ctx context.Context, client *LLMClient, data []byte, name string) ([]QuestionResult, error) {
	var seed importer.SeedFile
	if err := json.Unmarshal(data, &seed); err != nil {
		return nil, fmt.Errorf("parse %s: %w", name, err)
	}

	var results []QuestionResult
	for i, sq := range seed.Questions {
		fmt.Printf("  [%d/%d] %s\n", i+1, len(seed.Questions), truncate(sq.Question, 70))

		payload := questionPayload{
			Question:      sq.Question,
			CorrectAnswer: sq.CorrectAnswer,
			Distractors:   sq.Distractors,
			Explanation:   sq.Explanation,
		}
		if sq.Reference != nil {
			payload.ReferenceText = sq.Reference.Text
		}

		review, err := client.Review(ctx, payload)

		results = append(results, QuestionResult{
			Question: sq,
			Review:   review,
			Err:      err,
		})
	}

	return results, nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n-3] + "..."
}
