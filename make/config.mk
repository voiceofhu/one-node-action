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
SERVER_REPOSITORY ?= voiceofhu/one-node-server
SERVER_REF ?= main
WEB_REPOSITORY ?= voiceofhu/one-node-web
WEB_REF ?= main
SERVER_IMAGE_NAME ?= voiceofhu/one-node-server
DRY_RUN ?= false
GITHUB_API_URL ?= https://api.github.com
CURL ?= curl
ENV_FILE ?= $(PROJECT_ROOT)/.env

GENERATED_VERSION ?= $(shell node -e "\
  const d=new Date(new Date().toLocaleString('en-US',{timeZone:'Asia/Shanghai'}));\
  const stripLeadingZero=value=>String(Number(value));\
  const year=String(d.getFullYear()).slice(-2);\
  const monthDay=String(d.getMonth()+1).padStart(2,'0')+String(d.getDate()).padStart(2,'0');\
  const hourMinute=String(d.getHours()).padStart(2,'0')+String(d.getMinutes()).padStart(2,'0');\
  process.stdout.write([year,monthDay,hourMinute].map(stripLeadingZero).join('.'));\
")

# GNU Make 读取简单 KEY=VALUE 形式的 .env，并导出给发布命令。
ifneq (,$(wildcard $(ENV_FILE)))
include $(ENV_FILE)
export
endif
