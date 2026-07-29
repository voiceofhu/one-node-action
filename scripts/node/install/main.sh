#!/bin/sh

# One Node installer orchestration. Functional logic lives in sibling modules.
# Installer globals are shared across sourced modules.
# shellcheck disable=SC2034

if ! command -v initialize_install_config >/dev/null 2>&1; then
	printf '%s\n' \
		"[one-node-node] error: installer main module must be loaded through install.sh" >&2
	exit 1
fi

main() {
	umask 077
	initialize_install_config
	initialize_xray_config
	parse_install_arguments "$@"
	validate_install_host
	validate_install_config
	validate_xray_config
	validate_install_mode_transition
	initialize_install_workspace

	ensure_xray
	prepare_binary_source
	write_common_sources
	if [ "$INSTALL_MODE" = "native" ]; then
		write_native_source
	else
		write_docker_source
	fi

	prepare_install_target
	install_common_files
	if [ "$INSTALL_MODE" = "native" ]; then
		install_native_runtime
	else
		install_docker_runtime
	fi
	wait_for_enrollment

	COMMITTED="true"
	log "${INSTALL_MODE} installation complete; node enrollment is active"
}
