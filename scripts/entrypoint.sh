#!/bin/bash
# ============================================================
# 容器入口脚本
# ------------------------------------------------------------
# 1. 处理 code-server 密码配置（明文 / 已 hash / 自动生成）
# 2. 把环境变量写入 /etc/code-server/code-server.env
#    供 code-server.service 通过 EnvironmentFile 读取
# 3. 输出密码提示（用户必须能看到实际生效的密码）
# 4. 生成 code-server 的默认配置文件
# 5. exec 启动 systemd（PID 1）
# ============================================================
set -eu

ENV_FILE="/etc/code-server/code-server.env"
CONFIG_FILE="/etc/code-server/config.yaml"

# 准备目录与权限
mkdir -p /etc/code-server /home/coder/.local/share/code-server
chown -R coder:coder /home/coder

# 配置系统时区（如果传入了 TZ）
if [ -n "${TZ:-}" ] && [ -e "/usr/share/zoneinfo/${TZ}" ]; then
    ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime
    echo "${TZ}" > /etc/timezone
    echo "[entrypoint] 系统时区已设置为 ${TZ}"
elif [ -n "${TZ:-}" ]; then
    echo "[entrypoint] ⚠ TZ=${TZ} 在 /usr/share/zoneinfo 中找不到，仍使用 UTC"
fi

# ============================================================
# 密码解析：优先级 HASHED_PASSWORD > PASSWORD > 自动生成
# ============================================================
RESOLVED_PASSWORD=""
RESOLVED_HASHED=""
PASSWORD_SOURCE=""

if [ -n "${HASHED_PASSWORD:-}" ]; then
    # 优先使用已 hash 的密码
    RESOLVED_HASHED="${HASHED_PASSWORD}"
    PASSWORD_SOURCE="env:HASHED_PASSWORD"
elif [ -n "${PASSWORD:-}" ]; then
    # 使用明文密码，code-server 自身会 hash
    RESOLVED_PASSWORD="${PASSWORD}"
    PASSWORD_SOURCE="env:PASSWORD"
else
    # 都没有设置，自动生成 16 位随机密码
    RESOLVED_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
    PASSWORD_SOURCE="auto-generated"
fi

# 写入 systemd 单元可见的 env 文件
{
    echo "# 由 docker-entrypoint.sh 自动生成，请勿手工编辑"
    [ -n "${RESOLVED_PASSWORD}" ] && echo "PASSWORD=${RESOLVED_PASSWORD}"
    [ -n "${RESOLVED_HASHED}" ]  && echo "HASHED_PASSWORD=${RESOLVED_HASHED}"
    [ -n "${SUDO_PASSWORD:-}" ]   && echo "SUDO_PASSWORD=${SUDO_PASSWORD}"
    [ -n "${HASHED_SUDO_PASSWORD:-}" ] && echo "HASHED_SUDO_PASSWORD=${HASHED_SUDO_PASSWORD}"
    echo "DISABLE_TELEMETRY=1"
} > "${ENV_FILE}"
chmod 0600 "${ENV_FILE}"

# 输出密码配置摘要（用醒目边框方便用户从日志中查找）
echo "================================================================"
echo "  ★ code-server 密码已就绪"
echo "================================================================"
echo "  来源：${PASSWORD_SOURCE}"
if [ "${PASSWORD_SOURCE}" = "auto-generated" ]; then
    echo "  ⚠ 密码为自动生成，仅适合临时使用"
    echo "  ★ 密码：${RESOLVED_PASSWORD}"
    echo "  ★ 访问：http://<host>:3443"
elif [ "${PASSWORD_SOURCE}" = "env:PASSWORD" ]; then
    echo "  ★ 密码：使用环境变量 PASSWORD（长度 ${#PASSWORD}）"
elif [ "${PASSWORD_SOURCE}" = "env:HASHED_PASSWORD" ]; then
    echo "  ★ 密码：使用环境变量 HASHED_PASSWORD（argon2 hash）"
fi
echo "================================================================"

# 生成 code-server 默认配置文件
if [ ! -e "${CONFIG_FILE}" ]; then
    cat > "${CONFIG_FILE}" <<'YAML'
bind-addr: 0.0.0.0:8080
auth: password
disable-telemetry: true
YAML
fi
chmod 0644 "${CONFIG_FILE}"

# 默认启动 systemd
if [ "$#" -eq 0 ]; then
    set -- /lib/systemd/systemd --system
fi

# 用 exec 让 systemd 接管 PID 1
exec "$@"
