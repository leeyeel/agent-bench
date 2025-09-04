#!/usr/bin/env bash
#   Ctrl-b S   切换“同步输入”开/关
#   Ctrl-b ←/→ 在左右 pane 切换焦点
#   :kill-session 或 Ctrl-d 退出

set -euo pipefail

SESSION="${SESSION:-PYWEN_CLAUDE_SBS}"
TEST_DIR="tests"
CLAUDE_CMD="${CLAUDE_CMD:-claude --dangerously-skip-permissions}"
PYWEN_CMD="${PYWEN_CMD:-pywen}"

FIFO_DIR="${FIFO_DIR:-/tmp/agent-done}"
CLAUDE_FIFO="$FIFO_DIR/claude.done"
PYWEN_FIFO="$FIFO_DIR/pywen.done"

mkdir -p "$FIFO_DIR"
[[ -p "$CLAUDE_FIFO" ]] || mkfifo "$CLAUDE_FIFO"
[[ -p "$PYWEN_FIFO"  ]] || mkfifo "$PYWEN_FIFO"

usage() {
  cat <<EOF
Usage: $0 [-t TEST_DIR] [-d SECONDS] [-s]
  -t TEST_DIR   测试用例目录（默认：$TEST_DIR）
  -d SECONDS    自动模式下每条用例提交后等待秒数（默认：$DELAY）
  -s            step 模式：每条用例提交前等待你按 Enter
环境变量可覆盖：
  SESSION, CLAUDE_CMD, PYWEN_CMD
EOF
  exit 1
}

while getopts ":t:d:sh" opt; do
  case "$opt" in
    t) TEST_DIR="$OPTARG" ;;
    d) DELAY="$OPTARG" ;;
    s) STEP=1 ;;
    h|*) usage ;;
  esac
done

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux new-session -d -s "$SESSION" \
    "CLAUDE_CODE_ENABLE_TELEMETRY=0 $CLAUDE_CMD"

  tmux split-window -h -t "$SESSION" \
    "PYWEN_AUTO_CONFIRM=1 $PYWEN_CMD"

  tmux select-layout -t "$SESSION" even-horizontal
  tmux set-option -t "$SESSION" mouse on
  tmux set-option -t "$SESSION" pane-border-status top
  tmux set-option -t "$SESSION" pane-border-format " #[bold]#P » #{pane_current_command}"
  tmux set-option -t "$SESSION" status-position top

  tmux setw -t "$SESSION" synchronize-panes on
  tmux bind-key S setw synchronize-panes
fi

tmux select-pane -t "$SESSION:.+0"

shopt -s nullglob
tests=("$TEST_DIR"/*.txt)
if (( ${#tests[@]} == 0 )); then
  echo "No *.txt found in $TEST_DIR"
  exec tmux attach -t "$SESSION"
fi

echo "会话：$SESSION"
echo "用例目录：$TEST_DIR"
echo "—— 将依次发送每个用例，并等待双方 DONE 信号 ——"
sleep 1

wait_one_done() {
  local fifo="$1"; local case_id="$2"
  while IFS= read -r line < "$fifo"; do
    [[ "$line" == "$case_id DONE" ]] && return 0
  done
}

for f in "${tests[@]}"; do
  case_id="$(basename "$f")"

  printf "\n[CASE] %s\n" "$case_id"

  tmux send-keys -t "$SESSION" "CASE_ID=$case_id" Enter

  tmux load-buffer -t "$SESSION" - < "$f"
  tmux paste-buffer -t "$SESSION"
  tmux send-keys -t "$SESSION" Enter

  wait_one_done "$CLAUDE_FIFO" "$case_id"
  wait_one_done "$PYWEN_FIFO"  "$case_id"

  echo "[DONE] $case_id"
done

echo -e "\n全部用例完成，进入会话（Ctrl-b S 切同步输入，Ctrl-b ←/→ 切 pane）..."
exec tmux attach -t "$SESSION"
