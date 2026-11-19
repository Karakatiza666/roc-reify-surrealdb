#!/usr/bin/env bash
# The release-build budget: an app with QUERIES prepared queries (default
# 400), built with `--opt=speed`, must build in LIMIT seconds (default 60).
# Before the `Box` payload and `prepared_request` (src/Surreal.roc), the
# build time grew faster than the count of queries: 400 took 200 to 255 s.
# With them, it takes about 30 s.
# Usage: ROC=/path/to/roc [QUERIES=400] [LIMIT=60] scripts/build_budget.sh
# Slow (half a minute), so scripts/all_tests.sh runs it only with BUILD_BUDGET=1.
set -euo pipefail
ROC="${ROC:-roc}"
QUERIES="${QUERIES:-400}"
LIMIT="${LIMIT:-60}"
cd "$(dirname "$0")/.."
export ROC_CACHE_DIR="${ROC_CACHE_DIR:-$PWD/.cache/roc}"
work="$PWD/.tmp/budget"
rm -rf "$work"
mkdir -p "$work/app" "$ROC_CACHE_DIR"

python3 scripts/gen_budget.py "$QUERIES" "$work/app/budget.roc" ../../../src/internal.roc
# Fetch the dependencies first, so that the time limit is only the build.
"$ROC" check "$work/app/budget.roc" >"$work/check.log" 2>&1 || {
	cat "$work/check.log" >&2
	exit 1
}

start=$(date +%s)
status=0
timeout "$LIMIT" "$ROC" build --opt=speed --output="$work/budget" "$work/app/budget.roc" >"$work/build.log" 2>&1 || status=$?
secs=$(($(date +%s) - start))
if [ "$status" = 124 ]; then
	echo "build budget: $QUERIES queries did not build in ${LIMIT}s" >&2
	exit 1
fi
# Exit code 2 is a build with warnings; there must be none.
if [ "$status" != 0 ]; then
	cat "$work/build.log" >&2
	echo "build budget: the build failed (exit $status)" >&2
	exit 1
fi

# Each query prints its script (with no newline at the end); none may be
# an error.
"$work/budget" >"$work/out.txt"
scripts=$(grep -o 'SELECT ' "$work/out.txt" | wc -l)
if grep -q 'error: ' "$work/out.txt" || [ "$scripts" != "$QUERIES" ]; then
	grep -o -m3 'error: .\{0,200\}' "$work/out.txt" >&2 || true
	echo "build budget: expected $QUERIES scripts, got $scripts" >&2
	exit 1
fi
echo "build budget: $QUERIES queries built in ${secs}s (limit ${LIMIT}s)"
