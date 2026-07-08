package pipeline

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"unicode"
)

// Paragraph represents a chunked paragraph from a chapter.
type Paragraph struct {
	ID      string `json:"id"`      // "phak_05_001"
	Page    string `json:"page"`    // "5-2"
	Section string `json:"section"` // "Forces Acting on the Aircraft"
	Text    string `json:"text"`
}

var (
	pageMarker    = regexp.MustCompile(`^--- Page (\d+-\d+) ---$`)
	figureCaption = regexp.MustCompile(`(?i)^Figure\s+\d+-\d+\.`)
)

// ChunkText reads extracted text files and writes paragraph JSON for each chapter.
func ChunkText(textDir string) error {
	for _, source := range []string{"phak", "afh"} {
		sourceDir := filepath.Join(textDir, source)
		entries, err := filepath.Glob(filepath.Join(sourceDir, "ch*.txt"))
		if err != nil {
			return fmt.Errorf("glob %s: %w", sourceDir, err)
		}

		for _, path := range entries {
			// Extract chapter number from filename
			base := filepath.Base(path)
			var chNum int
			if _, err := fmt.Sscanf(base, "ch%d.txt", &chNum); err != nil {
				continue
			}

			data, err := os.ReadFile(path)
			if err != nil {
				return fmt.Errorf("read %s: %w", path, err)
			}

			paragraphs := ChunkChapter(source, chNum, string(data))
			outPath := filepath.Join(sourceDir, fmt.Sprintf("ch%02d_paragraphs.json", chNum))

			out, err := json.MarshalIndent(paragraphs, "", "  ")
			if err != nil {
				return fmt.Errorf("marshal %s: %w", outPath, err)
			}
			out = append(out, '\n')

			if err := os.WriteFile(outPath, out, 0644); err != nil {
				return fmt.Errorf("write %s: %w", outPath, err)
			}
			fmt.Printf("  %s (%d paragraphs)\n", outPath, len(paragraphs))
		}
	}
	return nil
}

// ChunkChapter splits chapter text into paragraphs with metadata.
func ChunkChapter(source string, chapter int, text string) []Paragraph {
	blocks := strings.Split(text, "\n\n")

	var paragraphs []Paragraph
	currentPage := ""
	currentSection := ""
	seq := 0

	for _, block := range blocks {
		block = strings.TrimSpace(block)
		if block == "" {
			continue
		}

		// Handle lines within a block — check for page markers and headers
		lines := strings.Split(block, "\n")
		var contentLines []string
		for _, line := range lines {
			trimmed := strings.TrimSpace(line)

			// Check for page marker
			if m := pageMarker.FindStringSubmatch(trimmed); m != nil {
				currentPage = m[1]
				continue
			}

			// Skip figure captions
			if figureCaption.MatchString(trimmed) {
				continue
			}

			// Detect section headers: ALL CAPS or Title Case, reasonable length
			if isSectionHeader(trimmed) {
				currentSection = trimmed
				continue
			}

			contentLines = append(contentLines, line)
		}

		content := strings.TrimSpace(strings.Join(contentLines, "\n"))
		if content == "" {
			continue
		}

		// Merge short fragments into previous paragraph
		if len(content) < 50 && len(paragraphs) > 0 {
			paragraphs[len(paragraphs)-1].Text += " " + content
			continue
		}

		// Split very long paragraphs
		if len(content) > 2000 {
			parts := splitLongParagraph(content)
			for _, part := range parts {
				seq++
				paragraphs = append(paragraphs, Paragraph{
					ID:      fmt.Sprintf("%s_%02d_%03d", source, chapter, seq),
					Page:    currentPage,
					Section: currentSection,
					Text:    part,
				})
			}
			continue
		}

		seq++
		paragraphs = append(paragraphs, Paragraph{
			ID:      fmt.Sprintf("%s_%02d_%03d", source, chapter, seq),
			Page:    currentPage,
			Section: currentSection,
			Text:    content,
		})
	}

	return paragraphs
}

// isSectionHeader returns true if the line looks like a section header.
func isSectionHeader(s string) bool {
	if len(s) <= 3 || len(s) >= 120 {
		return false
	}
	// Skip lines that look like regular sentences (contain periods mid-text)
	if strings.Count(s, ".") > 1 {
		return false
	}
	// ALL CAPS check
	if s == strings.ToUpper(s) && strings.ContainsAny(s, "ABCDEFGHIJKLMNOPQRSTUVWXYZ") {
		return true
	}
	// Title Case check: majority of words start with uppercase
	words := strings.Fields(s)
	if len(words) < 2 {
		return false
	}
	upperCount := 0
	for _, w := range words {
		if len(w) > 0 && unicode.IsUpper(rune(w[0])) {
			upperCount++
		}
	}
	// At least 60% of words capitalized (allows for "of", "the", "and")
	return float64(upperCount)/float64(len(words)) >= 0.6
}

// splitLongParagraph splits text > 2000 chars at the nearest ". " after midpoint.
func splitLongParagraph(text string) []string {
	if len(text) <= 2000 {
		return []string{text}
	}

	mid := len(text) / 2
	idx := strings.Index(text[mid:], ". ")
	if idx == -1 {
		// No good split point, return as-is
		return []string{text}
	}

	splitAt := mid + idx + 1 // include the period
	parts := []string{strings.TrimSpace(text[:splitAt])}

	rest := strings.TrimSpace(text[splitAt:])
	if len(rest) > 2000 {
		parts = append(parts, splitLongParagraph(rest)...)
	} else if rest != "" {
		parts = append(parts, rest)
	}

	return parts
}
