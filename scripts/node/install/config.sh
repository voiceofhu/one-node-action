#!/bin/sh

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
	ONE_NODE_VERSION=${ONE_NODE_VERSION:-}
	ONE_NODE_RELEASE_BASE_URL=${ONE_NODE_RELEASE_BASE_URL:-}
	ONE_NODE_BINARY_SHA256_AMD64=${ONE_NODE_BINARY_SHA256_AMD64:-}
	ONE_NODE_BINARY_SHA256_ARM64=${ONE_NODE_BINARY_SHA256_ARM64:-}
	ONE_NODE_DOCKER_IMAGE=${ONE_NODE_DOCKER_IMAGE:-}
	ONE_NODE_STATE_DIR=${ONE_NODE_STATE_DIR:-/var/lib/one-node-node}
	ONE_NODE_EXPECTED_CONFIG_REVISION=${ONE_NODE_EXPECTED_CONFIG_REVISION:-0}
	ONE_NODE_EXPECTED_BINDINGS_REVISION=${ONE_NODE_EXPECTED_BINDINGS_REVISION:-0}
	ONE_NODE_ALLOW_INSECURE=${ONE_NODE_ALLOW_INSECURE:-false}
	ONE_NODE_ENROLL_TIMEOUT=${ONE_NODE_ENROLL_TIMEOUT:-120}
	ONE_NODE_ARCH=""
	ONE_NODE_BINARY_NAME=""
	ONE_NODE_BINARY_URL=""
	ONE_NODE_BINARY_SHA256=""
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
	for pair in \
		"ONE_NODE_SERVER|$ONE_NODE_SERVER" \
		"ONE_NODE_ID|$ONE_NODE_ID" \
		"ONE_NODE_BOOTSTRAP_TOKEN|$ONE_NODE_BOOTSTRAP_TOKEN" \
		"ONE_NODE_VERSION|$ONE_NODE_VERSION" \
		"ONE_NODE_EXPECTED_CONFIG_REVISION|$ONE_NODE_EXPECTED_CONFIG_REVISION" \
		"ONE_NODE_EXPECTED_BINDINGS_REVISION|$ONE_NODE_EXPECTED_BINDINGS_REVISION"
	do
		name=${pair%%|*}
		value=${pair#*|}
		require_value "$name" "$value"
		require_single_line "$name" "$value"
	done

	case "$ONE_NODE_ID" in
	''|*[!0-9]*|0) die "ONE_NODE_ID must be a positive integer" ;;
	esac
	case "$ONE_NODE_VERSION" in
	''|*[!0-9.]*) die "ONE_NODE_VERSION must be a dotted numeric version" ;;
	esac
	validate_decimal "$ONE_NODE_EXPECTED_CONFIG_REVISION" ||
		die "ONE_NODE_EXPECTED_CONFIG_REVISION must be canonical decimal"
	validate_decimal "$ONE_NODE_EXPECTED_BINDINGS_REVISION" ||
		die "ONE_NODE_EXPECTED_BINDINGS_REVISION must be canonical decimal"
	case "$ONE_NODE_ENROLL_TIMEOUT" in
	''|*[!0-9]*|0) die "ONE_NODE_ENROLL_TIMEOUT must be a positive integer" ;;
	esac
	case "$ONE_NODE_ALLOW_INSECURE" in
	true|false) ;;
	*) die "ONE_NODE_ALLOW_INSECURE must be true or false" ;;
	esac

	case "$ONE_NODE_SERVER" in
	https://*|grpcs://*) ;;
	http://*|grpc://*|*:* )
		[ "$ONE_NODE_ALLOW_INSECURE" = "true" ] ||
			die "plaintext control connections require ONE_NODE_ALLOW_INSECURE=true"
		;;
	*) die "ONE_NODE_SERVER is invalid" ;;
	esac
	case "$ONE_NODE_STATE_DIR" in
	/*) ;;
	*) die "ONE_NODE_STATE_DIR must be absolute" ;;
	esac
	ONE_NODE_STATE_DIR=$(realpath -m -- "$ONE_NODE_STATE_DIR")
	case "$ONE_NODE_STATE_DIR" in
	/var/lib/one-node-node|/var/lib/one-node-node/*) ;;
	*) die "ONE_NODE_STATE_DIR must remain under /var/lib/one-node-node" ;;
	esac

	if [ "$INSTALL_MODE" = "native" ]; then
		require_value "ONE_NODE_RELEASE_BASE_URL" "$ONE_NODE_RELEASE_BASE_URL"
		release_tag=${ONE_NODE_RELEASE_BASE_URL%/}
		release_tag=${release_tag##*/}
		case "$release_tag" in
		node-rc-v"$ONE_NODE_VERSION"-rc.*) ;;
		*) die "ONE_NODE_RELEASE_BASE_URL must pin the requested immutable RC" ;;
		esac
		rc_number=${release_tag##*.}
		case "$rc_number" in
		''|*[!0-9]*|0) die "ONE_NODE_RELEASE_BASE_URL has an invalid RC number" ;;
		esac
		case "$ONE_NODE_RELEASE_BASE_URL" in
		https://*) ;;
		http://*)
			[ "$ONE_NODE_ALLOW_INSECURE" = "true" ] ||
				die "HTTP release assets require ONE_NODE_ALLOW_INSECURE=true"
			;;
		*) die "ONE_NODE_RELEASE_BASE_URL must use HTTP or HTTPS" ;;
		esac
		ONE_NODE_BINARY_SHA256=$(normalize_sha256 "$ONE_NODE_BINARY_SHA256")
		validate_sha256 "$ONE_NODE_BINARY_SHA256" ||
			die "selected binary checksum must be a pinned SHA-256"
		ONE_NODE_BINARY_URL="${ONE_NODE_RELEASE_BASE_URL%/}/${ONE_NODE_BINARY_NAME}"
	else
		require_value "ONE_NODE_DOCKER_IMAGE" "$ONE_NODE_DOCKER_IMAGE"
		case "$ONE_NODE_DOCKER_IMAGE" in
		*@sha256:*) ;;
		*) die "ONE_NODE_DOCKER_IMAGE must be pinned by digest" ;;
		esac
		image_digest=${ONE_NODE_DOCKER_IMAGE##*@sha256:}
		validate_sha256 "$(normalize_sha256 "$image_digest")" ||
			die "ONE_NODE_DOCKER_IMAGE has an invalid digest"
	fi
}
