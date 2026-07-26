# One Node Action 的 Make 入口。
# 根文件只负责加载配置和功能模块，并提供统一的命令帮助。
SHELL := /bin/bash
PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

.DEFAULT_GOAL := help

# 配置先于命令模块加载，确保发布和检查目标读取同一组路径与仓库参数。
include $(PROJECT_ROOT)/make/config.mk
include $(PROJECT_ROOT)/make/check.mk
include $(PROJECT_ROOT)/make/release.mk

.PHONY: help

help:
	@printf '%s\n' \
		"One Node Action" \
		"" \
		"用法:" \
		"  make <目标> [变量=值]" \
		"" \
		"检查:" \
		"  check                     校验公开入口、实现脚本和基础行为" \
		"" \
		"发布:" \
		"  deploy-node               生成时间版本、提交并推送标签，再触发 Release workflow" \
		"" \
		"常用变量:" \
		"  VERSION=26.726.1530       可选；默认按上海时间自动生成" \
		"  TAG=v26.726.1530          可选；覆盖 VERSION，标签规范化为 v<version>" \
		"  NODE_DIR                  Node 本地仓库，默认 $(NODE_DIR)" \
		"  NODE_BRANCH               Node 发布分支，默认 $(NODE_BRANCH)" \
		"  NODE_REMOTE               Node 推送远端，默认 $(NODE_REMOTE)" \
		"  ACTION_REF=main           Action workflow 分支，默认 $(ACTION_REF)" \
		"  DRY_RUN=true              只展示发布计划，不更新版本、提交、推送或触发" \
		"  GH_TOKEN                  GitHub PAT；可写入 $(ENV_FILE)" \
		"" \
		"示例:" \
		"  make check" \
		"  make deploy-node DRY_RUN=true" \
		"  make deploy-node"
