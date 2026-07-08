# Pipeline Test Run 2 — Pre-Full-Run Validation

Second end-to-end test of the pipeline, validating the `--pipeline` orchestration flag before launching the full 35-chapter, 10-run production run.

## Changes Since Test Run 1

1. **`--pipeline` flag**: Single command orchestrates all stages sequentially, replacing the Makefile target chain.
2. **`nix run .#pipeline`**: Nix app entry point wraps `quiz --pipeline`.
3. **Parallel generation + cross-check**: `GenerateAndCheck` uses a goroutine pipeline — large LLM generates while small LLM cross-checks concurrently, keeping both GPUs busy.
4. **`--chapters` filter**: Limits mining/generation to specific chapters (e.g. `--chapters phak:04`) for targeted testing.
5. **Resume flags**: `--skip-extract`, `--skip-chunk`, `--start-run N` allow resuming a failed run without repeating earlier stages.
6. **Qwen3 `reasoning_content` fix**: Qwen3 models put JSON output in `reasoning_content` instead of `content`. The LLM client now falls back to `reasoning_content` when `content` is empty.

## Hardware & Models

| Component | Details |
|-----------|---------|
| GPU 0 (large, generation + validation) | AMD MI50 32GB (gfx906), `:8090` |
| GPU 1 (small, cross-check) | AMD W7500 8GB (gfx1102), `:8091` |
| Large model | Qwen3-30B-A3B-Instruct (llama.cpp, `:8090`) |
| Small model | Qwen2.5-7B-Instruct Q5_K_M (llama.cpp, `:8091`) |

## Test Configuration

- **Chapter**: PHAK ch04 only (`--chapters phak:04`)
- **Runs**: 2
- **Command**: `nix develop --command ./quiz --pipeline --runs 2 --chapters phak:04 --skip-extract --skip-chunk`
- **Text extraction/chunking**: Skipped (reused from test run 1)

## Results

| Stage | Metric | Value |
|-------|--------|-------|
| Input paragraphs | PHAK ch04 | 42 |
| Knowledge items (Run 1) | mined facts | 272 |
| Knowledge items (Run 2) | mined facts | ~270 (similar) |
| Questions generated (Run 1) | after cross-check | 234 passed |
| Questions generated (Run 2) | after cross-check | 233 passed |
| Merged questions | consensus filtering | 71 |
| Final validation | all `database/questions/` | 414/472 passed (88%) |

## Observations

1. **Both GPUs utilized concurrently**: The parallel pipeline works — `[gen]` and `[chk]` lines interleave in the output, confirming the large GPU generates while the small GPU cross-checks simultaneously.

2. **Qwen3 reasoning_content**: The fix works. All 272 knowledge items mined successfully per run (vs. 0 before the fix when `content` was empty).

3. **Conversion ratios** (PHAK ch04):
   - Paragraphs -> knowledge items: 6.5x (42 -> 272)
   - Knowledge items -> cross-check pass: 86% (272 -> 234)
   - Two-run consensus: 30% of per-run questions survive merge (234 -> 71)

4. **Cross-check is more discriminating**: With Qwen2.5-7B (vs. Qwen2.5-3B in test run 1), the cross-check now rejects ~14% of generated questions. This is an improvement over the 0% rejection rate in test run 1.

5. **Validation failures**: 58/472 failures in the validate stage are mostly reference_text mismatches in pre-existing question files (other chapters), not in the newly generated ch04 questions. These are from the original hand-written question set.

6. **W7500 service fix**: The NixOS llama-cpp service for the W7500 was crash-looping because `hfFile` pointed to `qwen2.5-7b-instruct-q5_k_m.gguf` (doesn't exist — it's a split file). Fixed to `qwen2.5-7b-instruct-q5_k_m-00001-of-00002.gguf`.

## Ready for Full Run

The pipeline is validated. Next step:

```bash
nix run .#pipeline -- --runs 10
```

This will process all 35 chapters (17 PHAK + 18 AFH) with 10 independent runs for consensus filtering. Expected output: 500-1000+ validated questions.
