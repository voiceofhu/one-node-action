#!/bin/sh

# Host Xray discovery, bootstrap configuration, and installation through the
# official XTLS installer.

initialize_xray_config() {
	ONE_NODE_XRAY_INSTALLER_URL=${ONE_NODE_XRAY_INSTALLER_URL:-https://github.com/XTLS/Xray-install/raw/main/install-release.sh}
	XRAY_CONFIG_DIR="/usr/local/etc/xray"
	XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
	XRAY_GEODATA_DIR="/usr/local/share/xray"
	XRAY_MANAGED_CONFIG_MARKER="${XRAY_CONFIG_DIR}/.one-node-managed-config"
	XRAY_SERVICE_NAME="xray.service"
	XRAY_SERVICE_FILE="/etc/systemd/system/xray.service"
	XRAY_SERVICE_OVERRIDE_DIR="${XRAY_SERVICE_FILE}.d"
	XRAY_SERVICE_USER_OVERRIDE_FILE="${XRAY_SERVICE_OVERRIDE_DIR}/99-one-node-service-user.conf"
	XRAY_SERVICE_USER_CHANGED=""
	XRAY_CONFIG_OWNERSHIP=""
}

validate_xray_config() {
	require_single_line "ONE_NODE_XRAY_INSTALLER_URL" "$ONE_NODE_XRAY_INSTALLER_URL"
	case "$ONE_NODE_XRAY_INSTALLER_URL" in
		https://*) ;;
		*) die "ONE_NODE_XRAY_INSTALLER_URL must use HTTPS" ;;
	esac

	# The Xray API is an unauthenticated local control plane. Do not allow the
	# bootstrap installer to expose it on a non-loopback address.
	case "$ONE_NODE_XRAY_API_ADDR" in
		127.0.0.1:*) ;;
		*) die "ONE_NODE_XRAY_API_ADDR must use the IPv4 loopback address (127.0.0.1:<port>)" ;;
	esac
	xray_api_port=${ONE_NODE_XRAY_API_ADDR##*:}
	case "$xray_api_port" in
		''|*[!0-9]*) die "ONE_NODE_XRAY_API_ADDR must contain a numeric port" ;;
	esac
	if ! [ "$xray_api_port" -ge 1 ] 2>/dev/null ||
		! [ "$xray_api_port" -le 65535 ] 2>/dev/null; then
		die "ONE_NODE_XRAY_API_ADDR port must be between 1 and 65535"
	fi
}

resolve_xray_binary() {
	xray_path=$(command -v xray 2>/dev/null || true)
	if [ -z "$xray_path" ] && [ -x /usr/local/bin/xray ]; then
		xray_path=/usr/local/bin/xray
	fi
	[ -n "$xray_path" ] || return 1
	xray_path=$(realpath -- "$xray_path")
	[ -f "$xray_path" ] && [ ! -L "$xray_path" ] || return 1
	"$xray_path" version >/dev/null 2>&1 || return 1
	printf '%s\n' "$xray_path"
}

xray_artifacts_ready() {
	XRAY_BINARY_HOST=$(resolve_xray_binary) || return 1
	for xray_file in \
		"${XRAY_GEODATA_DIR}/geoip.dat" \
		"${XRAY_GEODATA_DIR}/geosite.dat" \
		"$XRAY_SERVICE_FILE"
	do
		[ -f "$xray_file" ] && [ ! -L "$xray_file" ] || return 1
	done
}

xray_config_valid() {
	xray_config_path=$1
	[ -f "$xray_config_path" ] && [ ! -L "$xray_config_path" ] ||
		return 1
	"$XRAY_BINARY_HOST" -test -config "$xray_config_path" >/dev/null 2>&1
}

write_xray_service_user_override() {
	install -d -m 0755 "$XRAY_SERVICE_OVERRIDE_DIR"
	xray_service_user_source="${TEMP_DIR}/one-node-xray-service-user.conf"
	cat > "$xray_service_user_source" <<'EOF'
[Service]
User=root
EOF
	chmod 0644 "$xray_service_user_source"

	if [ -f "$XRAY_SERVICE_USER_OVERRIDE_FILE" ] &&
		[ ! -L "$XRAY_SERVICE_USER_OVERRIDE_FILE" ] &&
		[ "$(sha256sum "$xray_service_user_source" | awk '{ print $1 }')" = "$(sha256sum "$XRAY_SERVICE_USER_OVERRIDE_FILE" | awk '{ print $1 }')" ]; then
		return
	fi
	if [ -e "$XRAY_SERVICE_USER_OVERRIDE_FILE" ] ||
		[ -L "$XRAY_SERVICE_USER_OVERRIDE_FILE" ]; then
		[ -f "$XRAY_SERVICE_USER_OVERRIDE_FILE" ] &&
			[ ! -L "$XRAY_SERVICE_USER_OVERRIDE_FILE" ] ||
			die "Xray service user override must be a regular file: $XRAY_SERVICE_USER_OVERRIDE_FILE"
	fi

	xray_service_user_target_tmp=$(mktemp "${XRAY_SERVICE_OVERRIDE_DIR}/.99-one-node-service-user.conf.XXXXXX")
	install -m 0644 "$xray_service_user_source" "$xray_service_user_target_tmp"
	mv -f "$xray_service_user_target_tmp" "$XRAY_SERVICE_USER_OVERRIDE_FILE"
	XRAY_SERVICE_USER_CHANGED="true"
	log "configured $XRAY_SERVICE_NAME to run as root so it can read protected TLS private keys"
}

ensure_xray_service_user() {
	write_xray_service_user_override
	systemctl daemon-reload
	xray_service_user=$(systemctl show "$XRAY_SERVICE_NAME" --property=User --value) ||
		die "failed to resolve the effective Xray service user"
	[ "$xray_service_user" = "root" ] ||
		die "effective Xray service user is ${xray_service_user:-empty}, expected root"
}

xray_config_is_official_placeholder() {
	[ -f "$XRAY_CONFIG_FILE" ] && [ ! -L "$XRAY_CONFIG_FILE" ] ||
		return 1
	xray_placeholder=$(tr -d '[:space:]' < "$XRAY_CONFIG_FILE") ||
		return 1
	[ "$xray_placeholder" = "{}" ]
}

write_managed_xray_config() {
	install -d -m 0755 "$XRAY_CONFIG_DIR"
	xray_config_source="${TEMP_DIR}/one-node-xray-config.json"
	cat > "$xray_config_source" <<EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "api": {
    "tag": "api",
    "listen": "${ONE_NODE_XRAY_API_ADDR}",
    "services": [
      "HandlerService",
      "LoggerService",
      "StatsService",
      "RoutingService"
    ]
  },
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true,
        "statsUserOnline": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "stats": {},
  "inbounds": [],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    }
  ]
}
EOF
	chmod 0644 "$xray_config_source"
	xray_config_valid "$xray_config_source" ||
		die "generated One Node Xray bootstrap configuration failed Xray validation"

	xray_config_target_tmp=$(mktemp "${XRAY_CONFIG_DIR}/.config.json.XXXXXX")
	install -m 0644 "$xray_config_source" "$xray_config_target_tmp"
	mv -f "$xray_config_target_tmp" "$XRAY_CONFIG_FILE"
	printf '%s\n' \
		"managed_by=one-node-action" \
		"purpose=bootstrap" \
		> "$XRAY_MANAGED_CONFIG_MARKER"
	chmod 0644 "$XRAY_MANAGED_CONFIG_MARKER"
	XRAY_CONFIG_OWNERSHIP="managed"
	log "prepared One Node Xray bootstrap configuration at $XRAY_CONFIG_FILE"
}

prepare_xray_config() {
	if [ -e "$XRAY_CONFIG_FILE" ]; then
		[ -f "$XRAY_CONFIG_FILE" ] && [ ! -L "$XRAY_CONFIG_FILE" ] ||
			die "existing Xray config must be a regular file: $XRAY_CONFIG_FILE"
		if xray_config_is_official_placeholder; then
			log "replacing the official empty Xray placeholder with the One Node bootstrap configuration"
			write_managed_xray_config
			return
		fi
		xray_config_valid "$XRAY_CONFIG_FILE" ||
			die "existing Xray config is invalid and was preserved: $XRAY_CONFIG_FILE"
		XRAY_CONFIG_OWNERSHIP="existing"
		log "preserving the existing valid Xray configuration at $XRAY_CONFIG_FILE"
		return
	fi

	write_managed_xray_config
}

xray_api_ready() {
	timeout 5 "$XRAY_BINARY_HOST" api statsquery \
		"--server=${ONE_NODE_XRAY_API_ADDR}" >/dev/null 2>&1
}

xray_installation_ready() {
	xray_artifacts_ready || return 1
	xray_config_valid "$XRAY_CONFIG_FILE" || return 1
	systemctl is-enabled "$XRAY_SERVICE_NAME" >/dev/null 2>&1 || return 1
	systemctl is-active "$XRAY_SERVICE_NAME" >/dev/null 2>&1 || return 1
	xray_api_ready
}

activate_xray_service() {
	systemctl daemon-reload
	if ! systemctl enable "$XRAY_SERVICE_NAME"; then
		die "failed to enable $XRAY_SERVICE_NAME"
	fi
	if ! systemctl restart "$XRAY_SERVICE_NAME"; then
		if [ "$XRAY_CONFIG_OWNERSHIP" = "existing" ]; then
			die "existing Xray config was preserved but $XRAY_SERVICE_NAME could not start; inspect journalctl -u $XRAY_SERVICE_NAME"
		fi
		die "One Node Xray bootstrap config passed validation but $XRAY_SERVICE_NAME could not start; inspect journalctl -u $XRAY_SERVICE_NAME"
	fi

	xray_ready_remaining=10
	while [ "$xray_ready_remaining" -gt 0 ]; do
		if systemctl is-active "$XRAY_SERVICE_NAME" >/dev/null 2>&1 &&
			xray_api_ready; then
			return
		fi
		sleep 1
		xray_ready_remaining=$((xray_ready_remaining - 1))
	done

	if [ "$XRAY_CONFIG_OWNERSHIP" = "existing" ]; then
		die "existing Xray config was preserved but StatsService is not reachable at ${ONE_NODE_XRAY_API_ADDR}; configure the local Xray API before installing One Node"
	fi
	die "Xray started with the One Node bootstrap config but StatsService is not reachable at ${ONE_NODE_XRAY_API_ADDR}; inspect journalctl -u $XRAY_SERVICE_NAME"
}

ensure_xray() {
	if xray_artifacts_ready; then
		ensure_xray_service_user
	fi
	if [ -z "$XRAY_SERVICE_USER_CHANGED" ] && xray_installation_ready; then
		log "using existing Xray installation at $XRAY_BINARY_HOST"
		return
	fi

	if ! xray_artifacts_ready; then
		if ! command -v bash >/dev/null 2>&1; then
			command -v apt-get >/dev/null 2>&1 ||
				die "bash is required to install Xray"
			log "installing bash for the official Xray installer"
			apt-get update
			env DEBIAN_FRONTEND=noninteractive apt-get install -y bash
		fi

		xray_installer="${TEMP_DIR}/xray-install-release.sh"
		log "installing the latest Xray release with the official XTLS installer"
		curl -q --fail --silent --show-error --location \
			--connect-timeout 10 --max-time 30 --max-filesize 1048576 \
			--proto '=https' --proto-redir '=https' \
			--output "$xray_installer" "$ONE_NODE_XRAY_INSTALLER_URL" ||
			die "unable to download the official Xray installer"
		[ -s "$xray_installer" ] ||
			die "downloaded Xray installer is empty"
		chmod 0700 "$xray_installer"
		bash -n "$xray_installer" ||
			die "downloaded Xray installer has invalid syntax"
		if ! bash "$xray_installer" install -u root; then
			# On a first install the upstream script creates config.json as `{}`.
			# Xray validates that placeholder but exits because it has no
			# listener, so some upstream revisions report a service-start
			# failure after all required artifacts have already been installed.
			xray_artifacts_ready ||
				die "official Xray installer failed before installing the binary and GeoData"
			log "official Xray artifacts are installed; preparing the One Node configuration before starting the service"
		fi
	fi

	xray_artifacts_ready ||
		die "official Xray installer completed without the Xray binary and GeoData"
	ensure_xray_service_user
	prepare_xray_config
	activate_xray_service
	xray_installation_ready ||
		die "Xray installation did not become ready after service activation"
	log "Xray installation is ready"
}
