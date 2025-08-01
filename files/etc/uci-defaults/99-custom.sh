#!/bin/sh
# 99-custom.sh - ImmortalWrt 固件首次启动脚本 (/etc/uci-defaults/99-custom.sh)
# 这是一个根据您的特定需求定制的完整脚本。

# 用于调试的日志文件
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting custom configuration at $(date)" > $LOGFILE

# 设置默认防火墙规则，方便首次访问 WebUI
uci set firewall.@zone[1].input='ACCEPT'
echo "Firewall WAN input set to ACCEPT for initial setup." >> $LOGFILE

# 添加主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"
echo "Added Android time server DNS entry." >> $LOGFILE

# 检查 pppoe-settings 文件是否存在，但暂时不使用它来强制设置协议
# 这允许您之后在 WebUI 中手动配置 PPPoE
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Skipping." >> $LOGFILE
else
    # 引入该文件以备其他脚本可能需要其中的变量
    . "$SETTINGS_FILE"
    echo "PPPoE settings file found and sourced." >> $LOGFILE
fi

# ==================== 定制化网络配置开始 ====================
# 此代码块使用您的固定配置替换了原始的动态检测逻辑。
# LAN 口固定为 eth0，WAN 口固定为 eth1。
# WAN 口默认设置为 DHCP，允许您后续手动输入 PPPoE 详细信息。

echo "Applying hardcoded network configuration..." >> $LOGFILE

# 1. 配置 LAN 接口
uci set network.lan.proto='static'
uci set network.lan.ipaddr='192.168.8.1'      # 您期望的内网管理地址
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.device='eth0'            # 强制 LAN 口为 eth0
echo "LAN configured: static, 192.168.8.1, on eth0." >> $LOGFILE

# 2. 配置 WAN 接口 (默认使用 DHCP)
uci set network.wan=interface
uci set network.wan.device='eth1'            # 强制 WAN 口为 eth1
uci set network.wan.proto='dhcp'             # 设置为 DHCP 作为安全默认值
echo "WAN configured: DHCP on eth1. Please configure PPPoE manually in LuCI." >> $LOGFILE

# 3. 配置 WAN6 接口
uci set network.wan6=interface
uci set network.wan6.device='eth1'           # 将 WAN6 绑定到 eth1
uci set network.wan6.proto='dhcpv6'
echo "WAN6 configured: DHCPv6 on eth1." >> $LOGFILE

echo "Custom network configuration applied." >> $LOGFILE
# ==================== 定制化网络配置结束 ====================

# 如果安装了 Docker，则配置防火墙规则
if command -v dockerd >/dev/null 2>&1; then
    echo "Docker detected, configuring firewall rules..." >> $LOGFILE
    FW_FILE="/etc/config/firewall"

    # 清理旧的 Docker 规则以防重复
    uci -q delete firewall.docker
    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            uci delete firewall.@forwarding[$idx]
        fi
    done
    uci commit firewall

    # 添加新的 Docker 区域和转发规则
    cat <<EOF >>"$FW_FILE"

config zone 'docker'
	option name 'docker'
	option input 'ACCEPT'
	option output 'ACCEPT'
	option forward 'ACCEPT'
	list subnet '172.16.0.0/12'

config forwarding
	option src 'docker'
	option dest 'lan'

config forwarding
	option src 'docker'
	option dest 'wan'

config forwarding
	option src 'lan'
	option dest 'docker'
EOF
    echo "Docker firewall rules configured." >> $LOGFILE
else
    echo "Docker not detected, skipping firewall configuration." >> $LOGFILE
fi

# 允许从所有接口访问网页终端
uci -q delete ttyd.@ttyd[0].interface
echo "Web terminal (ttyd) access configured for all interfaces." >> $LOGFILE

# 允许从所有接口进行 SSH 连接
uci set dropbear.@dropbear[0].Interface=''
echo "SSH (dropbear) access configured for all interfaces." >> $LOGFILE

# 提交所有对网络及其他服务的更改
uci commit
echo "All uci changes committed." >> $LOGFILE

# 在版本文件中设置自定义作者信息
FILE_PATH="/etc/openwrt_release"
if [ -f "$FILE_PATH" ]; then
    NEW_DESCRIPTION="Compiled by chenwh"
    sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"
    echo "Author information updated." >> $LOGFILE
fi

echo "Custom configuration script finished at $(date)." >> $LOGFILE
exit 0
