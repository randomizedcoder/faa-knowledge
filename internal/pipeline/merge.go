package pipeline

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unicode"

	"github.com/das/faa-knowledge/internal/importer"
)

// ConsensusInfo records agreement across runs for a question.
type ConsensusInfo struct {
	Runs      int    `json:"runs"`
	Agreement int    `json:"agreement"`
	Level     string `json:"level"` // "strong", "weak", "none"
}

// MergeReport summarizes the merge results.
type MergeReport struct {
	TotalCandidates int
	StrongConsensus int
	WeakConsensus   int
	NoConsensus     int
	FinalAccepted   int
}

type clusterEntry struct {
	question importer.SeedQuestion
	runID    int
}

// Merge compares question outputs across runs and produces consensus-filtered output.
func Merge(numRuns int, outputDir string) (*MergeReport, error) {
	// Group all questions by source+chapter across runs
	type chapterKey struct {
		source  string
		chapter int
	}
	allQuestions := make(map[chapterKey][]clusterEntry)

	for run := 1; run <= numRuns; run++ {
		questionsDir := filepath.Join("runs", fmt.Sprintf("run_%02d", run), "questions")
		entries, err := filepath.Glob(filepath.Join(questionsDir, "*.json"))
		if err != nil {
			continue
		}

		for _, path := range entries {
			data, err := os.ReadFile(path)
			if err != nil {
				fmt.Printf("Warning: could not read %s: %v\n", path, err)
				continue
			}

			var sf importer.SeedFile
			if err := json.Unmarshal(data, &sf); err != nil {
				fmt.Printf("Warning: could not parse %s: %v\n", path, err)
				continue
			}

			key := chapterKey{source: sf.Source, chapter: sf.Chapter}
			for _, q := range sf.Questions {
				allQuestions[key] = append(allQuestions[key], clusterEntry{question: q, runID: run})
			}
		}
	}

	report := &MergeReport{}

	for key, entries := range allQuestions {
		clusters := clusterQuestions(entries)
		report.TotalCandidates += len(clusters)

		var accepted []importer.SeedQuestion
		for _, cluster := range clusters {
			// Count distinct runs
			runs := make(map[int]bool)
			for _, e := range cluster {
				runs[e.runID] = true
			}
			agreement := len(runs)

			// Scale thresholds proportionally to number of runs
			strongThresh := max(2, (numRuns*80+99)/100) // >=80% agreement
			weakThresh := max(2, (numRuns*60+99)/100)   // >=60% agreement

			var level string
			switch {
			case agreement >= strongThresh:
				level = "strong"
				report.StrongConsensus++
			case agreement >= weakThresh:
				level = "weak"
				report.WeakConsensus++
			default:
				level = "none"
				report.NoConsensus++
				continue // reject
			}

			// Pick the best variant (longest explanation as a heuristic)
			best := cluster[0].question
			for _, e := range cluster[1:] {
				if len(e.question.Explanation) > len(best.Explanation) {
					best = e.question
				}
			}

			_ = level // consensus info available if needed later
			accepted = append(accepted, best)
		}

		if len(accepted) == 0 {
			continue
		}

		report.FinalAccepted += len(accepted)

		sf := importer.SeedFile{
			Source:    key.source,
			Chapter:  key.chapter,
			Questions: accepted,
		}

		if err := os.MkdirAll(outputDir, 0755); err != nil {
			return nil, fmt.Errorf("mkdir %s: %w", outputDir, err)
		}

		outPath := filepath.Join(outputDir, fmt.Sprintf("%s_ch%02d.json", strings.ToLower(key.source), key.chapter))
		out, err := json.MarshalIndent(sf, "", "  ")
		if err != nil {
			return nil, fmt.Errorf("marshal: %w", err)
		}
		out = append(out, '\n')

		if err := os.WriteFile(outPath, out, 0644); err != nil {
			return nil, fmt.Errorf("write %s: %w", outPath, err)
		}
	}

	return report, nil
}

// clusterQuestions groups similar questions using text similarity.
func clusterQuestions(entries []clusterEntry) [][]clusterEntry {
	var clusters [][]clusterEntry
	used := make([]bool, len(entries))

	for i := range entries {
		if used[i] {
			continue
		}
		cluster := []clusterEntry{entries[i]}
		used[i] = true

		keyA := NormalizeText(entries[i].question.Question + " " + entries[i].question.CorrectAnswer)

		for j := i + 1; j < len(entries); j++ {
			if used[j] {
				continue
			}
			keyB := NormalizeText(entries[j].question.Question + " " + entries[j].question.CorrectAnswer)
			if SimilarityScore(keyA, keyB) >= 0.8 {
				cluster = append(cluster, entries[j])
				used[j] = true
			}
		}

		clusters = append(clusters, cluster)
	}

	return clusters
}

// NormalizeText lowercases and removes non-alphanumeric characters for comparison.
func NormalizeText(s string) string {
	s = strings.ToLower(s)
	var b strings.Builder
	for _, r := range s {
		if unicode.IsLetter(r) || unicode.IsDigit(r) || r == ' ' {
			b.WriteRune(r)
		}
	}
	return strings.Join(strings.Fields(b.String()), " ")
}

// SimilarityScore returns a 0.0-1.0 similarity score based on Levenshtein distance.
func SimilarityScore(a, b string) float64 {
	if a == b {
		return 1.0
	}
	maxLen := len(a)
	if len(b) > maxLen {
		maxLen = len(b)
	}
	if maxLen == 0 {
		return 1.0
	}
	dist := levenshtein(a, b)
	return 1.0 - float64(dist)/float64(maxLen)
}

// levenshtein computes the edit distance between two strings.
func levenshtein(a, b string) int {
	la, lb := len(a), len(b)
	if la == 0 {
		return lb
	}
	if lb == 0 {
		return la
	}

	// Use two rows for space efficiency
	prev := make([]int, lb+1)
	curr := make([]int, lb+1)

	for j := 0; j <= lb; j++ {
		prev[j] = j
	}

	for i := 1; i <= la; i++ {
		curr[0] = i
		for j := 1; j <= lb; j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			curr[j] = min(curr[j-1]+1, min(prev[j]+1, prev[j-1]+cost))
		}
		prev, curr = curr, prev
	}

	return prev[lb]
}

// PrintMergeReport prints a summary of the merge results.
func PrintMergeReport(report *MergeReport) {
	fmt.Println("\n=== Merge Report ===")
	fmt.Printf("Total question clusters: %d\n", report.TotalCandidates)
	fmt.Printf("Strong consensus (>=80%%): %d\n", report.StrongConsensus)
	fmt.Printf("Weak consensus (>=60%%):   %d\n", report.WeakConsensus)
	fmt.Printf("No consensus:             %d\n", report.NoConsensus)
	fmt.Printf("Final accepted:           %d\n", report.FinalAccepted)
}
