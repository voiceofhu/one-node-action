#!/bin/sh

# One Node uninstaller orchestration. Runtime logic lives in sibling modules.

if ! command -v initialize_uninstall_config >/dev/null 2>&1; then
	printf '%s\n' \
		"[one-node-node] error: uninstaller main module must be loaded through uninstall.sh" >&2
	exit 1
fi

main() {
	umask 077
	initialize_uninstall_config
	trap cleanup_uninstall_temp_dir EXIT HUP INT TERM
	parse_uninstall_arguments "$@"

	[ "$(id -u)" -eq 0 ] || die "run this uninstaller as root"
	command -v realpath >/dev/null 2>&1 ||
		die "realpath is required (install coreutils)"

	load_installation_state
	if [ -z "$installed_mode" ]; then
		log "no One Node installation was found"
		return 0
	fi
	validate_installation_state

	if [ "$installed_mode" = "native" ]; then
		uninstall_native
	else
		uninstall_docker
	fi
	uninstall_xray
	remove_installation_state
	cleanup_uninstall_temp_dir
	trap - EXIT HUP INT TERM
	log "One Node was uninstalled"
}
