#!/bin/sh

if ! command -v initialize_uninstall_config >/dev/null 2>&1; then
	printf '%s\n' \
		"[one-node-node] error: uninstaller main module must be loaded through uninstall-v2.sh" >&2
	exit 1
fi

main() {
	umask 077
	initialize_uninstall_config
	parse_uninstall_arguments "$@"
	[ "$(id -u)" -eq 0 ] || die "run this uninstaller as root"
	command -v realpath >/dev/null 2>&1 ||
		die "realpath is required (install coreutils)"
	command -v stat >/dev/null 2>&1 ||
		die "stat is required (install coreutils)"
	if ! load_v2_installation; then
		return 0
	fi

	if [ "$installed_mode" = "native" ]; then
		uninstall_native
	else
		uninstall_docker
	fi
	remove_v2_files
	log "One Node sing-box runtime was uninstalled; state retained at ${state_dir}"
}
