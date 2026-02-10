#!/bin/sh

tmux list-sessions -F '#S' 2>/dev/null | grep "^${GAME}_" | sed "s/^${GAME}_//"