# ==============================================================================
# Release Node 命令
# ------------------------------------------------------------------------------
# 先在同级 Node 仓库更新版本并创建不可变源码标签，再回到公共 Action 仓库
# 通过 GitHub API 调度打包 workflow。Release 资产仍只由 workflow 生成。
# ==============================================================================

.PHONY: deploy-node

deploy-node:
	@set -euo pipefail; \
	input_tag="$(TAG)"; \
	input_version="$(VERSION)"; \
	node_dir="$(NODE_DIR)"; \
	if [ -n "$$input_tag" ]; then \
		version="$${input_tag#node-v}"; \
	elif [ -n "$$input_version" ]; then \
		version="$$input_version"; \
	else \
		generated_tag="$$($(MAKE) --no-print-directory -s -C "$$node_dir" generated-tag)"; \
		version="$${generated_tag#v}"; \
	fi; \
	version="$${version#v}"; \
	[[ "$$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$$ ]] || { \
		echo "Generated VERSION must be semantic, for example 26.726.1530" >&2; \
		exit 1; \
	}; \
	source_tag="v$$version"; \
	release_tag="node-v$$version"; \
	node_branch="$(NODE_BRANCH)"; \
	node_remote="$(NODE_REMOTE)"; \
	[ -d "$$node_dir/.git" ] || { \
		echo "Node repository not found: $$node_dir" >&2; \
		exit 1; \
	}; \
	[[ "$$node_branch" =~ ^[0-9A-Za-z._/-]+$$ ]] || { \
		echo "NODE_BRANCH contains unsupported characters" >&2; \
		exit 1; \
	}; \
	[[ "$$node_remote" =~ ^[0-9A-Za-z._/-]+$$ ]] || { \
		echo "NODE_REMOTE contains unsupported characters" >&2; \
		exit 1; \
	}; \
	printf '%s\n' \
		"Release Node plan:" \
		"  node_repository:   $(NODE_REPOSITORY)" \
		"  node_directory:    $$node_dir" \
		"  node_branch:       $$node_branch" \
		"  node_remote:       $$node_remote" \
		"  source_tag:        $$source_tag" \
		"  action_repository: $(ACTION_REPOSITORY)" \
		"  action_ref:        $(ACTION_REF)" \
		"  release_tag:       $$release_tag"; \
	case "$(DRY_RUN)" in \
		true|1|yes|y) \
			echo "DRY_RUN=true: no version, Git, push, or workflow changes were made."; \
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
	remote_tag="$$(git -C "$$node_dir" ls-remote --tags "$$node_remote" "refs/tags/$$source_tag")"; \
	if [ -n "$$remote_tag" ]; then \
		git -C "$$node_dir" fetch --quiet --no-tags "$$node_remote" "refs/tags/$$source_tag"; \
		remote_version="$$(git -C "$$node_dir" show "FETCH_HEAD:VERSION" 2>/dev/null || true)"; \
		[ "$$remote_version" = "$$version" ] || { \
			echo "Remote Node tag $$source_tag does not contain matching VERSION metadata." >&2; \
			exit 1; \
		}; \
		echo "Remote Node tag $$source_tag already exists; reusing it without changing the source repository."; \
	else \
		[ -z "$$(git -C "$$node_dir" status --porcelain)" ] || { \
			echo "Node worktree must be clean before creating $$source_tag: $$node_dir" >&2; \
			exit 1; \
		}; \
		current_branch="$$(git -C "$$node_dir" symbolic-ref --quiet --short HEAD)" || { \
			echo "Node repository must be on branch $$node_branch, not detached HEAD." >&2; \
			exit 1; \
		}; \
		[ "$$current_branch" = "$$node_branch" ] || { \
			echo "Node repository is on $$current_branch; expected $$node_branch." >&2; \
			exit 1; \
		}; \
		git -C "$$node_dir" pull --ff-only "$$node_remote" "$$node_branch"; \
		$(MAKE) --no-print-directory -C "$$node_dir" test; \
		if git -C "$$node_dir" show-ref --verify --quiet "refs/tags/$$source_tag"; then \
			tag_commit="$$(git -C "$$node_dir" rev-list -n 1 "$$source_tag")"; \
			head_commit="$$(git -C "$$node_dir" rev-parse HEAD)"; \
			tag_version="$$(git -C "$$node_dir" show "$$source_tag:VERSION" 2>/dev/null || true)"; \
			[ "$$tag_commit" = "$$head_commit" ] && [ "$$tag_version" = "$$version" ] || { \
				echo "Local tag $$source_tag exists but does not match HEAD and VERSION." >&2; \
				exit 1; \
			}; \
			echo "Reusing local Node tag $$source_tag after a previous partial publish."; \
		else \
			$(MAKE) --no-print-directory -C "$$node_dir" set-version NEW_VERSION="$$version"; \
			git -C "$$node_dir" add -- VERSION; \
			if ! git -C "$$node_dir" diff --cached --quiet -- VERSION; then \
				git -C "$$node_dir" commit -m "chore: release $$source_tag" -- VERSION; \
			else \
				echo "VERSION is already $$source_tag; tagging the current Node commit."; \
			fi; \
			git -C "$$node_dir" tag -a "$$source_tag" -m "One Node Node $$source_tag"; \
		fi; \
		git -C "$$node_dir" push --atomic "$$node_remote" \
			"HEAD:refs/heads/$$node_branch" \
			"refs/tags/$$source_tag"; \
	fi; \
	payload=$$(printf \
		'{"ref":"%s","inputs":{"node_ref":"%s","version_tag":"v%s"}}' \
		"$(ACTION_REF)" "$$source_tag" "$$version"); \
	$(CURL) --fail --silent --show-error \
		--request POST \
		--header "Authorization: Bearer $$api_token" \
		--header "Accept: application/vnd.github+json" \
		--header "X-GitHub-Api-Version: 2022-11-28" \
		--data "$$payload" \
		"$(GITHUB_API_URL)/repos/$(ACTION_REPOSITORY)/actions/workflows/release-node.yml/dispatches"; \
	printf '%s\n' \
		"Triggered Release Node:" \
		"  repository: $(ACTION_REPOSITORY)" \
		"  node_ref:   $$source_tag" \
		"  release:    $$release_tag"
