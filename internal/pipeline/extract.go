package pipeline

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/das/faa-knowledge/internal/extractor"
)

// pdfSources maps PDF filenames to their source codes.
var pdfSources = map[string]string{
	"phak.pdf": "phak",
	"afh.pdf":  "afh",
}

// ExtractText extracts chapter text from both PDFs and writes pdfs_text/{source}/ch{NN}.txt
func ExtractText(pdfDir, outDir string) error {
	for pdfFile, source := range pdfSources {
		pdfPath := filepath.Join(pdfDir, pdfFile)
		if _, err := os.Stat(pdfPath); os.IsNotExist(err) {
			fmt.Printf("Skipping %s (not found)\n", pdfPath)
			continue
		}

		fmt.Printf("Extracting %s...\n", pdfPath)
		pages, err := extractor.ExtractPages(pdfPath)
		if err != nil {
			return fmt.Errorf("extract %s: %w", pdfPath, err)
		}

		chapters := extractor.SplitChapters(pages)
		sourceDir := filepath.Join(outDir, source)
		if err := os.MkdirAll(sourceDir, 0755); err != nil {
			return fmt.Errorf("mkdir %s: %w", sourceDir, err)
		}

		for chNum, chPages := range chapters {
			text := chapterTextFromPages(chPages)
			outPath := filepath.Join(sourceDir, fmt.Sprintf("ch%02d.txt", chNum))
			if err := os.WriteFile(outPath, []byte(text), 0644); err != nil {
				return fmt.Errorf("write %s: %w", outPath, err)
			}
			fmt.Printf("  %s (%d pages)\n", outPath, len(chPages))
		}
	}

	return nil
}

func chapterTextFromPages(pages []extractor.Page) string {
	var b strings.Builder
	for _, p := range pages {
		label := extractor.DetectPageLabel(p.Text)
		if label != "" {
			fmt.Fprintf(&b, "\n--- Page %s ---\n", label)
		}
		b.WriteString(p.Text)
		b.WriteString("\n")
	}
	return b.String()
}
