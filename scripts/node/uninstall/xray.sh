#!/bin/sh

# Host Xray removal through the official XTLS installer.

xray_is_installed() {
	[ -x /usr/local/bin/xray ] ||
		[ -e /etc/systemd/system/xray.service ] ||
		[ -e /etc/systemd/system/xray@.service ]
}

uninstall_xray() {
	if ! xray_is_installed; then
		log "host Xray was already absent"
		return 0
	fi

	command -v curl >/dev/null 2>&1 ||
		die "curl is required to load the official Xray uninstaller"
	command -v bash >/dev/null 2>&1 ||
		die "bash is required to run the official Xray uninstaller"

	prepare_uninstall_temp_dir
	xray_installer="${UNINSTALL_TEMP_DIR}/xray-install-release.sh"
	curl -q --fail --silent --show-error --location \
		--connect-timeout 10 --max-time 30 --max-filesize 1048576 \
		--proto '=https' --proto-redir '=https' \
		--output "$xray_installer" "$ONE_NODE_XRAY_INSTALLER_URL" ||
		die "unable to download the official Xray uninstaller"
	[ -s "$xray_installer" ] ||
		die "downloaded Xray uninstaller is empty"
	chmod 0700 "$xray_installer"
	bash -n "$xray_installer" ||
		die "downloaded Xray uninstaller has invalid syntax"

	log "uninstalling host Xray with the official XTLS installer"
	bash "$xray_installer" remove ||
		die "official Xray uninstaller failed"
	log "host Xray was uninstalled"
}
