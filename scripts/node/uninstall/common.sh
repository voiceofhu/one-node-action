#!/bin/sh

# Shared uninstaller configuration, validation, and installation detection.
# Uninstaller globals are shared across sourced modules.
# shellcheck disable=SC2034

initialize_uninstall_config() {
	INSTALL_DIR="/opt/one-node-node"
	UNIT_FILE="/etc/systemd/system/one-node-node.service"
	COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
	INSTALL_RECORD="${INSTALL_DIR}/.installation"
	DEFAULT_STATE_DIR="/var/lib/one-node-node"
	CONTAINER_NAME="one-node-node"
	REQUESTED_MODE=""
	installed_mode=""
	state_dir="$DEFAULT_STATE_DIR"
}

log() {
	printf '%s\n' "[one-node-node] $*"
}

die() {
	printf '%s\n' "[one-node-node] error: $*" >&2
	exit 1
}

show_help() {
	printf '%s\n' \
		"Uninstall One Node." \
		"" \
		"Usage: uninstall.sh [--mode <native|docker>]" \
		"" \
		"The mode is normally detected from the protected installation record."
}

parse_uninstall_arguments() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--mode)
				[ "$#" -ge 2 ] || die "--mode requires native or docker"
				[ -z "$REQUESTED_MODE" ] ||
					die "--mode may be supplied only once"
				REQUESTED_MODE=$2
				shift 2
				;;
			--help|-h)
				show_help
				exit 0
				;;
			*) die "unknown argument: $1" ;;
		esac
	done
	case "$REQUESTED_MODE" in
		""|native|docker) ;;
		*) die "--mode must be native or docker" ;;
	esac
}

load_installation_state() {
	if [ -e "$INSTALL_RECORD" ]; then
		[ -f "$INSTALL_RECORD" ] && [ ! -L "$INSTALL_RECORD" ] ||
			die "installation record must be a regular file"
		installed_mode=$(sed -n 's/^runtime=//p' "$INSTALL_RECORD" | head -n 1)
		recorded_state_dir=$(sed -n 's/^state_dir=//p' "$INSTALL_RECORD" | head -n 1)
		if [ -n "$recorded_state_dir" ]; then
			state_dir=$recorded_state_dir
		fi
	fi
	if [ -z "$installed_mode" ]; then
		if [ -f "$UNIT_FILE" ] && [ ! -L "$UNIT_FILE" ]; then
			installed_mode="native"
		elif command -v docker >/dev/null 2>&1 &&
			docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
			installed_mode="docker"
		fi
	fi
}

validate_installation_state() {
	case "$installed_mode" in
		native|docker) ;;
		*) die "installation record contains an unsupported runtime" ;;
	esac
	if [ -n "$REQUESTED_MODE" ] && [ "$REQUESTED_MODE" != "$installed_mode" ]; then
		die "One Node is installed in ${installed_mode} mode, not ${REQUESTED_MODE}"
	fi

	case "$state_dir" in
		/*) ;;
		*) die "recorded state directory is not absolute" ;;
	esac
	state_dir=$(realpath -m -- "$state_dir")
	case "$state_dir" in
		*[!A-Za-z0-9_./-]*)
			die "recorded state directory contains unsupported characters"
			;;
	esac
	case "$state_dir" in
		/|/bin|/boot|/dev|/etc|/home|/lib|/lib32|/lib64|/media|/mnt|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var|"$INSTALL_DIR")
			die "refusing to remove unsafe state directory: $state_dir"
			;;
	esac
}

remove_installation_state() {
	rm -rf -- "$INSTALL_DIR"
	if [ -e "$state_dir" ]; then
		[ -d "$state_dir" ] && [ ! -L "$state_dir" ] ||
			die "state directory must be a real directory"
		rm -rf -- "$state_dir"
	fi
}
