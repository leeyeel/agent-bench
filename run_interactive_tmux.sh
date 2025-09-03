#!/usr/bin/env bash
# ./run_interactive_tmux.sh -t tests -s both --attach

set -euo pipefail

TEST_DIR="tests"
SHOW="claude"                               
CLAUDE_CMD="${CLAUDE_CMD:-claude}"          
PYWEN_CMD="${PYWEN_CMD:-pywen}"
ATTACH=0
WAIT_SEC=6

usage() {
  cat <<EOF
Usage: $0 [-t TEST_DIR] [-s SHOW] [--attach] [--wait N]

Options:
  -t TEST_DIR   用例目录（默认: $TEST_DIR）
  -s SHOW       可见输出：claude | pywen | both | none（默认: $SHOW）
  --attach      对每条用例都 attach 到 Claude 的 tmux（看 TUI，手动 Ctrl-b d 退出继续）
  --wait N      不 attach 时，每条用例注入后等待 N 秒（默认: $WAIT_SEC）
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t) TEST_DIR="$2"; shift 2 ;;
    -s) SHOW="$2"; shift 2 ;;
    --attach) ATTACH=1; shift ;;
    --wait) WAIT_SEC="${2:-6}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

case "$SHOW" in
  claude|pywen|both|none) ;;
  *) echo "Invalid SHOW=$SHOW"; usage ;;
esac

hr()    { printf '\n\033[1;36m%s\033[0m\n' "────────────────────────────────────────────────────────"; }
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
  session="CC_${case_id}"

  hr
  title "[CASE $case_id] $(date -Iseconds)"
  echo -e "Prompt: $f\n"
  echo -e "Prompt: $prompt\n"

  if ! tmux has-session -t "$session" 2>/dev/null; then
    tmux new-session -d -s "$session" \
      "CLAUDE_CODE_ENABLE_TELEMETRY=0 $CLAUDE_CMD"
    sleep 1.0
  fi

  tmux send-keys -t "$session" "$prompt" Enter

  if [[ "$SHOW" == "claude" || "$SHOW" == "both" ]]; then
    if (( ATTACH == 1 )); then
      title ">>> Claude Code (tmux attach: $session)"
      tmux attach -t "$session"
    else
      sleep "$WAIT_SEC"
      echo "(Claude running in tmux session: $session; use: tmux attach -t $session)"
    fi
  fi

  run_pywen() {
    "$PYWEN_CMD"
  }

  case "$SHOW" in
    pywen)
      title ">>> Pywen (visible)"
      run_pywen
      ;;
    both)
      title ">>> Pywen (visible)"
      run_pywen
      ;;
    claude|none)
      run_pywen >/dev/null 2>&1 || true
      ;;
  esac

done

hr
title "ALL DONE."
echo "备注：未保存任何输出/屏幕快照。Claude 的 TUI 会话可随时用 'tmux attach -t CC_<case>' 查看。"

