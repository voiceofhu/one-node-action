# one-node-action

One Node 的公开安装入口与 Node Release 打包仓库。节点源码保存在私有
`voiceofhu/one-node-node`；公共 Action 固定检出节点提交，构建 Linux amd64
二进制，并把产物发布到本仓库的 Release。

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

## Node Release

`.github/workflows/node-release.yml` 是手动触发的公开打包流程：

1. 校验本仓库的安装、卸载入口；
2. 使用 `GH_TOKEN` 检出私有 `voiceofhu/one-node-node` 的指定 ref；
3. 将 ref 固定为完整提交 SHA；
4. 运行 Go 测试和 Debian 安装器集成测试；
5. 构建静态 `linux/amd64` 节点二进制；
6. 在本仓库发布不可变的 `node-v<version>` Release。

Release assets：

- `one-node-node-linux-amd64`
- `one-node-node-linux-amd64.sha256`
- `install.sh`
- `install.sh.sha256`
- `uninstall.sh`
- `uninstall.sh.sha256`
- `SHA256SUMS`

若同名 Release 已存在，workflow 只在 Node 源提交和完整资产列表都一致时视为
成功，不会覆盖已有资产。

Action 仓库需要配置 `GH_TOKEN` Secret。Token 必须能读取私有
`voiceofhu/one-node-node`，并能在 `voiceofhu/one-node-action` 运行 workflow
和创建 Release。

也可以从本地通过 GitHub API 触发：

```bash
printf '%s\n' 'GH_TOKEN=ghp_xxx' > .env
make deploy-node TAG=v0.1.0 NODE_REF=265d977
```

`.env` 已被忽略，不要提交 Token。

## 检查

```bash
make check
```

完整安装器集成测试仍由 Node 仓库的 `make test-installer` 执行。测试使用一次性
Debian 容器，不会修改宿主机的 `/opt` 或 `/etc`。
