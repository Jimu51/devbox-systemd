# ============================================================
# 屏蔽容器内不适用的 systemd 单元
# ------------------------------------------------------------
# 容器中没有真实的控制台、终端、登录会话，
# 屏蔽这些单元可加速启动并避免日志噪音。
#
# 注意：不再屏蔽 systemd-hostnamed（dbus-org.freedesktop.hostname1），
# 否则 hostnamectl、D-Bus 主机名查询会失败，systemctl 也会提示 "hostname unset"。
# 主机名同步由 entrypoint.sh 负责写入 /etc/hostname。
# ============================================================

#!/bin/bash
set -e

mask() {
    # 将目标 unit 链接到 /dev/null，实现彻底屏蔽
    local unit="$1"
    if [ -e "/lib/systemd/system/${unit}" ] || [ -e "/etc/systemd/system/${unit}" ]; then
        ln -sf /dev/null "/etc/systemd/system/${unit}"
        echo "  已屏蔽 ${unit}"
    else
        echo "  跳过   ${unit}（不存在）"
    fi
}

echo "[mask-units] 开始屏蔽容器内不适用的 systemd 单元"

# 控制台 / 终端相关
mask console-getty.service
mask console-getty.socket
mask console-setup.service
mask serial-getty@.service
mask serial-getty.socket
mask getty@.service
mask getty.target

# 用户登录会话
mask systemd-logind.service
mask systemd-logind.socket
mask systemd-userdbd.service
mask systemd-userdbd.socket

# 一次性启动辅助
mask systemd-machine-id-setup.service
mask systemd-firstboot.service

# D-Bus 服务（容器内无桌面 / 用户会话）
# 注意：保留 dbus-org.freedesktop.hostname1 不屏蔽，否则 hostnamectl 会失败
mask dbus-org.freedesktop.login1.service
mask dbus-org.freedesktop.timedate1.service
mask dbus-org.freedesktop.locale1.service

# 时间同步
rm -f /etc/systemd/system/dbus-org.freedesktop.timesync1.service
ln -sf /dev/null /etc/systemd/system/dbus-org.freedesktop.timesync1.service 2>/dev/null || true

# 网络等待：容器中 networkd 通常无配置，wait-online 会一直阻塞 multi-user.target
mask systemd-networkd.service
mask systemd-networkd-wait-online.service
# 让 network-online.target 直接满足，避免 unit 卡在启动
mkdir -p /etc/systemd/system/network-online.target.wants
cat > /etc/systemd/system/network-online.target <<'UNIT'
[Unit]
Description=Network is Online (container stub)
Documentation=man:systemd.special(7)
UNIT
rm -rf /etc/systemd/system/network-online.target.wants/*

# 初始化 machine-id：容器启动时 systemd 会自动生成
rm -f /etc/machine-id
echo "uninitialized" > /etc/machine-id