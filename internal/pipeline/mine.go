package pipeline

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/das/faa-knowledge/internal/llm"
)

// KnowledgeItem represents a single testable fact extracted from a paragraph.
type KnowledgeItem struct {
	ID          string   `json:"id"`
	ParagraphID string   `json:"paragraph_id"`
	Page        string   `json:"page"`
	Section     string   `json:"section"`
	Fact        string   `json:"fact"`
	SourceText  string   `json:"source_text"`
	Difficulty  int      `json:"difficulty"`
	Categories  []string `json:"categories"`
}

// KnowledgeFile holds all knowledge items for one chapter.
type KnowledgeFile struct {
	Source  string          `json:"source"`
	Chapter int            `json:"chapter"`
	Items   []KnowledgeItem `json:"items"`
}

const mineSystemPrompt = `You are an FAA aviation knowledge expert. Your job is to extract testable facts from FAA handbook text.

Given a paragraph from an FAA handbook, extract distinct, testable facts that could be used to generate multiple-choice questions for a Private Pilot License study tool.

Rules:
- Each fact should be a single, self-contained statement
- Facts should be specific enough to test in a quiz (not vague generalizations)
- Include facts about procedures, definitions, limitations, and safety-critical information
- Assign difficulty 1 (basic recall), 2 (understanding/application), or 3 (analysis/judgment)
- Assign categories from: "written_exam", "checkride_oral", "general_knowledge"
- Skip trivial or untestable statements

Return JSON only:
{"facts": [{"fact": "...", "difficulty": 1, "categories": ["written_exam"]}]}`

const mineUserTemplate = `Extract testable facts from this FAA handbook paragraph:

Source: %s Chapter %d
Section: %s

Text:
%s`

type mineResponse struct {
	Facts []struct {
		Fact       string   `json:"fact"`
		Difficulty int      `json:"difficulty"`
		Categories []string `json:"categories"`
	} `json:"facts"`
}

// ChapterFilter is a set of "source:chapter" keys (e.g. "phak:04"). Nil means all chapters.
type ChapterFilter map[string]bool

// ParseChapterFilter parses a comma-separated string like "phak:04,afh:03" into a ChapterFilter.
func ParseChapterFilter(s string) ChapterFilter {
	if s == "" {
		return nil
	}
	f := make(ChapterFilter)
	for _, part := range strings.Split(s, ",") {
		f[strings.TrimSpace(part)] = true
	}
	return f
}

func (f ChapterFilter) Match(source string, chapter int) bool {
	if f == nil {
		return true
	}
	key := fmt.Sprintf("%s:%02d", strings.ToLower(source), chapter)
	return f[key]
}

// PipelineOpts controls checkpointing and dry-run behavior.
type PipelineOpts struct {
	Force  bool
	DryRun bool
}

// Mine processes all paragraph files and extracts knowledge items.
func Mine(ctx context.Context, client *llm.Client, textDir string, runID int, filter ChapterFilter, opts PipelineOpts) error {
	for _, source := range []string{"phak", "afh"} {
		sourceDir := filepath.Join(textDir, source)
		entries, err := filepath.Glob(filepath.Join(sourceDir, "ch*_paragraphs.json"))
		if err != nil {
			return fmt.Errorf("glob %s: %w", sourceDir, err)
		}

		for _, path := range entries {
			var chNum int
			base := filepath.Base(path)
			if _, err := fmt.Sscanf(base, "ch%d_paragraphs.json", &chNum); err != nil {
				continue
			}

			if !filter.Match(source, chNum) {
				continue
			}

			outDir := filepath.Join("runs", fmt.Sprintf("run_%02d", runID), "knowledge")
			outPath := filepath.Join(outDir, fmt.Sprintf("%s_ch%02d.json", source, chNum))

			if !opts.Force {
				if hasItems(outPath) {
					fmt.Printf("  [skip] %s (exists, use --force to regenerate)\n", outPath)
					continue
				}
			}

			data, err := os.ReadFile(path)
			if err != nil {
				return fmt.Errorf("read %s: %w", path, err)
			}

			var paragraphs []Paragraph
			if err := json.Unmarshal(data, &paragraphs); err != nil {
				return fmt.Errorf("parse %s: %w", path, err)
			}

			if opts.DryRun {
				fmt.Printf("  [dry-run] would mine %s ch%02d (%d paragraphs)\n", source, chNum, len(paragraphs))
				continue
			}

			fmt.Printf("Mining %s ch%02d (%d paragraphs)...\n", source, chNum, len(paragraphs))
			kf, err := MineChapter(ctx, client, source, chNum, paragraphs, runID)
			if err != nil {
				return fmt.Errorf("mine %s ch%02d: %w", source, chNum, err)
			}

			if err := os.MkdirAll(outDir, 0755); err != nil {
				return fmt.Errorf("mkdir %s: %w", outDir, err)
			}

			out, err := json.MarshalIndent(kf, "", "  ")
			if err != nil {
				return fmt.Errorf("marshal: %w", err)
			}
			out = append(out, '\n')

			if err := os.WriteFile(outPath, out, 0644); err != nil {
				return fmt.Errorf("write %s: %w", outPath, err)
			}
			fmt.Printf("  -> %s (%d items)\n", outPath, len(kf.Items))
		}
	}
	return nil
}

// MineChapter extracts knowledge items from all paragraphs in a chapter.
func MineChapter(ctx context.Context, client *llm.Client, source string, chapter int, paragraphs []Paragraph, runID int) (*KnowledgeFile, error) {
	kf := &KnowledgeFile{
		Source:  source,
		Chapter: chapter,
	}

	seq := 0
	connFails := 0
	for i, p := range paragraphs {
		if len(p.Text) < 50 {
			continue
		}

		userPrompt := fmt.Sprintf(mineUserTemplate, source, chapter, p.Section, p.Text)

		var resp mineResponse
		if err := client.CompleteJSON(ctx, mineSystemPrompt, userPrompt, &resp); err != nil {
			fmt.Printf("  [%d/%d] ERROR: %v\n", i+1, len(paragraphs), err)
			if llm.IsConnError(err) {
				connFails++
				if connFails >= maxConsecutiveConnFails {
					return nil, fmt.Errorf("aborting after %d consecutive connection failures — is the LLM server up? last: %w", connFails, err)
				}
			}
			continue
		}
		connFails = 0

		for _, f := range resp.Facts {
			seq++
			kf.Items = append(kf.Items, KnowledgeItem{
				ID:          fmt.Sprintf("%s_%02d_ki_%03d", source, chapter, seq),
				ParagraphID: p.ID,
				Page:        p.Page,
				Section:     p.Section,
				Fact:        f.Fact,
				SourceText:  p.Text,
				Difficulty:  f.Difficulty,
				Categories:  f.Categories,
			})
		}

		fmt.Printf("  [%d/%d] %d facts from %s\n", i+1, len(paragraphs), len(resp.Facts), p.ID)
	}

	return kf, nil
}

// hasItems returns true if path is a JSON file with a non-empty "items" array.
func hasItems(path string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	var probe struct {
		Items []json.RawMessage `json:"items"`
	}
	if err := json.Unmarshal(data, &probe); err != nil {
		return false
	}
	return len(probe.Items) > 0
}
