#!/bin/sh

# Stable public entrypoint. The implementation is split under
# scripts/node/install so the public raw URL can remain unchanged.

set -eu
umask 077

ONE_NODE_ACTION_DEFAULT_BASE_URL="https://raw.githubusercontent.com/voiceofhu/one-node-action"
ONE_NODE_ACTION_REF_API="https://api.github.com/repos/voiceofhu/one-node-action/git/ref/heads/main"
ONE_NODE_INSTALL_MODULES="common.sh config.sh host.sh xray.sh files.sh native.sh docker.sh enrollment.sh main.sh"
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
	source_dir="${entrypoint_dir}/scripts/node/install"
	[ -f "${source_dir}/main.sh" ] && [ ! -L "${source_dir}/main.sh" ] ||
		return 1
	printf '%s\n' "$source_dir"
}

entrypoint_resolve_default_base_url() {
	response=$(curl -q --proto '=https' --tlsv1.2 \
		--fail --silent --show-error --no-location \
		--connect-timeout 10 --max-time 30 --max-filesize 262144 \
		--header 'Accept: application/vnd.github+json' \
		--header 'X-GitHub-Api-Version: 2022-11-28' \
		"$ONE_NODE_ACTION_REF_API") ||
		entrypoint_die "unable to resolve the installer commit from GitHub"
	revision=$(printf '%s' "$response" | tr ',' '\n' |
		awk -F'"' '$2 == "sha" { print $4; exit }')
	[ "${#revision}" -eq 40 ] ||
		entrypoint_die "GitHub returned an invalid installer commit"
	case "$revision" in
		*[!0-9a-f]*)
			entrypoint_die "GitHub returned an invalid installer commit"
			;;
	esac
	printf '%s/%s/scripts/node/install\n' \
		"$ONE_NODE_ACTION_DEFAULT_BASE_URL" \
		"$revision"
}

entrypoint_download_modules() {
	destination=$1
	command -v curl >/dev/null 2>&1 ||
		entrypoint_die "curl is required to load the installer"

	if [ -n "${ONE_NODE_SCRIPT_BASE_URL:-}" ]; then
		base_url=${ONE_NODE_SCRIPT_BASE_URL%/}
		case "$base_url" in
			*/install) ;;
			*) base_url="${base_url}/install" ;;
		esac
	else
		base_url=$(entrypoint_resolve_default_base_url)
	fi

	case "$base_url" in
		https://*)
			transport_protocol='=https'
			;;
		http://127.0.0.1:*|http://localhost:*|http://host.orb.internal:*)
			transport_protocol='=http'
			;;
		*)
			entrypoint_die "ONE_NODE_SCRIPT_BASE_URL must use HTTPS or an approved local development host"
			;;
	esac

	for module in $ONE_NODE_INSTALL_MODULES; do
		curl -q --proto "$transport_protocol" --tlsv1.2 \
			--fail --silent --show-error --no-location \
			--connect-timeout 10 --max-time 30 --max-filesize 1048576 \
			"${base_url}/${module}" \
			--output "${destination}/${module}" ||
			entrypoint_die "unable to download installer module: $module"
		[ -s "${destination}/${module}" ] ||
			entrypoint_die "downloaded installer module is empty: $module"
		chmod 0600 "${destination}/${module}"
		/bin/sh -n "${destination}/${module}" ||
			entrypoint_die "downloaded installer module has invalid syntax: $module"
	done
}

entrypoint_load_modules() {
	source_dir=$(entrypoint_local_source_dir 2>/dev/null || true)
	if [ -z "$source_dir" ]; then
		ONE_NODE_ENTRYPOINT_TEMP_DIR=$(mktemp -d "/tmp/one-node-installer.XXXXXX")
		chmod 0700 "$ONE_NODE_ENTRYPOINT_TEMP_DIR"
		trap entrypoint_cleanup EXIT HUP INT TERM
		entrypoint_download_modules "$ONE_NODE_ENTRYPOINT_TEMP_DIR"
		source_dir=$ONE_NODE_ENTRYPOINT_TEMP_DIR
	fi

	for module in $ONE_NODE_INSTALL_MODULES; do
		module_path="${source_dir}/${module}"
		[ -f "$module_path" ] && [ ! -L "$module_path" ] ||
			entrypoint_die "installer module must be a regular file: $module"
		# shellcheck disable=SC1090
		. "$module_path"
	done

	entrypoint_cleanup
	ONE_NODE_ENTRYPOINT_TEMP_DIR=""
	trap - EXIT HUP INT TERM
}

entrypoint_load_modules

if [ "${ONE_NODE_INSTALLER_LIBRARY_ONLY:-0}" != "1" ]; then
	main "$@"
fi
