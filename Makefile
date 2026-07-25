SHELL := /bin/bash

PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ACTION_REPOSITORY ?= voiceofhu/one-node-action
ACTION_REF ?= main
NODE_REF ?= main
TAG ?=
GITHUB_API_URL ?= https://api.github.com
ENV_FILE ?= $(PROJECT_ROOT)/.env

ifneq (,$(wildcard $(ENV_FILE)))
include $(ENV_FILE)
export
endif

.DEFAULT_GOAL := help

.PHONY: help check deploy-node

help:
	@printf '%s\n' \
		"One Node Action" \
		"" \
		"用法:" \
		"  make check" \
		"  make deploy-node TAG=v0.1.0 [NODE_REF=main]" \
		"" \
		"deploy-node 通过 GitHub API 触发公共 Action 仓库的 Node Release workflow。" \
		"GH_TOKEN 可写入仓库根目录的 .env。"

check:
	sh -n install.sh uninstall.sh \
		scripts/node/install/main.sh \
		scripts/node/uninstall/main.sh \
		tests/scripts_test.sh
	./tests/scripts_test.sh

deploy-node:
	@set -euo pipefail; \
	tag="$(TAG)"; \
	[ -n "$$tag" ] || { echo "TAG is required, for example TAG=v0.1.0" >&2; exit 1; }; \
	version="$${tag#node-v}"; \
	version="$${version#v}"; \
	[[ "$$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$$ ]] || { \
		echo "TAG must be a semantic version such as v0.1.0" >&2; \
		exit 1; \
	}; \
	node_ref="$(NODE_REF)"; \
	[[ "$$node_ref" =~ ^[0-9A-Za-z._/-]+$$ ]] || { \
		echo "NODE_REF contains unsupported characters" >&2; \
		exit 1; \
	}; \
	token="$${GH_TOKEN:-}"; \
	[ -n "$$token" ] || { echo "GH_TOKEN is required" >&2; exit 1; }; \
	payload=$$(printf \
		'{"ref":"%s","inputs":{"node_ref":"%s","version_tag":"v%s"}}' \
		"$(ACTION_REF)" "$$node_ref" "$$version"); \
	curl --fail --silent --show-error \
		--request POST \
		--header "Authorization: Bearer $$token" \
		--header "Accept: application/vnd.github+json" \
		--header "X-GitHub-Api-Version: 2022-11-28" \
		--data "$$payload" \
		"$(GITHUB_API_URL)/repos/$(ACTION_REPOSITORY)/actions/workflows/node-release.yml/dispatches"; \
	printf '%s\n' \
		"Triggered Node Release:" \
		"  repository: $(ACTION_REPOSITORY)" \
		"  node_ref:   $$node_ref" \
		"  release:    node-v$$version"
