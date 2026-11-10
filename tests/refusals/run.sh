#!/usr/bin/env bash
# Each `.roc` file here must fail to compile, at the line and with the
# text that its first two lines give:
#   # refused-at: <line>
#   # message: <text>
# Usage: ROC=/path/to/roc tests/refusals/run.sh
set -uo pipefail
ROC="${ROC:-roc}"
# A relative path to roc is from the folder the script was started in.
case "$ROC" in */*) ROC="$(realpath "$ROC")" ;; esac
cd "$(dirname "$0")"
failures=0
for f in *.roc; do
	line=$(sed -n '1s/^# refused-at: //p' "$f")
	message=$(sed -n '2s/^# message: //p' "$f")
	out=$("$ROC" check "$f" 2>&1)
	if [ $? -eq 0 ]; then
		echo "FAIL $f: it compiled"
		failures=$((failures + 1))
	elif ! grep -qF "$f:$line:" <<<"$out"; then
		echo "FAIL $f: no error at line $line"
		grep -F "── " <<<"$out" | head -5
		failures=$((failures + 1))
	elif ! grep -qF "$message" <<<"$out"; then
		echo "FAIL $f: no \"$message\" in the report"
		failures=$((failures + 1))
	else
		echo "ok   $f: refused at line $line"
	fi
done
exit $((failures > 0))
