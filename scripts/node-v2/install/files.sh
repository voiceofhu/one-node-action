#!/bin/sh

# Fresh-install workspace and exact file ownership. Upgrade rollback is A03.
# shellcheck disable=SC2034

initialize_install_workspace() {
	TEMP_DIR=$(mktemp -d "/tmp/one-node-v2-install.XXXXXX")
	chmod 0700 "$TEMP_DIR"
	BINARY_SOURCE="${TEMP_DIR}/${PROGRAM}"
	ENV_SOURCE="${TEMP_DIR}/${PROGRAM}.env"
	UNIT_SOURCE="${TEMP_DIR}/${PROGRAM}.service"
	COMPOSE_SOURCE="${TEMP_DIR}/docker-compose.yml"
	RECORD_SOURCE="${TEMP_DIR}/.installation-v2"
	BINARY_FILE="${INSTALL_DIR}/${PROGRAM}"
	IDENTITY_FILE="${ONE_NODE_STATE_DIR}/node-secret"
	RUNTIME_STATE_FILE="${ONE_NODE_STATE_DIR}/runtime-active.json"
	INSTALL_STARTED="false"
	INSTALL_COMMITTED="false"
	trap on_install_exit EXIT
	trap 'exit 1' HUP INT TERM
}

on_install_exit() {
	exit_status=$?
	trap - EXIT HUP INT TERM
	if [ "$INSTALL_STARTED" = "true" ] && [ "$INSTALL_COMMITTED" != "true" ]; then
		set +e
		if [ "$INSTALL_MODE" = "native" ]; then
			systemctl disable --now one-node-node.service >/dev/null 2>&1
			rm -f -- "$UNIT_FILE"
			systemctl daemon-reload >/dev/null 2>&1
		else
			if command -v docker >/dev/null 2>&1; then
				docker compose -f "$COMPOSE_FILE" down --remove-orphans >/dev/null 2>&1
				docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
			fi
		fi
		rm -f -- "$BINARY_FILE" "$ENV_FILE" "$COMPOSE_FILE" "$INSTALL_RECORD"
		set -e
		log "installation did not become ready; credential state was preserved for a safe retry"
	fi
	rm -rf -- "$TEMP_DIR"
	exit "$exit_status"
}

prepare_native_binary() {
	log "downloading ${ONE_NODE_BINARY_NAME}"
	download_file "$ONE_NODE_BINARY_URL" "$BINARY_SOURCE"
	actual_sha256=$(sha256sum "$BINARY_SOURCE" | awk '{ print $1 }')
	[ "$actual_sha256" = "$ONE_NODE_BINARY_SHA256" ] ||
		die "binary SHA256 verification failed"
	chmod 0755 "$BINARY_SOURCE"
	version_output=$("$BINARY_SOURCE" version) ||
		die "downloaded binary cannot run on this machine"
	case "$version_output" in
	"one-node-node $ONE_NODE_VERSION "*"; sing-box "*) ;;
	*) die "downloaded binary has unexpected product or data-plane metadata" ;;
	esac
}

write_common_sources() {
	: >"$ENV_SOURCE"
	chmod 0600 "$ENV_SOURCE"
	write_env "NODE_NODE_ID" "$ONE_NODE_ID"
	write_env "NODE_HEARTBEAT_INTERVAL" "30s"
	write_env "NODE_STATE_DIR" "$ONE_NODE_STATE_DIR"
	write_env "CONTROL_ADDR" "$ONE_NODE_SERVER"
	write_env "CONTROL_BOOTSTRAP_TOKEN" "$ONE_NODE_BOOTSTRAP_TOKEN"
	write_env "CONTROL_BOOTSTRAP_ENV_FILE" "$ENV_FILE"
	write_env "LOG_LEVEL" "info"

	printf '%s\n' \
		"format=v2" \
		"runtime=${INSTALL_MODE}" \
		"state_dir=${ONE_NODE_STATE_DIR}" \
		"version=${ONE_NODE_VERSION}" \
		"architecture=${ONE_NODE_ARCH}" \
		"image=${ONE_NODE_DOCKER_IMAGE}" \
		>"$RECORD_SOURCE"
	chmod 0600 "$RECORD_SOURCE"
}

prepare_install_directories() {
	install -d -m 0755 "$INSTALL_DIR"
	if [ -e "$ONE_NODE_STATE_DIR" ]; then
		[ -d "$ONE_NODE_STATE_DIR" ] && [ ! -L "$ONE_NODE_STATE_DIR" ] ||
			die "ONE_NODE_STATE_DIR must be a real directory"
		chmod 0700 "$ONE_NODE_STATE_DIR"
	else
		install -d -m 0700 "$ONE_NODE_STATE_DIR"
	fi
}

install_common_files() {
	INSTALL_STARTED="true"
	if [ "$INSTALL_MODE" = "native" ]; then
		install -m 0755 "$BINARY_SOURCE" "$BINARY_FILE"
	fi
	install -m 0600 "$ENV_SOURCE" "$ENV_FILE"
	install -m 0600 "$RECORD_SOURCE" "$INSTALL_RECORD"
}
