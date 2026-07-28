#!/bin/sh

# Native systemd runtime removal.

uninstall_native() {
	command -v systemctl >/dev/null 2>&1 ||
		die "systemd is required to uninstall the native service"
	systemctl disable --now one-node-node.service >/dev/null 2>&1 || true
	rm -f -- "$UNIT_FILE"
	systemctl daemon-reload
}
