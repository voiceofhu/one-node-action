#!/bin/sh

# V2 uninstaller removes only One Node-owned runtime files. Credential state is
# retained for reinstall/recovery; purge and upgrade rollback belong to A03.

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
		"Node credential and runtime state are retained for safe recovery."
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
	[ -f "$INSTALL_RECORD" ] && [ ! -L "$INSTALL_RECORD" ] ||
		die "v2 installation record must be a regular file"
	[ "$(stat -c '%a' "$INSTALL_RECORD")" = "600" ] ||
		die "v2 installation record permissions must be 0600"
	format=$(sed -n 's/^format=//p' "$INSTALL_RECORD" | head -n 1)
	installed_mode=$(sed -n 's/^runtime=//p' "$INSTALL_RECORD" | head -n 1)
	state_dir=$(sed -n 's/^state_dir=//p' "$INSTALL_RECORD" | head -n 1)
	[ "$format" = "v2" ] || die "installation record is not owned by install-v2"
	case "$installed_mode" in
	native|docker) ;;
	*) die "v2 installation record has an unsupported runtime" ;;
	esac
	if [ -n "$REQUESTED_MODE" ] && [ "$REQUESTED_MODE" != "$installed_mode" ]; then
		die "One Node is installed in ${installed_mode} mode, not ${REQUESTED_MODE}"
	fi
	case "$state_dir" in
	/*) ;;
	*) die "recorded state directory is invalid" ;;
	esac
	state_dir=$(realpath -m -- "$state_dir")
	case "$state_dir" in
	*[!A-Za-z0-9_./-]*) die "recorded state directory contains unsupported characters" ;;
	esac
	case "$state_dir" in
	/|/bin|/boot|/dev|/etc|/home|/lib|/lib32|/lib64|/media|/mnt|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var|"$INSTALL_DIR")
		die "recorded state directory is unsafe"
		;;
	esac
	return 0
}

remove_v2_files() {
	rm -f -- "$INSTALL_DIR/one-node-node" "$INSTALL_DIR/one-node-node.env" \
		"$COMPOSE_FILE" "$INSTALL_RECORD"
	rmdir "$INSTALL_DIR" 2>/dev/null || true
}
