#!/usr/bin/env bash
# The local checks. Usage: ROC=/path/to/roc scripts/all_tests.sh
# When SurrealDB answers on 127.0.0.1:8000 (root/root), also runs
# tests/check.py, which runs the scripts the examples print against it.
# Start one with:
#   docker run --rm -d --name surreal-roc -p 8000:8000 surrealdb/surrealdb:v3.3.4 start --user root --pass root memory
set -euo pipefail
ROC="${ROC:-roc}"
cd "$(dirname "$0")/.."
# Keep the roc cache inside the repository.
export ROC_CACHE_DIR="${ROC_CACHE_DIR:-$PWD/.cache/roc}"
mkdir -p "$ROC_CACHE_DIR"

"$ROC" version
# The public package, and the internal one that only the tests use.
"$ROC" check src/main.roc
"$ROC" check src/internal.roc
# The expects next to the code.
"$ROC" test src/main.roc
# Every example must check.
for f in examples/*.roc; do
	"$ROC" check "$f"
done
# The tests: apps with expects and no main!, so `roc check` does not apply to
# them; `roc test` checks and runs them, over the internal modules and the
# recorded fixtures.
for f in tests/*Test.roc; do
	"$ROC" test "$f"
done
# The examples against a live SurrealDB.
if (: >/dev/tcp/127.0.0.1/8000) 2>/dev/null; then
	SURREAL_URL="${SURREAL_URL:-http://127.0.0.1:8000}" python3 -I tests/check.py "$ROC"
else
	echo "SurrealDB not on 127.0.0.1:8000: tests/check.py skipped"
fi
