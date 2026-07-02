#!/bin/bash

# ==========================================
# Realm 中转管理面板 v2.0 (美化版)
# ==========================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# 路径定义
REALM_BIN="/usr/local/bin/realm"
REALM_DIR="/etc/realm"
DB_FILE="${REALM_DIR}/realms.db"
TOML_FILE="${REALM_DIR}/config.toml"
SERVICE_FILE="/etc/systemd/system/realm.service"
SYSCTL_FILE="/etc/sysctl.d/99-realm-tune.conf"

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}\n  ✘ 请使用 root 用户运行此脚本\n${NC}"; 
    exit 1
fi

# ================= 界面组件 =================
show_header() {
    clear
    echo -e "${CYAN}"
    cat << 'HEADER'
    ╔═══════════════════════════════════════════════════════╗
    ║                                                       ║
    ║          █████╗ ███████╗███████╗██████╗  ██████╗      ║
    ║         ██╔══██╗╚══███╔╝██╔════╝██╔══██╗██╔═══██╗     ║
    ║         ███████║  ███╔╝ █████╗  ██████╔╝██║   ██║     ║
    ║         ██╔══██║ ███╔╝  ██╔══╝  ██╔══██╗██║   ██║     ║
    ║         ██║  ██║███████╗███████╗██║  ██║╚██████╔╝     ║
    ║         ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝ ╚═════╝      ║
    ║                                                       ║
    ║              中转机管理面板 v2.0                       ║
    ║                                                       ║
    ╚═══════════════════════════════════════════════════════╝
HEADER
    echo -e "${NC}"
}

show_system_info() {
    local kernel=$(uname -r)
    local uptime=$(uptime -p 2>/dev/null | sed 's/up //')
    [ -z "$uptime" ] && uptime=$(uptime | sed 's/.*up //' | sed 's/,.*//')
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    local mem_used=$(free -m | awk '/^Mem:/{print $3}')
    local mem_percent=$((mem_used * 100 / mem_total))
    local realm_status="未运行"
    local realm_color="${RED}"
    if systemctl is-active --quiet realm 2>/dev/null; then
        realm_status="运行中"
        realm_color="${GREEN}"
    fi
    
    local bbr_status="未启用"
    local bbr_color="${RED}"
    local current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [ "$current_cc" = "bbr" ]; then
        bbr_status="已启用"
        bbr_color="${GREEN}"
    fi
    
    local is_xanmod="否"
    local xanmod_color="${GRAY}"
    if echo "$kernel" | grep -qi "xanmod"; then
        is_xanmod="是"
        xanmod_color="${GREEN}"
    fi
    
    echo -e "  ${DIM}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${DIM}│${NC}  ${WHITE}系统信息${NC}                                                ${DIM}│${NC}"
    echo -e "  ${DIM}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "  ${DIM}│${NC}  内核版本  ${GRAY}│${NC} ${CYAN}${kernel}${NC} $(echo "$kernel" | grep -qi xanmod && echo "${GREEN}[XanMod]${NC}" || echo "")"
    echo -e "  ${DIM}│${NC}  运行时间  ${GRAY}│${NC} ${WHITE}${uptime}${NC}"
    echo -e "  ${DIM}│${NC}  内存使用  ${GRAY}│${NC} ${WHITE}${mem_used}/${mem_total}MB${NC} ${DIM}(${mem_percent}%)${NC}"
    echo -e "  ${DIM}│${NC}  Realm状态${GRAY}│${NC} ${realm_color}● ${realm_status}${NC}"
    echo -e "  ${DIM}│${NC}  BBR状态  ${GRAY}│${NC} ${bbr_color}● ${bbr_status}${NC}"
    echo -e "  ${DIM}│${NC}  XanMod   ${GRAY}│${NC} ${xanmod_color}${is_xanmod}${NC}"
    echo -e "  ${DIM}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

show_menu() {
    echo -e "  ${MAGENTA}━━━ 系统优化 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GRAY}  1${NC}  ${BLUE}🧹${NC}  ${WHITE}深度净化系统${NC}          ${DIM}清理流氓程序释放内存${NC}"
    echo -e "  ${GRAY}  2${NC}  ${BLUE}📦${NC}  ${WHITE}安装/管理 BBRv3 内核${NC}   ${DIM}替换为 XanMod 高性能内核${NC}"
    echo -e "  ${GRAY}  3${NC}  ${BLUE}⚡${NC}  ${WHITE}应用 BBRv3 极限调优${NC}     ${DIM}自动识别内存动态优化${NC}"
    echo ""
    echo -e "  ${MAGENTA}━━━ 中转规则 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GRAY}  4${NC}  ${GREEN}➕${NC}  ${WHITE}添加落地机中转规则${NC}"
    echo -e "  ${GRAY}  5${NC}  ${GREEN}📋${NC}  ${WHITE}查看所有中转规则${NC}"
    echo -e "  ${GRAY}  6${NC}  ${RED}➖${NC}  ${WHITE}删除中转规则${NC}"
    echo ""
    echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GRAY}  0${NC}  ${DIM}退出脚本${NC}"
    echo ""
}

show_prompt() {
    echo -e "  ${DIM}───────────────────────────────────────────────────────────${NC}"
    echo -en "  ${CYAN}▶ 请输入选项${NC} ${GRAY}»${NC} "
}

show_success() {
    echo -e "\n  ${GREEN}✓ $1${NC}\n"
}

show_error() {
    echo -e "\n  ${RED}✘ $1${NC}\n"
}

show_warning() {
    echo -e "\n  ${YELLOW}⚠ $1${NC}\n"
}

show_info() {
    echo -e "\n  ${CYAN}ℹ $1${NC}\n"
}

wait_continue() {
    echo -e "\n  ${DIM}按 Enter 键继续...${NC}"
    read -s
}

# ================= 核心逻辑 =================
init_env() {
    mkdir -p ${REALM_DIR} 2>/dev/null
    touch ${DB_FILE} 2>/dev/null
    
    if [ -f "${REALM_BIN}" ] && [ -s "${REALM_BIN}" ]; then
        chmod +x ${REALM_BIN} > /dev/null 2>&1
        if [ ! -f "${SERVICE_FILE}" ]; then
            create_service
        fi
        return
    fi
    
    if [ ! -f "${SERVICE_FILE}" ]; then
        echo -e "  ${YELLOW}首次运行，正在初始化 Realm 环境...${NC}"
        download_realm
        create_service
    fi
}

download_realm() {
    echo -e "  ${BLUE}正在从私有仓库下载 Realm...${NC}"
    wget -O ${REALM_BIN} https://raw.githubusercontent.com/wuy62380-ship-it/realmctl.sh/main/realm > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        curl -Lo ${REALM_BIN} https://raw.githubusercontent.com/wuy62380-ship-it/realmctl.sh/main/realm > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            show_error "Realm 下载失败！请检查网络连接"
            exit 1
        fi
    fi
    chmod +x ${REALM_BIN}
    show_success "Realm 核心程序安装完成"
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
    systemctl daemon-reload > /dev/null 2>&1
    systemctl enable realm > /dev/null 2>&1
}

manage_firewall() {
    local port=$1 action=$2
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
    generate_toml
    systemctl restart realm 2>/dev/null
    if [ $? -eq 0 ]; then
        show_success "Realm 已重载生效"
    else
        show_error "Realm 重启失败，请检查日志: journalctl -u realm"
    fi
}

# ================= 1. 深度净化系统 =================
clean_system_junk() {
    show_header
    echo -e "  ${BLUE}━━━ 深度净化系统 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${YELLOW}正在扫描并清理系统冗余组件...${NC}"
    echo ""
    
    local cleaned=0
    
    if systemctl is-active --quiet apt-daily.timer 2>/dev/null; then
        systemctl disable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null
        echo -e "  ${GREEN}✓${NC} ${WHITE}已禁用 APT 自动更新${NC}          ${DIM}防止 CPU/内存突刺${NC}"
        cleaned=1
    fi
    
    if dpkg -l | grep -q landscape-client 2>/dev/null; then
        apt-get remove -y landscape-client landscape-common > /dev/null 2>&1
        echo -e "  ${GREEN}✓${NC} ${WHITE}已卸载 Landscape 监控${NC}        ${DIM}释放大量内存${NC}"
        cleaned=1
    fi
    
    if systemctl is-active --quiet aegis-agent 2>/dev/null; then
        systemctl stop aegis-agent && systemctl disable aegis-agent 2>/dev/null
        echo -e "  ${GREEN}✓${NC} ${WHITE}已休眠阿里云安骑士${NC}"
        cleaned=1
    fi
    
    if systemctl is-active --quiet tat_agent 2>/dev/null; then
        systemctl stop tat_agent && systemctl disable tat_agent 2>/dev/null
        echo -e "  ${GREEN}✓${NC} ${WHITE}已休眠腾讯云自动化助手${NC}"
        cleaned=1
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
        echo -e "  ${GREEN}✓${NC} ${WHITE}已限制日志上限${NC}              ${DIM}50MB / 3天${NC}"
        cleaned=1
    fi
    
    apt-get clean > /dev/null 2>&1
    
    echo ""
    if [ $cleaned -eq 0 ]; then
        show_info "系统非常纯净，无需清理"
    else
        show_success "净化完成！物理内存已归还系统"
    fi
    
    wait_continue
}

# ================= 2. 安装 XanMod 内核 =================
check_disk_space() { 
    local req=$1 avail=$(df / | awk 'NR==2{print $4}')
    [ "$avail" -lt "$((req*1024*1024))" ] && { show_error "磁盘空间不足，至少需要 ${req}GB"; return 1; }
    return 0
}

check_swap() { 
    if [ "$(swapon -s | wc -l)" -le 1 ]; then
        echo -e "  ${YELLOW}创建 1G 临时 Swap 防止 OOM...${NC}"
        fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile > /dev/null 2>&1 && swapon /swapfile
    fi
    return 0
}

bbr_on() { 
    mkdir -p /etc/sysctl.d
    sed -i '/net.core.default_qdisc/d; /net.ipv4.tcp_congestion_control/d' ${SYSCTL_FILE} 2>/dev/null
    echo -e "net.core.default_qdisc = fq_pie\nnet.ipv4.tcp_congestion_control = bbr" >> ${SYSCTL_FILE}
    sysctl --system > /dev/null 2>&1
}

server_reboot() { 
    echo ""
    echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}  ✓ 内核替换成功！${NC}"
    echo -e "  ${YELLOW}  按 Enter 键重启服务器...${NC}"
    echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read
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
    
    # 【修复】Debian 13 (trixie/forky) 使用 releases 通用源
    if echo "trixie forky" | grep -qw "$os_codename"; then
        echo -e "  ${YELLOW}检测到 Debian 测试版 ($os_codename)，使用通用源...${NC}"
        os_codename="releases"
    fi
    
    if echo "jammy focal bullseye buster" | grep -qw "$os_codename"; then 
        show_error "XanMod 已停止对 $os_codename 的支持"
        return 1
    fi
    
    [ -z "$os_codename" ] && { show_error "无法获取系统代号"; return 1; }
    
    apt-get install -y wget gnupg ca-certificates > /dev/null 2>&1 || return 1
    mkdir -p /usr/share/keyrings /etc/apt/sources.list.d
    
    wget -qO - "https://dl.xanmod.org/archive.key" | gpg --dearmor -o "$keyring" --yes 2>/dev/null
    chmod 644 "$keyring"
    echo "deb [signed-by=$keyring] http://deb.xanmod.org $os_codename main" > "$list_file"
    
    echo -e "  ${GREEN}✓ XanMod 源配置完成${NC} ${DIM}($os_codename)${NC}"
}

xanmod_detect_package() {
    local psabi_level=$(awk 'BEGIN{ while(!/flags/) if(getline<"/proc/cpuinfo"!=1) exit 1; if(/lm/&&/cmov/&&/cx8/&&/fpu/&&/fxsr/&&/mmx/&&/syscall/&&/sse2/) level=1; if(level==1&&/cx16/&&/lahf/&&/popcnt/&&/sse4_1/&&/sse4_2/&&/ssse3/) level=2; if(level==2&&/avx/&&/avx2/&&/bmi1/&&/bmi2/&&/f16c/&&/fma/&&/abm/&&/movbe/&&/xsave/) level=3; if(level>0){print level;exit}}' /proc/cpuinfo 2>/dev/null) || return 1
    [ "$psabi_level" -gt 3 ] && psabi_level=3
    apt-get update -y >/dev/null 2>&1
    for prefix in linux-xanmod linux-xanmod-lts; do 
        local l="$psabi_level"
        while [ "$l" -ge 1 ]; do 
            local p="${prefix}-x64v${l}"
            if apt-cache policy "$p" 2>/dev/null | grep -q 'Candidate: [^ ]'; then 
                printf '%s\n' "$p"
                return 0
            fi
            l=$((l-1))
        done
    done
    return 1
}

install_bbrv3() {
    show_header
    echo -e "  ${RED}━━━ 安装 XanMod BBRv3 内核 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${RED}  ⚠ 此操作将替换系统内核！仅限 Debian/Ubuntu x86_64${NC}"
    echo ""
    echo -en "  ${YELLOW}确定继续？${NC} ${GRAY}[y/N]${NC} » "
    local confirm
    read confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return
    
    if [ "$(uname -m)" = "aarch64" ]; then 
        show_error "ARM 架构暂不支持，请使用专用脚本"
        wait_continue
        return
    fi
    
    if [ -r /etc/os-release ]; then 
        . /etc/os-release
        if [ "$ID" != "debian" ] && [ "$ID" != "ubuntu" ]; then 
            show_error "仅支持 Debian/Ubuntu"
            wait_continue
            return
        fi
    else 
        return
    fi
    
    local installed_kernel=$(dpkg-query -W -f='${Package}\n' 'linux-*xanmod*' 2>/dev/null | grep '^linux-.*xanmod' | head -1)
    
    if [ -n "$installed_kernel" ]; then
        echo -e "  ${GREEN}✓ 检测到已安装: ${installed_kernel}${NC}"
        echo ""
        while true; do 
            show_header
            echo -e "  ${CYAN}━━━ XanMod 内核管理 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo -e "  ${WHITE}当前运行内核${NC}  ${GRAY}│${NC}  ${CYAN}$(uname -r)${NC}"
            echo -e "  ${WHITE}已安装内核${NC}    ${GRAY}│${NC}  ${GREEN}${installed_kernel}${NC}"
            echo ""
            echo -e "  ${GRAY}  1${NC}  ${WHITE}更新内核到最新版本${NC}"
            echo -e "  ${GRAY}  2${NC}  ${RED}卸载内核还原系统${NC}"
            echo -e "  ${GRAY}  0${NC}  ${DIM}返回主菜单${NC}"
            echo ""
            echo -en "  ${CYAN}▶ 请选择${NC} ${GRAY}»${NC} "
            local c; read c
            case $c in 
                1) 
                    check_disk_space 3 && check_swap && xanmod_add_repo && apt-get update -y
                    local pkg=$(xanmod_detect_package)
                    [ -n "$pkg" ] && apt-get install -y --only-upgrade "$pkg" && bbr_on && server_reboot
                    ;; 
                2) 
                    echo -en "  ${RED}确定卸载 XanMod 内核？${NC} ${GRAY}[y/N]${NC} » "
                    local sure; read sure
                    [[ "$sure" =~ ^[Yy]$ ]] && apt-get purge -y 'linux-*xanmod*' && apt-get autoremove -y && update-grub && rm -f /etc/apt/sources.list.d/xanmod-release.list && server_reboot
                    ;; 
                *) break ;; 
            esac
        done
    else
        check_disk_space 3 && check_swap && xanmod_add_repo
        echo ""
        echo -e "  ${YELLOW}正在检测适合的内核包...${NC}"
        local pkg_name=$(xanmod_detect_package)
        if [ -z "$pkg_name" ]; then
            echo ""
            show_error "无法找到适合的 XanMod 内核包！"
            echo -e "  ${DIM}可能原因：系统版本过新/过旧，或仓库连接失败${NC}"
            echo -e "  ${DIM}尝试手动运行: apt-cache search xanmod${NC}"
            wait_continue
            return
        fi
        echo -e "  ${GREEN}✓ 检测到: ${pkg_name}${NC}"
        echo ""
        echo -e "  ${YELLOW}开始安装...${NC}"
        apt-get install -y ${pkg_name} && bbr_on && server_reboot
    fi
}

# ================= 3. 应用 BBRv3 极限调优 =================
tune_bbrv3() {
    show_header
    echo -e "  ${YELLOW}━━━ 应用 BBRv3 极限调优 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local current_kernel=$(uname -r)
    local is_running_xanmod="no"
    echo "$current_kernel" | grep -qi "xanmod" && is_running_xanmod="yes"
    
    local installed_xanmod=$(dpkg-query -W -f='${Package} ${Version}\n' 'linux-*xanmod*' 2>/dev/null | grep '^linux-.*xanmod')
    local has_xanmod_installed="no"
    [ -n "$installed_xanmod" ] && has_xanmod_installed="yes"
    
    if [ "$is_running_xanmod" = "no" ]; then
        if [ "$has_xanmod_installed" = "yes" ]; then
            echo -e "  ${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
            echo -e "  ${YELLOW}║  ⚠  XanMod 内核已安装，但当前系统尚未使用它            ║${NC}"
            echo -e "  ${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
            echo ""
            echo -e "  ${RED}当前运行${NC}  ${GRAY}│${NC}  ${current_kernel}"
            echo -e "  ${GREEN}已安装${NC}    ${GRAY}│${NC}"
            echo "$installed_xanmod" | while read pkg ver; do
                echo -e "             ${GRAY}│${NC}  ${GREEN}📦 ${pkg} ${DIM}${ver}${NC}"
            done
            echo ""
            echo -e "  ${CYAN}💡 解决方法：重启服务器以加载新内核${NC}"
            echo ""
            echo -en "  ${YELLOW}是否现在重启？${NC} ${GRAY}[y/N]${NC} » "
            local reboot_now; read reboot_now
            [[ "$reboot_now" =~ ^[Yy]$ ]] && reboot
            wait_continue
            return 1
        else
            echo -e "  ${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
            echo -e "  ${RED}║  ✘ 系统未安装 BBRv3 内核！                            ║${NC}"
            echo -e "  ${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
            echo ""
            echo -e "  ${RED}当前内核${NC}  ${GRAY}│${NC}  ${current_kernel}"
            echo ""
            echo -e "  ${CYAN}👉 请先执行${NC} ${WHITE}[2. 安装/管理BBRv3 内核]${NC}"
            echo -e "  ${CYAN}   安装完成后需要重启服务器${NC}"
            echo ""
            wait_continue
            return 1
        fi
    fi
    
    echo -e "  ${GREEN}✓ 检测到 XanMod 内核: ${current_kernel}${NC}"
    echo ""
    
    local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_mb=$((total_mem_kb / 1024))
    local total_pages=$((total_mem_kb / 4))
    local tcp_mem_low=$((total_pages * 5 / 100))
    local tcp_mem_med=$((total_pages * 15 / 100))
    local tcp_mem_high=$((total_pages * 30 / 100))
    [ $tcp_mem_low -lt 8192 ] && tcp_mem_low=8192
    [ $tcp_mem_med -lt 16384 ] && tcp_mem_med=16384
    [ $tcp_mem_high -lt 32768 ] && tcp_mem_high=32768
    
    echo -e "  ${WHITE}系统内存${NC}  ${GRAY}│${NC}  ${CYAN}${total_mem_mb} MB${NC}"
    echo -e "  ${WHITE}TCP 内存池${NC}${GRAY}│${NC}  ${DIM}${tcp_mem_low} / ${tcp_mem_med} / ${tcp_mem_high}${NC}"
    echo ""
    echo -e "  ${YELLOW}正在写入内核参数...${NC}"
    
    mkdir -p /etc/sysctl.d
    cat > ${SYSCTL_FILE} << EOF
# --- Realm XanMod BBRv3 智能自适应调优 ---
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 系统内存: ${total_mem_mb}MB

# === BBRv3 拥塞控制 ===
net.core.default_qdisc = fq_pie
net.ipv4.tcp_congestion_control = bbr

# === 缓冲区设置 (32MB) ===
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

# === TCP 内存池 ===
net.ipv4.tcp_mem = ${tcp_mem_low} ${tcp_mem_med} ${tcp_mem_high}

# === Keepalive ===
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# === 端口范围 ===
net.ipv4.ip_local_port_range = 1024 65535
EOF

    sysctl --system > /dev/null 2>&1
    
    local verify_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    local verify_cong=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    
    echo ""
    echo -e "  ${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${GREEN}║  ✓ BBRv3 极限调优已成功应用！                          ║${NC}"
    echo -e "  ${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ${GREEN}║${NC}  ${WHITE}队列算法${NC}  ${GRAY}│${NC}  ${CYAN}${verify_qdisc}"
    echo -e "  ${GREEN}║${NC}  ${WHITE}拥塞控制${NC}  ${GRAY}│${NC}  ${CYAN}${verify_cong}"
    echo -e "  ${GREEN}║${NC}  ${WHITE}缓冲区${NC}    ${GRAY}│${NC}  ${CYAN}32MB"
    echo -e "  ${GREEN}║${NC}  ${WHITE}内存优化${NC}  ${GRAY}│${NC}  ${CYAN}已根据 ${total_mem_mb}MB 动态计算"
    echo -e "  ${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    
    wait_continue
}

# ================= 4. 添加落地机 =================
add_realm() {
    show_header
    echo -e "  ${GREEN}━━━ 添加中转规则 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo -en "  ${WHITE}中转机监听端口${NC} ${GRAY}»${NC} "
    local local_port; read local_port
    if ! [[ "$local_port" =~ ^[0-9]+$ ]] || [ "$local_port" -lt 1 ] || [ "$local_port" -gt 65535 ]; then 
        show_error "端口无效，请输入 1-65535 之间的数字"
        wait_continue
        return
    fi
    if ss -tulnp | grep -q ":${local_port} "; then 
        show_error "端口 $local_port 已被占用"
        wait_continue
        return
    fi
    if grep -q "^${local_port}|" "${DB_FILE}"; then 
        show_error "端口 $local_port 的规则已存在"
        wait_continue
        return
    fi
    
    echo ""
    echo -e "  ${DIM}格式: IP:端口 (如 1.2.3.4:443)${NC}"
    echo -en "  ${WHITE}落地机地址${NC}     ${GRAY}»${NC} "
    local remote_addr; read remote_addr
    if ! echo "$remote_addr" | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$"; then 
        show_error "格式错误！必须是 IPv4:端口 格式"
        wait_continue
        return
    fi
    
    echo ""
    echo -e "  ${WHITE}选择节点用途${NC}"
    echo -e "  ${GRAY}  1${NC} 🎬 直播    ${GRAY}2${NC} 🎮 游戏    ${GRAY}3${NC} 🌐 通用 ${DIM}(默认)${NC}"
    echo -en "  ${CYAN}▶${NC} "
    local cat_num; read cat_num
    local category="通用"
    case $cat_num in 1) category="直播";; 2) category="游戏";; esac
    
    echo ""
    echo -en "  ${WHITE}备注名称${NC}       ${GRAY}»${NC} ${DIM}(可留空)${NC} "
    local remark; read remark
    
    echo "${local_port}|${remote_addr}|${category}|${remark}" >> ${DB_FILE}
    manage_firewall "$local_port" "open"
    
    echo ""
    show_success "规则添加成功！"
    echo -e "  ${GRAY}监听${NC} ${CYAN}0.0.0.0:${local_port}${NC} ${GRAY}→${NC} ${CYAN}${remote_addr}${NC}"
    
    reload_realm
    wait_continue
}

# ================= 5. 查看节点 =================
list_realms() {
    show_header
    echo -e "  ${CYAN}━━━ 中转规则列表 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ ! -s "${DB_FILE}" ]; then 
        show_info "暂无任何规则"
        wait_continue
        return
    fi
    
    local count=$(grep -v '^#' "${DB_FILE}" | grep -v '^$' | wc -l)
    echo -e "  ${DIM}共 ${count} 条规则${NC}"
    echo ""
    echo -e "  ${DIM}┌──────────┬────────────┬─────────────────────────┬──────────────────┐${NC}"
    echo -e "  ${DIM}│${NC} ${WHITE}监听端口${NC}   ${DIM}│${NC} ${WHITE}用途${NC}        ${DIM}│${NC} ${WHITE}落地机地址${NC}              ${DIM}│${NC} ${WHITE}备注${NC}            ${DIM}│${NC}"
    echo -e "  ${DIM}├──────────┼────────────┼─────────────────────────┼──────────────────┤${NC}"
    
    while IFS='|' read -r local_port remote_addr category remark; do
        [[ -z "$local_port" || "$local_port" == \#* ]] && continue
        [ -z "$category" ] && category="通用"
        [ -z "$remark" ] && remark="-"
        
        local icon="🌐"
        [ "$category" == "直播" ] && icon="🎬"
        [ "$category" == "游戏" ] && icon="🎮"
        
        printf "  ${DIM}│${NC} ${CYAN}%-8s${NC} ${DIM}│${NC} ${YELLOW}%-10s${NC} ${DIM}│${NC} %-23s ${DIM}│${NC} %-16s ${DIM}│${NC}\n" "$local_port" "$icon $category" "$remote_addr" "$remark"
    done < "${DB_FILE}"
    
    echo -e "  ${DIM}└──────────┴────────────┴─────────────────────────┴──────────────────┘${NC}"
    
    wait_continue
}

# ================= 6. 删除节点 =================
del_realm() {
    show_header
    echo -e "  ${RED}━━━ 删除中转规则 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ ! -s "${DB_FILE}" ]; then 
        show_info "暂无任何规则"
        wait_continue
        return
    fi
    
    # 先显示列表
    local count=$(grep -v '^#' "${DB_FILE}" | grep -v '^$' | wc -l)
    echo -e "  ${DIM}共 ${count} 条规则${NC}"
    echo ""
    echo -e "  ${DIM}┌──────────┬────────────┬─────────────────────────┬──────────────────┐${NC}"
    echo -e "  ${DIM}│${NC} ${WHITE}监听端口${NC}   ${DIM}│${NC} ${WHITE}用途${NC}        ${DIM}│${NC} ${WHITE}落地机地址${NC}              ${DIM}│${NC} ${WHITE}备注${NC}            ${DIM}│${NC}"
    echo -e "  ${DIM}├──────────┼────────────┼─────────────────────────┼──────────────────┤${NC}"
    
    while IFS='|' read -r local_port remote_addr category remark; do
        [[ -z "$local_port" || "$local_port" == \#* ]] && continue
        [ -z "$category" ] && category="通用"
        [ -z "$remark" ] && remark="-"
        local icon="🌐"
        [ "$category" == "直播" ] && icon="🎬"
        [ "$category" == "游戏" ] && icon="🎮"
        printf "  ${DIM}│${NC} ${CYAN}%-8s${NC} ${DIM}│${NC} ${YELLOW}%-10s${NC} ${DIM}│${NC} %-23s ${DIM}│${NC} %-16s ${DIM}│${NC}\n" "$local_port" "$icon $category" "$remote_addr" "$remark"
    done < "${DB_FILE}"
    
    echo -e "  ${DIM}└──────────┴────────────┴─────────────────────────┴──────────────────┘${NC}"
    echo ""
    
    echo -en "  ${RED}输入要删除的监听端口${NC} ${GRAY}»${NC} "
    local del_port; read del_port
    [ -z "$del_port" ] && return
    
    if ! grep -q "^${del_port}|" "${DB_FILE}"; then 
        show_error "未找到端口 $del_port 的规则"
        wait_continue
        return
    fi
    
    grep -v "^${del_port}|" "${DB_FILE}" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "${DB_FILE}"
    manage_firewall "$del_port" "close"
    
    show_success "已删除端口 $del_port 的规则"
    reload_realm
    wait_continue
}

# ================= 主菜单 =================
menu() {
    init_env
    while true; do
        show_header
        show_system_info
        show_menu
        show_prompt
        read choice
        case $choice in
            1) clean_system_junk ;;
            2) install_bbrv3 ;;
            3) tune_bbrv3 ;;
            4) add_realm ;;
            5) list_realms ;;
            6) del_realm ;;
            0) 
                echo ""
                echo -e "  ${DIM}再见！${NC}"
                echo ""
                exit 0 
                ;;
            *) 
                show_error "无效选项，请输入 0-6"
                sleep 1
                ;;
        esac
    done
}
menu
