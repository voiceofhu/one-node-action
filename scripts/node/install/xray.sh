#!/bin/sh

# Host Xray discovery and installation through the official XTLS installer.

initialize_xray_config() {
	ONE_NODE_XRAY_INSTALLER_URL=${ONE_NODE_XRAY_INSTALLER_URL:-https://github.com/XTLS/Xray-install/raw/main/install-release.sh}
}

validate_xray_config() {
	require_single_line "ONE_NODE_XRAY_INSTALLER_URL" "$ONE_NODE_XRAY_INSTALLER_URL"
	case "$ONE_NODE_XRAY_INSTALLER_URL" in
		https://*) ;;
		*) die "ONE_NODE_XRAY_INSTALLER_URL must use HTTPS" ;;
	esac
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

xray_installation_ready() {
	XRAY_BINARY_HOST=$(resolve_xray_binary) || return 1
	for xray_file in \
		/usr/local/etc/xray/config.json \
		/usr/local/share/xray/geoip.dat \
		/usr/local/share/xray/geosite.dat
	do
		[ -f "$xray_file" ] && [ ! -L "$xray_file" ] || return 1
	done
	systemctl is-enabled xray.service >/dev/null 2>&1 || return 1
	systemctl is-active xray.service >/dev/null 2>&1 || return 1
}

ensure_xray() {
	if xray_installation_ready; then
		log "using existing Xray installation at $XRAY_BINARY_HOST"
		return
	fi

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
	bash "$xray_installer" install

	xray_installation_ready ||
		die "official Xray installer completed without a ready Xray service, config, and GeoData"
	log "Xray installation is ready"
}
