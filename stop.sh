#/bin/sh

tmux list-panes -t "${GAME}_$NAME" -F '#{pane_pid}' | xargs -r kill
