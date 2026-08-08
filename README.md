# one-node-action

One Node 的公开安装入口与 Node 发布仓库。安装、卸载脚本始终直接来自本仓库
代码，不进入版本 Release。节点源码保存在私有
`voiceofhu/one-node-node`；公共 Action 固定检出节点提交，构建 Linux amd64
与 arm64 二进制，同时发布原生产物到本仓库 Release、发布 Docker 镜像到 GHCR。

## 公共入口

Server 使用以下稳定 URL：

- `https://github.com/voiceofhu/one-node-action/raw/refs/heads/main/install.sh`
- `https://github.com/voiceofhu/one-node-action/raw/refs/heads/main/uninstall.sh`
- `https://github.com/voiceofhu/one-node-action/raw/refs/heads/main/upgrade.sh`

根目录文件只负责稳定入口和模块加载。实际逻辑放在 `scripts/node/`，按公共
manifest、安装、升级、回滚和卸载拆分。模块清单由根入口显式声明，远程执行时
默认从本仓库的 GitHub raw 地址下载并校验语法后统一加载；本地或开发环境仍可
通过 `ONE_NODE_SCRIPT_BASE_URL` 覆盖模块地址。

Server 生成命令只传递节点注册所需的地址、身份和一次性令牌。本地直接运行根目录
脚本时，会使用工作区中的实现，便于测试。

安装方式保持不变：

- `install.sh --mode native`：安装原生二进制并注册 systemd 服务。
- `install.sh --mode docker`：安装或复用 Docker，以 Compose 运行节点代理。
- `upgrade.sh`：为 Native 或 Docker 安装切换不可变版本；失败时自动回滚。
- `upgrade.sh --rollback`：显式恢复 manifest 中唯一保留的上一版本。
- `uninstall.sh`：根据 `/opt/one-node-node/.installation` 自动识别安装方式，只
  删除经过 canonical allowlist 验证的 One Node 自有路径。

安装器只部署 sing-box One Node runtime。Native 模式只管理单一
`one-node-node.service`；Docker 模式只管理 manifest 记录的完整 One Node 镜像和
容器。安装、升级和卸载均不安装、修改或删除宿主机的其他代理软件，也不卸载
Docker Engine。成功条件为控制面身份激活且 runtime active revision 达到 Server
指定值；配置 revision 未指定时仍必须观测到大于零的有效配置。

安装器默认从 GitHub Release 和 GHCR 获取当前节点版本；Native 模式会使用同一
Release 的 `SHA256SUMS` 校验下载的二进制。目标 Debian 需要预先提供 `curl`；
安装器会继续检查其余必备命令。

## Release Node

`.github/workflows/release-node.yml` 是手动触发的公开发布流程：

1. 使用 `GH_TOKEN` 将私有 `voiceofhu/one-node-node` ref 固定为完整提交 SHA；
2. 运行 Go、核心 race、capability E2E、Debian 安装器和公开入口检查；
3. 从同一提交构建 `linux/amd64` 与 `linux/arm64` 节点二进制；
4. 在本仓库发布不可变的 `node-rc-v<version>-rc.<n>` prerelease；
5. 从同一 Node 提交构建并发布双架构完整 Docker 镜像。

Release assets：

- `one-node-node-linux-amd64`
- `one-node-node-linux-arm64`
- `SHA256SUMS`

安装和卸载入口保留在 `main` 分支，由上面的稳定 raw URL 提供，不复制进
Release。Docker 镜像发布为：

- `ghcr.io/voiceofhu/one-node-node:sha-<40位Node提交SHA>`
- `ghcr.io/voiceofhu/one-node-node:rc-<version>-rc.<n>`

RC tag 用于 Canary；完整提交 tag 用于审计和不可变复现。workflow 不发布或移动
`latest`、stable 或普通版本 tag，避免补发旧版本时意外回滚默认镜像。

若同名 Release 已存在，workflow 只在 Node 源提交和完整资产列表都一致时视为
成功，不会覆盖已有资产。

Action 仓库需要配置 `GH_TOKEN` Secret。Token 必须能读取私有
`voiceofhu/one-node-node`，并能在 `voiceofhu/one-node-action` 运行 workflow
和创建 Release，同时需要对 `voiceofhu/one-node-node` GHCR package 具有写权限。

也可以从本地完成整套发布：

```bash
printf '%s\n' 'GH_TOKEN=ghp_xxx' > .env
make deploy-node DRY_RUN=true
make deploy-node NODE_RC=1
```

`deploy-node` 会进入同级 `one-node-node` 仓库，要求发布分支工作区干净，
按上海时区生成 `年后两位.MMDD.HHmm` 版本，例如 `26.726.1530`。同步远端并
运行 Node 测试后，命令会更新根目录 `VERSION`、只提交版本文件，并原子推送
发布分支和 `v<version>` 源码标签；随后回到 Action 发布流程，以该不可变标签
触发 `release-node.yml`，最终在本仓库生成
`node-rc-v<version>-rc.<n>` prerelease。Node
仓库路径、分支和远端可分别通过
`NODE_DIR`、`NODE_BRANCH`、`NODE_REMOTE` 覆盖。

默认无需传入版本；需要复现或补发指定版本时，可以通过
`VERSION=26.726.1530` 或 `TAG=v26.726.1530` 覆盖。`NODE_RC` 指定正整数 RC
序号，默认是 `1`；同一源码需要新的 Canary 时显式递增该值。

若远端源码标签已经存在，命令不会改写 Node 历史，而是直接复用该标签重新触发
workflow。`DRY_RUN=true` 只打印完整计划，不更新版本、不提交、不推送也不触发。

`.env` 已被忽略，不要提交 Token。

## Deploy Server

`make deploy-server` 会触发 `.github/workflows/server.yml`，固定 Server 与 Web
的完整提交，先把 Web 构建为 Next.js 静态 `out`，再将它和 Go Server 一起构建
为 `linux/amd64` Docker 镜像并上传到 GHCR。默认版本仍按上海时区生成，也可用
`VERSION` 或 `TAG` 指定：

```bash
make deploy-server DRY_RUN=true
make deploy-server
make deploy-server VERSION=26.804.1530
```

每次发布都会生成以下镜像标签：

- `ghcr.io/voiceofhu/one-node-server:<version>`
- `ghcr.io/voiceofhu/one-node-server:sha-<server-sha>-web-<web-sha>`
- `ghcr.io/voiceofhu/one-node-server:latest`

部署始终使用同时固定 Server/Web 提交的标签，不使用 `latest`。Action 需要
`GH_TOKEN` 以及 `DEPLOY_USER`、`DEPLOY_SSH_KEY`、`DEPLOY_KNOWN_HOSTS` 三个
Repository Secrets。`DEPLOY_KNOWN_HOSTS` 的第一条非注释记录必须是未哈希的
部署主机；workflow 从该记录读取主机和可选端口，不需要额外的 Host Secret。

远端 `/opt/one-node` 需要预先存在且可写，并包含生产 `.env`。部署用户需要直接
运行 Docker/Compose；workflow 只原子更新 `docker-compose.yml`，不会上传、覆盖
或打印 `.env`。默认接入外部 `db-networks`，HTTP 映射到
`127.0.0.1:27520`，控制通道映射到 `127.0.0.1:27524`。部署完成后会同时检查
`/api/healthz` 和 `/` 静态站点；失败时尝试恢复上一镜像。

## 检查

```bash
make check
```

完整安装器集成测试仍由 Node 仓库的 `make test-installer` 执行。测试使用一次性
Debian 容器，不会修改宿主机的 `/opt` 或 `/etc`。
