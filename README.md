# one-node-action

One Node 的公开安装入口与 Node 发布仓库。安装、卸载脚本始终直接来自本仓库
代码，不进入版本 Release。节点源码保存在私有
`voiceofhu/one-node-node`；公共 Action 固定检出节点提交，构建 Linux amd64
二进制，同时发布原生产物到本仓库 Release、发布 Docker 镜像到 GHCR。

## 公共入口

Server 使用以下稳定 URL：

- `https://github.com/voiceofhu/one-node-action/raw/refs/heads/main/install.sh`
- `https://github.com/voiceofhu/one-node-action/raw/refs/heads/main/uninstall.sh`

根目录文件只负责稳定入口和实现加载。实际逻辑按安装、卸载分别放在：

- `scripts/node/install/main.sh`
- `scripts/node/uninstall/main.sh`

通过 raw URL 执行时，入口先从 GitHub API 把 `main` 解析成固定的 40 位提交
SHA，再从该提交加载对应实现；单次执行不会混用不同提交的文件。本地直接运行
根目录脚本时，会使用工作区中的实现，便于测试。

安装方式保持不变：

- `install.sh --mode native`：安装原生二进制并注册 systemd 服务。
- `install.sh --mode docker`：安装或复用 Docker，以 Compose 运行节点代理。
- `uninstall.sh`：根据 `/opt/one-node-node/.installation` 自动识别安装方式。

## Release Node

`.github/workflows/release-node.yml` 是手动触发的公开发布流程：

1. 校验本仓库的安装、卸载入口；
2. 使用 `GH_TOKEN` 检出私有 `voiceofhu/one-node-node` 的指定 ref；
3. 将 ref 固定为完整提交 SHA；
4. 运行 Go 测试和 Debian 安装器集成测试；
5. 构建静态 `linux/amd64` 节点二进制；
6. 在本仓库发布不可变的 `node-v<version>` Release；
7. 从同一 Node 提交构建并发布 `linux/amd64` Docker 镜像。

Release assets：

- `one-node-node-linux-amd64`
- `SHA256SUMS`

安装和卸载入口保留在 `main` 分支，由上面的稳定 raw URL 提供，不复制进
Release。Docker 镜像发布为：

- `ghcr.io/voiceofhu/one-node-node:<version>`
- `ghcr.io/voiceofhu/one-node-node:sha-<40位Node提交SHA>`

版本 tag 用于部署；完整提交 tag 用于审计和不可变复现。workflow 不发布
`latest`，避免补发旧版本时意外回滚默认镜像。

若同名 Release 已存在，workflow 只在 Node 源提交和完整资产列表都一致时视为
成功，不会覆盖已有资产。

Action 仓库需要配置 `GH_TOKEN` Secret。Token 必须能读取私有
`voiceofhu/one-node-node`，并能在 `voiceofhu/one-node-action` 运行 workflow
和创建 Release，同时需要对 `voiceofhu/one-node-node` GHCR package 具有写权限。

也可以从本地完成整套发布：

```bash
printf '%s\n' 'GH_TOKEN=ghp_xxx' > .env
make deploy-node DRY_RUN=true
make deploy-node
```

`deploy-node` 会进入同级 `one-node-node` 仓库，要求发布分支工作区干净，
按上海时区生成 `年后两位.MMDD.HHmm` 版本，例如 `26.726.1530`。同步远端并
运行 Node 测试后，命令会更新根目录 `VERSION`、只提交版本文件，并原子推送
发布分支和 `v<version>` 源码标签；随后回到 Action 发布流程，以该不可变标签
触发 `release-node.yml`，最终在本仓库生成 `node-v<version>` Release。Node
仓库路径、分支和远端可分别通过
`NODE_DIR`、`NODE_BRANCH`、`NODE_REMOTE` 覆盖。

默认无需传入版本；需要复现或补发指定版本时，可以通过
`VERSION=26.726.1530` 或 `TAG=v26.726.1530` 覆盖。

若远端源码标签已经存在，命令不会改写 Node 历史，而是直接复用该标签重新触发
workflow。`DRY_RUN=true` 只打印完整计划，不更新版本、不提交、不推送也不触发。

`.env` 已被忽略，不要提交 Token。

## 检查

```bash
make check
```

完整安装器集成测试仍由 Node 仓库的 `make test-installer` 执行。测试使用一次性
Debian 容器，不会修改宿主机的 `/opt` 或 `/etc`。
