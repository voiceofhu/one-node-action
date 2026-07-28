#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
TEST_TEMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_TEMP_DIR"' EXIT HUP INT TERM

INSTALL_MODULES="common.sh config.sh host.sh xray.sh files.sh native.sh docker.sh enrollment.sh main.sh"
UNINSTALL_MODULES="common.sh native.sh docker.sh main.sh"

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
grep -F 'xray_installation_ready' \
	"$ROOT_DIR/scripts/node/install/xray.sh" >/dev/null
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

printf '%s\n' "One Node action script checks passed"
