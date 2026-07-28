#!/bin/sh

# Docker/Compose preparation, source generation, state capture, and activation.
# Installer globals are shared across sourced modules.
# shellcheck disable=SC2034

ensure_docker() {
	if ! command -v docker >/dev/null 2>&1; then
		command -v apt-get >/dev/null 2>&1 ||
			die "Docker is required for Docker installation"
		log "installing Docker Engine and Compose"
		apt-get update
		env DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
		if ! env DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-v2; then
			env DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-plugin
		fi
	fi
	systemctl enable --now docker.service
	docker info >/dev/null 2>&1 || die "Docker daemon is unavailable"
	docker compose version >/dev/null 2>&1 ||
		die "Docker Compose plugin is required"
}

write_docker_source() {
	ensure_docker
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
}

capture_docker_runtime_state() {
	if docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null |
		grep -qx true; then
		OLD_DOCKER_RUNNING="true"
	fi
}

install_docker_runtime() {
	COMPOSE_TARGET_TMP=$(mktemp "${INSTALL_DIR}/.docker-compose.yml.XXXXXX")
	install -m 0600 "$COMPOSE_SOURCE" "$COMPOSE_TARGET_TMP"
	mv -f "$COMPOSE_TARGET_TMP" "$COMPOSE_FILE"
	COMPOSE_TARGET_TMP=""
	docker compose -f "$COMPOSE_FILE" up -d --force-recreate
	docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" |
		grep -qx true ||
		die "Docker service did not become active"
}
