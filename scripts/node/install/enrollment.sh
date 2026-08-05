#!/bin/sh

# Post-start enrollment readiness checks shared by Native and Docker modes.

runtime_is_active() {
	if [ "$INSTALL_MODE" = "native" ]; then
		systemctl is-active --quiet one-node-node.service
	else
		docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null |
			grep -qx true
	fi
}

print_runtime_logs() {
	log "recent ${INSTALL_MODE} runtime logs:"
	if [ "$INSTALL_MODE" = "native" ]; then
		journalctl --unit one-node-node.service --lines 120 --no-pager --output cat >&2 || true
	else
		docker logs --tail 120 "$CONTAINER_NAME" >&2 || true
	fi
}

wait_for_enrollment() {
	enrolled="false"
	remaining=$ONE_NODE_ENROLL_TIMEOUT
	while [ "$remaining" -gt 0 ]; do
		if ! runtime_is_active; then
			print_runtime_logs
			die "${INSTALL_MODE} service stopped before node enrollment completed"
		fi
		if [ -s "$IDENTITY_FILE" ] &&
			grep -Eq '"state"[[:space:]]*:[[:space:]]*"active"' "$IDENTITY_FILE" &&
			! grep -Eq '^[[:space:]]*(export[[:space:]]+)?CONTROL_BOOTSTRAP_TOKEN[[:space:]]*=' "$ENV_FILE"; then
			enrolled="true"
			break
		fi
		sleep 1
		remaining=$((remaining - 1))
	done
	if [ "$enrolled" != "true" ]; then
		print_runtime_logs
		die "node enrollment did not complete before the timeout"
	fi
	[ "$(stat -c '%a' "$IDENTITY_FILE")" = "600" ] ||
		die "node credential file permissions are not 0600"
}
