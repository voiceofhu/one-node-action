#!/bin/sh

ensure_docker() {
	if ! command -v docker >/dev/null 2>&1; then
		command -v apt-get >/dev/null 2>&1 || die "Docker is required"
		log "installing Debian Docker Engine and Compose"
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

prepare_docker_image() {
	ensure_docker
	docker pull "$ONE_NODE_DOCKER_IMAGE"
	version_output=$(docker run --rm --entrypoint /usr/local/bin/one-node-node \
		"$ONE_NODE_DOCKER_IMAGE" version) ||
		die "immutable One Node image cannot run on this machine"
	case "$version_output" in
	"one-node-node $ONE_NODE_VERSION "*"; sing-box "*) ;;
	*) die "immutable image has unexpected product or data-plane metadata" ;;
	esac
}

write_docker_source() {
	cat >"$COMPOSE_SOURCE" <<EOF
services:
  one-node-node:
    image: "${ONE_NODE_DOCKER_IMAGE}"
    container_name: "${CONTAINER_NAME}"
    network_mode: host
    restart: unless-stopped
    read_only: true
    cap_add:
      - NET_ADMIN
      - NET_RAW
    env_file:
      - "${ENV_FILE}"
    volumes:
      - "${INSTALL_DIR}:${INSTALL_DIR}"
      - "${ONE_NODE_STATE_DIR}:${ONE_NODE_STATE_DIR}"
      - "/etc/ssl/certs:/etc/ssl/certs:ro"
    tmpfs:
      - /tmp:mode=1777
    command:
      - start
EOF
	chmod 0600 "$COMPOSE_SOURCE"
}

install_docker_runtime() {
	install -m 0600 "$COMPOSE_SOURCE" "$COMPOSE_FILE"
	docker compose -f "$COMPOSE_FILE" up -d
	docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" | grep -qx true ||
		die "One Node container did not become active"
}
