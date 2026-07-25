#!/bin/sh
set -eu

umask 077

INSTALL_DIR="/opt/one-node-node"
UNIT_FILE="/etc/systemd/system/one-node-node.service"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
INSTALL_RECORD="${INSTALL_DIR}/.installation"
DEFAULT_STATE_DIR="/var/lib/one-node-node"
CONTAINER_NAME="one-node-node"
REQUESTED_MODE=""

log() {
	printf '%s\n' "[one-node-node] $*"
}

die() {
	printf '%s\n' "[one-node-node] error: $*" >&2
	exit 1
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--mode)
			[ "$#" -ge 2 ] || die "--mode requires native or docker"
			[ -z "$REQUESTED_MODE" ] || die "--mode may be supplied only once"
			REQUESTED_MODE=$2
			shift 2
			;;
		--help|-h)
			printf '%s\n' \
				"Uninstall One Node." \
				"" \
				"Usage: uninstall.sh [--mode <native|docker>]" \
				"" \
				"The mode is normally detected from the protected installation record."
			exit 0
			;;
		*) die "unknown argument: $1" ;;
	esac
done
case "$REQUESTED_MODE" in
	""|native|docker) ;;
	*) die "--mode must be native or docker" ;;
esac

[ "$(id -u)" -eq 0 ] || die "run this uninstaller as root"
command -v realpath >/dev/null 2>&1 || die "realpath is required (install coreutils)"

installed_mode=""
state_dir="$DEFAULT_STATE_DIR"
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

if [ -z "$installed_mode" ]; then
	log "no One Node installation was found"
	exit 0
fi
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
	*[!A-Za-z0-9_./-]*) die "recorded state directory contains unsupported characters" ;;
esac
case "$state_dir" in
	/|/bin|/boot|/dev|/etc|/home|/lib|/lib32|/lib64|/media|/mnt|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var|"$INSTALL_DIR")
		die "refusing to remove unsafe state directory: $state_dir"
		;;
esac

if [ "$installed_mode" = "native" ]; then
	command -v systemctl >/dev/null 2>&1 || die "systemd is required to uninstall the native service"
	systemctl disable --now one-node-node.service >/dev/null 2>&1 || true
	rm -f -- "$UNIT_FILE"
	systemctl daemon-reload
else
	command -v docker >/dev/null 2>&1 || die "Docker is required to uninstall the Docker service"
	if [ -f "$COMPOSE_FILE" ] && [ ! -L "$COMPOSE_FILE" ]; then
		docker compose -f "$COMPOSE_FILE" down --remove-orphans
	else
		docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
	fi
fi

rm -rf -- "$INSTALL_DIR"
if [ -e "$state_dir" ]; then
	[ -d "$state_dir" ] && [ ! -L "$state_dir" ] ||
		die "state directory must be a real directory"
	rm -rf -- "$state_dir"
fi

log "One Node was uninstalled; Docker and the host Xray installation were preserved"
