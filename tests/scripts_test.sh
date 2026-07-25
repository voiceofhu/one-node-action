#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)

sh -n "$ROOT_DIR/install.sh"
sh -n "$ROOT_DIR/uninstall.sh"

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

printf '%s\n' "One Node action script checks passed"
