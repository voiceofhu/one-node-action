#!/bin/sh

write_native_source() {
	cat >"$UNIT_SOURCE" <<'EOF'
[Unit]
Description=One Node sing-box runtime
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

install_native_runtime() {
	install -m 0644 "$UNIT_SOURCE" "$UNIT_FILE"
	systemctl daemon-reload
	systemctl enable --now one-node-node.service
	systemctl is-active --quiet one-node-node.service ||
		die "one-node-node.service did not become active"
}
