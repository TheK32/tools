# 本机服务管理器（中文）

一个面向 Linux 主机的 Bash 工具，用于以中文查看和管理 systemd 服务、监听端口及 Docker 容器。它适合个人服务器和日常运维，不是通用监控平台。

## 前提条件

- Linux，且 PID 1 使用 systemd
- Bash 4 或更新版本
- `systemctl` 和 `journalctl`
- `ss`（通常由 `iproute2` 提供）
- Docker 为可选依赖；仅在执行 `docker` 或 `all` 时使用

系统服务的启动、停止、重启、启用与禁用需要 root 权限，例如：

```bash
sudo bash service-manager-cn.sh restart nginx
```

## 使用方式

先赋予脚本执行权限：

```bash
chmod +x service-manager-cn.sh
```

不带参数时会打开交互菜单；在非交互输入中，则输出服务、端口和 Docker 信息。

```bash
./service-manager-cn.sh
./service-manager-cn.sh all
./service-manager-cn.sh list
./service-manager-cn.sh list-all
./service-manager-cn.sh user-list
./service-manager-cn.sh user-list-all
./service-manager-cn.sh ports
./service-manager-cn.sh docker
```

管理系统服务：

```bash
./service-manager-cn.sh status nginx
sudo ./service-manager-cn.sh restart nginx
sudo ./service-manager-cn.sh enable nginx
./service-manager-cn.sh logs nginx
```

管理当前用户的服务：

```bash
./service-manager-cn.sh user-status example.service
./service-manager-cn.sh user-restart example.service
./service-manager-cn.sh user-logs example.service
```

支持的服务操作为：`start`、`stop`、`restart`、`status`、`enable`、`disable` 和 `logs`。可通过 `--help` 查看完整帮助，`--version` 查看版本。

## 用户级服务说明

`user-*` 命令仅操作**当前用户**的 systemd user manager，不会列出或修改其他用户的服务。它需要一个可用的用户会话；在某些 SSH、CI 或非登录环境中，user manager 可能不可用，脚本会明确报错而不是把它误报为“没有服务”。

如果希望用户服务在没有登录会话时继续运行，可按系统策略启用 lingering：

```bash
loginctl enable-linger "$USER"
```

## 安全提示

该脚本不会下载或执行远程代码，但系统服务操作会改变主机运行状态。请先用 `status` 或 `logs` 确认目标服务，并仅以必要权限运行。

## 开发与检查

仓库提供 GitHub Actions 检查 Bash 语法和 ShellCheck。可在本地运行：

```bash
bash -n service-manager-cn.sh
shellcheck service-manager-cn.sh
```

## 许可证

当前仓库尚未声明许可证；在复用或分发前，请由仓库维护者补充适合的许可证。
