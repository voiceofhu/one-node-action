# one-node-action

One Node 的公开安装与卸载脚本统一放在这里：

- `install.sh --mode native`：安装原生二进制并注册 systemd 服务。
- `install.sh --mode docker`：安装或复用 Docker，以 Compose 运行节点代理。
- `uninstall.sh`：根据 `/opt/one-node-node/.installation` 自动识别安装方式并卸载。

两种安装方式都使用 Server 生成的一次性注册参数，并继续校验固定的节点二进制
SHA-256。Docker 模式复用宿主机 Xray，通过 host network 访问 Xray API；卸载时
保留 Docker 和宿主机 Xray，只移除 One Node 服务、安装目录和节点身份目录。

本地检查：

```bash
make check
```
