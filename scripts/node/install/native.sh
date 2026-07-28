#!/bin/sh

# Native systemd source generation, state capture, and activation.
# Installer globals are shared across sourced modules.
# shellcheck disable=SC2034

write_native_source() {
	cat > "$UNIT_SOURCE" <<'EOF'
[Unit]
Description=One Node runtime agent
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/one-node-node
EnvironmentFile=/opt/one-node-node/one-node-node.env
ExecStart=/opt/one-node-node/one-node-node start
Restart=always
RestartSec=5s
UMask=0077
TimeoutStopSec=30s

[Install]
WantedBy=multi-user.target
EOF
}

capture_native_runtime_state() {
	if systemctl is-active --quiet one-node-node.service; then
		OLD_SERVICE_ACTIVE="true"
	fi
	if systemctl is-enabled --quiet one-node-node.service; then
		OLD_SERVICE_ENABLED="true"
	fi
}

install_native_runtime() {
	UNIT_TARGET_TMP=$(mktemp "/etc/systemd/system/.${PROGRAM}.service.XXXXXX")
	install -m 0644 "$UNIT_SOURCE" "$UNIT_TARGET_TMP"
	mv -f "$UNIT_TARGET_TMP" "$UNIT_FILE"
	UNIT_TARGET_TMP=""
	systemctl daemon-reload
	systemctl enable --now one-node-node.service
	systemctl restart one-node-node.service
	systemctl is-active --quiet one-node-node.service ||
		die "service did not become active"
}
