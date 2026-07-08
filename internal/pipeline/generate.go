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

const generateSystemPrompt = `You are an FAA Designated Pilot Examiner creating multiple-choice questions for a Private Pilot License study tool.

Given a testable fact from an FAA handbook, create one high-quality multiple-choice question.

Rules:
- The question should test understanding, not just rote memorization
- The correct answer must be unambiguously supported by the source fact
- Create exactly 3 plausible but clearly incorrect distractors
- Distractors should be wrong for specific, identifiable reasons
- The explanation should reference the source material
- Do NOT use "all of the above" or "none of the above"

Return JSON only:
{
  "question": "...",
  "correct_answer": "...",
  "distractors": ["...", "...", "..."],
  "explanation": "..."
}`

const generateUserTemplate = `Create a quiz question from this fact:

Source: %s Chapter %d
Section: %s
Difficulty: %d

Fact: %s

Source text from handbook:
%s`

type generateResponse struct {
	Question      string   `json:"question"`
	CorrectAnswer string   `json:"correct_answer"`
	Distractors   []string `json:"distractors"`
	Explanation   string   `json:"explanation"`
}

// Generate reads knowledge items from a run and generates questions.
func Generate(ctx context.Context, client *llm.Client, runID int) error {
	knowledgeDir := filepath.Join("runs", fmt.Sprintf("run_%02d", runID), "knowledge")
	entries, err := filepath.Glob(filepath.Join(knowledgeDir, "*.json"))
	if err != nil {
		return fmt.Errorf("glob %s: %w", knowledgeDir, err)
	}

	for _, path := range entries {
		data, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("read %s: %w", path, err)
		}

		var kf KnowledgeFile
		if err := json.Unmarshal(data, &kf); err != nil {
			return fmt.Errorf("parse %s: %w", path, err)
		}

		fmt.Printf("Generating from %s ch%02d (%d items)...\n", kf.Source, kf.Chapter, len(kf.Items))
		sf, err := GenerateChapter(ctx, client, &kf, runID)
		if err != nil {
			return fmt.Errorf("generate %s ch%02d: %w", kf.Source, kf.Chapter, err)
		}

		outDir := filepath.Join("runs", fmt.Sprintf("run_%02d", runID), "questions")
		if err := os.MkdirAll(outDir, 0755); err != nil {
			return fmt.Errorf("mkdir %s: %w", outDir, err)
		}

		outPath := filepath.Join(outDir, fmt.Sprintf("%s_ch%02d.json", kf.Source, kf.Chapter))
		out, err := json.MarshalIndent(sf, "", "  ")
		if err != nil {
			return fmt.Errorf("marshal: %w", err)
		}
		out = append(out, '\n')

		if err := os.WriteFile(outPath, out, 0644); err != nil {
			return fmt.Errorf("write %s: %w", outPath, err)
		}
		fmt.Printf("  -> %s (%d questions)\n", outPath, len(sf.Questions))
	}
	return nil
}

// GenerateChapter generates questions for all knowledge items in a chapter.
func GenerateChapter(ctx context.Context, client *llm.Client, kf *KnowledgeFile, runID int) (*importer.SeedFile, error) {
	sf := &importer.SeedFile{
		Source:  strings.ToUpper(kf.Source),
		Chapter: kf.Chapter,
	}

	for i, ki := range kf.Items {
		sq, err := GenerateFromItem(ctx, client, ki, kf.Source, kf.Chapter)
		if err != nil {
			fmt.Printf("  [%d/%d] ERROR: %v\n", i+1, len(kf.Items), err)
			continue
		}
		sf.Questions = append(sf.Questions, *sq)
		fmt.Printf("  [%d/%d] %s\n", i+1, len(kf.Items), truncateStr(sq.Question, 60))
	}

	return sf, nil
}

// GenerateFromItem generates a single question from a knowledge item.
func GenerateFromItem(ctx context.Context, client *llm.Client, ki KnowledgeItem, source string, chapter int) (*importer.SeedQuestion, error) {
	userPrompt := fmt.Sprintf(generateUserTemplate, source, chapter, ki.Section, ki.Difficulty, ki.Fact, ki.SourceText)

	var resp generateResponse
	if err := client.CompleteJSON(ctx, generateSystemPrompt, userPrompt, &resp); err != nil {
		return nil, err
	}

	sq := &importer.SeedQuestion{
		Section:       ki.Section,
		Difficulty:    ki.Difficulty,
		Categories:    ki.Categories,
		Question:      resp.Question,
		CorrectAnswer: resp.CorrectAnswer,
		Distractors:   resp.Distractors,
		Explanation:   resp.Explanation,
		Reference: &importer.Reference{
			Page: ki.Page,
			Text: ki.SourceText,
		},
	}

	return sq, nil
}

func truncateStr(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n-3] + "..."
}
