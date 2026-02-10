#!/bin/sh

cd "$GAME/run/$NAME"
if [[ $FG == 1 ]]; then
	./start.sh
else
	tmux new -d -s "${GAME}_$NAME" ./start.sh
fi
