#!/usr/bin/env bash
#   Ctrl-b S   切换“同步输入”开/关
#   Ctrl-b ←/→ 在左右 pane 切换焦点
#   :kill-session 或 Ctrl-d 退出

set -euo pipefail

SESSION="${SESSION:-PYWEN_CLAUDE_SBS}"
TEST_DIR="tests"
DELAY=30  # 自动模式下，每条用例提交后等待的秒数
STEP=0    # 1=逐条确认模式（按 Enter 才发下一条）
MODEL="${MODEL:-claude-3-5-sonnet-20241022}"
CLAUDE_CMD="${CLAUDE_CMD:-claude --dangerously-skip-permissions --model $MODEL}"
PYWEN_CMD="${PYWEN_CMD:-pywen}"

usage() {
  cat <<EOF
Usage: $0 [-t TEST_DIR] [-d SECONDS] [-s]
  -t TEST_DIR   测试用例目录（默认：$TEST_DIR）
  -d SECONDS    自动模式下每条用例提交后等待秒数（默认：$DELAY）
  -s            step 模式：每条用例提交前等待你按 Enter
环境变量可覆盖：
  SESSION, MODEL, CLAUDE_CMD, PYWEN_CMD
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
echo "模式：$([[ $STEP -eq 1 ]] && echo step/手动 || echo auto/${DELAY}s)"
echo "提示：进入 tmux 后可用 Ctrl-b S 切换同步输入"
sleep 1

for f in "${tests[@]}"; do
  case_id="$(basename "$f")"
  if [[ $STEP -eq 1 ]]; then
    read -r -p $'\n[按 Enter 发送] '"$case_id"$' ...'
  else
    printf '\n[发送] %s ...\n' "$case_id"
  fi

  tmux load-buffer -t "$SESSION" - < "$f"
  tmux paste-buffer -t "$SESSION"

  tmux send-keys -t "$SESSION" Enter

  if [[ $STEP -eq 0 ]]; then
    sleep "$DELAY"
  fi
done

echo -e "\n全部用例已发送。即将进入会话（Ctrl-b S 切换同步输入，Ctrl-b → 切 pane）。"
exec tmux attach -t "$SESSION"

