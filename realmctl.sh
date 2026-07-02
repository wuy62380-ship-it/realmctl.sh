#!/bin/bash

# ==========================================
# Realm 中转管理面板 v3.0 (YW内核特化版)
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
    ║           中转网关管理面板 (YW特化版)                   ║
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
    local realm_status="未运行"; local realm_color="${RED}"
    systemctl is-active --quiet realm 2>/dev/null && { realm_status="运行中"; realm_color="${GREEN}"; }
    
    local bbr_status="未启用"; local bbr_color="${RED}"
    local current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    [ "$current_cc" = "bbr" ] && { bbr_status="已启用"; bbr_color="${GREEN}"; }
    
    local is_xanmod="否"; local xanmod_color="${GRAY}"
    echo "$kernel" | grep -qi "xanmod" && { is_xanmod="是"; xanmod_color="${GREEN}"; }
    
    # 智能鉴定调优模式
    local rmem=$(sysctl -n net.core.rmem_max 2>/dev/null)
    local mode="未调优"
    if [ "$rmem" = "8388608" ] && sysctl -n net.core.optmem_max 2>/dev/null | grep -q "20480"; then
        mode="${GREEN}中转网关模式${NC}"
    elif [ "$rmem" = "16777216" ]; then
        mode="${CYAN}低内存自适应模式${NC}"
    elif [ "$rmem" = "4194304" ]; then
        mode="${YELLOW}极限防死机模式${NC}"
    elif [ "$rmem" -gt 16777216 ]; then
        mode="${MAGENTA}非网关大缓冲模式${NC}"
    fi
    
    echo -e "  ${DIM}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${DIM}│${NC}  ${WHITE}系统信息${NC}                                                ${DIM}│${NC}"
    echo -e "  ${DIM}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "  ${DIM}│${NC}  内核版本  ${GRAY}│${NC} ${CYAN}${kernel}${NC} $(echo "$kernel" | grep -qi xanmod && echo "${GREEN}[XanMod]${NC}" || "")"
    echo -e "  ${DIM}│${NC}  运行时间  ${GRAY}│${NC} ${WHITE}${uptime}${NC}"
    echo -e "  ${DIM}│${NC}  内存使用  ${GRAY}│${NC} ${WHITE}${mem_used}/${mem_total}MB${NC} ${DIM}(${mem_percent}%)${NC}"
    echo -e "  ${DIM}│${NC}  Realm状态${GRAY}│${NC} ${realm_color}● ${realm_status}${NC}"
    echo -e "  ${DIM}│${NC}  拥塞控制${GRAY}│${NC} ${bbr_color}● ${bbr_status}${NC} ${GRAY}(${current_cc:-N/A})${NC}"
    echo -e "  ${DIM}│${NC}  XanMod   ${GRAY}│${NC} ${xanmod_color}${is_xanmod}${NC}"
    echo -e "  ${DIM}│${NC}  调优模式${GRAY}│${NC} $mode"
    echo -e "  ${DIM}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

show_menu() {
    echo -e "  ${MAGENTA}━━━ 系统优化 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GRAY}  1${NC}  ${BLUE}🧹${NC}  ${WHITE}深度净化系统${NC}          ${DIM}清理流氓程序释放内存${NC}"
    echo -e "  ${GRAY}  2${NC}  ${BLUE}📦${NC}  ${WHITE}安装/管理 BBRv3 内核${NC}   ${DIM}替换为 XanMod 高性能内核${NC}"
    echo -e "  ${GRAY}  3${NC}  ${BLUE}⚡${NC}  ${WHITE}应用网关极限调优${NC}       ${DIM}动态自适应+防卡顿特化${NC}"
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

show_success() { echo -e "\n  ${GREEN}✓ $1${NC}\n"; }
show_error() { echo -e "\n  ${RED}✘ $1${NC}\n"; }
show_warning() { echo -e "\n  ${YELLOW}⚠ $1${NC}\n"; }
show_info() { echo -e "\n  ${CYAN}ℹ $1${NC}\n"; }
wait_continue() { echo -e "\n  ${DIM}按 Enter 键继续...${NC}"; read -s; }

# ================= Realm 核心逻辑 =================
init_env() {
    mkdir -p ${REALM_DIR} 2>/dev/null; touch ${DB_FILE} 2>/dev/null
    if [ -f "${REALM_BIN}" ] && [ -s "${REALM_BIN}" ]; then
        chmod +x ${REALM_BIN} > /dev/null 2>&1
        [ ! -f "${SERVICE_FILE}" ] && create_service
        return
    fi
    if [ ! -f "${SERVICE_FILE}" ]; then
        echo -e "  ${YELLOW}首次运行，正在初始化 Realm 环境...${NC}"
        download_realm; create_service
    fi
}

download_realm() {
    echo -e "  ${BLUE}正在从私有仓库下载 Realm...${NC}"
    wget -O ${REALM_BIN} https://raw.githubusercontent.com/wuy62380-ship-it/realmctl.sh/main/realm > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        curl -Lo ${REALM_BIN} https://raw.githubusercontent.com/wuy62380-ship-it/realmctl.sh/main/realm > /dev/null 2>&1
        [ $? -ne 0 ] && { show_error "Realm 下载失败！请检查网络"; exit 1; }
    fi
    chmod +x ${REALM_BIN}; show_success "Realm 核心程序安装完成"
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
    systemctl daemon-reload > /dev/null 2>&1; systemctl enable realm > /dev/null 2>&1
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
    generate_toml; systemctl restart realm 2>/dev/null
    [ $? -eq 0 ] && show_success "Realm 已重载生效" || show_error "Realm 重启失败"
}

# ================= 1. 深度净化系统 =================
clean_system_junk() {
    show_header
    echo -e "  ${BLUE}━━━ 深度净化系统 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo -e "  ${YELLOW}正在扫描并清理系统冗余组件...${NC}\n"
    local cleaned=0
    if systemctl is-active --quiet apt-daily.timer 2>/dev/null; then
        systemctl disable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null
        echo -e "  ${GREEN}✓${NC} ${WHITE}已禁用 APT 自动更新${NC}          ${DIM}防止 CPU/内存突刺${NC}"; cleaned=1
    fi
    if dpkg -l | grep -q landscape-client 2>/dev/null; then
        apt-get remove -y landscape-client landscape-common > /dev/null 2>&1
        echo -e "  ${GREEN}✓${NC} ${WHITE}已卸载 Landscape 监控${NC}        ${DIM}释放大量内存${NC}"; cleaned=1
    fi
    if systemctl is-active --quiet aegis-agent 2>/dev/null; then
        systemctl stop aegis-agent && systemctl disable aegis-agent 2>/dev/null
        echo -e "  ${GREEN}✓${NC} ${WHITE}已休眠阿里云安骑士${NC}"; cleaned=1
    fi
    if systemctl is-active --quiet tat_agent 2>/dev/null; then
        systemctl stop tat_agent && systemctl disable tat_agent 2>/dev/null
        echo -e "  ${GREEN}✓${NC} ${WHITE}已休眠腾讯云自动化助手${NC}"; cleaned=1
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
        echo -e "  ${GREEN}✓${NC} ${WHITE}已限制日志上限${NC}              ${DIM}50MB / 3天${NC}"; cleaned=1
    fi
    apt-get clean > /dev/null 2>&1
    [ $cleaned -eq 0 ] && show_info "系统非常纯净，无需清理" || show_success "净化完成！物理内存已归还系统"
    wait_continue
}

# ============================================================================
# 提取自 YW 内核模块：BBRv3 安装与环境保障
# ============================================================================

# 极小内存应急保障
check_swap() {
    local swap_total=$(free -m | awk '/Swap/{print $2}')
    if [ "$swap_total" -ge 512 ] || grep -q "/dev/zram" /proc/swaps 2>/dev/null; then return 0; fi
    if [ -f /swapfile ] && [ "$swap_total" -lt 512 ]; then
        swapon /swapfile >/dev/null 2>&1
        swap_total=$(free -m | awk '/Swap/{print $2}')
        [ "$swap_total" -ge 512 ] && return 0
    fi
    if df / | grep -q "/$" && [ ! -f /etc/pve/.version ]; then
        echo -e "  ${YELLOW}正在创建 512MB 应急 Swap...${NC}"
        dd if=/dev/zero of=/swapfile bs=1M count=512 2>/dev/null
        chmod 600 /swapfile; mkswap /swapfile >/dev/null 2>&1; swapon /swapfile >/dev/null 2>&1
        grep -q "/swapfile none" /etc/fstab 2>/dev/null || echo "/swapfile none swap sw 0 0" >> /etc/fstab
        echo -e "  ${GREEN}✅ 应急 Swap 创建完成。${NC}"
    fi
}

auto_setup_zram() {
    if grep -q "/dev/zram" /proc/swaps 2>/dev/null; then return 0; fi
    echo -e "  ${YELLOW}正在尝试自动配置 zram 替代 zswap...${NC}"
    if command -v apt >/dev/null 2>&1; then
        if ! command -v zramctl >/dev/null 2>&1; then apt-get install -y zram-tools >/dev/null 2>&1 || return 1; fi
        sed -i 's/^ALGO=.*/ALGO=zstd/' /etc/default/zramswap 2>/dev/null
        sed -i 's/^PERCENT=.*/PERCENT=50/' /etc/default/zramswap 2>/dev/null
        systemctl enable zramswap >/dev/null 2>&1; systemctl restart zramswap >/dev/null 2>&1
        grep -q "/dev/zram" /proc/swaps 2>/dev/null && echo -e "  ${GREEN}✅ zram 配置成功并已启动！${NC}" || echo -e "  ${YELLOW}zram 启动失败，可能内核不支持。${NC}"
    fi
}

xanmod_add_repo() {
    local keyring="/usr/share/keyrings/xanmod-archive-keyring.gpg"
    local list_file="/etc/apt/sources.list.d/xanmod-release.list"
    local os_codename=""
    if command -v lsb_release >/dev/null 2>&1; then os_codename=$(lsb_release -sc)
    elif [ -r /etc/os-release ]; then os_codename=$(. /etc/os-release && echo "$VERSION_CODENAME"); fi
    
    # 原生支持 Debian 13 (trixie/forky)
    if ! echo "bookworm trixie forky sid noble plucky" | grep -qw "$os_codename"; then os_codename="releases"; fi
    if echo "jammy focal bullseye buster releases" | grep -qw "$os_codename"; then 
        show_error "XanMod 已停止对当前系统 ($os_codename) 支持"; return 1
    fi
    [ -z "$os_codename" ] && { show_error "无法获取系统代号"; return 1; }
    
    apt-get install -y wget gnupg ca-certificates >/dev/null 2>&1 || return 1
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
        local l="$psabi_level"
        while [ "$l" -ge 1 ]; do 
            local p="${prefix}-x64v${l}"
            if apt-cache policy "$p" 2>/dev/null | grep -q 'Candidate: [^ ]'; then printf '%s\n' "$p"; return 0; fi
            l=$((l-1))
        done
    done
    return 1
}

# ================= 2. 安装 XanMod 内核 =================
install_bbrv3() {
    show_header
    echo -e "  ${RED}━━━ 安装 XanMod BBRv3 内核 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo -e "  ${RED}  ⚠ 此操作将替换系统内核！仅限 Debian/Ubuntu x86_64${NC}\n"
    echo -en "  ${YELLOW}确定继续？${NC} ${GRAY}[y/N]${NC} » "
    local confirm; read confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return
    
    if [ "$(uname -m)" = "aarch64" ]; then 
        show_error "ARM 架构暂不支持"; wait_continue; return
    fi
    if [ -r /etc/os-release ]; then 
        . /etc/os-release
        if [ "$ID" != "debian" ] && [ "$ID" != "ubuntu" ]; then 
            show_error "仅支持 Debian/Ubuntu"; wait_continue; return
        fi
    else return; fi
    
    local installed_kernel=$(dpkg-query -W -f='${Package}\n' 'linux-*xanmod*' 2>/dev/null | grep '^linux-.*xanmod' | head -1)
    
    if [ -n "$installed_kernel" ]; then
        while true; do 
            show_header
            echo -e "  ${CYAN}━━━ XanMod 内核管理 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
            echo -e "  ${WHITE}当前运行内核${NC}  ${GRAY}│${NC}  ${CYAN}$(uname -r)${NC}"
            echo -e "  ${WHITE}已安装内核${NC}    ${GRAY}│${NC}  ${GREEN}${installed_kernel}${NC}\n"
            echo -e "  ${GRAY}  1${NC}  ${WHITE}更新内核到最新版本${NC}"
            echo -e "  ${GRAY}  2${NC}  ${RED}卸载内核还原系统${NC}"
            echo -e "  ${GRAY}  0${NC}  ${DIM}返回主菜单${NC}\n"
            echo -en "  ${CYAN}▶ 请选择${NC} ${GRAY}»${NC} "
            local c; read c
            case $c in 
                1) 
                    check_swap && xanmod_add_repo
                    local pkg=$(xanmod_detect_package)
                    if [ -n "$pkg" ]; then
                        apt-get install -y --only-upgrade "$pkg"
                        echo -e "net.core.default_qdisc = fq_pie\nnet.ipv4.tcp_congestion_control = bbr" > ${SYSCTL_FILE}
                        sysctl --system >/dev/null 2>&1
                        echo -e "\n  ${GREEN}✓ 内核更新成功！${NC}"; read -p "  按回车键重启..." && reboot
                    else
                        show_error "找不到合适的内核包，可能源未刷新成功"
                        wait_continue
                    fi
                    ;; 
                2) 
                    echo -en "  ${RED}确定卸载 XanMod 内核？${NC} ${GRAY}[y/N]${NC} » "
                    local sure; read sure
                    if [[ "$sure" =~ ^[Yy]$ ]]; then
                        apt-get purge -y 'linux-*xanmod*' && apt-get autoremove -y && update-grub
                        rm -f /etc/apt/sources.list.d/xanmod-release.list
                        echo -e "\n  ${GREEN}✓ 已还原系统！${NC}"; read -p "  按回车键重启..." && reboot
                    fi
                    ;; 
                *) break ;; 
            esac
        done
    else
        check_swap && xanmod_add_repo
        echo -e "  ${YELLOW}正在检测适合的内核包...${NC}"
        local pkg_name=$(xanmod_detect_package)
        if [ -z "$pkg_name" ]; then
            show_error "无法找到适合的 XanMod 内核包！"
            echo -e "  ${DIM}建议手动执行: apt update && apt-cache search linux-xanmod 查看可用包${NC}"
            wait_continue; return
        fi
        echo -e "  ${GREEN}✓ 检测到: ${pkg_name}${NC}\n"
        echo -e "  ${YELLOW}开始安装 (过程可能较慢)...${NC}"
        apt-get install -y ${pkg_name}
        if [ $? -eq 0 ]; then
            echo -e "net.core.default_qdisc = fq_pie\nnet.ipv4.tcp_congestion_control = bbr" > ${SYSCTL_FILE}
            sysctl --system >/dev/null 2>&1
            echo -e "\n  ${GREEN}✓ 内核安装成功！${NC}"; read -p "  按回车键重启..." && reboot
        else
            show_error "内核安装失败！请检查网络或磁盘空间"
            wait_continue
        fi
    fi
}

# ============================================================================
# 提取自 YW 内核模块：中转网关专属极限调优
# ============================================================================

apply_gateway_tune() {
    local CONF="${SYSCTL_FILE}"
    echo -e "  ${YELLOW}正在计算中转网关专属参数...${NC}"
    
    # 基础网关参数 (保 CPU 算加密，不抢软中断)
    local SWAPPINESS=10 DIRTY_RATIO=20 DIRTY_BG_RATIO=10 OVERCOMMIT=1 VFS_PRESSURE=50
    local MIN_FREE_KB=32768
    local RMEM_MAX=8388608 WMEM_MAX=8388608 # 默认 8MB
    local TCP_RMEM="4096 16384 8388608" TCP_WMEM="4096 16384 8388608"
    local SOMAXCONN=65535 BACKLOG=100000 SYN_BACKLOG=8192 PORT_RANGE="1024 65535"
    local SCHED_AUTOGROUP=0 THP="never" NUMA=0 FIN_TIMEOUT=30
    local KEEPALIVE_TIME=300 KEEPALIVE_INTVL=30 KEEPALIVE_PROBES=5 UDP_RMEM_MIN=16384
    local TCP_NOTSENT_LOWAT=16384 TCP_FASTOPEN=3 TCP_TW_REUSE=1 TCP_MTU_PROBING=1
    local TCP_SLOW_START_AFTER_IDLE=0 TCP_ECN=0 
    
    # XanMod 强制 fq_pie，普通内核 fallback 到 fq
    local CC="bbr" QDISC="fq_pie"
    if ! uname -r | grep -qi "xanmod"; then QDISC="fq"; fi

    # 内存自适应算法
    local MEM_MB_VAL=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
    local HAS_SWAP=$(free -m | awk '/Swap/{print $2}')
    local IS_LOW_MEM=0

    if [ "$MEM_MB_VAL" -ge 16384 ]; then
        MIN_FREE_KB=131072; SWAPPINESS=5
    elif [ "$MEM_MB_VAL" -ge 4096 ]; then
        MIN_FREE_KB=65536
    elif [ "$MEM_MB_VAL" -ge 1024 ]; then
        # 1G-4G 内存：缓冲区放大到 16MB 防不够用
        RMEM_MAX=16777216; WMEM_MAX=16777216
        TCP_RMEM="4096 32768 16777216"; TCP_WMEM="4096 32768 16777216"
    else
        # 极小内存 (<1G)：强制降级防死机
        IS_LOW_MEM=1
        MIN_FREE_KB=16384; OVERCOMMIT=0; SWAPPINESS=10
        RMEM_MAX=4194304; WMEM_MAX=4194304; SOMAXCONN=1024; BACKLOG=1000
        TCP_RMEM="4096 32768 4194304"; TCP_WMEM="4096 32768 4194304"
    fi

    # TCP 内存池自适应
    local TCP_MEM_MIN=$((MEM_MB_VAL * 256)); local TCP_MEM_DEF=$((MEM_MB_VAL * 512)); local TCP_MEM_MAX=$((MEM_MB_VAL * 1024))
    [ "$TCP_MEM_MIN" -lt 8192 ] && TCP_MEM_MIN=8192
    [ "$TCP_MEM_DEF" -lt 16384 ] && TCP_MEM_DEF=16384; [ "$TCP_MEM_MAX" -lt 32768 ] && TCP_MEM_MAX=32768

    local TW_BUCKETS=$((SOMAXCONN * 4)); local MAX_ORPHANS=$((SOMAXCONN * 2))
    [ "$TW_BUCKETS" -gt 524288 ] && TW_BUCKETS=524288; [ "$MAX_ORPHANS" -gt 131072 ] && MAX_ORPHANS=131072

    # 极小内存特殊处理
    if [ "$IS_LOW_MEM" -eq 1 ]; then
        if [ -f /sys/module/zswap/parameters/enabled ]; then echo N > /sys/module/zswap/parameters/enabled 2>/dev/null; fi
        if [ "$HAS_SWAP" -gt 0 ]; then
            echo -e "  ${YELLOW}检测极小内存(${MEM_MB_VAL}MB)，已禁用 zswap 并部署 zram...${NC}"
            auto_setup_zram
        else
            echo -e "  ${RED}检测极小内存(${MEM_MB_VAL}MB)无Swap！强制降级防死机...${NC}"
            check_swap; auto_setup_zram
        fi
    fi

    local backup_conf="${CONF}.bak.$(date +%s)"; [ -f "$CONF" ] && cp "$CONF" "$backup_conf"
    
    cat > "$CONF" << EOF
# Realm 中转网关专属极限调优 (提取自 YW 内核模块)
# 场景: Gateway | 内存: ${MEM_MB_VAL}MB | 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# ── TCP 拥塞控制 ──
net.core.default_qdisc = $QDISC
net.ipv4.tcp_congestion_control = $CC

# ── TCP 缓冲区 ──
net.core.rmem_max = $RMEM_MAX
net.core.wmem_max = $WMEM_MAX
net.core.rmem_default = $(echo "$TCP_RMEM" | awk '{print $2}')
net.core.wmem_default = $(echo "$TCP_WMEM" | awk '{print $2}')
net.ipv4.tcp_rmem = $TCP_RMEM
net.ipv4.tcp_wmem = $TCP_WMEM

# ── UDP 缓冲区 ──
net.ipv4.udp_rmem_min = $UDP_RMEM_MIN
net.ipv4.udp_wmem_min = $UDP_RMEM_MIN

# ── 连接队列 ──
net.core.somaxconn = $SOMAXCONN
net.core.netdev_max_backlog = $BACKLOG
net.ipv4.tcp_max_syn_backlog = $SYN_BACKLOG

# ── TCP 连接优化 ──
net.ipv4.tcp_fastopen = $TCP_FASTOPEN
net.ipv4.tcp_tw_reuse = $TCP_TW_REUSE
net.ipv4.tcp_fin_timeout = $FIN_TIMEOUT
net.ipv4.tcp_keepalive_time = $KEEPALIVE_TIME
net.ipv4.tcp_keepalive_intvl = $KEEPALIVE_INTVL
net.ipv4.tcp_keepalive_probes = $KEEPALIVE_PROBES
net.ipv4.tcp_max_tw_buckets = $TW_BUCKETS
net.ipv4.tcp_max_orphans = $MAX_ORPHANS
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_mtu_probing = $TCP_MTU_PROBING
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_notsent_lowat = $TCP_NOTSENT_LOWAT

# ── 网络低延迟/防抖动特化 ──
net.ipv4.tcp_slow_start_after_idle = $TCP_SLOW_START_AFTER_IDLE
net.ipv4.tcp_ecn = $TCP_ECN

# ── 端口与内存 ──
net.ipv4.ip_local_port_range = $PORT_RANGE
net.ipv4.tcp_mem = $TCP_MEM_MIN $TCP_MEM_DEF $TCP_MEM_MAX

# ── 虚拟内存 ──
vm.swappiness = $SWAPPINESS
vm.dirty_ratio = $DIRTY_RATIO
vm.dirty_background_ratio = $DIRTY_BG_RATIO
vm.overcommit_memory = $OVERCOMMIT
vm.min_free_kbytes = $MIN_FREE_KB
vm.vfs_cache_pressure = $VFS_PRESSURE

# ── CPU/内核调度 ──
kernel.sched_autogroup_enabled = $SCHED_AUTOGROUP
 $( [ -f /proc/sys/kernel/numa_balancing ] && echo "kernel.numa_balancing = $NUMA" || echo "# numa_balancing 不支持" )

# ── 安全防护 ──
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# ── 文件描述符 ──
fs.file-max = 1048576
fs.nr_open = 1048576

# ── 连接跟踪 ──
 $( if [ -f /proc/sys/net/netfilter/nf_conntrack_max ]; then
echo "net.netfilter.nf_conntrack_max = $((SOMAXCONN * 32))"
echo "net.netfilter.nf_conntrack_tcp_timeout_established = 7200"
echo "net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30"
echo "net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15"
echo "net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 15"
else
echo "# conntrack 未启用"
fi )

# ── 中转网关专属：保 CPU 算加密，不抢软中断 ──
net.core.optmem_max = 20480
EOF

    echo -e "  ${YELLOW}正在加载配置...${NC}"
    local sysctl_err=$(sysctl -p "$CONF" 2>&1 | grep -v "Invalid argument" | grep -v "No such file or directory" | grep -v "unknown key")
    [ -n "$sysctl_err" ] && echo -e "  ${DIM}忽略非关键异常: $(echo "$sysctl_err" | head -n 1)${NC}"
    
    # 提升文件描述符限制
    if ! grep -q "# Realm-optimize" /etc/security/limits.conf 2>/dev/null; then
        echo -e "\n# Realm-optimize" >> /etc/security/limits.conf
        echo -e "* soft nofile 1048576\n* hard nofile 1048576\nroot soft nofile 1048576\nroot hard nofile 1048576" >> /etc/security/limits.conf
    fi
    ulimit -n 1048576 2>/dev/null
}

# ================= 3. 应用调优入口 =================
tune_bbrv3() {
    show_header
    echo -e "  ${YELLOW}━━━ 应用中转网关极限调优 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
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
            echo -e "  ${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}\n"
            echo -e "  ${RED}当前运行${NC}  ${GRAY}│${NC}  ${current_kernel}"
            echo -e "  ${GREEN}已安装${NC}    ${GRAY}│${NC}"
            echo "$installed_xanmod" | while read pkg ver; do echo -e "             ${GRAY}│${NC}  ${GREEN}📦 ${pkg} ${DIM}${ver}${NC}"; done
            echo -e "\n  ${CYAN}💡 解决方法：重启服务器以加载新内核${NC}\n"
            echo -en "  ${YELLOW}是否现在重启？${NC} ${GRAY}[y/N]${NC} » "
            local reboot_now; read reboot_now
            [[ "$reboot_now" =~ ^[Yy]$ ]] && reboot
            wait_continue; return 1
        else
            echo -e "  ${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
            echo -e "  ${YELLOW}║  ⚠  未检测到 XanMod 内核，将使用普通 BBR 网关模式     ║${NC}"
            echo -e "  ${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}\n"
            echo -en "  ${YELLOW}继续应用调优？${NC} ${GRAY}[y/N]${NC} » "
            local cont; read cont
            [[ ! "$cont" =~ ^[Yy]$ ]] && return 1
        fi
    else
        echo -e "  ${GREEN}✓ 检测到 XanMod 内核: ${current_kernel}${NC}\n"
    fi
    
    apply_gateway_tune
    
    local verify_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    local verify_cong=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local rmem_mb=$(awk "BEGIN{printf \"%.0f\", $(sysctl -n net.core.rmem_max)/1024/1024}")
    
    echo ""
    echo -e "  ${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${GREEN}║  ✓ 中转网关极限调优已成功应用！                        ║${NC}"
    echo -e "  ${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ${GREEN}║${NC}  ${WHITE}队列算法${NC}  ${GRAY}│${NC}  ${CYAN}${verify_qdisc}"
    echo -e "  ${GREEN}║${NC}  ${WHITE}拥塞控制${NC}  ${GRAY}│${NC}  ${CYAN}${verify_cong}"
    echo -e "  ${GREEN}║${NC}  ${WHITE}TCP缓冲${NC}   ${GRAY}│${NC}  ${CYAN}${rmem_mb}MB ${DIM}(保 CPU 算加密)${NC}"
    echo -e "  ${GREEN}║${NC}  ${WHITE}特化防护${NC}  ${GRAY}│${NC}  ${CYAN}防抖动/防重定向/连接跟踪优化${NC}"
    echo -e "  ${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    
    wait_continue
}

# ================= 4. 添加落地机 =================
add_realm() {
    show_header
    echo -e "  ${GREEN}━━━ 添加中转规则 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo -en "  ${WHITE}中转机监听端口${NC} ${GRAY}»${NC} "; local local_port; read local_port
    if ! [[ "$local_port" =~ ^[0-9]+$ ]] || [ "$local_port" -lt 1 ] || [ "$local_port" -gt 65535 ]; then 
        show_error "端口无效"; wait_continue; return
    fi
    if ss -tulnp | grep -q ":${local_port} "; then show_error "端口 $local_port 已被占用"; wait_continue; return; fi
    if grep -q "^${local_port}|" "${DB_FILE}"; then show_error "端口 $local_port 规则已存在"; wait_continue; return; fi
    
    echo -e "\n  ${DIM}格式: IP:端口 (如 1.2.3.4:443)${NC}"
    echo -en "  ${WHITE}落地机地址${NC}     ${GRAY}»${NC} "; local remote_addr; read remote_addr
    if ! echo "$remote_addr" | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$"; then 
        show_error "格式错误！必须是 IPv4:端口"; wait_continue; return
    fi
    
    echo -e "\n  ${WHITE}选择节点用途${NC}"
    echo -e "  ${GRAY}  1${NC} 🎬 直播    ${GRAY}2${NC} 🎮 游戏    ${GRAY}3${NC} 🌐 通用 ${DIM}(默认)${NC}"
    echo -en "  ${CYAN}▶${NC} "; local cat_num; read cat_num
    local category="通用"; case $cat_num in 1) category="直播";; 2) category="游戏";; esac
    
    echo -en "\n  ${WHITE}备注名称${NC}       ${GRAY}»${NC} ${DIM}(可留空)${NC} "; local remark; read remark
    
    echo "${local_port}|${remote_addr}|${category}|${remark}" >> ${DB_FILE}
    manage_firewall "$local_port" "open"
    show_success "规则添加成功！\n  ${GRAY}监听${NC} ${CYAN}0.0.0.0:${local_port}${NC} ${GRAY}→${NC} ${CYAN}${remote_addr}${NC}"
    reload_realm; wait_continue
}

# ================= 5 & 6. 查看/删除节点 =================
list_realms() {
    show_header
    echo -e "  ${CYAN}━━━ 中转规则列表 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    if [ ! -s "${DB_FILE}" ]; then show_info "暂无任何规则"; wait_continue; return; fi
    local count=$(grep -v '^#' "${DB_FILE}" | grep -v '^$' | wc -l)
    echo -e "  ${DIM}共 ${count} 条规则${NC}\n"
    echo -e "  ${DIM}┌──────────┬────────────┬─────────────────────────┬──────────────────┐${NC}"
    echo -e "  ${DIM}│${NC} ${WHITE}监听端口${NC}   ${DIM}│${NC} ${WHITE}用途${NC}        ${DIM}│${NC} ${WHITE}落地机地址${NC}              ${DIM}│${NC} ${WHITE}备注${NC}            ${DIM}│${NC}"
    echo -e "  ${DIM}├──────────┼────────────┼─────────────────────────┼──────────────────┤${NC}"
    while IFS='|' read -r local_port remote_addr category remark; do
        [[ -z "$local_port" || "$local_port" == \#* ]] && continue
        [ -z "$category" ] && category="通用"; [ -z "$remark" ] && remark="-"
        local icon="🌐"; [ "$category" == "直播" ] && icon="🎬"; [ "$category" == "游戏" ] && icon="🎮"
        printf "  ${DIM}│${NC} ${CYAN}%-8s${NC} ${DIM}│${NC} ${YELLOW}%-10s${NC} ${DIM}│${NC} %-23s ${DIM}│${NC} %-16s ${DIM}│${NC}\n" "$local_port" "$icon $category" "$remote_addr" "$remark"
    done < "${DB_FILE}"
    echo -e "  ${DIM}└──────────┴────────────┴─────────────────────────┴──────────────────┘${NC}"
    wait_continue
}

del_realm() {
    show_header
    echo -e "  ${RED}━━━ 删除中转规则 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    if [ ! -s "${DB_FILE}" ]; then show_info "暂无任何规则"; wait_continue; return; fi
    list_realms
    echo -en "  ${RED}输入要删除的监听端口${NC} ${GRAY}»${NC} "; local del_port; read del_port
    [ -z "$del_port" ] && return
    if ! grep -q "^${del_port}|" "${DB_FILE}"; then show_error "未找到端口 $del_port 的规则"; wait_continue; return; fi
    grep -v "^${del_port}|" "${DB_FILE}" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "${DB_FILE}"
    manage_firewall "$del_port" "close"
    show_success "已删除端口 $del_port 的规则"
    reload_realm; wait_continue
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
            0) echo -e "\n  ${DIM}再见！${NC}\n"; exit 0 ;;
            *) show_error "无效选项，请输入 0-6"; sleep 1 ;;
        esac
    done
}
menu
