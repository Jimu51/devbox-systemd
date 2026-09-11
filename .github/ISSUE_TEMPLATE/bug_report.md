---
name: Bug 报告
about: 报告 systemdbox 镜像或脚本的问题
title: '[Bug] '
labels: bug
assignees: ''
---

## 🐛 问题描述

清晰简洁地描述这个 bug。

## 🔄 复现步骤

1. 启动命令：`docker compose up -d` 或 `docker run ...`
2. 执行的动作
3. 看到的问题

## ✅ 预期行为

清晰描述你期望发生什么。

## ❌ 实际行为

实际发生了什么？贴出错误日志或截图。

## 🖥️ 环境信息

```bash
# 在容器内执行后粘贴结果
cat /etc/os-release
docker exec devbox-systemd python3 --version
docker exec devbox-systemd node --version
docker exec devbox-systemd java -version 2>&1
docker exec devbox-systemd code-server --version
docker exec devbox-systemd systemctl is-system-running
```

## 📋 主机环境

- OS: （如 Debian 12 / Ubuntu 22.04 / macOS）
- Docker 版本：`docker --version`
- 内核版本：`uname -r`
- cgroup 版本：`cat /proc/filesystems | grep cgroup`

## 🖼️ 截图 / 日志

如果适用，添加截图或完整的容器日志（`docker logs devbox-systemd`）。

## 📝 其他信息

任何其他有助于排查问题的上下文。