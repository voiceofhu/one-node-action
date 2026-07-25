#!/bin/sh
set -eu

umask 077

PROGRAM="one-node-node"
INSTALL_DIR="/opt/one-node-node"
ENV_FILE="${INSTALL_DIR}/one-node-node.env"
UNIT_FILE="/etc/systemd/system/one-node-node.service"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
INSTALL_RECORD="${INSTALL_DIR}/.installation"
CONTAINER_NAME="one-node-node"

INSTALL_MODE="native"
while [ "$#" -gt 0 ]; do
	case "$1" in
		--mode)
			[ "$#" -ge 2 ] || {
				printf '%s\n' "[one-node-node] error: --mode requires native or docker" >&2
				exit 1
			}
			INSTALL_MODE=$2
			shift 2
			;;
		--help|-h)
			printf '%s\n' \
				"Install One Node." \
				"" \
				"Usage: install.sh --mode <native|docker>" \
				"" \
				"  native  Install a systemd service." \
				"  docker  Install a Docker Compose service."
			exit 0
			;;
		*)
			printf '%s\n' "[one-node-node] error: unknown argument: $1" >&2
			exit 1
			;;
	esac
done
case "$INSTALL_MODE" in
	native|docker) ;;
	*)
		printf '%s\n' "[one-node-node] error: --mode must be native or docker" >&2
		exit 1
		;;
esac

log() {
	printf '%s\n' "[one-node-node] $*"
}

die() {
	printf '%s\n' "[one-node-node] error: $*" >&2
	exit 1
}

require_value() {
	name=$1
	value=$2
	[ -n "$value" ] || die "${name} is required"
}

require_single_line() {
	name=$1
	value=$2
	case "$value" in
		*'
'*|*''*) die "${name} must be a single line" ;;
	esac
}

escape_dotenv() {
	printf '%s' "$1" | sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g' \
		-e 's/\$/\\$/g'
}

write_env() {
	key=$1
	value=$2
	escaped=$(escape_dotenv "$value")
	printf '%s="%s"\n' "$key" "$escaped" >> "$ENV_SOURCE"
}

download_binary() {
	url=$1
	destination=$2
	case "$url" in
		https://*)
			allowed_protocols='=https'
			;;
		http://*)
			[ "$ONE_NODE_ALLOW_INSECURE" = "true" ] || die "HTTP binary downloads require ONE_NODE_ALLOW_INSECURE=true"
			allowed_protocols='=http,https'
			;;
		*) die "binary download URL must use HTTP or HTTPS" ;;
	esac
	curl --fail --location --silent --show-error --retry 3 \
		--proto "$allowed_protocols" --proto-redir "$allowed_protocols" \
		--output "$destination" "$url"
}

[ "$(id -u)" -eq 0 ] || die "run this installer as root"
[ -r /etc/os-release ] || die "cannot identify the operating system"

# /etc/os-release is controlled by the installed operating system.
# shellcheck disable=SC1091
. /etc/os-release
[ "${ID:-}" = "debian" ] || die "only Debian is supported"

command -v dpkg >/dev/null 2>&1 || die "dpkg is required"
[ "$(dpkg --print-architecture)" = "amd64" ] || die "only Debian amd64 is supported"
case "$(uname -m)" in
	x86_64|amd64) ;;
	*) die "only x86_64/amd64 machines are supported" ;;
esac

if [ "$INSTALL_MODE" = "native" ]; then
	command -v systemctl >/dev/null 2>&1 || die "systemd is required for native installation"
fi
command -v curl >/dev/null 2>&1 || die "curl is required to run this installer"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required (install coreutils)"
command -v sed >/dev/null 2>&1 || die "sed is required"
command -v realpath >/dev/null 2>&1 || die "realpath is required (install coreutils)"
command -v grep >/dev/null 2>&1 || die "grep is required"
command -v stat >/dev/null 2>&1 || die "stat is required (install coreutils)"

ONE_NODE_SERVER=${ONE_NODE_SERVER:-}
ONE_NODE_ID=${ONE_NODE_ID:-}
ONE_NODE_BOOTSTRAP_TOKEN=${ONE_NODE_BOOTSTRAP_TOKEN:-}
ONE_NODE_BINARY_URL=${ONE_NODE_BINARY_URL:-}
ONE_NODE_BINARY_SHA256=${ONE_NODE_BINARY_SHA256:-}
ONE_NODE_XRAY_API_ADDR=${ONE_NODE_XRAY_API_ADDR:-127.0.0.1:27522}
ONE_NODE_STATE_DIR=${ONE_NODE_STATE_DIR:-/var/lib/one-node-node}
ONE_NODE_ALLOW_INSECURE=${ONE_NODE_ALLOW_INSECURE:-false}
ONE_NODE_ENROLL_TIMEOUT=${ONE_NODE_ENROLL_TIMEOUT:-60}
ONE_NODE_DOCKER_IMAGE=${ONE_NODE_DOCKER_IMAGE:-debian:bookworm-slim}

require_value "ONE_NODE_SERVER" "$ONE_NODE_SERVER"
require_value "ONE_NODE_ID" "$ONE_NODE_ID"
require_value "ONE_NODE_BOOTSTRAP_TOKEN" "$ONE_NODE_BOOTSTRAP_TOKEN"
require_value "ONE_NODE_BINARY_URL" "$ONE_NODE_BINARY_URL"
require_value "ONE_NODE_BINARY_SHA256" "$ONE_NODE_BINARY_SHA256"

require_single_line "ONE_NODE_SERVER" "$ONE_NODE_SERVER"
require_single_line "ONE_NODE_ID" "$ONE_NODE_ID"
require_single_line "ONE_NODE_BOOTSTRAP_TOKEN" "$ONE_NODE_BOOTSTRAP_TOKEN"
require_single_line "ONE_NODE_BINARY_URL" "$ONE_NODE_BINARY_URL"
require_single_line "ONE_NODE_BINARY_SHA256" "$ONE_NODE_BINARY_SHA256"
require_single_line "ONE_NODE_XRAY_API_ADDR" "$ONE_NODE_XRAY_API_ADDR"
require_single_line "ONE_NODE_STATE_DIR" "$ONE_NODE_STATE_DIR"
require_single_line "ONE_NODE_ALLOW_INSECURE" "$ONE_NODE_ALLOW_INSECURE"
require_single_line "ONE_NODE_ENROLL_TIMEOUT" "$ONE_NODE_ENROLL_TIMEOUT"
require_single_line "ONE_NODE_DOCKER_IMAGE" "$ONE_NODE_DOCKER_IMAGE"

case "$ONE_NODE_SERVER" in
	*' '*|*'	'*) die "ONE_NODE_SERVER must not contain whitespace" ;;
esac
case "$ONE_NODE_ID" in
	''|*[!0-9]*) die "ONE_NODE_ID must be a positive integer" ;;
esac
if ! [ "$ONE_NODE_ID" -gt 0 ] 2>/dev/null; then
	die "ONE_NODE_ID must be a positive integer"
fi
case "$ONE_NODE_BOOTSTRAP_TOKEN" in
	*' '*|*'	'*) die "ONE_NODE_BOOTSTRAP_TOKEN must not contain whitespace" ;;
esac
case "$ONE_NODE_ENROLL_TIMEOUT" in
	''|*[!0-9]*) die "ONE_NODE_ENROLL_TIMEOUT must be a positive integer" ;;
esac
if ! [ "$ONE_NODE_ENROLL_TIMEOUT" -gt 0 ] 2>/dev/null; then
	die "ONE_NODE_ENROLL_TIMEOUT must be a positive integer"
fi
case "$ONE_NODE_SERVER" in
	https://*|grpcs://*) ;;
	http://*|grpc://*)
		[ "$ONE_NODE_ALLOW_INSECURE" = "true" ] || die "plaintext control connections require ONE_NODE_ALLOW_INSECURE=true"
		;;
	*://*) die "ONE_NODE_SERVER uses an unsupported scheme" ;;
	*)
		[ "$ONE_NODE_ALLOW_INSECURE" = "true" ] || die "a control address without a TLS scheme requires ONE_NODE_ALLOW_INSECURE=true"
		;;
esac
case "$ONE_NODE_STATE_DIR" in
	/*) ;;
	*) die "ONE_NODE_STATE_DIR must be an absolute path" ;;
esac
ONE_NODE_STATE_DIR=$(realpath -m -- "$ONE_NODE_STATE_DIR")
case "$ONE_NODE_STATE_DIR" in
	*[!A-Za-z0-9_./-]*) die "ONE_NODE_STATE_DIR contains unsupported characters" ;;
esac
case "$ONE_NODE_STATE_DIR" in
	/|/bin|/boot|/dev|/etc|/home|/lib|/lib32|/lib64|/media|/mnt|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var|"$INSTALL_DIR")
		die "ONE_NODE_STATE_DIR must point to a dedicated subdirectory"
		;;
esac
case "$ONE_NODE_BINARY_URL" in
	https://*) ;;
	http://*)
		[ "$ONE_NODE_ALLOW_INSECURE" = "true" ] || die "HTTP binary downloads require ONE_NODE_ALLOW_INSECURE=true"
		;;
	*) die "ONE_NODE_BINARY_URL must use HTTP or HTTPS" ;;
esac
case "$ONE_NODE_DOCKER_IMAGE" in
	''|*' '*|*'	'*) die "ONE_NODE_DOCKER_IMAGE must be a non-empty image reference without whitespace" ;;
esac

installed_mode=""
if [ -f "$INSTALL_RECORD" ] && [ ! -L "$INSTALL_RECORD" ]; then
	installed_mode=$(sed -n 's/^runtime=//p' "$INSTALL_RECORD" | head -n 1)
fi
if [ -z "$installed_mode" ]; then
	if [ -f "$UNIT_FILE" ] && [ ! -L "$UNIT_FILE" ]; then
		installed_mode="native"
	elif command -v docker >/dev/null 2>&1 &&
		docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
		installed_mode="docker"
	fi
fi
if [ -n "$installed_mode" ] && [ "$installed_mode" != "$INSTALL_MODE" ]; then
	die "One Node is installed in ${installed_mode} mode; uninstall it before switching to ${INSTALL_MODE}"
fi

ensure_docker() {
	if ! command -v docker >/dev/null 2>&1; then
		command -v apt-get >/dev/null 2>&1 || die "Docker is required for Docker installation"
		log "installing Docker Engine and Compose"
		apt-get update
		env DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
		if ! env DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-v2; then
			env DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-plugin
		fi
	fi
	if command -v systemctl >/dev/null 2>&1; then
		systemctl enable --now docker.service
	fi
	docker info >/dev/null 2>&1 || die "Docker daemon is unavailable"
	docker compose version >/dev/null 2>&1 || die "Docker Compose plugin is required"
}

TEMP_DIR=$(mktemp -d)
BACKUP_DIR="${TEMP_DIR}/backup"
BINARY_FILE="${INSTALL_DIR}/${PROGRAM}"
IDENTITY_FILE="${ONE_NODE_STATE_DIR}/node-secret"
BINARY_TARGET_TMP=""
ENV_TARGET_TMP=""
UNIT_TARGET_TMP=""
COMPOSE_TARGET_TMP=""
RECORD_TARGET_TMP=""
INSTALL_STARTED="false"
COMMITTED="false"
OLD_BINARY_PRESENT="false"
OLD_ENV_PRESENT="false"
OLD_UNIT_PRESENT="false"
OLD_COMPOSE_PRESENT="false"
OLD_RECORD_PRESENT="false"
OLD_IDENTITY_PRESENT="false"
OLD_SERVICE_ACTIVE="false"
OLD_SERVICE_ENABLED="false"
OLD_DOCKER_RUNNING="false"

restore_file() {
	backup_path=$1
	target_path=$2
	target_dir=$(dirname "$target_path")
	restore_tmp=$(mktemp "${target_dir}/.one-node-rollback.XXXXXX") || return 1
	if ! cp -p "$backup_path" "$restore_tmp"; then
		rm -f "$restore_tmp"
		return 1
	fi
	if ! mv -f "$restore_tmp" "$target_path"; then
		rm -f "$restore_tmp"
		return 1
	fi
	return 0
}

rollback_installation() {
	log "installation failed; restoring previous node installation"
	set +e
	rollback_failed="false"
	if [ "$INSTALL_MODE" = "native" ]; then
		systemctl stop one-node-node.service >/dev/null 2>&1
	else
		docker compose -f "$COMPOSE_FILE" down --remove-orphans >/dev/null 2>&1
	fi

	if [ "$OLD_BINARY_PRESENT" = "true" ]; then
		restore_file "${BACKUP_DIR}/binary" "$BINARY_FILE" || rollback_failed="true"
	else
		rm -f "$BINARY_FILE"
	fi
	if [ "$OLD_ENV_PRESENT" = "true" ]; then
		restore_file "${BACKUP_DIR}/env" "$ENV_FILE" || rollback_failed="true"
	else
		rm -f "$ENV_FILE"
	fi
	if [ "$OLD_UNIT_PRESENT" = "true" ]; then
		restore_file "${BACKUP_DIR}/unit" "$UNIT_FILE" || rollback_failed="true"
	else
		rm -f "$UNIT_FILE"
	fi
	if [ "$OLD_COMPOSE_PRESENT" = "true" ]; then
		restore_file "${BACKUP_DIR}/compose" "$COMPOSE_FILE" || rollback_failed="true"
	else
		rm -f "$COMPOSE_FILE"
	fi
	if [ "$OLD_RECORD_PRESENT" = "true" ]; then
		restore_file "${BACKUP_DIR}/record" "$INSTALL_RECORD" || rollback_failed="true"
	else
		rm -f "$INSTALL_RECORD"
	fi
	if [ "$OLD_IDENTITY_PRESENT" = "true" ]; then
		restore_file "${BACKUP_DIR}/identity" "$IDENTITY_FILE" || rollback_failed="true"
	else
		rm -f "$IDENTITY_FILE"
	fi

	if [ "$INSTALL_MODE" = "native" ]; then
		systemctl daemon-reload >/dev/null 2>&1
		if [ "$OLD_SERVICE_ENABLED" = "true" ]; then
			systemctl enable one-node-node.service >/dev/null 2>&1 || rollback_failed="true"
		else
			systemctl disable one-node-node.service >/dev/null 2>&1
		fi
		if [ "$OLD_SERVICE_ACTIVE" = "true" ]; then
			systemctl restart one-node-node.service >/dev/null 2>&1 || rollback_failed="true"
		else
			systemctl stop one-node-node.service >/dev/null 2>&1
		fi
	elif [ "$OLD_DOCKER_RUNNING" = "true" ] && [ "$OLD_COMPOSE_PRESENT" = "true" ]; then
		docker compose -f "$COMPOSE_FILE" up -d >/dev/null 2>&1 || rollback_failed="true"
	else
		docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
	fi
	set -e
	[ "$rollback_failed" = "false" ]
}

on_exit() {
	exit_status=$?
	trap - EXIT HUP INT TERM
	if [ "$INSTALL_STARTED" = "true" ] && [ "$COMMITTED" != "true" ]; then
		if ! rollback_installation; then
			exit_status=1
		fi
	fi
	[ -z "$BINARY_TARGET_TMP" ] || rm -f "$BINARY_TARGET_TMP"
	[ -z "$ENV_TARGET_TMP" ] || rm -f "$ENV_TARGET_TMP"
	[ -z "$UNIT_TARGET_TMP" ] || rm -f "$UNIT_TARGET_TMP"
	[ -z "$COMPOSE_TARGET_TMP" ] || rm -f "$COMPOSE_TARGET_TMP"
	[ -z "$RECORD_TARGET_TMP" ] || rm -f "$RECORD_TARGET_TMP"
	rm -rf "$TEMP_DIR"
	exit "$exit_status"
}

trap on_exit EXIT
trap 'exit 1' HUP INT TERM
BINARY_SOURCE="${TEMP_DIR}/${PROGRAM}"
ENV_SOURCE="${TEMP_DIR}/${PROGRAM}.env"
UNIT_SOURCE="${TEMP_DIR}/${PROGRAM}.service"
COMPOSE_SOURCE="${TEMP_DIR}/docker-compose.yml"
RECORD_SOURCE="${TEMP_DIR}/.installation"

log "downloading linux/amd64 binary"
download_binary "$ONE_NODE_BINARY_URL" "$BINARY_SOURCE"

expected_sha256=$ONE_NODE_BINARY_SHA256
expected_sha256=$(printf '%s' "$expected_sha256" | tr 'A-F' 'a-f')
case "$expected_sha256" in
	''|*[!0-9a-f]*) die "ONE_NODE_BINARY_SHA256 is not a valid SHA256 digest" ;;
esac
[ "${#expected_sha256}" -eq 64 ] || die "ONE_NODE_BINARY_SHA256 must contain 64 hexadecimal characters"

actual_sha256=$(sha256sum "$BINARY_SOURCE" | awk '{ print $1 }')
[ "$actual_sha256" = "$expected_sha256" ] || die "binary SHA256 verification failed"
chmod 0755 "$BINARY_SOURCE"
"$BINARY_SOURCE" version >/dev/null 2>&1 || die "downloaded binary cannot run on this machine"

: > "$ENV_SOURCE"
chmod 0600 "$ENV_SOURCE"
write_env "NODE_NODE_ID" "$ONE_NODE_ID"
write_env "NODE_HEARTBEAT_INTERVAL" "30s"
write_env "NODE_STATE_DIR" "$ONE_NODE_STATE_DIR"
write_env "CONTROL_ADDR" "$ONE_NODE_SERVER"
write_env "CONTROL_BOOTSTRAP_TOKEN" "$ONE_NODE_BOOTSTRAP_TOKEN"
write_env "CONTROL_BOOTSTRAP_ENV_FILE" "$ENV_FILE"
write_env "XRAY_API_ADDR" "$ONE_NODE_XRAY_API_ADDR"
write_env "XRAY_CONFIG_PATH" "/usr/local/etc/xray/config.json"
write_env "XRAY_BINARY_PATH" "xray"
write_env "LOG_LEVEL" "info"

printf '%s\n' \
	"runtime=${INSTALL_MODE}" \
	"state_dir=${ONE_NODE_STATE_DIR}" \
	> "$RECORD_SOURCE"
chmod 0600 "$RECORD_SOURCE"

cat > "$UNIT_SOURCE" <<'EOF'
[Unit]
Description=One Node runtime agent
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/one-node-node
EnvironmentFile=/opt/one-node-node/one-node-node.env
ExecStart=/opt/one-node-node/one-node-node start
Restart=always
RestartSec=5s
UMask=0077
TimeoutStopSec=30s

[Install]
WantedBy=multi-user.target
EOF

if [ "$INSTALL_MODE" = "docker" ]; then
	ensure_docker
	XRAY_BINARY_HOST=$(command -v xray 2>/dev/null || true)
	[ -n "$XRAY_BINARY_HOST" ] || die "xray must be installed on the host before Docker installation"
	XRAY_BINARY_HOST=$(realpath -- "$XRAY_BINARY_HOST")
	[ -f "$XRAY_BINARY_HOST" ] && [ ! -L "$XRAY_BINARY_HOST" ] || die "xray must resolve to a regular executable"
	install -d -m 0755 /usr/local/etc/xray
	cat > "$COMPOSE_SOURCE" <<EOF
services:
  one-node-node:
    image: "${ONE_NODE_DOCKER_IMAGE}"
    container_name: "${CONTAINER_NAME}"
    network_mode: host
    restart: unless-stopped
    env_file:
      - "${ENV_FILE}"
    volumes:
      - "${INSTALL_DIR}:${INSTALL_DIR}"
      - "${ONE_NODE_STATE_DIR}:${ONE_NODE_STATE_DIR}"
      - "/usr/local/etc/xray:/usr/local/etc/xray"
      - "${XRAY_BINARY_HOST}:/usr/local/bin/xray:ro"
      - "/etc/ssl/certs:/etc/ssl/certs:ro"
    entrypoint:
      - "${BINARY_FILE}"
      - "start"
EOF
	chmod 0600 "$COMPOSE_SOURCE"
fi

[ ! -L "$INSTALL_DIR" ] || die "installation directory must not be a symbolic link"
install -d -m 0755 "$INSTALL_DIR"
if [ -e "$ONE_NODE_STATE_DIR" ]; then
	[ -d "$ONE_NODE_STATE_DIR" ] && [ ! -L "$ONE_NODE_STATE_DIR" ] || die "ONE_NODE_STATE_DIR must be a real directory"
	chmod 0700 "$ONE_NODE_STATE_DIR"
else
	install -d -m 0700 "$ONE_NODE_STATE_DIR"
fi

install -d -m 0700 "$BACKUP_DIR"
if [ "$INSTALL_MODE" = "native" ]; then
	if systemctl is-active --quiet one-node-node.service; then
		OLD_SERVICE_ACTIVE="true"
	fi
	if systemctl is-enabled --quiet one-node-node.service; then
		OLD_SERVICE_ENABLED="true"
	fi
elif docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -qx true; then
	OLD_DOCKER_RUNNING="true"
fi
if [ -e "$BINARY_FILE" ]; then
	[ -f "$BINARY_FILE" ] && [ ! -L "$BINARY_FILE" ] || die "existing node binary must be a regular file"
	cp -p "$BINARY_FILE" "${BACKUP_DIR}/binary"
	OLD_BINARY_PRESENT="true"
fi
if [ -e "$ENV_FILE" ]; then
	[ -f "$ENV_FILE" ] && [ ! -L "$ENV_FILE" ] || die "existing node environment must be a regular file"
	cp -p "$ENV_FILE" "${BACKUP_DIR}/env"
	OLD_ENV_PRESENT="true"
fi
if [ -e "$UNIT_FILE" ]; then
	[ -f "$UNIT_FILE" ] && [ ! -L "$UNIT_FILE" ] || die "existing node service unit must be a regular file"
	cp -p "$UNIT_FILE" "${BACKUP_DIR}/unit"
	OLD_UNIT_PRESENT="true"
fi
if [ -e "$COMPOSE_FILE" ]; then
	[ -f "$COMPOSE_FILE" ] && [ ! -L "$COMPOSE_FILE" ] || die "existing Docker Compose file must be a regular file"
	cp -p "$COMPOSE_FILE" "${BACKUP_DIR}/compose"
	OLD_COMPOSE_PRESENT="true"
fi
if [ -e "$INSTALL_RECORD" ]; then
	[ -f "$INSTALL_RECORD" ] && [ ! -L "$INSTALL_RECORD" ] || die "existing installation record must be a regular file"
	cp -p "$INSTALL_RECORD" "${BACKUP_DIR}/record"
	OLD_RECORD_PRESENT="true"
fi
if [ -e "$IDENTITY_FILE" ]; then
	[ -f "$IDENTITY_FILE" ] && [ ! -L "$IDENTITY_FILE" ] || die "existing node identity must be a regular file"
	cp -p "$IDENTITY_FILE" "${BACKUP_DIR}/identity"
	OLD_IDENTITY_PRESENT="true"
fi

INSTALL_STARTED="true"

BINARY_TARGET_TMP=$(mktemp "${INSTALL_DIR}/.${PROGRAM}.XXXXXX")
install -m 0755 "$BINARY_SOURCE" "$BINARY_TARGET_TMP"
mv -f "$BINARY_TARGET_TMP" "$BINARY_FILE"
BINARY_TARGET_TMP=""
ENV_TARGET_TMP=$(mktemp "${INSTALL_DIR}/.${PROGRAM}.env.XXXXXX")
install -m 0600 "$ENV_SOURCE" "$ENV_TARGET_TMP"
mv -f "$ENV_TARGET_TMP" "$ENV_FILE"
ENV_TARGET_TMP=""
chmod 0600 "$ENV_FILE"
RECORD_TARGET_TMP=$(mktemp "${INSTALL_DIR}/.installation.XXXXXX")
install -m 0600 "$RECORD_SOURCE" "$RECORD_TARGET_TMP"
mv -f "$RECORD_TARGET_TMP" "$INSTALL_RECORD"
RECORD_TARGET_TMP=""

if [ "$INSTALL_MODE" = "native" ]; then
	UNIT_TARGET_TMP=$(mktemp "/etc/systemd/system/.${PROGRAM}.service.XXXXXX")
	install -m 0644 "$UNIT_SOURCE" "$UNIT_TARGET_TMP"
	mv -f "$UNIT_TARGET_TMP" "$UNIT_FILE"
	UNIT_TARGET_TMP=""
	systemctl daemon-reload
	systemctl enable --now one-node-node.service
	systemctl restart one-node-node.service
	systemctl is-active --quiet one-node-node.service || die "service did not become active"
else
	COMPOSE_TARGET_TMP=$(mktemp "${INSTALL_DIR}/.docker-compose.yml.XXXXXX")
	install -m 0600 "$COMPOSE_SOURCE" "$COMPOSE_TARGET_TMP"
	mv -f "$COMPOSE_TARGET_TMP" "$COMPOSE_FILE"
	COMPOSE_TARGET_TMP=""
	docker compose -f "$COMPOSE_FILE" up -d --force-recreate
	docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" | grep -qx true ||
		die "Docker service did not become active"
fi

enrolled="false"
remaining=$ONE_NODE_ENROLL_TIMEOUT
while [ "$remaining" -gt 0 ]; do
	if [ "$INSTALL_MODE" = "native" ]; then
		systemctl is-active --quiet one-node-node.service ||
			die "service stopped before node enrollment completed"
	else
		docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null |
			grep -qx true ||
			die "Docker service stopped before node enrollment completed"
	fi
	if [ -s "$IDENTITY_FILE" ] && \
		grep -Eq '"state"[[:space:]]*:[[:space:]]*"active"' "$IDENTITY_FILE" && \
		! grep -Eq '^[[:space:]]*(export[[:space:]]+)?CONTROL_BOOTSTRAP_TOKEN[[:space:]]*=' "$ENV_FILE"; then
		enrolled="true"
		break
	fi
	sleep 1
	remaining=$((remaining - 1))
done
[ "$enrolled" = "true" ] || die "node enrollment did not complete before the timeout"
[ "$(stat -c '%a' "$IDENTITY_FILE")" = "600" ] || die "node credential file permissions are not 0600"

COMMITTED="true"
log "${INSTALL_MODE} installation complete; node enrollment is active"
