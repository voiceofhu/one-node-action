# ==============================================================================
# Action 仓库配置
# ------------------------------------------------------------------------------
# 配置既可由环境变量覆盖，也可通过 `make <目标> VAR=value` 临时覆盖。
# 本地 .env 只用于注入 Secret，不应提交到 Git。
# ==============================================================================

ACTION_REPOSITORY ?= voiceofhu/one-node-action
ACTION_REF ?= main
NODE_REPOSITORY ?= voiceofhu/one-node-node
NODE_DIR ?= $(abspath $(PROJECT_ROOT)/../one-node-node)
NODE_BRANCH ?= main
NODE_REMOTE ?= origin
DRY_RUN ?= false
GITHUB_API_URL ?= https://api.github.com
CURL ?= curl
ENV_FILE ?= $(PROJECT_ROOT)/.env

# GNU Make 读取简单 KEY=VALUE 形式的 .env，并导出给发布命令。
ifneq (,$(wildcard $(ENV_FILE)))
include $(ENV_FILE)
export
endif
