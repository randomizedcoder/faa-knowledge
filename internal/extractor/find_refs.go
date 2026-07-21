// Copyright (c) 2026 randomizedcoder. All Rights Reserved.
// Proprietary and confidential -- see the LICENSE file in the project root.

package extractor

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

const refSystemPrompt = `You are an FAA aviation knowledge expert. You are given chapter text from an FAA handbook and a quiz question. Your job is to find the exact paragraph in the chapter text that supports the question and its correct answer.

Return JSON only with this structure:
{
  "page": "5-12",
  "text": "The exact paragraph from the chapter text."
}

Rules:
- "page" must be the handbook page label (e.g., "5-12" meaning chapter 5, page 12). Look for page markers in the text.
- "text" must be copied verbatim from the chapter text. Do not paraphrase.
- If multiple paragraphs are relevant, pick the single most relevant one.
- If you cannot find a supporting paragraph, return {"page": "", "text": ""}.`

const refUserTemplate = `Chapter text from %s Chapter %d:
---
%s
---

Question: %s
Correct answer: %s
Explanation: %s

Find the paragraph in the chapter text that supports this question. Return JSON with "page" and "text".`

// FindReference sends chapter text + question to the LLM and returns a Reference.
func FindReference(ctx context.Context, client *llm.Client, source string, chapter int, chapterText string, sq importer.SeedQuestion) (*importer.Reference, error) {
	userPrompt := fmt.Sprintf(refUserTemplate, source, chapter, chapterText, sq.Question, sq.CorrectAnswer, sq.Explanation)

	var ref importer.Reference
	if err := client.CompleteJSON(ctx, refSystemPrompt, userPrompt, &ref); err != nil {
		return nil, err
	}

	if ref.Page == "" && ref.Text == "" {
		return nil, nil // no reference found
	}

	return &ref, nil
}

// pdfFilename returns the expected PDF filename for a source code.
func pdfFilename(source string) string {
	switch strings.ToUpper(source) {
	case "PHAK":
		return "phak.pdf"
	case "AFH":
		return "afh.pdf"
	default:
		return strings.ToLower(source) + ".pdf"
	}
}

// AddRefsToFile loads a question JSON file, extracts references from the corresponding PDF, and writes them back.
func AddRefsToFile(ctx context.Context, client *llm.Client, pdfDir, jsonPath string) error {
	data, err := os.ReadFile(jsonPath)
	if err != nil {
		return fmt.Errorf("read %s: %w", jsonPath, err)
	}

	var seed importer.SeedFile
	if err := json.Unmarshal(data, &seed); err != nil {
		return fmt.Errorf("parse %s: %w", jsonPath, err)
	}

	pdfPath := filepath.Join(pdfDir, pdfFilename(seed.Source))
	fmt.Printf("Extracting text from %s...\n", pdfPath)

	pages, err := ExtractPages(pdfPath)
	if err != nil {
		return fmt.Errorf("extract PDF: %w", err)
	}

	chText := ChapterText(pages, seed.Chapter)
	if chText == "" {
		return fmt.Errorf("no text found for %s chapter %d", seed.Source, seed.Chapter)
	}

	// Truncate chapter text if extremely long (LLM context limit)
	const maxChapterLen = 80000
	if len(chText) > maxChapterLen {
		chText = chText[:maxChapterLen]
	}

	changed := false
	for i := range seed.Questions {
		sq := &seed.Questions[i]
		if sq.Reference != nil {
			fmt.Printf("  [%d/%d] skip (already has ref): %s\n", i+1, len(seed.Questions), truncate(sq.Question, 60))
			continue
		}

		fmt.Printf("  [%d/%d] %s\n", i+1, len(seed.Questions), truncate(sq.Question, 60))

		ref, err := FindReference(ctx, client, seed.Source, seed.Chapter, chText, *sq)
		if err != nil {
			fmt.Printf("    ERROR: %v\n", err)
			continue
		}

		if ref == nil {
			fmt.Printf("    no reference found\n")
			continue
		}

		sq.Reference = ref
		changed = true
		fmt.Printf("    -> p.%s (%d chars)\n", ref.Page, len(ref.Text))
	}

	if !changed {
		fmt.Printf("  No changes to %s\n", jsonPath)
		return nil
	}

	out, err := json.MarshalIndent(seed, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal %s: %w", jsonPath, err)
	}
	out = append(out, '\n')

	if err := os.WriteFile(jsonPath, out, 0644); err != nil {
		return fmt.Errorf("write %s: %w", jsonPath, err)
	}
	fmt.Printf("  Wrote %s\n", jsonPath)
	return nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n-3] + "..."
}
