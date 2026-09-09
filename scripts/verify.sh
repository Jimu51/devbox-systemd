#!/bin/bash
# ============================================================
# 镜像冒烟测试脚本
# ------------------------------------------------------------
# 用法：
#   CONTAINER=devbox ./scripts/verify.sh
# 检查：
#   1. 各组件版本
#   2. systemd 运行状态
#   3. code-server 服务健康状况
# ============================================================
set -eu

CONTAINER="${CONTAINER:-devbox}"

echo "==> 组件版本"
docker exec "${CONTAINER}" bash -c '
    echo "Python : $(python3.12 --version 2>&1)"
    echo "pip    : $(python3.12 -m pip --version 2>&1)"
    echo "Node   : $(node --version 2>&1)"
    echo "npm    : $(npm --version 2>&1)"
    echo "Java   : $(java -version 2>&1 | head -1)"
    echo "javac  : $(javac -version 2>&1)"
    echo "code-server : $(code-server --version 2>&1 | head -1)"
    echo "systemd PID 1 : $(cat /proc/1/comm)"
'

echo
echo "==> systemd 运行状态"
docker exec "${CONTAINER}" bash -c '
    systemctl is-system-running || true
    systemctl status code-server --no-pager || true
'

echo
echo "==> 健康检查"
docker exec "${CONTAINER}" bash -c '
    code-server --version >/dev/null
    curl -fsS -o /dev/null -w "GET /healthz -> %{http_code}\n" http://127.0.0.1:8080/healthz || true
'

echo
echo "==> 完成"
