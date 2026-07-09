# Initial Pipeline Test Results

First end-to-end run of the question generation pipeline.

## Hardware & Models

| Component | Details |
|-----------|---------|
| GPU 0 (generation) | AMD Radeon (ROCm), serving on `:8090` |
| GPU 1 (cross-check) | AMD Radeon (ROCm), serving on `:8091` |
| Large model | Qwen3-Coder-30B-Instruct (vLLM, `:8090`) |
| Small model | Qwen2.5-3B-Instruct (vLLM, `:8091`) |

## Test Configuration

- **Chapters**: PHAK ch04, AFH ch03, AFH ch06
- **Runs**: 2 (parallel mining + generation, then merge)
- **Merge strategy**: Consensus filtering (question appears in both runs)

## Results

| Stage | Metric | Value |
|-------|--------|-------|
| Input paragraphs | 3 chapters | 268 (142 + 84 + 42) |
| Knowledge items (Run 1) | mined facts | 1,429 (721 + 454 + 254) |
| Knowledge items (Run 2) | mined facts | 1,437 (734 + 457 + 246) |
| Questions generated (Run 1) | per-item | 1,422 (717 + 454 + 251) |
| Questions generated (Run 2) | per-item | 1,433 (732 + 456 + 245) |
| Total clusters | after merge | 2,385 |
| Consensus questions | strong (both runs agree) | 388 (202 + 129 + 57) |
| Cross-check pass | small LLM review | 388/388 (100%) |

## Token Usage

| Endpoint | Model | Tokens |
|----------|-------|--------|
| `:8090` | Qwen3-Coder-30B | ~765K output tokens |
| `:8091` | Qwen2.5-3B | ~28K output tokens |

## Timing

| Phase | Wall clock |
|-------|-----------|
| Mine + generate (2 runs, parallel) | ~5.5 hours |

## Observations

1. **Qwen3 thinking text**: The model sometimes emits `<think>...</think>` blocks inside JSON responses. The pipeline's JSON extraction handles this by stripping content before the first `{`, but it causes occasional parse failures that are retried or skipped.

2. **Conversion ratios**:
   - Paragraphs -> knowledge items: ~5.3x (268 paragraphs -> ~1,430 facts)
   - Knowledge items -> questions: ~99.5% success rate (nearly 1:1)
   - Questions -> consensus: ~16% survive merge (2,855 total -> 388 consensus)
   - Consensus -> cross-check pass: 100% (388/388)

3. **Consensus filtering is aggressive**: Only ~16% of generated questions survive the two-run agreement filter. This is by design -- it selects for questions that are stable across independent generation runs.

4. **Cross-check pass rate**: 100% pass rate suggests the consensus questions are high quality, but also that the small model may not be discriminating enough. Worth monitoring as we scale up.

5. **GPU utilization gap**: Both GPUs sit idle most of the time since all stages run sequentially. Generation only uses `:8090`, cross-check only uses `:8091`.

## Next Steps

- Pipeline generation and cross-checking across both GPUs (producer-consumer pattern)
- Scale to all PHAK and AFH chapters
- Evaluate whether cross-check model needs to be more discriminating
- Increase to 10 runs for stronger consensus signal
