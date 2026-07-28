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
	"$(PROJECT_ROOT)/tests/scripts_test.sh"
