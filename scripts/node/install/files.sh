#!/bin/sh

# Transaction workspace, generated common files, backup, and rollback.
# Installer globals are shared across sourced modules.
# shellcheck disable=SC2034

initialize_install_workspace() {
	TEMP_DIR=$(mktemp -d)
	chmod 0700 "$TEMP_DIR"
	BACKUP_DIR="${TEMP_DIR}/backup"
	BINARY_FILE="${INSTALL_DIR}/${PROGRAM}"
	IDENTITY_FILE="${ONE_NODE_STATE_DIR}/node-secret"
	BINARY_SOURCE="${TEMP_DIR}/${PROGRAM}"
	ENV_SOURCE="${TEMP_DIR}/${PROGRAM}.env"
	UNIT_SOURCE="${TEMP_DIR}/${PROGRAM}.service"
	COMPOSE_SOURCE="${TEMP_DIR}/docker-compose.yml"
	RECORD_SOURCE="${TEMP_DIR}/.installation"

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

	trap on_install_exit EXIT
	trap 'exit 1' HUP INT TERM
}

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
			systemctl enable one-node-node.service >/dev/null 2>&1 ||
				rollback_failed="true"
		else
			systemctl disable one-node-node.service >/dev/null 2>&1
		fi
		if [ "$OLD_SERVICE_ACTIVE" = "true" ]; then
			systemctl restart one-node-node.service >/dev/null 2>&1 ||
				rollback_failed="true"
		else
			systemctl stop one-node-node.service >/dev/null 2>&1
		fi
	elif [ "$OLD_DOCKER_RUNNING" = "true" ] && [ "$OLD_COMPOSE_PRESENT" = "true" ]; then
		docker compose -f "$COMPOSE_FILE" up -d >/dev/null 2>&1 ||
			rollback_failed="true"
	else
		docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
	fi
	set -e
	[ "$rollback_failed" = "false" ]
}

on_install_exit() {
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

prepare_binary_source() {
	log "downloading linux/amd64 binary"
	download_binary "$ONE_NODE_BINARY_URL" "$BINARY_SOURCE"
	actual_sha256=$(sha256sum "$BINARY_SOURCE" | awk '{ print $1 }')
	[ "$actual_sha256" = "$ONE_NODE_BINARY_SHA256" ] ||
		die "binary SHA256 verification failed"
	chmod 0755 "$BINARY_SOURCE"
	"$BINARY_SOURCE" version >/dev/null 2>&1 ||
		die "downloaded binary cannot run on this machine"
}

write_common_sources() {
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
}

backup_install_file() {
	target_path=$1
	backup_name=$2
	description=$3
	[ -e "$target_path" ] || return 1
	[ -f "$target_path" ] && [ ! -L "$target_path" ] ||
		die "$description must be a regular file"
	cp -p "$target_path" "${BACKUP_DIR}/${backup_name}" ||
		die "failed to back up $description"
}

prepare_install_target() {
	[ ! -L "$INSTALL_DIR" ] ||
		die "installation directory must not be a symbolic link"
	install -d -m 0755 "$INSTALL_DIR"
	if [ -e "$ONE_NODE_STATE_DIR" ]; then
		[ -d "$ONE_NODE_STATE_DIR" ] && [ ! -L "$ONE_NODE_STATE_DIR" ] ||
			die "ONE_NODE_STATE_DIR must be a real directory"
		chmod 0700 "$ONE_NODE_STATE_DIR"
	else
		install -d -m 0700 "$ONE_NODE_STATE_DIR"
	fi

	install -d -m 0700 "$BACKUP_DIR"
	if [ "$INSTALL_MODE" = "native" ]; then
		capture_native_runtime_state
	else
		capture_docker_runtime_state
	fi
	if backup_install_file "$BINARY_FILE" binary "existing node binary"; then
		OLD_BINARY_PRESENT="true"
	fi
	if backup_install_file "$ENV_FILE" env "existing node environment"; then
		OLD_ENV_PRESENT="true"
	fi
	if backup_install_file "$UNIT_FILE" unit "existing node service unit"; then
		OLD_UNIT_PRESENT="true"
	fi
	if backup_install_file "$COMPOSE_FILE" compose "existing Docker Compose file"; then
		OLD_COMPOSE_PRESENT="true"
	fi
	if backup_install_file "$INSTALL_RECORD" record "existing installation record"; then
		OLD_RECORD_PRESENT="true"
	fi
	if backup_install_file "$IDENTITY_FILE" identity "existing node identity"; then
		OLD_IDENTITY_PRESENT="true"
	fi
}

install_common_files() {
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
}
