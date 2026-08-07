#!/bin/sh

log() {
	printf '%s\n' "[one-node-node] $*"
}

die() {
	printf '%s\n' "[one-node-node] error: $*" >&2
	exit 1
}

show_help() {
	printf '%s\n' \
		"Install the One Node sing-box data plane." \
		"" \
		"Usage: install-v2.sh --mode <native|docker>" \
		"" \
		"  native  Install one one-node-node systemd service." \
		"  docker  Install one complete immutable One Node image."
}

require_value() {
	name=$1
	value=$2
	[ -n "$value" ] || die "${name} is required"
}

require_single_line() {
	name=$1
	value=$2
	case "$value" in
	*'
'*|*''*) die "${name} must be a single line" ;;
	esac
}

normalize_sha256() {
	printf '%s' "$1" | tr 'A-F' 'a-f'
}

validate_sha256() {
	digest=$1
	case "$digest" in
	''|*[!0-9a-f]*) return 1 ;;
	esac
	[ "${#digest}" -eq 64 ]
}

validate_decimal() {
	value=$1
	case "$value" in
	''|*[!0-9]*) return 1 ;;
	esac
	[ "$value" = "0" ] || [ "${value#0}" = "$value" ]
}

escape_dotenv() {
	printf '%s' "$1" | sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g' \
		-e 's/\$/\\$/g'
}

write_env() {
	key=$1
	value=$2
	escaped=$(escape_dotenv "$value")
	printf '%s="%s"\n' "$key" "$escaped" >>"$ENV_SOURCE"
}

download_file() {
	url=$1
	destination=$2
	case "$url" in
	https://*) protocols='=https' ;;
	http://*)
		[ "$ONE_NODE_ALLOW_INSECURE" = "true" ] ||
			die "HTTP downloads require ONE_NODE_ALLOW_INSECURE=true"
		protocols='=http,https'
		;;
	*) die "download URL must use HTTP or HTTPS" ;;
	esac
	curl --fail --location --silent --show-error --retry 3 \
		--proto "$protocols" --proto-redir "$protocols" \
		--output "$destination" "$url"
}
