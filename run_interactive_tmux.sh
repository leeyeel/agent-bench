#!/usr/bin/env bash
#   Ctrl-b 方向键         在左右 pane 之间切换焦点
#   Ctrl-b S              左右同步/不同步输入
#   Ctrl-b :kill-session  退出整个会话，或直接 Ctrl-d 关闭 pane
#
set -euo pipefail

SESSION="${SESSION:-PYWEN_CLAUDE_SBS}"
CLAUDE_CMD="${CLAUDE_CMD:-claude --dangerously-skip-permissions}"
PYWEN_CMD="${PYWEN_CMD:-pywen}"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  exec tmux attach -t "$SESSION"
fi

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

# 绑定热键
tmux bind-key S setw synchronize-panes

tmux select-pane -t "$SESSION:.+0"
exec tmux attach -t "$SESSION"
