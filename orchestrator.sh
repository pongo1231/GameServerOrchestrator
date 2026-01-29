#!/bin/sh

usage() {
    echo "Usage:"
    echo "  $0 $GAME setup <configs...>"
    echo "  $0 $GAME setup-all"
    echo "  $0 $GAME start <configs...>"
    echo "  $0 $GAME start-fg <config>"
    echo "  $0 $GAME start-all [mode (no-restart)]"
    echo "  $0 $GAME stop <configs...>"
    echo "  $0 $GAME stop-all"
    echo "  $0 $GAME update"
    echo "  $0 $GAME exists <config>"
    echo "  $0 $GAME running (<config>)"
    exit 1
}

apply_module() {
    local module="$1"

    case " $APPLIED_MODULES " in
        *" $module "*) return 0 ;;
    esac

    APPLIED_MODULES="$APPLIED_MODULES $module"

    local src="$MODULES_DIR/$module"
	[[ "$(realpath "$src")" == "$MODULES_ABS_DIR"* ]] || {
		echo " -> WARNING: module \"$module\" has illegal name, skipping!"
		return 1
	}
    
    [[ -d "$src" ]] || {
        echo " -> WARNING: module \"$module\" not found, skipping!"
        return 1
    }

    if [[ -f "$src/modules.txt" ]]; then
        while IFS= read -r sub || [[ -n "$sub" ]]; do
            [[ -n "$sub" ]] || continue
            case "$sub" in
                /*) continue ;;
            esac
            apply_module "$sub"
        done < "$src/modules.txt"
    fi

    echo " -> $module"

    cp -a "$src/." "$target/" || return 1
}

setup_server() {
    local cfg="$1"
    local name=$(basename "$cfg")
    target="$RUN_DIR/$name"
    modules_file="$cfg/modules.txt"

    [[ -d "$cfg" ]] || {
        echo "ERROR: config \"$name\" does not exist"
        return 1
    }

    echo "Setting up server \"$name\"..."

    local running=0
    if is_running "$name"; then
        echo "Server is running, skipping cleanup!"
        running=1
    else
        rm -rf "$target" || return 1
    fi;
    mkdir -p "$target" || return 1

    echo "Applying common files..."
    for common in "$COMMON_DIR"/*/; do
        [[ -d "$common" ]] || continue
        cname=$(basename "$common")
        echo "  -> $cname"

        if [[ "$cname" = "00-base" ]]; then
            cp -a "$common/." "$target/" || ((running)) || return 1
        else
            cp -a "$common/." "$target/" || ((running)) || return 1
        fi
    done

    if [[ -f "$modules_file" ]]; then
        echo "Applying modules..."
        APPLIED_MODULES=""

        while IFS= read -r module || [[ -n "$module" ]]; do
            [[ -n "$module" ]] || continue
            case "$module" in
                /*) continue ;;
            esac
            apply_module "$module"
        done < "$modules_file"
    fi

    echo "Applying config..."
    cp -a "$cfg/." "$target/" || ((running)) || return 1

    if [[ -d "$OVERRIDES_DIR" ]]; then
        echo "Applying overrides..."
        for override in "$OVERRIDES_DIR"/*/; do
            [[ -d "$override" ]] || continue
            echo "  -> $(basename "$override")"
            cp -a "$override/." "$target/" || ((running)) || return 1
        done
    fi

    echo "Server \"$name\" successfully set up!"
    printf "\n"
}

start_server() {
    local name="$1"
    local mode="$2"
    
    local cfg="$CONFIGS_DIR/$name"

    [[ -d "$cfg" ]] || {
        echo "ERROR: config \""$name"\" does not exist!"
        return 1
    }

    is_running "$name" && {
        stop_server "$name"
        while is_running "$name"; do
            sleep 1
        done
    }

    setup_server "$cfg" || {
        echo "ERROR: setup failed for \"$name\" - not starting!"
        return 1
    }

    echo "Starting server \"${GAME}_$name\"..."
    pwd="$PWD"
    (
      cd $PWD/$RUN_DIR/$name || exit 1
      if [[ "$mode" == "fg" ]]; then
          exec "$pwd/start.sh" "$GAME" "$name"
      else
          exec tmux new-session -d -s "$1_$2" "$pwd/start.sh" "$GAME" "$name"
      fi
    )

    printf "\n"
}

stop_server() {
    local name="$1"

    is_running "$name" || {
        echo "Server \"$name\" is not running!"
        return 0
    }

    echo "Stopping server \"${GAME}_$name\"..."
    tmux send-keys -t "${GAME}_$name" C-c
}

setup_all() {
    for cfg in "$CONFIGS_DIR"/*/; do
        [[ -d "$cfg" ]] || continue
        setup_server "$cfg" || {
            echo "ERROR: skipping config \"$(basename "$cfg")\"!"
            printf "\n"
        }
    done
}

start_all() {
    local mode="$1"

    for cfg in "$CONFIGS_DIR"/*/; do
        local cfgname="$(basename "$cfg")"

        ([[ -d "$cfg" ]] && [[ ! -e "$cfg/.noautostart" ]] && ([[ "$mode" != "no-restart" ]] || !(is_running "$cfgname"))) || continue
        start_server "$cfgname"
    done
}

is_running() {
    local name="$1"

    tmux has-session -t "=${GAME}_$name" 2>/dev/null
}

if [[ -z "$1" ]]; then
    echo "Usage: $0 <game>"
    exit 1
fi

if [[ ! -d "$1" ]]; then
    echo "ERROR: Game \"$1\" does not exist!"
    exit 1
fi

GAME="$1"
COMMON_DIR="$GAME/common"
MODULES_DIR="$GAME/modules"
MODULES_ABS_DIR="$(realpath "$MODULES_DIR")"
CONFIGS_DIR="$GAME/configs"
OVERRIDES_DIR="$GAME/overrides"
RUN_DIR="$GAME/run"

case "$2" in
    setup)
        shift 2
        [[ $# -ge 1 ]] || usage
        for cfg in "$@"; do
            setup_server "$CONFIGS_DIR/$cfg"
        done
        ;;

    setup-all)
        setup_all
        ;;

    start)
        shift 2
        [[ $# -ge 1 ]] || usage
        for name in "$@"; do
            start_server "$name"
        done
        ;;

    start-fg)
        shift 2
        [[ $# -ge 1 ]] || usage
        start_server "$1" "fg"
        ;;

    start-all)
        shift 2
        [[ $# -ge 1 ]] && [[ $1 != "no-restart" ]] && usage
        start_all "$1"
        ;;

    stop)
        shift 2
        [[ $# -ge 1 ]] || usage
        for name in "$@"; do
            stop_server "$name"
        done
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

    exists)
        shift 2
        [[ $# -ge 1 ]] || usage
        [[ -d "$PWD/$GAME/configs/$1" ]]
        ;;

    running)
        shift 2
        [[ $# -ge 1 ]] || {
            sessions=""
            for s in $(tmux list-sessions -F '#S' 2>/dev/null | grep "^${GAME}_"); do
                sessions="$sessions$s "
            done
            [[ -z "$sessions" ]] && exit 1
            echo "$sessions"
            exit 0
        }
        is_running "$1"
        ;;

    *)
        usage
        ;;
esac
