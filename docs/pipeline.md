# Knowledge Extraction Pipeline

Automated pipeline for generating FAA quiz questions directly from handbook PDFs. Scales from ~100 hand-written questions to 500–1000+ grounded questions using LLM-powered extraction with multi-run consensus filtering.

## Architecture

6-stage pipeline — stages 1–2 are deterministic, stages 3–6 use LLMs. All intermediate outputs saved to disk as JSON.

```
PDFs → Extract → Chunk → Mine (LLM) → Generate (LLM) → Cross-check (small LLM) → Validate (large LLM)
       Stage 1   Stage 2  Stage 3      Stage 4          Stage 5                    Stage 6
```

| Stage | Input | Output | LLM? |
|-------|-------|--------|------|
| 1. Extract text | PDF files | Raw text per chapter | No |
| 2. Chunk | Raw text | Paragraph JSON | No |
| 3. Mine knowledge | Paragraphs | Knowledge items | Large LLM |
| 4. Generate questions | Knowledge items | Questions | Large LLM |
| 5. Cross-check | Questions | Flagged issues | Small LLM |
| 6. Validate | Flagged questions | Accepted/rejected | Large LLM |

## Multi-Run Consensus

The core reliability mechanism. Stages 3–4 (mine + generate) run **N times** (default 10) independently, producing separate output directories:

```
runs/
├── run_01/
│   ├── knowledge/phak_ch05.json
│   └── questions/phak_ch05.json
├── run_02/
│   ├── knowledge/phak_ch05.json
│   └── questions/phak_ch05.json
├── ...
└── run_10/
    ├── knowledge/phak_ch05.json
    └── questions/phak_ch05.json
```

A **merge step** compares outputs across all runs:

- Knowledge items that appear in all N runs → high confidence, keep
- Questions where the correct answer agrees across all N runs → high confidence
- Questions where answers diverge → flagged for review

This is **sampling consensus** — if the LLM produces different answers from the same source text across independent runs, the knowledge item is likely ambiguous or poorly grounded in the source material. The disagreement itself is the signal.

### Consensus Thresholds

| Level | Agreement | Action |
|-------|-----------|--------|
| **Strong** | ≥8/10 runs agree | Auto-accept |
| **Weak** | 6–7/10 runs agree | Accept majority answer, flag for review |
| **None** | <6/10 runs agree | Reject — likely ambiguous |

The merge produces final `database/questions/` and `database/knowledge/` files with a `consensus` field showing agreement level.

## Two-LLM Validation Chain

Two separate LLM endpoints reduce correlated errors:

| Role | Endpoint | GPU / Model | Purpose |
|------|----------|-------------|---------|
| Large LLM | `l2:8095` | MI50 32GB (gfx906) | Generation quality — mines knowledge items, generates questions, final validation |
| Small LLM | `l2:8096` | W5700 8GB (gfx1010) | Independent cross-check — different-size model catches errors the large model is blind to |

Both roles run on host `l2` (all inference stays on one machine). The model per role is
whatever `modelMode` selects in `~/nixos/desktop/l2/llama-service.nix` (`large`/`small` tier).

Endpoints are the flag defaults and can be overridden per-run with `--llm-url` / `--small-llm-url`
or the `FAA_LLM_URL` / `FAA_SMALL_LLM_URL` environment variables. The llama.cpp servers
themselves are managed by the NixOS configs on hosts `l` and `l2`, not by this repo.

Using a different model for cross-checking means systematic biases in the generation model don't carry through to validation.

## Output Structure

```
pdfs_text/{source}/ch{NN}.txt                    # Stage 1: raw text
pdfs_text/{source}/ch{NN}_paragraphs.json        # Stage 2: chunked paragraphs
runs/run_{NN}/knowledge/{source}_ch{NN}.json     # Stage 3: knowledge items (per run)
runs/run_{NN}/questions/{source}_ch{NN}.json     # Stage 4: questions (per run)
database/knowledge/{source}_ch{NN}.json          # Merged knowledge items
database/questions/{source}_ch{NN}.json          # Merged questions (final)
```

## Checkpointing and Resume

The pipeline supports per-chapter checkpointing. On restart, it skips completed work automatically.

**How it works:**
- Before mining a chapter, checks if `runs/run_NN/knowledge/source_chNN.json` exists with a non-empty `items` array
- Before generating questions, checks if `runs/run_NN/questions/source_chNN.json` exists with a non-empty `questions` array
- Hollow stubs (files with `"items": null` from a crash) are detected and re-processed

**Flags:**
- `--dry-run` — preview what would be skipped vs processed, without executing
- `--force` — ignore checkpoints and regenerate everything

**Usage:**
```bash
# See what would run
./quiz --pipeline --runs 5 --skip-extract --skip-chunk --dry-run

# Resume from where it left off
./quiz --pipeline --runs 5 --skip-extract --skip-chunk

# Force full regeneration
./quiz --pipeline --runs 5 --skip-extract --skip-chunk --force

# Via Makefile
make pipeline DRY_RUN=--dry-run
make pipeline FORCE=--force
```

## CLI Flags

```
--extract-text          Stage 1: PDFs → text files
--chunk-text            Stage 2: text → paragraphs
--mine                  Stage 3: paragraphs → knowledge items
--generate              Stage 4: knowledge items → questions
--merge                 Merge: compare runs, produce consensus output
--cross-check           Stage 5: small LLM review
--validate              Stage 6: large LLM validation (exists)
--runs N                Number of pipeline runs (default 5)
--run-id N              Run a specific run number (for parallelism)
--llm-url               Large LLM endpoint (default http://l2:8095, env FAA_LLM_URL)
--small-llm-url         Small LLM endpoint (default http://localhost:8090, env FAA_SMALL_LLM_URL)
--dry-run               Show what would be done without executing
--force                 Force regeneration of existing output files
--skip-extract          Skip text extraction stage
--skip-chunk            Skip text chunking stage
--chapters              Filter chapters (e.g. phak:04,afh:03)
```

## Paragraph Chunking Rules

Deterministic, no LLM. Applied in stage 2.

1. Split on double-newline boundaries
2. Detect section headers (ALL CAPS or Title Case before blank line)
3. Track current page label from `--- Page X-Y ---` markers
4. Skip figure captions and page footers
5. Merge short fragments (< 50 chars) into previous paragraph
6. Split very long paragraphs (> 2000 chars) at sentence boundaries

## Schemas

### Knowledge Item

```json
{
  "id": "phak_05_ki_001",
  "paragraph_id": "phak_05_001",
  "page": "5-2",
  "section": "Forces Acting on the Aircraft",
  "fact": "The four forces acting on an aircraft in flight are lift, weight, thrust, and drag.",
  "source_text": "verbatim paragraph from handbook",
  "difficulty": 1,
  "categories": ["written_exam", "general_knowledge"]
}
```

### Question

Same as the current `SeedQuestion` format. The `reference` field is pre-populated at generation time since the source text and page number are already known from the knowledge item.

### Merge Consensus

```json
{
  "question": "What are the four forces acting on an aircraft in flight?",
  "correct_answer": "Lift, weight, thrust, and drag",
  "consensus": {
    "runs": 10,
    "agreement": 10,
    "level": "strong"
  }
}
```

## Estimated Yield

| Stage | Count |
|-------|-------|
| Source chapters | ~35 |
| Knowledge items per chapter | ~20 |
| Raw questions | ~700 |
| After consensus filtering (reject ~10–15% ambiguous) | ~600 |
| After cross-check + validation | **500–550 final** |

## Implementation Files

```
internal/extractor/chunk.go        # paragraph chunking
internal/extractor/save.go         # save text/chunks to disk
internal/generator/mine.go         # LLM knowledge item extraction
internal/generator/generate.go     # LLM question generation
internal/generator/crosscheck.go   # small LLM cross-validation
internal/generator/merge.go        # multi-run consensus merge
```

## Makefile Targets

```makefile
RUNS ?= 5
FORCE ?=
DRY_RUN ?=

pipeline: build
	$(NIX_RUN) ./quiz --pipeline --runs $(RUNS) $(FORCE) $(DRY_RUN)

extract-text: build
	$(NIX_RUN) ./quiz --extract-text

chunk-text: build
	$(NIX_RUN) ./quiz --chunk-text

mine-all: build
	@for i in $$(seq 1 $(RUNS)); do \
	  $(NIX_RUN) ./quiz --mine --generate --run-id $$i; \
	done

merge: build
	$(NIX_RUN) ./quiz --merge --runs $(RUNS)

cross-check: build
	$(NIX_RUN) ./quiz --cross-check

validate: build
	$(NIX_RUN) ./quiz --validate
```

## Pipeline Run Example

Full pipeline from PDFs to final questions:

```bash
# 1. Extract text from PDFs
make extract-text

# 2. Chunk into paragraphs
make chunk-text

# 3. Run knowledge mining + question generation 10 times
make mine-all RUNS=10

# 4. Merge runs with consensus filtering
make merge RUNS=10

# 5. Cross-check with small LLM
make cross-check

# 6. Final validation with large LLM
make validate

# Or run the full pipeline:
make pipeline RUNS=10
```
