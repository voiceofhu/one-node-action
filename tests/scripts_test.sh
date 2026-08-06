#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
TEST_TEMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_TEMP_DIR"' EXIT HUP INT TERM

INSTALL_MODULES="common.sh config.sh host.sh xray.sh files.sh native.sh docker.sh enrollment.sh main.sh"
UNINSTALL_MODULES="common.sh native.sh docker.sh xray.sh main.sh"

sh -n "$ROOT_DIR/install.sh"
sh -n "$ROOT_DIR/uninstall.sh"
for module in $INSTALL_MODULES; do
	sh -n "$ROOT_DIR/scripts/node/install/$module"
	grep -F "$module" "$ROOT_DIR/install.sh" >/dev/null
done
for module in $UNINSTALL_MODULES; do
	sh -n "$ROOT_DIR/scripts/node/uninstall/$module"
	grep -F "$module" "$ROOT_DIR/uninstall.sh" >/dev/null
done

grep -F "scripts/node/install" "$ROOT_DIR/install.sh" >/dev/null
grep -F "scripts/node/uninstall" "$ROOT_DIR/uninstall.sh" >/dev/null
grep -F "https://raw.githubusercontent.com/voiceofhu/one-node-action" \
	"$ROOT_DIR/install.sh" >/dev/null
grep -F "https://raw.githubusercontent.com/voiceofhu/one-node-action" \
	"$ROOT_DIR/uninstall.sh" >/dev/null
grep -F 'https://github.com/XTLS/Xray-install/raw/main/install-release.sh' \
	"$ROOT_DIR/scripts/node/install/xray.sh" >/dev/null
# The literal installer variable proves the module delegates version selection.
# shellcheck disable=SC2016
grep -F 'bash "$xray_installer" install' \
	"$ROOT_DIR/scripts/node/install/xray.sh" >/dev/null
# shellcheck disable=SC2016
grep -F 'bash "$xray_installer" install -u root' \
	"$ROOT_DIR/scripts/node/install/xray.sh" >/dev/null
# The literal installer variable proves the uninstaller delegates to XTLS.
# shellcheck disable=SC2016
grep -F 'bash "$xray_installer" remove' \
	"$ROOT_DIR/scripts/node/uninstall/xray.sh" >/dev/null
grep -F 'docker ps -aq' \
	"$ROOT_DIR/scripts/node/uninstall/docker.sh" >/dev/null
grep -F 'apt-get purge -y' \
	"$ROOT_DIR/scripts/node/uninstall/docker.sh" >/dev/null
grep -F 'xray_installation_ready' \
	"$ROOT_DIR/scripts/node/install/xray.sh" >/dev/null
# The literal variable expression proves the generated config follows the
# enrollment-provided local API address.
# shellcheck disable=SC2016
grep -F '"listen": "${ONE_NODE_XRAY_API_ADDR}"' \
	"$ROOT_DIR/scripts/node/install/xray.sh" >/dev/null
grep -F '"statsUserOnline": true' \
	"$ROOT_DIR/scripts/node/install/xray.sh" >/dev/null
grep -F 'write_env "XRAY_STATS_INTERVAL" "30s"' \
	"$ROOT_DIR/scripts/node/install/files.sh" >/dev/null
grep -F 'write_env "XRAY_MANAGE_SERVICE" "true"' \
	"$ROOT_DIR/scripts/node/install/files.sh" >/dev/null
grep -F 'write_env "XRAY_MANAGE_SERVICE" "false"' \
	"$ROOT_DIR/scripts/node/install/files.sh" >/dev/null
if grep -Eq '^XRAY_(INSTALLER_COMMIT|INSTALLER_SHA256|VERSION)=' \
	"$ROOT_DIR/scripts/node/install/xray.sh"; then
	printf '%s\n' "Xray installation still contains a pinned version or installer revision" >&2
	exit 1
fi
if grep -F -- '--version' "$ROOT_DIR/scripts/node/install/xray.sh" >/dev/null; then
	printf '%s\n' "Xray installation still overrides the official latest-version selection" >&2
	exit 1
fi

"$ROOT_DIR/install.sh" --help | grep -F "native" >/dev/null
"$ROOT_DIR/install.sh" --help | grep -F "docker" >/dev/null
"$ROOT_DIR/uninstall.sh" --help | grep -F "native" >/dev/null
"$ROOT_DIR/uninstall.sh" --help | grep -F "docker" >/dev/null

if "$ROOT_DIR/install.sh" --mode package >/dev/null 2>&1; then
	printf '%s\n' "installer accepted an unsupported mode" >&2
	exit 1
fi
if "$ROOT_DIR/uninstall.sh" --mode package >/dev/null 2>&1; then
	printf '%s\n' "uninstaller accepted an unsupported mode" >&2
	exit 1
fi
if sh "$ROOT_DIR/scripts/node/install/main.sh" \
	>"$TEST_TEMP_DIR/standalone-install-main.log" 2>&1; then
	printf '%s\n' "installer main module ran without the public module loader" >&2
	exit 1
fi
grep -F "must be loaded through install.sh" \
	"$TEST_TEMP_DIR/standalone-install-main.log" >/dev/null
if sh "$ROOT_DIR/scripts/node/uninstall/main.sh" \
	>"$TEST_TEMP_DIR/standalone-uninstall-main.log" 2>&1; then
	printf '%s\n' "uninstaller main module ran without the public module loader" >&2
	exit 1
fi
grep -F "must be loaded through uninstall.sh" \
	"$TEST_TEMP_DIR/standalone-uninstall-main.log" >/dev/null

install -d -m 0755 "$TEST_TEMP_DIR/bin"
cp "$ROOT_DIR/install.sh" "$TEST_TEMP_DIR/install.sh"
cp "$ROOT_DIR/uninstall.sh" "$TEST_TEMP_DIR/uninstall.sh"
chmod 0755 "$TEST_TEMP_DIR/install.sh" "$TEST_TEMP_DIR/uninstall.sh"
cat > "$TEST_TEMP_DIR/bin/curl" <<'FAKE_CURL'
#!/bin/sh
set -eu
output=""
url=""
while [ "$#" -gt 0 ]; do
	case "$1" in
		--output)
			output=$2
			shift 2
			;;
		http://*|https://*)
			url=$1
			shift
			;;
		*) shift ;;
	esac
done
[ -n "$output" ] && [ -n "$url" ]
module=${url##*/}
case "$url" in
	*/install/*) source_file="${ONE_NODE_TEST_ROOT}/scripts/node/install/${module}" ;;
	*/uninstall/*) source_file="${ONE_NODE_TEST_ROOT}/scripts/node/uninstall/${module}" ;;
	*) exit 1 ;;
esac
cp "$source_file" "$output"
printf '%s\n' "$url" >> "${ONE_NODE_TEST_TEMP}/module-requests.log"
FAKE_CURL
chmod 0755 "$TEST_TEMP_DIR/bin/curl"

export ONE_NODE_TEST_ROOT="$ROOT_DIR"
export ONE_NODE_TEST_TEMP="$TEST_TEMP_DIR"
PATH="$TEST_TEMP_DIR/bin:$PATH" \
	ONE_NODE_SCRIPT_BASE_URL="http://127.0.0.1:9999/scripts/node" \
	"$TEST_TEMP_DIR/install.sh" --help |
	grep -F "native" >/dev/null
PATH="$TEST_TEMP_DIR/bin:$PATH" \
	ONE_NODE_SCRIPT_BASE_URL="http://127.0.0.1:9999/scripts/node" \
	"$TEST_TEMP_DIR/uninstall.sh" --help |
	grep -F "native" >/dev/null
for module in $INSTALL_MODULES; do
	grep -F "/install/$module" "$TEST_TEMP_DIR/module-requests.log" >/dev/null
done
for module in $UNINSTALL_MODULES; do
	grep -F "/uninstall/$module" "$TEST_TEMP_DIR/module-requests.log" >/dev/null
done

install -d -m 0755 \
	"$TEST_TEMP_DIR/xray-bin" \
	"$TEST_TEMP_DIR/xray-config" \
	"$TEST_TEMP_DIR/xray-geodata"
printf '%s\n' "geoip" > "$TEST_TEMP_DIR/xray-geodata/geoip.dat"
printf '%s\n' "geosite" > "$TEST_TEMP_DIR/xray-geodata/geosite.dat"
printf '%s\n' "[Service]" > "$TEST_TEMP_DIR/xray.service"
cat > "$TEST_TEMP_DIR/xray-bin/xray" <<'FAKE_XRAY'
#!/bin/sh
set -eu
case "${1:-}" in
	version)
		printf '%s\n' "Xray 26.test"
		;;
	-test)
		config_path=""
		while [ "$#" -gt 0 ]; do
			case "$1" in
				-config)
					config_path=$2
					shift 2
					;;
				*) shift ;;
			esac
		done
		[ -n "$config_path" ]
		! grep -F "INVALID_CONFIG" "$config_path" >/dev/null
		;;
	api)
		[ "${2:-}" = "statsquery" ]
		[ "${3:-}" = "--server=127.0.0.1:27522" ]
		;;
	*)
		exit 1
		;;
esac
FAKE_XRAY
chmod 0755 "$TEST_TEMP_DIR/xray-bin/xray"

(
	for module in $INSTALL_MODULES; do
		# shellcheck disable=SC1090
		. "$ROOT_DIR/scripts/node/install/$module"
	done
	initialize_install_config
	initialize_xray_config
	TEMP_DIR="$TEST_TEMP_DIR/xray-work"
	install -d -m 0700 "$TEMP_DIR"
	XRAY_CONFIG_DIR="$TEST_TEMP_DIR/xray-config"
	XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
	XRAY_GEODATA_DIR="$TEST_TEMP_DIR/xray-geodata"
	XRAY_SERVICE_FILE="$TEST_TEMP_DIR/xray.service"
	XRAY_SERVICE_OVERRIDE_DIR="${XRAY_SERVICE_FILE}.d"
	XRAY_SERVICE_USER_OVERRIDE_FILE="${XRAY_SERVICE_OVERRIDE_DIR}/99-one-node-service-user.conf"
	XRAY_MANAGED_CONFIG_MARKER="${XRAY_CONFIG_DIR}/.one-node-managed-config"
	PATH="$TEST_TEMP_DIR/xray-bin:$PATH"
	export PATH XRAY_GEODATA_DIR XRAY_SERVICE_FILE
	XRAY_BINARY_HOST=$(resolve_xray_binary)
	export XRAY_BINARY_HOST

	printf '%s\n' '{}' > "$XRAY_CONFIG_FILE"
	prepare_xray_config
	[ "$XRAY_CONFIG_OWNERSHIP" = "managed" ]
	grep -F '"listen": "127.0.0.1:27522"' "$XRAY_CONFIG_FILE" >/dev/null
	grep -F '"HandlerService"' "$XRAY_CONFIG_FILE" >/dev/null
	grep -F '"StatsService"' "$XRAY_CONFIG_FILE" >/dev/null
	grep -F '"statsUserOnline": true' "$XRAY_CONFIG_FILE" >/dev/null
	[ -f "$XRAY_MANAGED_CONFIG_MARKER" ]

	XRAY_SERVICE_USER_CHANGED=""
	write_xray_service_user_override
	[ "$XRAY_SERVICE_USER_CHANGED" = "true" ]
	grep -F '[Service]' "$XRAY_SERVICE_USER_OVERRIDE_FILE" >/dev/null
	grep -F 'User=root' "$XRAY_SERVICE_USER_OVERRIDE_FILE" >/dev/null
	XRAY_SERVICE_USER_CHANGED=""
	write_xray_service_user_override
	[ -z "$XRAY_SERVICE_USER_CHANGED" ]

	printf '%s\n' '{"log":{"loglevel":"error"},"inbounds":[]}' \
		> "$XRAY_CONFIG_FILE"
	custom_sha=$(sha256sum "$XRAY_CONFIG_FILE" | awk '{ print $1 }')
	prepare_xray_config
	[ "$XRAY_CONFIG_OWNERSHIP" = "existing" ]
	[ "$(sha256sum "$XRAY_CONFIG_FILE" | awk '{ print $1 }')" = "$custom_sha" ]

	printf '%s\n' 'INVALID_CONFIG' > "$XRAY_CONFIG_FILE"
	invalid_sha=$(sha256sum "$XRAY_CONFIG_FILE" | awk '{ print $1 }')
	if (prepare_xray_config) >/dev/null 2>&1; then
		printf '%s\n' "invalid existing Xray config was accepted" >&2
		exit 1
	fi
	[ "$(sha256sum "$XRAY_CONFIG_FILE" | awk '{ print $1 }')" = "$invalid_sha" ]
)

printf '%s\n' "One Node action script checks passed"
