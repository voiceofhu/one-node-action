#!/bin/sh

# Shared logging, help text, validation, and serialization helpers.

log() {
	printf '%s\n' "[one-node-node] $*"
}

die() {
	printf '%s\n' "[one-node-node] error: $*" >&2
	exit 1
}

show_help() {
	printf '%s\n' \
		"Install One Node." \
		"" \
		"Usage: install.sh --mode <native|docker>" \
		"" \
		"  native  Install a systemd service." \
		"  docker  Install a Docker Compose service."
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
	printf '%s="%s"\n' "$key" "$escaped" >> "$ENV_SOURCE"
}

download_binary() {
	url=$1
	destination=$2
	case "$url" in
		https://*)
			allowed_protocols='=https'
			;;
		http://*)
			[ "$ONE_NODE_ALLOW_INSECURE" = "true" ] ||
				die "HTTP binary downloads require ONE_NODE_ALLOW_INSECURE=true"
			allowed_protocols='=http,https'
			;;
		*) die "binary download URL must use HTTP or HTTPS" ;;
	esac
	curl --fail --location --silent --show-error --retry 3 \
		--proto "$allowed_protocols" --proto-redir "$allowed_protocols" \
		--output "$destination" "$url"
}
