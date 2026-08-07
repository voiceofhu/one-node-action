#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
TEST_TEMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_TEMP_DIR"' EXIT HUP INT TERM

INSTALL_MODULES="install/common.sh shared/manifest.sh install/config.sh install/host.sh install/files.sh install/native.sh install/docker.sh install/readiness.sh install/main.sh"
UNINSTALL_MODULES="install/common.sh uninstall/common.sh shared/manifest.sh uninstall/paths.sh uninstall/native.sh uninstall/docker.sh uninstall/main.sh"
UPGRADE_MODULES="install/common.sh shared/manifest.sh install/host.sh install/files.sh install/docker.sh install/readiness.sh upgrade/common.sh upgrade/manifest.sh upgrade/native.sh upgrade/docker.sh upgrade/rollback.sh upgrade/main.sh"

for entrypoint in install.sh uninstall.sh upgrade.sh; do
	sh -n "$ROOT_DIR/$entrypoint"
done
for module in $(printf '%s\n' "$INSTALL_MODULES $UNINSTALL_MODULES $UPGRADE_MODULES" | tr ' ' '\n' | sort -u); do
	sh -n "$ROOT_DIR/scripts/node/$module"
done

# The permission reader supports the host's GNU or BSD stat variant.
# shellcheck disable=SC1090
. "$ROOT_DIR/scripts/node/install/common.sh"
mode_fixture="$TEST_TEMP_DIR/mode-fixture"
: >"$mode_fixture"
chmod 0600 "$mode_fixture"
[ "$(file_mode "$mode_fixture")" = "600" ]

for removed in install-v2.sh uninstall-v2.sh upgrade-v2.sh scripts/node-v2; do
	[ ! -e "$ROOT_DIR/$removed" ] || {
		printf '%s\n' "obsolete installer path remains: $removed" >&2
		exit 1
	}
done
if grep -R -i -E 'xray|node-v2|install-v2|uninstall-v2|upgrade-v2' \
	"$ROOT_DIR/install.sh" "$ROOT_DIR/uninstall.sh" "$ROOT_DIR/upgrade.sh" \
	"$ROOT_DIR/scripts/node" >/dev/null; then
	printf '%s\n' "canonical installer still contains a legacy name" >&2
	exit 1
fi

"$ROOT_DIR/install.sh" --help | grep -F "native" >/dev/null
"$ROOT_DIR/install.sh" --help | grep -F "docker" >/dev/null
"$ROOT_DIR/uninstall.sh" --help | grep -F "native" >/dev/null
"$ROOT_DIR/uninstall.sh" --help | grep -F "docker" >/dev/null
"$ROOT_DIR/upgrade.sh" --help | grep -F "roll back" >/dev/null

if "$ROOT_DIR/install.sh" --mode package >/dev/null 2>&1; then
	printf '%s\n' "installer accepted an unsupported mode" >&2
	exit 1
fi
if "$ROOT_DIR/uninstall.sh" --mode package >/dev/null 2>&1; then
	printf '%s\n' "uninstaller accepted an unsupported mode" >&2
	exit 1
fi
for module in install uninstall upgrade; do
	if sh "$ROOT_DIR/scripts/node/$module/main.sh" \
		>"$TEST_TEMP_DIR/standalone-$module.log" 2>&1; then
		printf '%s\n' "$module main module ran without its public loader" >&2
		exit 1
	fi
	grep -F "must be loaded through $module.sh" \
		"$TEST_TEMP_DIR/standalone-$module.log" >/dev/null
done

install -d -m 0755 "$TEST_TEMP_DIR/bin"
cat >"$TEST_TEMP_DIR/bin/curl" <<'FAKE_CURL'
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
relative=${url#*scripts/node/}
source_file="${ONE_NODE_TEST_ROOT}/scripts/node/${relative}"
[ -f "$source_file" ]
cp "$source_file" "$output"
FAKE_CURL
chmod 0755 "$TEST_TEMP_DIR/bin/curl"

export ONE_NODE_TEST_ROOT="$ROOT_DIR"
for entrypoint in install.sh uninstall.sh upgrade.sh; do
	cp "$ROOT_DIR/$entrypoint" "$TEST_TEMP_DIR/$entrypoint"
	chmod 0755 "$TEST_TEMP_DIR/$entrypoint"
	PATH="$TEST_TEMP_DIR/bin:$PATH" \
		ONE_NODE_ALLOW_INSECURE=true \
		ONE_NODE_SCRIPT_BASE_URL="http://127.0.0.1:9999/scripts/node" \
		"$TEST_TEMP_DIR/$entrypoint" --help >/dev/null
done

grep -F 'MANIFEST_FORMAT_V1="one-node-manifest-v1"' \
	"$ROOT_DIR/scripts/node/shared/manifest.sh" >/dev/null
grep -F 'MANIFEST_RECORD_PATH="${MANIFEST_INSTALL_DIR}/.installation"' \
	"$ROOT_DIR/scripts/node/shared/manifest.sh" >/dev/null
grep -F 'rm -rf -- "$MANIFEST_STATE_DIR"' \
	"$ROOT_DIR/scripts/node/uninstall/paths.sh" >/dev/null
if grep -R -E 'apt-get purge|docker system prune|docker (rm|rmi).*(xray|Xray)' \
	"$ROOT_DIR/scripts/node/uninstall" >/dev/null; then
	printf '%s\n' "uninstaller manages software outside its manifest" >&2
	exit 1
fi
