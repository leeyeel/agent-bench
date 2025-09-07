#!/usr/bin/env bash
#   Ctrl-b S   切换“同步输入”开/关
#   Ctrl-b ←/→ 在左右 pane 切换焦点
#   :kill-session 或 Ctrl-d 退出

set -euo pipefail

SESSION="${SESSION:-PYWEN_CLAUDE_SBS}"
TEST_DIR="tests"
DELAY=5
CLAUDE_CMD="${CLAUDE_CMD:-claude}"
PYWEN_CMD="${PYWEN_CMD:-pywen}"

FIFO_DIR="${FIFO_DIR:-/tmp/agent-done}"
CLAUDE_FIFO="$FIFO_DIR/claude.done"
PYWEN_FIFO="$FIFO_DIR/pywen.done"

mkdir -p "$FIFO_DIR"
[[ -p "$CLAUDE_FIFO" ]] || mkfifo "$CLAUDE_FIFO"
[[ -p "$PYWEN_FIFO"  ]] || mkfifo "$PYWEN_FIFO"

exec {CLAUDE_RD}<>"$CLAUDE_FIFO"
exec {PYWEN_RD}<>"$PYWEN_FIFO"

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
    "$CLAUDE_CMD --dangerously-skip-permissions"

  tmux split-window -h -t "$SESSION" \
    "$PYWEN_CMD"

  tmux select-layout -t "$SESSION" even-horizontal
  tmux set-option -t "$SESSION" mouse on
  tmux set-option -t "$SESSION" pane-border-status top
  tmux set-option -t "$SESSION" pane-border-format " #[bold]#P » #{pane_current_command}"
  tmux set-option -t "$SESSION" status-position top
fi

get_pane_id_by_cmd() {
  local pat="$1"
  tmux list-panes -t "$SESSION" -F '#{pane_id} #{pane_current_command}' \
    | awk -v pat="$pat" '$2 ~ pat {print $1; exit}'
}

CLAUDE_PANE="$(get_pane_id_by_cmd '^claude')"
PYWEN_PANE="$(get_pane_id_by_cmd '^pywen')"

CLAUDE_PANE="${CLAUDE_PANE:-$(tmux list-panes -t "$SESSION" -F '#{pane_id}' | sed -n '1p')}"
PYWEN_PANE="${PYWEN_PANE:-$(tmux list-panes -t "$SESSION" -F '#{pane_id}' | sed -n '2p')}"

ready_pane() {
  local pane="$1"
  tmux if -t "$pane" -F '#{pane_in_mode}' 'send-keys -t "#{pane_id}" -X cancel' ''
  sleep "${READY_DELAY:-0.03}"
}

feed_line_to_pane() {
  local pane="$1"; local line="$2"
  ready_pane "$pane"
  tmux send-keys -t "$pane" -l -- "$line"
  sleep "${ENTER_DELAY:-0.06}"
  tmux send-keys -t "$pane" C-m
  sleep "${ENTER_DELAY2:-0.02}"
  tmux send-keys -t "$pane" C-m
}

feed_file_to_pane() {
  local pane="$1"; local file="$2"
  ready_pane "$pane"

  if [[ -n "${PASTE_BRACKETED:-1}" && "${PASTE_BRACKETED:-1}" != "0" ]]; then
    { cat "$file"; printf '\n'; } | tmux load-buffer -t "$SESSION" -
    tmux paste-buffer -t "$pane" -p
  else
    { cat "$file"; printf '\n'; } | tmux load-buffer -t "$SESSION" -
    tmux paste-buffer -t "$pane"
  fi

  sleep "${ENTER_DELAY:-0.06}"
  tmux send-keys -t "$pane" C-m
  sleep "${ENTER_DELAY2:-0.02}"
  tmux send-keys -t "$pane" C-m
}


normalize_line() {
  printf "%s" "$1" | tr -d '\r' | awk '{$1=$1;print}'
}

read_try_line() {
  local fd="$1" out
  if IFS= read -r -t 0.1 -u "$fd" out; then
    printf "%s" "$out"
    return 0
  else
    return 1
  fi
}

wait_both_done() {
  local case_id="$1"
  local need_claude=1 need_pywen=1
  local line norm

  while (( need_claude==1 || need_pywen==1 )); do
    if (( need_claude==1 )); then
      if line="$(read_try_line "$CLAUDE_RD")"; then
        norm="$(normalize_line "$line")"
        if [[ "$norm" == "$case_id DONE" ]]; then
          need_claude=0
        fi
      fi
    fi

    if (( need_pywen==1 )); then
      if line="$(read_try_line "$PYWEN_RD")"; then
        norm="$(normalize_line "$line")"
        if [[ "$norm" == "$case_id DONE" ]]; then
          need_pywen=0
        fi
      fi
    fi
  done
}

shopt -s nullglob
tests=( "$TEST_DIR"/*.txt )
(( ${#tests[@]} > 0 )) || { echo "No *.txt in $TEST_DIR"; exec tmux attach -t "$SESSION"; }

echo "会话：$SESSION"
echo "Claude pane: $CLAUDE_PANE"
echo "Pywen  pane: $PYWEN_PANE"
echo "开始投喂 tests/*.txt（定向到两个 pane）..."
sleep 1

for f in "${tests[@]}"; do
  case_id="$(basename "$f")"
  printf "\n[CASE] %s\n" "$case_id"

  feed_line_to_pane "$CLAUDE_PANE" "CASE_ID=$case_id"
  feed_line_to_pane "$PYWEN_PANE"  "CASE_ID=$case_id"

  feed_file_to_pane "$CLAUDE_PANE" "$f"
  feed_file_to_pane "$PYWEN_PANE"  "$f"

  wait_both_done "$case_id"

  echo "[DONE] $case_id"
done

echo -e "\n全部用例完成，进入会话（Ctrl-b S 切同步输入，Ctrl-b ←/→ 切 pane）..."
tmux setw -t "$SESSION" synchronize-panes on
tmux bind-key S setw synchronize-panes
feed_line_to_pane "$CLAUDE_PANE" "/quit"
feed_line_to_pane "$PYWEN_PANE"  "/quit"
sleep 1
tmux kill-session -t "$SESSION" 2>/dev/null || true
