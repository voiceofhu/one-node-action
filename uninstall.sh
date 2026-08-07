#!/bin/sh

# Canonical sing-box uninstaller entrypoint. It removes only manifest-owned
# One Node paths and never manages host proxy software or the Docker engine.

set -eu
umask 077

ONE_NODE_UNINSTALL_MODULES="install/common.sh uninstall/common.sh shared/manifest.sh uninstall/paths.sh uninstall/native.sh uninstall/docker.sh uninstall/main.sh"
ONE_NODE_ENTRYPOINT_TEMP_DIR=""

entrypoint_die() {
	printf '%s\n' "[one-node-node] error: $*" >&2
	exit 1
}

entrypoint_cleanup() {
	[ -z "$ONE_NODE_ENTRYPOINT_TEMP_DIR" ] ||
		rm -rf -- "$ONE_NODE_ENTRYPOINT_TEMP_DIR"
}

entrypoint_local_source_dir() {
	case "$0" in
	*/*) ;;
	*) return 1 ;;
	esac
	entrypoint_dir=$(CDPATH='' cd -- "$(dirname "$0")" 2>/dev/null && pwd) ||
		return 1
	source_dir="${entrypoint_dir}/scripts/node"
	[ -f "${source_dir}/uninstall/main.sh" ] && [ ! -L "${source_dir}/uninstall/main.sh" ] ||
		return 1
	printf '%s\n' "$source_dir"
}

entrypoint_module_base_url() {
	base_url=${ONE_NODE_SCRIPT_BASE_URL:-}
	[ -n "$base_url" ] ||
		entrypoint_die "ONE_NODE_SCRIPT_BASE_URL must pin the uninstaller modules"
	base_url=${base_url%/}
	case "$base_url" in
	*/scripts/node) ;;
	*) entrypoint_die "ONE_NODE_SCRIPT_BASE_URL must end in scripts/node" ;;
	esac
	case "$base_url" in
	https://*) ;;
	http://127.0.0.1:*|http://localhost:*|http://host.orb.internal:*)
		[ "${ONE_NODE_ALLOW_INSECURE:-false}" = "true" ] ||
			entrypoint_die "local HTTP modules require ONE_NODE_ALLOW_INSECURE=true"
		;;
	*) entrypoint_die "uninstaller modules must use HTTPS" ;;
	esac
	printf '%s\n' "$base_url"
}

entrypoint_download_modules() {
	destination=$1
	command -v curl >/dev/null 2>&1 ||
		entrypoint_die "curl is required to load the uninstaller"
	base_url=$(entrypoint_module_base_url)
	case "$base_url" in
	https://*) protocols='=https' ;;
	*) protocols='=http,https' ;;
	esac
	for module in $ONE_NODE_UNINSTALL_MODULES; do
		module_dir=${module%/*}
		install -d -m 0700 "${destination}/${module_dir}"
		curl -q --proto "$protocols" --proto-redir "$protocols" --tlsv1.2 \
			--fail --silent --show-error --no-location \
			--connect-timeout 10 --max-time 30 --max-filesize 1048576 \
			"${base_url}/${module}" --output "${destination}/${module}" ||
			entrypoint_die "unable to download uninstaller module: $module"
		[ -s "${destination}/${module}" ] ||
			entrypoint_die "downloaded uninstaller module is empty: $module"
		chmod 0600 "${destination}/${module}"
		/bin/sh -n "${destination}/${module}" ||
			entrypoint_die "downloaded uninstaller module has invalid syntax: $module"
	done
}

entrypoint_load_modules() {
	source_dir=$(entrypoint_local_source_dir 2>/dev/null || true)
	if [ -z "$source_dir" ]; then
		ONE_NODE_ENTRYPOINT_TEMP_DIR=$(mktemp -d "/tmp/one-node-uninstaller.XXXXXX")
		chmod 0700 "$ONE_NODE_ENTRYPOINT_TEMP_DIR"
		trap entrypoint_cleanup EXIT HUP INT TERM
		entrypoint_download_modules "$ONE_NODE_ENTRYPOINT_TEMP_DIR"
		source_dir=$ONE_NODE_ENTRYPOINT_TEMP_DIR
	fi
	for module in $ONE_NODE_UNINSTALL_MODULES; do
		module_path="${source_dir}/${module}"
		[ -f "$module_path" ] && [ ! -L "$module_path" ] ||
			entrypoint_die "uninstaller module must be a regular file: $module"
		# shellcheck disable=SC1090
		. "$module_path"
	done
	entrypoint_cleanup
	ONE_NODE_ENTRYPOINT_TEMP_DIR=""
	trap - EXIT HUP INT TERM
}

entrypoint_load_modules

if [ "${ONE_NODE_UNINSTALLER_LIBRARY_ONLY:-0}" != "1" ]; then
	main "$@"
fi
