# ==============================================================================
# 公开脚本检查
# ------------------------------------------------------------------------------
# 保持根入口、拆分实现与测试脚本的 shell 语法和基础行为一致。
# ==============================================================================

.PHONY: check

check:
	sh -n "$(PROJECT_ROOT)/install.sh" "$(PROJECT_ROOT)/uninstall.sh" \
		"$(PROJECT_ROOT)"/scripts/node/install/*.sh \
		"$(PROJECT_ROOT)"/scripts/node/uninstall/*.sh \
		"$(PROJECT_ROOT)/tests/scripts_test.sh"
	sh -n "$(PROJECT_ROOT)/install-v2.sh" "$(PROJECT_ROOT)/uninstall-v2.sh" \
		"$(PROJECT_ROOT)"/scripts/node-v2/install/*.sh \
		"$(PROJECT_ROOT)"/scripts/node-v2/uninstall/*.sh
	bash -n "$(PROJECT_ROOT)/.github/scripts/deploy-server.sh"
	"$(PROJECT_ROOT)/tests/scripts_test.sh"
	$(MAKE) --no-print-directory deploy-server DRY_RUN=true VERSION=1.2.3 >/dev/null
