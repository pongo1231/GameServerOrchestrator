#!/bin/sh

usage() {
	echo "Usage:"
	echo "  $0 $GAME setup [* | <configs...>]"
	echo "  [RESTART=1] $0 $GAME start [* | <configs...>]"
	echo "  $0 $GAME stop [* | <configs...>]"
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

	cp -au "$src/." "$target/" || return 1
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
	fi
	mkdir -p "$target" || return 1

	echo "Applying common files..."
	for common in "$COMMON_DIR"/*/; do
		[[ -d "$common" ]] || continue
		cname=$(basename "$common")
		echo "  -> $cname"

		cp -au "$common/." "$target/" || ((running)) || return 1
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
	cp -au "$cfg/." "$target/" || ((running)) || return 1

	if [[ -d "$OVERRIDES_DIR" ]]; then
		echo "Applying overrides..."
		for override in "$OVERRIDES_DIR"/*/; do
			[[ -d "$override" ]] || continue
			echo "  -> $(basename "$override")"
			cp -au "$override/." "$target/" || ((running)) || return 1
		done
	fi

	echo "Server \"$name\" successfully set up!"
	printf "\n"
}

start_server() {
	local name="$1"

	[[ $RESTART != 1 ]] && is_running "$name" && {
		echo "Server \"$name\" is already running! Pass RESTART=1 to restart."
		return 1
	}

	local cfg="$CONFIGS_DIR/$name"

	[[ -d "$cfg" ]] || {
		echo "ERROR: config \"$name\" does not exist!"
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
	GAME="$GAME" NAME="$name" ./start.sh
	printf "\n"
}

stop_server() {
	local name="$1"

	is_running "$name" || {
		echo "Server \"$name\" is not running!"
		return 0
	}

	echo "Stopping server \"${GAME}_$name\"..."
	GAME="$GAME" NAME="$name" ./stop.sh
	printf "\n"
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
	for cfg in "$CONFIGS_DIR"/*/; do
		local cfgname="$(basename "$cfg")"

		([[ -d "$cfg" ]] &&
		 [[ ! -e "$cfg/.noautostart" ]] &&
		 ([[ $RESTART == 1 ]] || !(is_running "$cfgname"))) || continue

		start_server "$cfgname"
	done
}

is_running() {
	local name="$1"
	
	GAME="$GAME" NAME="$name" ./running.sh
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
		if [[ "$1" == "*" ]]; then
			setup_all
		else
			for cfg in "$@"; do
				setup_server "$CONFIGS_DIR/$cfg"
			done
		fi
		;;

	start)
		shift 2
		[[ $# -ge 1 ]] || usage
		if [[ "$1" == "*" ]]; then
			start_all
		else
			for name in "$@"; do
				start_server "$name"
			done
		fi
		;;

	stop)
		shift 2
		[[ $# -ge 1 ]] || usage
		if [[ "$1" == "*" ]]; then
			for name in $(GAME="$GAME" ./list-all.sh); do
				GAME="$GAME" NAME="$name" ./stop.sh
			done
		else
			for name in "$@"; do
				stop_server "$name"
			done
		fi
		;;

	update)
		$GAME="$GAME" ./update.sh || {
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
			for name in $(GAME="$GAME" ./list-all.sh); do
				sessions="$sessions$name "
			done
			[[ -z "$sessions" ]] && exit 1
			echo "$sessions"
			exit 0
		}
		is_running "$1" && echo "\"$1\" is running" || echo "\"$1\" is not running"
		;;

	*)
		usage
		;;
esac
