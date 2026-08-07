#!/bin/sh

validate_install_host() {
	[ "$(id -u)" -eq 0 ] || die "run this installer as root"
	[ -r /etc/os-release ] || die "cannot identify the operating system"
	# /etc/os-release is controlled by the installed operating system.
	# shellcheck disable=SC1091
	. /etc/os-release
	[ "${ID:-}" = "debian" ] || die "only Debian is supported"
	command -v dpkg >/dev/null 2>&1 || die "dpkg is required"
	command -v curl >/dev/null 2>&1 || die "curl is required"
	command -v stat >/dev/null 2>&1 || die "stat is required (install coreutils)"
	command -v awk >/dev/null 2>&1 || die "awk is required"

	resolve_host_architecture
	if [ "$INSTALL_MODE" = "native" ]; then
		command -v sha256sum >/dev/null 2>&1 ||
			die "sha256sum is required (install coreutils)"
		command -v systemctl >/dev/null 2>&1 ||
			die "systemd is required for native installation"
	fi
}

resolve_host_architecture() {
	dpkg_architecture=$(dpkg --print-architecture)
	machine_architecture=$(uname -m)
	case "$dpkg_architecture:$machine_architecture" in
	amd64:x86_64|amd64:amd64)
		ONE_NODE_ARCH="amd64"
		ONE_NODE_BINARY_SHA256=$ONE_NODE_BINARY_SHA256_AMD64
		;;
	arm64:aarch64|arm64:arm64)
		ONE_NODE_ARCH="arm64"
		ONE_NODE_BINARY_SHA256=$ONE_NODE_BINARY_SHA256_ARM64
		;;
	amd64:*|arm64:*) die "dpkg and kernel architectures do not match" ;;
	*) die "only Debian amd64 and arm64 are supported" ;;
	esac
	ONE_NODE_BINARY_NAME="one-node-node-linux-${ONE_NODE_ARCH}"
}

validate_install_target() {
	[ ! -L "$INSTALL_DIR" ] || die "installation directory must not be a symlink"
	[ ! -e "$INSTALL_RECORD" ] ||
		die "an installation already exists; upgrades belong to the upgrade workflow"
	[ ! -e "$UNIT_FILE" ] || die "one-node-node.service already exists"
	if command -v docker >/dev/null 2>&1 &&
		docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
		die "one-node-node container already exists"
	fi
}
