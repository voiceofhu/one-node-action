#!/bin/sh

# V2 uninstaller removes only canonical manifest-owned paths. Pre-existing
# credential state is never claimed by a later installation.

initialize_uninstall_config() {
	INSTALL_DIR="/opt/one-node-node"
	UNIT_FILE="/etc/systemd/system/one-node-node.service"
	COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
	INSTALL_RECORD="${INSTALL_DIR}/.installation-v2"
	CONTAINER_NAME="one-node-node"
	REQUESTED_MODE=""
	installed_mode=""
	state_dir=""
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
		"Uninstall the One Node sing-box runtime." \
		"" \
		"Usage: uninstall-v2.sh [--mode <native|docker>]" \
		"" \
		"Pre-existing credential and runtime state are retained."
}

parse_uninstall_arguments() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--mode)
			[ "$#" -ge 2 ] || die "--mode requires native or docker"
			[ -z "$REQUESTED_MODE" ] || die "--mode may be supplied only once"
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

load_v2_installation() {
	if [ ! -e "$INSTALL_RECORD" ]; then
		log "no v2 One Node installation was found"
		return 1
	fi
	manifest_load "$INSTALL_RECORD" || die "refusing unknown or unsafe v2 installation manifest"
	installed_mode=$MANIFEST_MODE
	state_dir=$MANIFEST_STATE_DIR
	if [ -n "$REQUESTED_MODE" ] && [ "$REQUESTED_MODE" != "$installed_mode" ]; then
		die "One Node is installed in ${installed_mode} mode, not ${REQUESTED_MODE}"
	fi
	return 0
}
