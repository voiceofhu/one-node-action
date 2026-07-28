#!/bin/sh

# Installer constants, argument parsing, and environment validation.
# Installer globals are shared across sourced modules.
# shellcheck disable=SC2034

initialize_install_config() {
	PROGRAM="one-node-node"
	INSTALL_DIR="/opt/one-node-node"
	ENV_FILE="${INSTALL_DIR}/one-node-node.env"
	UNIT_FILE="/etc/systemd/system/one-node-node.service"
	COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
	INSTALL_RECORD="${INSTALL_DIR}/.installation"
	CONTAINER_NAME="one-node-node"

	INSTALL_MODE="native"
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
}

parse_install_arguments() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--mode)
				[ "$#" -ge 2 ] || die "--mode requires native or docker"
				INSTALL_MODE=$2
				shift 2
				;;
			--help|-h)
				show_help
				exit 0
				;;
			*) die "unknown argument: $1" ;;
		esac
	done
	case "$INSTALL_MODE" in
		native|docker) ;;
		*) die "--mode must be native or docker" ;;
	esac
}

validate_install_config() {
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
			[ "$ONE_NODE_ALLOW_INSECURE" = "true" ] ||
				die "plaintext control connections require ONE_NODE_ALLOW_INSECURE=true"
			;;
		*://*) die "ONE_NODE_SERVER uses an unsupported scheme" ;;
		*)
			[ "$ONE_NODE_ALLOW_INSECURE" = "true" ] ||
				die "a control address without a TLS scheme requires ONE_NODE_ALLOW_INSECURE=true"
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
			[ "$ONE_NODE_ALLOW_INSECURE" = "true" ] ||
				die "HTTP binary downloads require ONE_NODE_ALLOW_INSECURE=true"
			;;
		*) die "ONE_NODE_BINARY_URL must use HTTP or HTTPS" ;;
	esac
	case "$ONE_NODE_DOCKER_IMAGE" in
		''|*' '*|*'	'*)
			die "ONE_NODE_DOCKER_IMAGE must be a non-empty image reference without whitespace"
			;;
	esac
	ONE_NODE_BINARY_SHA256=$(normalize_sha256 "$ONE_NODE_BINARY_SHA256")
	validate_sha256 "$ONE_NODE_BINARY_SHA256" ||
		die "ONE_NODE_BINARY_SHA256 must be a 64-character hexadecimal digest"
}
