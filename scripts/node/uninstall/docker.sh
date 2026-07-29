#!/bin/sh

# Docker Compose runtime removal and conditional Docker Engine cleanup.

installed_docker_packages() {
	docker_packages=""
	for docker_package in \
		docker-ce \
		docker-ce-cli \
		containerd.io \
		docker-buildx-plugin \
		docker-compose-plugin \
		docker-ce-rootless-extras \
		docker.io \
		docker-compose-v2 \
		docker-compose
	do
		if dpkg-query -W -f='${Status}' "$docker_package" 2>/dev/null |
			grep -Fq "install ok installed"; then
			docker_packages="${docker_packages}${docker_packages:+ }${docker_package}"
		fi
	done
	printf '%s\n' "$docker_packages"
}

uninstall_docker_engine_if_unused() {
	remaining_container_ids=$(docker ps -aq) ||
		die "unable to check whether other Docker containers remain"
	if [ -n "$remaining_container_ids" ]; then
		log "Docker was preserved because other containers remain"
		return 0
	fi

	if ! command -v apt-get >/dev/null 2>&1 ||
		! command -v dpkg-query >/dev/null 2>&1; then
		die "apt and dpkg-query are required to uninstall Docker"
	fi
	docker_packages=$(installed_docker_packages)
	[ -n "$docker_packages" ] ||
		die "no supported Debian Docker package was found to uninstall"

	systemctl disable --now docker.service docker.socket >/dev/null 2>&1 || true
	# Package names are collected from the fixed allow-list above.
	# shellcheck disable=SC2086
	env DEBIAN_FRONTEND=noninteractive apt-get purge -y $docker_packages
	log "Docker was uninstalled because no other containers remain"
}

uninstall_docker() {
	command -v docker >/dev/null 2>&1 ||
		die "Docker is required to uninstall the Docker service"
	if [ -f "$COMPOSE_FILE" ] && [ ! -L "$COMPOSE_FILE" ]; then
		docker compose -f "$COMPOSE_FILE" down --remove-orphans
	else
		docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
	fi
	uninstall_docker_engine_if_unused
}
