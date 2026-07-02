#!/bin/bash

# ==========================================
# Realm 中转管理面板
# 特性：原生支持本地文件检测与私有仓库下载
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

REALM_BIN="/usr/local/bin/realm"
REALM_DIR="/etc/realm"
DB_FILE="${REALM_DIR}/realms.db"
TOML_FILE="${REALM_DIR}/config.toml"
SERVICE_FILE="/etc/systemd/system/realm.service"
SYSCTL_FILE="/etc/sysctl.d/99-realm-tune.conf"

if [ "$EUID" -ne 0 ]; then echo -e "${RED}错误：请使用 root 用户运行${NC}"; exit 1; fi

# ================= 核心逻辑修复：智能初始化环境 =================
init_env() {
    mkdir -p ${REALM_DIR}; touch ${DB_FILE}
    
    # 【关键修复】优先检查二进制程序是否存在且非空
    if [ -f "${REALM_BIN}" ] && [ -s "${REALM_BIN}" ]; then
        chmod +x ${REALM_BIN} > /dev/null 2>&1
        echo -e "${GREEN}检测到 Realm 核心程序已存在，跳过下载。${NC}"
        # 如果程序在，但服务没建，补建服务
        if [ ! -f "${SERVICE_FILE}" ]; then
            create_service
        fi
        return
    fi
    
    # 只有当程序不存在，且服务也不存在时，才触发下载
    if [ ! -f "${SERVICE_FILE}" ]; then
        echo -e "${YELLOW}检测到首次运行，正在初始化 Realm 环境...${NC}"
        download_realm
        create_service
    fi
}

# ================= 核心逻辑修复：指向私有仓库下载 =================
download_realm() {
    echo -e "${BLUE}正在从私有仓库下载 Realm...${NC}"
    # 直接从你自己的 GitHub 仓库拉取纯二进制文件，彻底告别官方源 502
    wget -O ${REALM_BIN} https://raw.githubusercontent.com/wuy62380-ship-it/realmctl.sh/main/realm > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        # 失败时尝试 curl 备用方案
        curl -Lo ${REALM_BIN} https://raw.githubusercontent.com/wuy62380-ship-it/realmctl.sh/main/realm > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}Realm 下载失败！请检查服务器是否能连通 GitHub。${NC}"
            exit 1
        fi
    fi
    chmod +x ${REALM_BIN}
    echo -e "${GREEN}✅ Realm 核心程序安装完成！${NC}"
}

create_service() {
    cat > ${SERVICE_FILE} << EOF
[Unit]
Description=Realm Relay Service
After=network.target

[Service]
Type=simple
ExecStart=${REALM_BIN} -c ${TOML_FILE}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
OOMScoreAdjust=-1000

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable realm > /dev/null 2>&1
    echo -e "${GREEN}✅ Systemd 服务与 OOM 护盾已激活！${NC}"
}

manage_firewall() {
    local port=$1; local action=$2
    if command -v ufw &> /dev/null; then
        [ "$action" == "open" ] && ufw allow ${port}/tcp > /dev/null 2>&1 || ufw delete allow ${port}/tcp > /dev/null 2>&1
    elif command -v firewall-cmd &> /dev/null; then
        [ "$action" == "open" ] && firewall-cmd --permanent --add-port=${port}/tcp > /dev/null 2>&1 || firewall-cmd --permanent --remove-port=${port}/tcp > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
    fi
}

generate_toml() {
    echo -e "[log]\nlevel = \"warn\"\n" > ${TOML_FILE}
    [ ! -s "${DB_FILE}" ] && return
    while IFS='|' read -r local_port remote_addr category remark; do
        [[ -z "$local_port" || "$local_port" == \#* ]] && continue
        echo -e "[[endpoints]]\nlisten = \"0.0.0.0:${local_port}\"\nremote = \"${remote_addr}\"\n" >> ${TOML_FILE}
    done < "${DB_FILE}"
}

reload_realm() {
    generate_toml; systemctl restart realm
    [ $? -eq 0 ] && echo -e "${GREEN}✅ 操作成功！Realm 已重载生效。${NC}" || echo -e "${RED}❌ Realm 重启失败，请检查日志！${NC}"
}

# ================= 1. 深度净化系统 =================
clean_system_junk() {
    echo -e "${BLUE}================ 深度净化系统冗余组件 ================${NC}"
    echo -e "${YELLOW}正在安全释放被流氓程序占用的物理内存...${NC}"
    local cleaned=0
    if systemctl is-active --quiet apt-daily.timer 2>/dev/null; then
        systemctl disable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null
        echo -e "${GREEN}✅ 已禁用 APT 自动更新 (防 CPU/内存突刺)${NC}"; cleaned=1
    fi
    if dpkg -l | grep -q landscape-client; then
        apt-get remove -y landscape-client landscape-common > /dev/null 2>&1
        echo -e "${GREEN}✅ 已卸载 Landscape 监控 (释放大量内存)${NC}"; cleaned=1
    fi
    if systemctl is-active --quiet aegis-agent 2>/dev/null; then
        systemctl stop aegis-agent && systemctl disable aegis-agent 2>/dev/null
        echo -e "${GREEN}✅ 已休眠阿里云安骑士${NC}"; cleaned=1
    fi
    if systemctl is-active --quiet tat_agent 2>/dev/null; then
        systemctl stop tat_agent && systemctl disable tat_agent 2>/dev/null
        echo -e "${GREEN}✅ 已休眠腾讯云自动化助手${NC}"; cleaned=1
    fi
    if [ ! -f "/etc/systemd/journald.conf.d/override.conf" ]; then
        mkdir -p /etc/systemd/journald.conf.d
        cat > /etc/systemd/journald.conf.d/override.conf << EOF
[Journal]
SystemMaxUse=50M
SystemMaxFileSize=10M
MaxRetentionSec=3days
EOF
        systemctl restart systemd-journald 2>/dev/null
        echo -e "${GREEN}✅ 已限制系统日志上限为 50MB${NC}"; cleaned=1
    fi
    apt-get clean > /dev/null 2>&1
    [ $cleaned -eq 0 ] && echo -e "${YELLOW}系统非常纯净，无需清理。${NC}" || echo -e "${GREEN}🧹 净化完成！物理内存已归还系统。${NC}"
}

# ================= 2. 安装 XanMod 内核 =================
check_disk_space() { 
    local req=$1; 
    local avail=$(df / | awk 'NR==2{print $4}'); 
    [ "$avail" -lt "$((req*1024*1024))" ] && { echo -e "${RED}磁盘空间不足，至少需要 ${req}GB${NC}"; return 1; }; 
    return 0
}

check_swap() { 
    if [ "$(swapon -s | wc -l)" -le 1 ]; then
        echo -e "${YELLOW}未检测到 Swap，创建 1G 临时 Swap 防止安装 OOM...${NC}"; 
        fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile > /dev/null 2>&1 && swapon /swapfile
    fi
    return 0
}

bbr_on() { 
    sed -i '/net.core.default_qdisc/d; /net.ipv4.tcp_congestion_control/d' ${SYSCTL_FILE} 2>/dev/null
    mkdir -p /etc/sysctl.d
    echo -e "net.core.default_qdisc = fq_pie\nnet.ipv4.tcp_congestion_control = bbr" >> ${SYSCTL_FILE}
    sysctl --system > /dev/null 2>&1
}

server_reboot() { 
    echo -e "${GREEN}内核替换成功！按回车键重启服务器...${NC}"; 
    read; 
    reboot
}

xanmod_add_repo() {
    local keyring="/usr/share/keyrings/xanmod-archive-keyring.gpg"
    local list_file="/etc/apt/sources.list.d/xanmod-release.list"
    local os_codename=""
    
    if command -v lsb_release >/dev/null 2>&1; then 
        os_codename=$(lsb_release -sc)
    elif [ -r /etc/os-release ]; then 
        os_codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
    fi
    
    if ! echo "bookworm trixie forky sid noble plucky" | grep -qw "$os_codename"; then 
        os_codename="releases"
    fi
    
    if echo "jammy focal bullseye buster releases" | grep -qw "$os_codename"; then 
        echo -e "${RED}XanMod 已停止对当前系统($os_codename)支持${NC}"; 
        return 1
    fi
    
    [ -z "$os_codename" ] && { echo "无法获取系统代号"; return 1; }
    
    apt-get install -y wget gnupg ca-certificates || return 1
    mkdir -p /usr/share/keyrings /etc/apt/sources.list.d
    
    wget -qO - "https://dl.xanmod.org/archive.key" | gpg --dearmor -o "$keyring" --yes 2>/dev/null
    chmod 644 "$keyring"
    echo "deb [signed-by=$keyring] http://deb.xanmod.org $os_codename main" > "$list_file"
}

xanmod_detect_package() {
    local psabi_level=$(awk 'BEGIN{ while(!/flags/) if(getline<"/proc/cpuinfo"!=1) exit 1; if(/lm/&&/cmov/&&/cx8/&&/fpu/&&/fxsr/&&/mmx/&&/syscall/&&/sse2/) level=1; if(level==1&&/cx16/&&/lahf/&&/popcnt/&&/sse4_1/&&/sse4_2/&&/ssse3/) level=2; if(level==2&&/avx/&&/avx2/&&/bmi1/&&/bmi2/&&/f16c/&&/fma/&&/abm/&&/movbe/&&/xsave/) level=3; if(level>0){print level;exit}}' /proc/cpuinfo 2>/dev/null) || return 1
    [ "$psabi_level" -gt 3 ] && psabi_level=3
    apt-get update -y >/dev/null 2>&1
    for prefix in linux-xanmod linux-xanmod-lts; do 
        local l="$psabi_level"; 
        while [ "$l" -ge 1 ]; do 
            local p="${prefix}-x64v${l}"; 
            if apt-cache policy "$p" 2>/dev/null | grep -q 'Candidate: [^ ]'; then 
                printf '%s\n' "$p"; 
                return 0
            fi
            l=$((l-1))
        done
    done
    return 1
}

install_bbrv3() {
    echo -e "${BLUE}================ 安装 XanMod BBRv3 内核 ================${NC}"
    echo -e "${RED}⚠️  警告：此操作将替换系统内核！仅限 Debian/Ubuntu x86_64。${NC}"
    read -p "确定继续？(输入 y): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return
    
    if [ "$(uname -m)" = "aarch64" ]; then 
        echo -e "${RED}ARM架构请使用专用脚本${NC}"; 
        return
    fi
    
    if [ -r /etc/os-release ]; then 
        . /etc/os-release
        if [ "$ID" != "debian" ] && [ "$ID" != "ubuntu" ]; then 
            echo -e "${RED}仅支持 Debian/Ubuntu${NC}"; 
            return
        fi
    else 
        return
    fi
    
    # 【修复】检查是否已安装 XanMod 内核
    local installed_kernel=$(dpkg-query -W -f='${Package}\n' 'linux-*xanmod*' 2>/dev/null | grep '^linux-.*xanmod' | head -1)
    
    if [ -n "$installed_kernel" ]; then
        echo -e "${YELLOW}检测到已安装 XanMod 内核: ${GREEN}${installed_kernel}${NC}"
        echo ""
        while true; do 
            clear
            echo -e "${CYAN}当前运行内核: $(uname -r)${NC}"
            echo -e "${GREEN}已安装内核: ${installed_kernel}${NC}"
            echo ""
            echo "1. 更新内核到最新版本"
            echo "2. 卸载内核还原系统"
            echo "0. 返回主菜单"
            read -e -p "请选择: " c
            case $c in 
                1) 
                    check_disk_space 3 && check_swap && xanmod_add_repo && apt-get update -y && \
                    apt-get install -y --only-upgrade $(xanmod_detect_package) && bbr_on && server_reboot
                    ;; 
                2) 
                    apt-get purge -y 'linux-*xanmod*' && apt-get autoremove -y && update-grub && \
                    rm -f /etc/apt/sources.list.d/xanmod-release.list && server_reboot
                    ;; 
                *) break ;; 
            esac
        done
    else
        # 首次安装
        check_disk_space 3 && check_swap && xanmod_add_repo && apt-get update -y
        local pkg_name=$(xanmod_detect_package)
        if [ -z "$pkg_name" ]; then
            echo -e "${RED}无法检测到适合的 XanMod 内核包！${NC}"
            return
        fi
        echo -e "${YELLOW}即将安装: ${GREEN}${pkg_name}${NC}"
        apt-get install -y ${pkg_name} && bbr_on && server_reboot
    fi
}

# ================= 3. 应用 BBRv3 极限调优 (智能自适应版) =================
# 【核心修复】智能检测内核状态，区分"已安装未重启"和"未安装"
tune_bbrv3() {
    echo -e "${BLUE}================ 应用 BBRv3 极限调优参数 ================${NC}"
    
    local current_kernel=$(uname -r)
    local is_running_xanmod="no"
    
    # 检测当前运行的内核是否为 XanMod
    if echo "$current_kernel" | grep -qi "xanmod"; then
        is_running_xanmod="yes"
    fi
    
    # 【新增】检测是否安装了 XanMod 内核包（但可能未重启）
    local installed_xanmod_pkgs=$(dpkg-query -W -f='${Package} ${Version}\n' 'linux-*xanmod*' 2>/dev/null | grep '^linux-.*xanmod')
    local has_xanmod_installed="no"
    [ -n "$installed_xanmod_pkgs" ] && has_xanmod_installed="yes"
    
    # 情况判断
    if [ "$is_running_xanmod" = "no" ]; then
        if [ "$has_xanmod_installed" = "yes" ]; then
            # ========== 情况1：已安装但未重启 ==========
            echo -e "${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
            echo -e "${YELLOW}║  ⚠️  XanMod 内核已安装，但当前系统尚未使用它！        ║${NC}"
            echo -e "${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
            echo ""
            echo -e "${RED}当前运行内核: ${current_kernel}${NC}"
            echo ""
            echo -e "${GREEN}已安装的 XanMod 内核:${NC}"
            echo "$installed_xanmod_pkgs" | while read pkg ver; do
                echo -e "  📦 ${GREEN}${pkg}${NC} ${CYAN}${ver}${NC}"
            done
            echo ""
            echo -e "${YELLOW}💡 解决方法：重启服务器以加载新内核${NC}"
            echo ""
            read -p "是否现在重启？(y/n): " reboot_now
            if [[ "$reboot_now" =~ ^[Yy]$ ]]; then
                echo -e "${GREEN}正在重启...${NC}"
                reboot
            fi
            return 1
        else
            # ========== 情况2：根本没安装 ==========
            echo -e "${RED}╔══════════════════════════════════════════════════════════╗${NC}"
            echo -e "${RED}║  ❌ 错误：系统未安装 BBRv3 内核！                      ║${NC}"
            echo -e "${RED}╚══════════════════════════════════════════════════════════╝${NC}"
            echo ""
            echo -e "${RED}当前内核: ${current_kernel}${NC}"
            echo ""
            echo -e "${YELLOW}👉 请先返回主菜单，执行 ${CYAN}[2. 安装/管理BBRv3 内核]${YELLOW}，安装完成后重启服务器。${NC}"
            echo ""
            return 1
        fi
    fi
    
    # ========== 以下为正常运行 XanMod 内核的逻辑 ==========
    echo -e "${GREEN}✅ 检测到 XanMod 内核: ${current_kernel}${NC}"
    
    local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_mb=$((total_mem_kb / 1024))
    local total_pages=$((total_mem_kb / 4))
    local tcp_mem_low=$((total_pages * 5 / 100))
    local tcp_mem_med=$((total_pages * 15 / 100))
    local tcp_mem_high=$((total_pages * 30 / 100))
    [ $tcp_mem_low -lt 8192 ] && tcp_mem_low=8192
    [ $tcp_mem_med -lt 16384 ] && tcp_mem_med=16384
    [ $tcp_mem_high -lt 32768 ] && tcp_mem_high=32768
    
    echo -e "${YELLOW}检测到系统物理内存: ${CYAN}${total_mem_mb} MB${NC}"
    echo -e "${YELLOW}正在写入动态计算的内核参数...${NC}"
    
    mkdir -p /etc/sysctl.d
    cat > ${SYSCTL_FILE} << EOF
# --- Realm XanMod BBRv3 智能自适应调优 ---
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 系统内存: ${total_mem_mb}MB

# === BBRv3 拥塞控制 ===
net.core.default_qdisc = fq_pie
net.ipv4.tcp_congestion_control = bbr

# === 缓冲区设置 (32MB 上限) ===
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 1048576 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432

# === 连接队列 ===
net.core.netdev_max_backlog = 100000
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# === TCP 优化 ===
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_max_tw_buckets = 500000

# === TCP 内存池 (根据 ${total_mem_mb}MB 动态计算) ===
net.ipv4.tcp_mem = ${tcp_mem_low} ${tcp_mem_med} ${tcp_mem_high}

# === Keepalive ===
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# === 端口范围 ===
net.ipv4.ip_local_port_range = 1024 65535
EOF

    sysctl --system > /dev/null 2>&1
    
    # 验证是否生效
    local verify_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    local verify_cong=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ BBRv3 极限调优已成功应用！                          ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║  队列算法: ${CYAN}${verify_qdisc}${GREEN}                                  ║${NC}"
    echo -e "${GREEN}║  拥塞控制: ${CYAN}${verify_cong}${GREEN}                                        ║${NC}"
    echo -e "${GREEN}║  缓冲区:   ${CYAN}32MB${GREEN}                                         ║${NC}"
    echo -e "${GREEN}║  内存池:   ${CYAN}已根据 ${total_mem_mb}MB 动态优化${GREEN}                       ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
}

# ================= 4. 添加落地机 =================
add_realm() {
    echo -e "${BLUE}================ 添加中转规则 ================${NC}"
    read -p "中转机监听端口 (如 20000): " local_port
    if ! [[ "$local_port" =~ ^[0-9]+$ ]] || [ "$local_port" -lt 1 ] || [ "$local_port" -gt 65535 ]; then 
        echo -e "${RED}端口无效${NC}"; 
        return
    fi
    if ss -tulnp | grep -q ":${local_port} "; then 
        echo -e "${RED}端口已被占用${NC}"; 
        return
    fi
    if grep -q "^${local_port}|" "${DB_FILE}"; then 
        echo -e "${RED}该端口规则已存在${NC}"; 
        return
    fi
    
    echo -e "${YELLOW}提示：请输入落地机的纯 IPv4 地址，不要带协议头或域名。${NC}"
    read -p "落地机地址和端口 (如 1.2.3.4:443): " remote_addr
    if ! echo "$remote_addr" | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$"; then 
        echo -e "${RED}格式错误！必须是 IP:端口 格式。${NC}"; 
        return
    fi
    
    echo -e "${YELLOW}选择节点用途： 1.🎬直播  2.🎮游戏  3.🌐通用 (默认3)${NC}"
    read -p "请输入选项: " cat_num
    case $cat_num in 1) category="直播";; 2) category="游戏";; *) category="通用";; esac
    
    read -p "输入备注名称 (如 洛杉矶-01，可留空): " remark
    echo "${local_port}|${remote_addr}|${category}|${remark}" >> ${DB_FILE}
    manage_firewall "$local_port" "open"
    reload_realm
}

# ================= 5. 查看节点 =================
list_realms() {
    echo -e "${BLUE}================ 当前中转规则列表 ================${NC}"
    if [ ! -s "${DB_FILE}" ]; then 
        echo -e "${YELLOW}暂无任何规则。${NC}"; 
        return
    fi
    printf "${GREEN}%-10s %-12s %-25s %-20s${NC}\n" "监听端口" "用途分类" "落地机地址" "备注"
    printf "%-10s %-12s %-25s %-20s\n" "----------" "------------" "-------------------------" "--------------------"
    while IFS='|' read -r local_port remote_addr category remark; do
        [[ -z "$local_port" || "$local_port" == \#* ]] && continue
        [ -z "$category" ] && category="通用"; [ -z "$remark" ] && remark="-"
        icon="🌐"; [ "$category" == "直播" ] && icon="🎬"; [ "$category" == "游戏" ] && icon="🎮"
        printf "%-10s ${YELLOW}%-12s${NC} %-25s %-20s\n" "$local_port" "$icon $category" "$remote_addr" "$remark"
    done < "${DB_FILE}"
    echo "------------------------------------------------------"
}

# ================= 6. 删除节点 =================
del_realm() {
    list_realms
    [ ! -s "${DB_FILE}" ] && return
    read -p "输入要删除的规则对应的【监听端口】: " del_port
    if ! grep -q "^${del_port}|" "${DB_FILE}"; then 
        echo -e "${RED}未找到该端口的规则${NC}"; 
        return
    fi
    grep -v "^${del_port}|" "${DB_FILE}" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "${DB_FILE}"
    manage_firewall "$del_port" "close"
    reload_realm
}

# ================= 主菜单 =================
menu() {
    init_env
    while true; do
        echo ""
        echo -e "${GREEN} Realm 中转机管理面板 (私有仓库定制版)${NC}"
        echo "--------------------------------------------------"
        echo -e "${BLUE} 1. 深度净化系统 (清理流氓程序释放内存)${NC}"
        echo -e "${RED} 2. 安装/管理BBRv3 内核${NC}"
        echo -e "${YELLOW} 3. 应用 BBRv3 极限调优 (自动识别内存)${NC}"
        echo "--------------------------------------------------"
        echo " 4. 添加落地机中转规则"
        echo " 5. 查看所有中转规则"
        echo " 6. 删除中转规则"
        echo "--------------------------------------------------"
        echo " 0. 退出脚本"
        echo "--------------------------------------------------"
        read -p "请输入选项: " choice
        case $choice in
            1) clean_system_junk ;;
            2) install_bbrv3 ;;
            3) tune_bbrv3 ;;
            4) add_realm ;;
            5) list_realms ;;
            6) del_realm ;;
            0) echo -e "${GREEN}再见！${NC}"; exit 0 ;;
            *) echo -e "${RED}无效选项，请重新输入。${NC}" ;;
        esac
    done
}
menu
