#/bin/sh

tmux list-panes -t "${GAME}_$NAME" -F '#{pane_pid}' | xargs -r kill
tmux send-keys -t "${GAME}_$NAME" C-c
