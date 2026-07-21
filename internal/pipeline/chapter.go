// Copyright (c) 2026 randomizedcoder. All Rights Reserved.
// Proprietary and confidential -- see the LICENSE file in the project root.

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

// experimentDir is where the chapter-level experiment writes its output.
const experimentDir = "runs/experiment"

// --- Method B: outline -> generate --------------------------------------

const outlineSystemPrompt = `You are an FAA aviation knowledge expert analyzing a full chapter from an FAA handbook.

Split the chapter into coherent SUBJECT sections following the real topical structure of the text. Ignore figure captions, axis labels, table fragments, and other layout noise — group by subject, not by page.

For each section, extract the distinct, testable key points a Private Pilot student should learn. Use the full chapter context so points are accurate and non-redundant.

Rules:
- Each key point is a single, self-contained, testable statement (not a vague generalization).
- Cover procedures, definitions, limitations, markings, and safety-critical information.
- For each point, include a short verbatim quote from the chapter that supports it, and the page label (e.g. "8-3") it came from.
- Assign difficulty 1 (basic recall), 2 (understanding/application), or 3 (analysis/judgment).
- Assign categories from: "written_exam", "checkride_oral", "general_knowledge".

Return JSON only:
{"sections": [{"title": "...", "page_range": "8-1 to 8-4", "key_points": [{"point": "...", "difficulty": 1, "categories": ["written_exam"], "source_quote": "...", "page": "8-3"}]}]}`

const outlineUserTemplate = `Analyze this full FAA handbook chapter and produce the section outline with key points.

Source: %s Chapter %d

Chapter text:
%s`

type outlineResponse struct {
	Sections []struct {
		Title     string `json:"title"`
		PageRange string `json:"page_range"`
		KeyPoints []struct {
			Point       string   `json:"point"`
			Difficulty  int      `json:"difficulty"`
			Categories  []string `json:"categories"`
			SourceQuote string   `json:"source_quote"`
			Page        string   `json:"page"`
		} `json:"key_points"`
	} `json:"sections"`
}

// outlineChapter runs the single context-rich call that splits the chapter into
// subject sections with key points, and maps the result into a KnowledgeFile so
// the existing generator can reuse it.
func outlineChapter(ctx context.Context, client *llm.Client, source string, chapter int, text string) (*KnowledgeFile, error) {
	user := fmt.Sprintf(outlineUserTemplate, source, chapter, text)

	var resp outlineResponse
	if err := client.CompleteJSON(ctx, outlineSystemPrompt, user, &resp); err != nil {
		return nil, fmt.Errorf("outline chapter: %w", err)
	}

	kf := &KnowledgeFile{Source: source, Chapter: chapter}
	seq := 0
	for _, sec := range resp.Sections {
		for _, kp := range sec.KeyPoints {
			seq++
			page := kp.Page
			if page == "" {
				page = sec.PageRange
			}
			kf.Items = append(kf.Items, KnowledgeItem{
				ID:         fmt.Sprintf("%s_%02d_out_%03d", source, chapter, seq),
				Page:       page,
				Section:    sec.Title,
				Fact:       kp.Point,
				SourceText: kp.SourceQuote,
				Difficulty: kp.Difficulty,
				Categories: kp.Categories,
			})
		}
	}
	fmt.Printf("  outline: %d sections, %d key points\n", len(resp.Sections), len(kf.Items))
	return kf, nil
}

// --- Method C: whole-chapter -> finished questions ----------------------

const directSystemPrompt = `You are an FAA Designated Pilot Examiner creating multiple-choice questions for a Private Pilot License study tool, working from a full FAA handbook chapter.

Using the whole chapter for context, create high-quality multiple-choice questions that cover the key testable points, spread across the chapter's distinct subjects. Prefer breadth of coverage over many questions on one topic.

Rules per question:
- Test understanding, not rote memorization; the correct answer must be unambiguously supported by the chapter.
- Exactly 3 plausible but clearly incorrect distractors, each wrong for a specific reason.
- The explanation references the source material.
- Do NOT use "all of the above" or "none of the above".
- Include the section title, a short supporting quote, and the page label.
- Assign difficulty 1-3 and categories from: "written_exam", "checkride_oral", "general_knowledge".

Return JSON only:
{"questions": [{"section": "...", "difficulty": 1, "categories": ["written_exam"], "question": "...", "correct_answer": "...", "distractors": ["...","...","..."], "explanation": "...", "page": "8-3", "source_quote": "..."}]}`

const directUserTemplate = `Create about %d multiple-choice questions from this full FAA handbook chapter, spread across its subjects.

Source: %s Chapter %d

Chapter text:
%s`

type directResponse struct {
	Questions []struct {
		Section       string   `json:"section"`
		Difficulty    int      `json:"difficulty"`
		Categories    []string `json:"categories"`
		Question      string   `json:"question"`
		CorrectAnswer string   `json:"correct_answer"`
		Distractors   []string `json:"distractors"`
		Explanation   string   `json:"explanation"`
		Page          string   `json:"page"`
		SourceQuote   string   `json:"source_quote"`
	} `json:"questions"`
}

// directChapter turns a whole chapter into finished questions in one call.
func directChapter(ctx context.Context, client *llm.Client, source string, chapter, count int, text string) (*importer.SeedFile, error) {
	user := fmt.Sprintf(directUserTemplate, count, source, chapter, text)

	var resp directResponse
	if err := client.CompleteJSON(ctx, directSystemPrompt, user, &resp); err != nil {
		return nil, fmt.Errorf("direct chapter: %w", err)
	}

	sf := &importer.SeedFile{Source: strings.ToUpper(source), Chapter: chapter}
	for _, q := range resp.Questions {
		sq := importer.SeedQuestion{
			Section:       q.Section,
			Difficulty:    q.Difficulty,
			Categories:    q.Categories,
			Question:      q.Question,
			CorrectAnswer: q.CorrectAnswer,
			Distractors:   q.Distractors,
			Explanation:   q.Explanation,
		}
		if q.Page != "" || q.SourceQuote != "" {
			sq.Reference = &importer.Reference{Page: q.Page, Text: q.SourceQuote}
		}
		sf.Questions = append(sf.Questions, sq)
	}
	fmt.Printf("  direct: %d questions\n", len(sf.Questions))
	return sf, nil
}

// --- Experiment driver --------------------------------------------------

// GenChapterExperiment runs chapter-level generation for one chapter. method is
// "outline", "direct", or "both". When outDir is empty, output goes to
// runs/experiment/{source}_ch{NN}_{method}.json (experiment mode). When outDir
// is set, a single method writes the production filename {source}_ch{NN}.json
// there (e.g. database/questions).
func GenChapterExperiment(ctx context.Context, client *llm.Client, textDir, outDir, source string, chapter int, method string, cap int) error {
	if outDir != "" && method == "both" {
		return fmt.Errorf("--out-dir requires a single --method (outline or direct), not both")
	}

	text, err := readChapterText(textDir, source, chapter)
	if err != nil {
		return err
	}
	fmt.Printf("Loaded %s ch%02d: %d chars (~%d tokens)\n", source, chapter, len(text), len(text)/4)

	if method == "outline" || method == "both" {
		fmt.Println("=== Method B: outline -> generate ===")
		kf, err := outlineChapter(ctx, client, source, chapter, text)
		if err != nil {
			return err
		}
		items := SelectItems(kf.Items, cap)
		if cap > 0 && len(items) < len(kf.Items) {
			fmt.Printf("  (selected %d of %d key points)\n", len(items), len(kf.Items))
		}
		sf := &importer.SeedFile{Source: strings.ToUpper(source), Chapter: chapter}
		for i, ki := range items {
			sq, err := GenerateFromItem(ctx, client, ki, source, chapter)
			if err != nil {
				fmt.Printf("  [%d/%d] ERROR: %v\n", i+1, len(items), err)
				continue
			}
			sf.Questions = append(sf.Questions, *sq)
			fmt.Printf("  [%d/%d] %s\n", i+1, len(items), truncateStr(sq.Question, 60))
		}
		if err := writeChapterSeedFile(sf, outDir, source, chapter, "outline"); err != nil {
			return err
		}
	}

	if method == "direct" || method == "both" {
		fmt.Println("=== Method C: whole-chapter -> direct ===")
		count := cap
		if count <= 0 {
			count = 18
		}
		sf, err := directChapter(ctx, client, source, chapter, count, text)
		if err != nil {
			return err
		}
		if err := writeChapterSeedFile(sf, outDir, source, chapter, "direct"); err != nil {
			return err
		}
	}

	return nil
}

// readChapterText loads the extracted chapter text (pdfs_text/{source}/ch{NN}.txt).
func readChapterText(textDir, source string, chapter int) (string, error) {
	path := filepath.Join(textDir, strings.ToLower(source), fmt.Sprintf("ch%02d.txt", chapter))
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read chapter text %s: %w", path, err)
	}
	return string(data), nil
}

// writeChapterSeedFile writes sf to outDir. When outDir is empty it writes the
// experiment file runs/experiment/{source}_ch{NN}_{method}.json; otherwise it
// writes the production file outDir/{source}_ch{NN}.json.
func writeChapterSeedFile(sf *importer.SeedFile, outDir, source string, chapter int, method string) error {
	var dir, name string
	if outDir == "" {
		dir = experimentDir
		name = fmt.Sprintf("%s_ch%02d_%s.json", strings.ToLower(source), chapter, method)
	} else {
		dir = outDir
		name = fmt.Sprintf("%s_ch%02d.json", strings.ToLower(source), chapter)
	}
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("mkdir %s: %w", dir, err)
	}
	out, err := json.MarshalIndent(sf, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal: %w", err)
	}
	out = append(out, '\n')
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, out, 0644); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	fmt.Printf("  -> %s (%d questions)\n", path, len(sf.Questions))
	return nil
}
