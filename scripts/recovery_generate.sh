#!/usr/bin/env bash
# One-off recovery run after the tunnel drop:
#   1. re-mine AFH ch18 (zeroed by the drop)
#   2. exclude spurious mis-detected chapters (phak_ch26 / phak_ch35)
#   3. capped generation (~18 q/chapter) over the cached knowledge
#   4. merge run 1 -> database/questions
#   5. GLM-verify each question file
# Mining for the other 34 chapters is cached and reused.
set -uo pipefail
cd "$(dirname "$0")/.."

export FAA_LLM_URL="${FAA_LLM_URL:-http://localhost:8000}"
export FAA_LLM_MODEL="${FAA_LLM_MODEL:-/model}"
export FAA_LLM_THINK="${FAA_LLM_THINK:-1}"
quiz=./quiz
cap="${GEN_CAP:-18}"

echo "=== recovery: GLM $FAA_LLM_URL model=$FAA_LLM_MODEL think=$FAA_LLM_THINK cap=$cap ==="

echo "=== Step 1: re-mine AFH ch18 (--force) ==="
"$quiz" --mine --run-id 1 --chapters afh:18 --force || { echo "re-mine afh18 failed"; exit 1; }

echo "=== Step 2: set aside spurious chapters ==="
mkdir -p runs/run_01/knowledge_excluded
for c in phak_ch26 phak_ch35; do
  [ -f "runs/run_01/knowledge/$c.json" ] && mv "runs/run_01/knowledge/$c.json" runs/run_01/knowledge_excluded/ && echo "  excluded $c"
done

echo "=== Step 3: capped generation (cap=$cap) ==="
"$quiz" --generate --run-id 1 --gen-cap "$cap" --small-llm-url "" || { echo "generation aborted (server down?)"; exit 1; }

echo "=== Step 4: merge run 1 -> database/questions ==="
"$quiz" --merge --runs 1 || { echo "merge failed"; exit 1; }

echo "=== Step 5: GLM-verify each question file ==="
for f in database/questions/*.json; do
  echo "--- verify $f ---"
  if ! "$quiz" --validate --fix --file "$f"; then
    echo "verify aborted on $f (server down?) — stopping"; exit 1
  fi
done

echo "=== recovery complete ==="
