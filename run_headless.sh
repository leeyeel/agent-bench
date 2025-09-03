#!/usr/bin/env bash
#./run_noninteractive.sh -t bench/tests -s claude

set -euo pipefail

TEST_DIR="tests"
SHOW="claude"
CLAUDE_CMD="${CLAUDE_CMD:-claude}"
PYWEN_CMD="${PYWEN_CMD:-pywen}"

usage() {
  echo "Usage: $0 [-t TEST_DIR] [-s SHOW]"
  echo "  SHOW: claude | pywen | both | none"
  exit 1
}

while getopts ":t:s:h" opt; do
  case "$opt" in
    t) TEST_DIR="$OPTARG" ;;
    s) SHOW="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

case "$SHOW" in
  claude|pywen|both|none) ;;
  *) echo "Invalid SHOW=$SHOW"; usage ;;
esac

hr() { printf '\n\033[1;36m%s\033[0m\n' "────────────────────────────────────────────────────────"; }
title() { printf '\033[1;33m%s\033[0m\n' "$*"; }

shopt -s nullglob
tests=("$TEST_DIR"/*.txt)
if (( ${#tests[@]} == 0 )); then
  echo "No *.txt found in $TEST_DIR"
  exit 1
fi

for f in "${tests[@]}"; do
  case_id="$(basename "$f" .txt)"
  prompt="$(cat "$f")"

  hr
  title "[CASE $case_id] $(date -Iseconds)"
  echo -e "Prompt file: $f"
  echo -e "Prompt: $prompt\n"

  run_claude() {
    CLAUDE_CODE_ENABLE_TELEMETRY=0 \
    "$CLAUDE_CMD" -p "$prompt" \
      --dangerously-skip-permissions
  }

  run_pywen() {
    "$PYWEN_CMD" "$prompt"
  }

  case "$SHOW" in
    claude)
      title ">>> Claude Code (visible)"; #run_claude
      title ">>> Pywen (silent)";        run_pywen >/dev/null 2>&1 || true
      ;;
    pywen)
      title ">>> Claude Code (silent)";  run_claude >/dev/null 2>&1 || true
      title ">>> Pywen (visible)";       run_pywen
      ;;
    both)
      title ">>> Claude Code (visible)"; run_claude
      title ">>> Pywen (visible)";       run_pywen
      ;;
    none)
      title ">>> Claude Code (silent)";  run_claude >/dev/null 2>&1 || true
      title ">>> Pywen (silent)";        run_pywen  >/dev/null 2>&1 || true
      ;;
  esac

done

hr
title "ALL DONE."

