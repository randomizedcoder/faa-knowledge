// Copyright (c) 2026 randomizedcoder. All Rights Reserved.
// Proprietary and confidential -- see the LICENSE file in the project root.

package pipeline

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
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

// maxConsecutiveConnFails trips a stage-level circuit-breaker: once the LLM
// endpoint has failed this many times in a row (e.g. a dropped tunnel), abort
// the stage instead of grinding through thousands of doomed calls.
const maxConsecutiveConnFails = 8

// Generate reads knowledge items from a run and generates questions. When cap
// > 0, at most cap items per chapter are used (see SelectItems).
func Generate(ctx context.Context, client *llm.Client, runID, cap int) error {
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
		sf, err := GenerateChapter(ctx, client, &kf, runID, cap)
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

// GenerateChapter generates questions for the knowledge items in a chapter.
// When cap > 0, only the top cap items (per SelectItems) are used.
func GenerateChapter(ctx context.Context, client *llm.Client, kf *KnowledgeFile, runID, cap int) (*importer.SeedFile, error) {
	sf := &importer.SeedFile{
		Source:  strings.ToUpper(kf.Source),
		Chapter: kf.Chapter,
	}

	items := SelectItems(kf.Items, cap)
	if cap > 0 && len(items) < len(kf.Items) {
		fmt.Printf("  (selected %d of %d items)\n", len(items), len(kf.Items))
	}

	connFails := 0
	for i, ki := range items {
		sq, err := GenerateFromItem(ctx, client, ki, kf.Source, kf.Chapter)
		if err != nil {
			fmt.Printf("  [%d/%d] ERROR: %v\n", i+1, len(items), err)
			if llm.IsConnError(err) {
				connFails++
				if connFails >= maxConsecutiveConnFails {
					return nil, fmt.Errorf("aborting after %d consecutive connection failures — is the LLM server up? last: %w", connFails, err)
				}
			}
			continue
		}
		connFails = 0
		sf.Questions = append(sf.Questions, *sq)
		fmt.Printf("  [%d/%d] %s\n", i+1, len(items), truncateStr(sq.Question, 60))
	}

	return sf, nil
}

// SelectItems picks up to cap knowledge items from items, favoring harder,
// distinct facts. It drops near-duplicate facts (SimilarityScore > 0.85), then
// sorts by difficulty (descending) keeping document order within a difficulty,
// and returns the first cap. cap <= 0 returns items unchanged.
func SelectItems(items []KnowledgeItem, cap int) []KnowledgeItem {
	if cap <= 0 || len(items) <= cap {
		return items
	}

	// Drop near-duplicate facts, keeping the first occurrence.
	deduped := make([]KnowledgeItem, 0, len(items))
	kept := make([]string, 0, len(items))
	for _, ki := range items {
		norm := NormalizeText(ki.Fact)
		dup := false
		for _, k := range kept {
			if SimilarityScore(norm, k) > 0.85 {
				dup = true
				break
			}
		}
		if !dup {
			deduped = append(deduped, ki)
			kept = append(kept, norm)
		}
	}

	if len(deduped) <= cap {
		return deduped
	}

	// Stable sort by difficulty descending; ties keep document order.
	sort.SliceStable(deduped, func(i, j int) bool {
		return deduped[i].Difficulty > deduped[j].Difficulty
	})
	return deduped[:cap]
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
