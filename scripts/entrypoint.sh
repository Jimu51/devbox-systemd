#!/bin/bash
# ============================================================
# 容器入口脚本
# ------------------------------------------------------------
# 1. 同步内核 hostname 到 /etc/hostname（避免 systemctl 报 hostname）
# 2. 处理 code-server 密码配置（明文 / 已 hash / 自动生成）
# 3. 把环境变量写入 /etc/code-server/code-server.env
#    供 code-server.service 通过 EnvironmentFile 读取
# 4. 输出密码提示（用户必须能看到实际生效的密码）
# 5. 生成 code-server 的默认配置文件
# 6. exec 启动 systemd（PID 1）
# ============================================================
set -eu

ENV_FILE="/etc/code-server/code-server.env"
CONFIG_FILE="/etc/code-server/config.yaml"

# 准备目录与权限
mkdir -p /etc/code-server

# -----------------------------------------------------------
# coder 用户配置初始化（首次启动时）
# -----------------------------------------------------------
# 主机上 ./home 通过 bind mount 挂到 /home/coder，
# 如果主机目录是空的（首次启动或被清空），需要把镜像里的默认配置补齐：
#   - .local/share/code-server/User/settings.json（关闭 workspace trust 等）
#   - .m2/settings.xml（阿里云 Maven 镜像）
#   - .npmrc（淘宝 npm 源）
# 已存在则不覆盖（保留用户的自定义配置）
mkdir -p /home/coder/.local/share/code-server/User
mkdir -p /home/coder/.m2
if [ ! -f /home/coder/.local/share/code-server/User/settings.json ]; then
    cat > /home/coder/.local/share/code-server/User/settings.json <<'JSON'
{
    "security.workspace.trust.enabled": false,
    "security.workspace.trust.banner": "never",
    "security.workspace.trust.emptyWindow": true,
    "extensions.supportUntrustedWorkspaces": {
        "*": true
    },
    "workbench.startupEditor": "none",
    "telemetry.telemetryLevel": "off",
    "files.dialog.defaultPath": "/home/coder/workspace",
    "update.mode": "none"
}
JSON
    echo "[entrypoint] code-server 设置已初始化（首次启动）"
fi
if [ ! -f /home/coder/.m2/settings.xml ]; then
    cat > /home/coder/.m2/settings.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">
    <mirrors>
        <mirror>
            <id>aliyun-public</id>
            <mirrorOf>*</mirrorOf>
            <name>Aliyun Public Maven Mirror</name>
            <url>https://maven.aliyun.com/repository/public</url>
        </mirror>
    </mirrors>
</settings>
XML
    echo "[entrypoint] Maven 阿里云镜像配置已初始化（首次启动）"
fi
if [ ! -f /home/coder/.npmrc ]; then
    cat > /home/coder/.npmrc <<'NPMRC'
registry=https://registry.npmmirror.com/
fund=false
audit=false
update-notifier=false
loglevel=warn
NPMRC
    echo "[entrypoint] npm 淘宝源配置已初始化（首次启动）"
fi

# 修复权限（coder 用户拥有自己的文件）
chown -R coder:coder /home/coder 2>/dev/null || true

# ============================================================
# 主机名同步（修复 systemctl 报 "hostname unset" 的 bug）
# ------------------------------------------------------------
# Debian 12 base image 的 /etc/hostname 内容异常（容器 ID 或 "debain"），
# 不修复的话 systemd 启动时会执行 sethostname() 写入错误值，
# 同时 systemd-hostnamed 被 mask 时 D-Bus 主机名查询也会失败。
# 这里：
#   1. 读取内核实际 hostname（docker-compose 设置的"devbox"）
#   2. 写回 /etc/hostname（systemd 启动时会读取此文件）
#   3. 显式调用 hostname 命令再次确认 kernel hostname 也是 "devbox"
# ============================================================
ACTUAL_HOSTNAME="$(cat /proc/sys/kernel/hostname 2>/dev/null || hostname)"
[ -n "${ACTUAL_HOSTNAME}" ] || ACTUAL_HOSTNAME="devbox"
echo "${ACTUAL_HOSTNAME}" > /etc/hostname
# 再次显式调用 hostname 命令确保 kernel hostname 也是正确的，
# 防止 systemd-hostnamed service 启动早期读到错误的 hostname
hostname "${ACTUAL_HOSTNAME}" 2>/dev/null || true
echo "[entrypoint] 主机名已同步: ${ACTUAL_HOSTNAME}（写入 /etc/hostname 与内核）"

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

# 生成/修复 code-server 默认配置文件
# 注意：bind-addr 必须是 8443，与 systemd 单元 ExecStart 中的 --bind-addr 保持一致
# 不要写 default-folder（code-server 4.x 不支持），默认目录由 ExecStart 末尾参数控制
if [ ! -e "${CONFIG_FILE}" ]; then
    cat > "${CONFIG_FILE}" <<'YAML'
bind-addr: 0.0.0.0:8443
auth: password
disable-telemetry: true
disable-update-check: true
YAML
else
    # 修复老镜像中 bind-addr 是 8080 的问题
    if grep -q "^bind-addr: 0.0.0.0:8080" "${CONFIG_FILE}"; then
        sed -i 's|^bind-addr: 0.0.0.0:8080|bind-addr: 0.0.0.0:8443|' "${CONFIG_FILE}"
    fi
    # 移除无效的 default-folder（老镜像误加）
    sed -i '/^default-folder:/d' "${CONFIG_FILE}"
fi
chmod 0644 "${CONFIG_FILE}"

# 默认启动 systemd
if [ "$#" -eq 0 ]; then
    set -- /lib/systemd/systemd --system
fi

# 用 exec 让 systemd 接管 PID 1
exec "$@"