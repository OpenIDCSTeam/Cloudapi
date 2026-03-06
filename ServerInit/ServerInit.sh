chmod +x ./ServerInit
chmod +x ./ServerInit.service
mkdir                -p /opt/ServerInit/
cp ./ServerInit         /opt/ServerInit/
cp ./ServerInit.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now ServerInit

# 检测操作系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
else
    OS_ID=$(uname -s)
fi

echo "[网络配置] 检测到操作系统: $OS_ID"

# 根据操作系统类型配置网络
case "$OS_ID" in
    ubuntu|debian|arch|opensuse*)
        echo "[网络配置] 使用 systemd-networkd 配置网络"
        systemctl enable --now systemd-networkd

        mkdir -p /etc/systemd/network
        cat > /etc/systemd/network/99-dhcp-any.network << 'EOF'
[Match]
Name=*

[Network]
DHCP=yes
EOF

        echo "[网络配置] 网络配置文件已创建: /etc/systemd/network/99-dhcp-any.network"
        systemctl restart systemd-networkd
        echo "[网络配置] systemd-networkd 已重启"
        ;;
    
    centos|rhel|fedora|almalinux|rocky|ol)
        echo "[网络配置] 使用 NetworkManager 配置网络"
        
        # 确保 NetworkManager 已启用
        systemctl enable --now NetworkManager
        
        # 使用 nmcli 配置 DHCP
        # 获取活动的网络接口
        for interface in $(nmcli -t -f DEVICE device status | grep -v "^lo"); do
            echo "[网络配置] 配置接口 $interface 为 DHCP"
            nmcli con modify "$interface" ipv4.method auto 2>/dev/null || \
            nmcli device connect "$interface" 2>/dev/null
        done
        
        # 重启 NetworkManager 应用配置
        systemctl restart NetworkManager
        echo "[网络配置] NetworkManager 已重启"
        ;;
    
    *)
        echo "[网络配置] 未知操作系统 $OS_ID，跳过网络配置"
        echo "[网络配置] 请手动配置网络"
        ;;
esac

# 1. 清用户级 bash 历史（当前会话也清）
history -c && history -w

# 2. 清系统级历史记录（/root 和所有普通用户）
find /home /root -maxdepth 1 -type f -name '.bash_history' -exec truncate -s 0 {} \;

# 3. 清 /tmp、/var/tmp（跳过正在使用的文件）
find /tmp /var/tmp -type f -delete 2>/dev/null
find /tmp /var/tmp -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} + 2>/dev/null

# 4. 清 apt 缓存（Debian/Ubuntu 系列）
command -v apt >/dev/null && apt clean

# 5. 清 yum/dnf 缓存（RHEL/CentOS/Fedora/Alma/Rocky）
command -v yum  >/dev/null && yum clean all
command -v dnf  >/dev/null && dnf clean all

# 6. 清 zypper 缓存（openSUSE）
command -v zypper >/dev/null && zypper clean --all

# 7. 清 pacman 缓存（Arch）
command -v pacman >/dev/null && pacman -Scc --noconfirm

# 8. 清 snap 旧版本（Ubuntu 等）
command -v snap >/dev/null && snap list --all | awk '/disabled/{print $1,$2}' | while read snapname revision; do snap remove "$snapname" --revision="$revision"; done 2>/dev/null

# 9. 清 journal 日志（保留最近 24 小时）
journalctl --vacuum-time=1d

# 10. 清回收站（所有用户）
find /home /root -type d -name '.local' -exec find {}/Share/Trash -mindepth 1 -delete \; 2>/dev/null
