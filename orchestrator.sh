#!/bin/sh

usage() {
    echo "Usage:"
    echo "  $0 $GAME setup <config>"
    echo "  $0 $GAME setup-all"
    echo "  $0 $GAME start <config>"
    echo "  $0 $GAME start-all"
    echo "  $0 $GAME stop <config>"
    echo "  $0 $GAME stop-all"
    echo "  $0 $GAME update"
    exit 1
}

setup_server() {
    cfg="$1"
    name=$(basename "$cfg")
    target="$RUN_DIR/$name"
    modules_file="$cfg/modules.txt"

    (
        [ -d "$cfg" ] || {
            echo "ERROR: config \"$name\" does not exist"
            return 1
        }

        echo "Setting up server \"$name\"..."

        rm -rf "$target" || exit 1
        mkdir -p "$target" || exit 1

        echo "Applying common files..."
        for common in "$COMMON_DIR"/*/; do
            [ -d "$common" ] || continue
            cname=$(basename "$common")
            echo "  -> $cname"

            if [ "$cname" = "00-base" ]; then
                cp -a "$common/." "$target/" || exit 1
            else
                cp -a "$common/." "$target/" || exit 1
            fi
        done

        if [ -f "$modules_file" ]; then
            echo "Applying modules..."
            while IFS= read -r module || [ -n "$module" ]; do
                [ -n "$module" ] || continue
                src="$MODULES_DIR/$module"

                [ -d "$src" ] || {
                    echo "ERROR: module \"$module\" not found!"
                    exit 1
                }

                echo "  -> $module"
                cp -a "$src/." "$target/" || exit 1
            done < "$modules_file"
        fi

        echo "Applying config..."
        cp -a "$cfg/." "$target/" || exit 1

        if [ -d "$OVERRIDES_DIR" ]; then
            echo "Applying overrides..."
            for override in "$OVERRIDES_DIR"/*/; do
                [ -d "$override" ] || continue
                echo "  -> $(basename "$override")"
                cp -a "$override/." "$target/" || exit 1
            done
        fi

        echo "Server \"$name\" successfully set up!"
        printf "\n"
    )
}

start_server() {
    name="$1"
    cfg="$CONFIGS_DIR/$name"

    [ -d "$cfg" ] || {
        echo "ERROR: config \""$name"\" does not exist!"
        return 1
    }

    tmux has-session -t "=${GAME}_$name" 2>/dev/null && {
        echo "Server \"$name\" already running"
        return 0
    }

    setup_server "$cfg" || {
        echo "ERROR: setup failed for \"$name\" — not starting!"
        return 1
    }

    echo "Starting server \"${GAME}_$name\"..."
    pwd="$PWD"
    (cd $PWD/$RUN_DIR/$name && exec tmux new-session -d -s "$1_$2" "$pwd/start.sh" $GAME $name)

    printf "\n"
}

stop_server() {
    name="$1"

    tmux has-session -t "=${GAME}_$name" 2>/dev/null || {
        echo "Server \"$name\" not running!"
        return 0
    }

    echo "Stopping server \"${GAME}_$name\"..."
    tmux send-keys -t "${GAME}_$name" C-c
}

setup_all() {
    for cfg in "$CONFIGS_DIR"/*/; do
        [ -d "$cfg" ] || continue
        setup_server "$cfg" || {
            echo "ERROR: skipping config \"$(basename "$cfg")\"!"
            printf "\n"
        }
    done
}

start_all() {
    for s in $(tmux list-sessions -F '#S' 2>/dev/null | grep "^${GAME}_"); do
        should_sleep=1
        tmux send-keys -t "$s" C-c
    done

    while tmux list-sessions -F '#S' 2>/dev/null | grep -q "^${GAME}_"; do
        sleep 1
    done

    for cfg in "$CONFIGS_DIR"/*/; do
        [ -d "$cfg" ] || continue
        start_server "$(basename "$cfg")"
    done
}

if [ -z "$1" ]; then
    echo "Usage: $0 <game>"
    exit 1
fi

if [ ! -d "$1" ]; then
    echo "ERROR: Game \"$1\" does not exist!"
    exit 1
fi

GAME="$1"
COMMON_DIR="$GAME/common"
MODULES_DIR="$GAME/modules"
CONFIGS_DIR="$GAME/configs"
OVERRIDES_DIR="$GAME/overrides"
RUN_DIR="$GAME/run"

case "$2" in
    setup)
        [ -n "$2" ] || usage
        setup_server "$CONFIGS_DIR/$3" || exit 1
        ;;

    setup-all)
        setup_all
        ;;

    start)
        [ -n "$3" ] || usage
        start_server "$3"
        ;;

    start-all)
        start_all
        ;;

    stop)
        [ -n "$3" ] || usage
        stop_server "$3"
        ;;

    stop-all)
        for s in $(tmux list-sessions -F '#S' 2>/dev/null | grep "^${GAME}_"); do
            tmux send-keys -t "$s" C-c
        done
        ;;

    update)
        pwd="$PWD"
        (cd $PWD/$GAME && exec "$pwd/update.sh" $GAME) || {
            echo "ERROR: update failed!"
            exit 1
        }
        ;;

    *)
        usage
        ;;
esac
