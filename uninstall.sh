#!/bin/sh

# Stable public entrypoint. The implementation lives under
# scripts/node/uninstall so the public raw URL can remain unchanged.

set -eu
umask 077

ONE_NODE_ACTION_DEFAULT_BASE_URL="https://raw.githubusercontent.com/voiceofhu/one-node-action"
ONE_NODE_ACTION_REF_API="https://api.github.com/repos/voiceofhu/one-node-action/git/ref/heads/main"
ONE_NODE_ENTRYPOINT_TEMP_DIR=""

entrypoint_die() {
	printf '%s\n' "[one-node-node] error: $*" >&2
	exit 1
}

entrypoint_cleanup() {
	[ -z "$ONE_NODE_ENTRYPOINT_TEMP_DIR" ] ||
		rm -rf -- "$ONE_NODE_ENTRYPOINT_TEMP_DIR"
}

entrypoint_local_implementation() {
	case "$0" in
		*/*) ;;
		*) return 1 ;;
	esac

	entrypoint_dir=$(CDPATH='' cd -- "$(dirname "$0")" 2>/dev/null && pwd) ||
		return 1
	local_implementation="${entrypoint_dir}/scripts/node/uninstall/main.sh"
	[ -f "$local_implementation" ] && [ ! -L "$local_implementation" ] ||
		return 1
	printf '%s\n' "$local_implementation"
}

entrypoint_resolve_default_base_url() {
	response=$(curl -q --proto '=https' --tlsv1.2 \
		--fail --silent --show-error --no-location \
		--connect-timeout 10 --max-time 30 --max-filesize 262144 \
		--header 'Accept: application/vnd.github+json' \
		--header 'X-GitHub-Api-Version: 2022-11-28' \
		"$ONE_NODE_ACTION_REF_API") ||
		entrypoint_die "unable to resolve the uninstaller commit from GitHub"
	revision=$(printf '%s' "$response" | tr ',' '\n' |
		awk -F'"' '$2 == "sha" { print $4; exit }')
	[ "${#revision}" -eq 40 ] ||
		entrypoint_die "GitHub returned an invalid uninstaller commit"
	case "$revision" in
		*[!0-9a-f]*)
			entrypoint_die "GitHub returned an invalid uninstaller commit"
			;;
	esac
	printf '%s/%s/scripts/node\n' \
		"$ONE_NODE_ACTION_DEFAULT_BASE_URL" \
		"$revision"
}

entrypoint_download_implementation() {
	command -v curl >/dev/null 2>&1 ||
		entrypoint_die "curl is required to load the uninstaller"

	if [ -n "${ONE_NODE_SCRIPT_BASE_URL:-}" ]; then
		base_url=${ONE_NODE_SCRIPT_BASE_URL%/}
	else
		base_url=$(entrypoint_resolve_default_base_url)
		base_url=${base_url%/}
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

	ONE_NODE_ENTRYPOINT_TEMP_DIR=$(mktemp -d "/tmp/one-node-uninstaller.XXXXXX")
	trap entrypoint_cleanup EXIT HUP INT TERM
	downloaded_implementation="${ONE_NODE_ENTRYPOINT_TEMP_DIR}/main.sh"
	curl -q --proto "$transport_protocol" --tlsv1.2 \
		--fail --silent --show-error --no-location \
		--connect-timeout 10 --max-time 30 --max-filesize 1048576 \
		"${base_url}/uninstall/main.sh" \
		--output "$downloaded_implementation" ||
		entrypoint_die "unable to download the uninstaller implementation"
	[ -s "$downloaded_implementation" ] ||
		entrypoint_die "downloaded uninstaller implementation is empty"
	chmod 0600 "$downloaded_implementation"
	/bin/sh -n "$downloaded_implementation" ||
		entrypoint_die "downloaded uninstaller implementation has invalid syntax"
	implementation=$downloaded_implementation
}

implementation=$(entrypoint_local_implementation 2>/dev/null || true)
if [ -z "$implementation" ]; then
	entrypoint_download_implementation
fi

set +e
/bin/sh "$implementation" "$@"
status=$?
set -e
entrypoint_cleanup
trap - EXIT HUP INT TERM
exit "$status"
