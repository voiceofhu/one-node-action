#!/usr/bin/env bash
set -Eeuo pipefail

: "${SSH_HOST:?SSH_HOST is required}"
: "${REMOTE_DIR:?REMOTE_DIR is required}"
: "${DOCKER_IMAGE:?DOCKER_IMAGE is required}"
: "${COMPOSE_FILE:?COMPOSE_FILE is required}"
: "${GHCR_USERNAME:?GHCR_USERNAME is required}"
: "${GHCR_TOKEN:?GHCR_TOKEN is required}"

case "$REMOTE_DIR" in
	/*) ;;
	*)
		echo "REMOTE_DIR must be an absolute path" >&2
		exit 1
		;;
esac
if [ "$REMOTE_DIR" = / ]; then
	echo "REMOTE_DIR must not be /" >&2
	exit 1
fi
test -f "$COMPOSE_FILE" || {
	echo "Compose file not found: $COMPOSE_FILE" >&2
	exit 1
}

ssh "$SSH_HOST" "test -d '$REMOTE_DIR' && test -w '$REMOTE_DIR' && test -f '$REMOTE_DIR/.env' && docker info >/dev/null" || {
	echo "$REMOTE_DIR must exist, contain .env, and be writable; the deploy user must be able to run Docker" >&2
	exit 1
}

scp "$COMPOSE_FILE" "$SSH_HOST:$REMOTE_DIR/docker-compose.yml.next"
printf '%s' "$GHCR_TOKEN" |
	ssh "$SSH_HOST" "docker login ghcr.io --username '$GHCR_USERNAME' --password-stdin"

ssh "$SSH_HOST" bash -s -- "$REMOTE_DIR" "$DOCKER_IMAGE" <<'REMOTE_DEPLOY'
set -Eeuo pipefail

remote_dir=$1
image=$2
container_name=one-node-server
service_name=server

cd "$remote_dir"
test -f docker-compose.yml.next

compose() {
	compose_file=$1
	shift
	env DOCKER_IMAGE="$image" CONTAINER_NAME="$container_name" docker compose \
		--project-name one-node \
		--env-file .env \
		-f "$compose_file" \
		"$@"
}

compose docker-compose.yml.next config --quiet
previous_image=$(docker inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null || true)

rollback() {
	exit_code=$?
	trap - ERR
	echo "Deployment failed; attempting to restore the previous container" >&2
	if [ -n "$previous_image" ] && [ -f docker-compose.yml ]; then
		failed_image=$image
		image=$previous_image
		compose docker-compose.yml up -d "$service_name" || true
		image=$failed_image
	fi
	rm -f docker-compose.yml.next
	exit "$exit_code"
}
trap rollback ERR

compose docker-compose.yml.next pull "$service_name"
compose docker-compose.yml.next up -d "$service_name"

for attempt in $(seq 1 30); do
	container_status=$(docker inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null || true)
	case "$container_status" in
		restarting | exited | dead)
			echo "Container $container_name entered $container_status during startup" >&2
			docker logs --tail 120 "$container_name" >&2 || true
			false
			;;
	esac
	published_port=$(docker port "$container_name" 27520/tcp 2>/dev/null | sed -n '1s/.*://p' || true)
	if [ -n "$published_port" ] &&
		curl --fail --silent --show-error "http://127.0.0.1:${published_port}/api/healthz" >/dev/null &&
		curl --fail --silent --show-error "http://127.0.0.1:${published_port}/" >/dev/null; then
		echo "One Node Server is healthy and serving Web at /"
		break
	fi
	if [ "$attempt" = 30 ]; then
		docker logs --tail 120 "$container_name" >&2 || true
		false
	fi
	sleep 2
done

mv -f docker-compose.yml.next docker-compose.yml
trap - ERR
REMOTE_DEPLOY
