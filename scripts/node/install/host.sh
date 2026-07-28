#!/bin/sh

# Host compatibility checks and installed-mode detection.

validate_install_host() {
	[ "$(id -u)" -eq 0 ] || die "run this installer as root"
	[ -r /etc/os-release ] || die "cannot identify the operating system"

	# /etc/os-release is controlled by the installed operating system.
	# shellcheck disable=SC1091
	. /etc/os-release
	[ "${ID:-}" = "debian" ] || die "only Debian is supported"

	command -v dpkg >/dev/null 2>&1 || die "dpkg is required"
	[ "$(dpkg --print-architecture)" = "amd64" ] ||
		die "only Debian amd64 is supported"
	case "$(uname -m)" in
		x86_64|amd64) ;;
		*) die "only x86_64/amd64 machines are supported" ;;
	esac

	command -v systemctl >/dev/null 2>&1 ||
		die "systemd is required to install One Node and Xray"
	command -v curl >/dev/null 2>&1 ||
		die "curl is required to run this installer"
	command -v sha256sum >/dev/null 2>&1 ||
		die "sha256sum is required (install coreutils)"
	command -v sed >/dev/null 2>&1 || die "sed is required"
	command -v realpath >/dev/null 2>&1 ||
		die "realpath is required (install coreutils)"
	command -v grep >/dev/null 2>&1 || die "grep is required"
	command -v stat >/dev/null 2>&1 ||
		die "stat is required (install coreutils)"
}

validate_install_mode_transition() {
	installed_mode=""
	if [ -f "$INSTALL_RECORD" ] && [ ! -L "$INSTALL_RECORD" ]; then
		installed_mode=$(sed -n 's/^runtime=//p' "$INSTALL_RECORD" | head -n 1)
	fi
	if [ -z "$installed_mode" ]; then
		if [ -f "$UNIT_FILE" ] && [ ! -L "$UNIT_FILE" ]; then
			installed_mode="native"
		elif command -v docker >/dev/null 2>&1 &&
			docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
			installed_mode="docker"
		fi
	fi
	if [ -n "$installed_mode" ] && [ "$installed_mode" != "$INSTALL_MODE" ]; then
		die "One Node is installed in ${installed_mode} mode; uninstall it before switching to ${INSTALL_MODE}"
	fi
}
