# ==============================================================================
# Release Server 命令
# ------------------------------------------------------------------------------
# 解析版本后调度 server.yml；镜像构建、上传和远端部署全部由 Action 完成。
# ==============================================================================

.PHONY: deploy-server

deploy-server:
	@set -euo pipefail; \
	input_tag="$(TAG)"; \
	input_version="$(VERSION)"; \
	if [ -n "$$input_tag" ]; then \
		version="$${input_tag#server-v}"; \
	elif [ -n "$$input_version" ]; then \
		version="$$input_version"; \
	else \
		version="$(GENERATED_VERSION)"; \
	fi; \
	version="$${version#v}"; \
	[[ "$$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$$ ]] || { \
		echo "VERSION must be semantic, for example 26.804.1530" >&2; \
		exit 1; \
	}; \
	server_ref="$(SERVER_REF)"; \
	web_ref="$(WEB_REF)"; \
	[[ "$$server_ref" =~ ^[0-9A-Za-z._/-]+$$ ]] || { echo "SERVER_REF contains unsupported characters" >&2; exit 1; }; \
	[[ "$$web_ref" =~ ^[0-9A-Za-z._/-]+$$ ]] || { echo "WEB_REF contains unsupported characters" >&2; exit 1; }; \
	printf '%s\n' \
		"Deploy Server plan:" \
		"  action_repository: $(ACTION_REPOSITORY)" \
		"  action_ref:        $(ACTION_REF)" \
		"  server_repository: $(SERVER_REPOSITORY)" \
		"  server_ref:        $$server_ref" \
		"  web_repository:    $(WEB_REPOSITORY)" \
		"  web_ref:           $$web_ref" \
		"  image:             ghcr.io/$(SERVER_IMAGE_NAME):$$version" \
		"  remote_dir:        /opt/one-node"; \
	case "$(DRY_RUN)" in \
		true|1|yes|y) \
			echo "DRY_RUN=true: no workflow was triggered."; \
			exit 0; \
			;; \
	esac; \
	api_token="$${GH_TOKEN:-}"; \
	api_token="$${api_token%\"}"; \
	api_token="$${api_token#\"}"; \
	api_token="$${api_token%\'}"; \
	api_token="$${api_token#\'}"; \
	api_token="$${api_token#Bearer }"; \
	api_token="$${api_token#bearer }"; \
	[ -n "$$api_token" ] || { \
		echo "GH_TOKEN is required. Add the raw token to $(ENV_FILE)." >&2; \
		exit 1; \
	}; \
	response_file="$$(mktemp)"; \
	trap 'rm -f "$$response_file"' EXIT HUP INT TERM; \
	workflow_status="$$($(CURL) --silent --show-error \
		--output "$$response_file" \
		--write-out '%{http_code}' \
		--header "Authorization: Bearer $$api_token" \
		--header "Accept: application/vnd.github+json" \
		--header "X-GitHub-Api-Version: 2022-11-28" \
		"$(GITHUB_API_URL)/repos/$(ACTION_REPOSITORY)/actions/workflows/server.yml")"; \
	if [ "$$workflow_status" != 200 ]; then \
		echo "server.yml is not published on $(ACTION_REPOSITORY)'s default branch (HTTP $$workflow_status)." >&2; \
		echo "Commit and push the one-node-action workflow before running make deploy-server." >&2; \
		cat "$$response_file" >&2; \
		exit 1; \
	fi; \
	payload=$$(printf \
		'{"ref":"%s","inputs":{"server_ref":"%s","web_ref":"%s","version":"%s"}}' \
		"$(ACTION_REF)" "$$server_ref" "$$web_ref" "$$version"); \
	dispatch_status="$$($(CURL) --silent --show-error \
		--output "$$response_file" \
		--write-out '%{http_code}' \
		--request POST \
		--header "Authorization: Bearer $$api_token" \
		--header "Accept: application/vnd.github+json" \
		--header "X-GitHub-Api-Version: 2022-11-28" \
		--data "$$payload" \
		"$(GITHUB_API_URL)/repos/$(ACTION_REPOSITORY)/actions/workflows/server.yml/dispatches")"; \
	if [ "$$dispatch_status" -lt 200 ] || [ "$$dispatch_status" -ge 300 ]; then \
		echo "Failed to dispatch server.yml: HTTP $$dispatch_status" >&2; \
		cat "$$response_file" >&2; \
		exit 1; \
	fi; \
	rm -f "$$response_file"; \
	trap - EXIT HUP INT TERM; \
	printf '%s\n' \
		"Triggered Server deployment:" \
		"  repository: $(ACTION_REPOSITORY)" \
		"  version:    $$version"
