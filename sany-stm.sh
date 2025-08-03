#!/bin/bash
# ==== 路径和全局定义 ====
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ST_DIR="$SCRIPT_DIR/SillyTavern"
BACKUP_PARENT_DIR="$SCRIPT_DIR/backups"
safe_dirname=$(basename "$SCRIPT_DIR" | tr -c 'a-zA-Z0-9.-' '_')
SCREEN_NAME="sillytavern-bg-${safe_dirname}"
SERVICE_NAME="sillytavern-${safe_dirname}.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
PROXY_URL="https://ghfast.top/"
PROXY_ENABLED=false
PROXY_CONFIGURED_MANUALLY=false
AUTHOR="三月"
UPDATE_DATE="2025-08-04"
CONTACT_INFO_LINE1="欢迎加群获取最新脚本"
CONTACT_INFO_LINE2="交流群：923018427   API群：1013506523"
SCRIPT_VERSION="1.05" # 版本号提升
SCRIPT_NAME="sany-stm.sh"
# ==== 颜色定义 ====
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m';
CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m';
# ==== 全局变量 ====
SUDO_CMD=""
SUDO_PRIVILEGES_REQUESTED=false
# ==== 基础函数 ====
err() { echo -e "${RED}错误: $1${NC}" >&2; }
info() { echo -e "${CYAN}信息: $1${NC}"; }
success() { echo -e "${GREEN}成功: $1${NC}"; }
warn() { echo -e "${YELLOW}警告: $1${NC}"; }
_request_sudo_privileges() {
    if [[ "$EUID" -eq 0 ]]; then SUDO_CMD=""; return 0; fi
    if ! command -v sudo &>/dev/null; then err "此操作需要 sudo，但该命令未安装。"; SUDO_CMD=""; return 1; fi
    if sudo -v; then SUDO_CMD="sudo"; SUDO_PRIVILEGES_REQUESTED=true; return 0;
    else err "获取 sudo 权限失败。"; SUDO_CMD=""; return 1; fi
}

install_or_update_nodejs() {
    info "正在检查 Node.js 版本..."
    local MIN_NODE_VERSION=18
    local REQUIRED_NODE_VERSION=20
    
    if ! command -v node &>/dev/null; then
        warn "未找到 Node.js。正在尝试安装 Node.js v${REQUIRED_NODE_VERSION}..."
    else
        local current_version=$(node -v)
        local major_version=$(echo "$current_version" | sed 's/v//' | cut -d'.' -f1)
        if [[ "$major_version" -lt "$MIN_NODE_VERSION" ]]; then
            warn "当前 Node.js 版本 ($current_version)过旧，需要 >= v${MIN_NODE_VERSION}。"
            info "正在尝试升级到 Node.js v${REQUIRED_NODE_VERSION}..."
        else
            success "Node.js 版本 ($current_version) 符合要求 (>= v${MIN_NODE_VERSION})。"
            return 0
        fi
    fi

    if [[ -n "$TERMUX_VERSION" ]]; then
        info "Termux 环境：正在安装/更新 nodejs-lts..."
        pkg install -y nodejs-lts || { err "在 Termux 中安装 nodejs-lts 失败。"; return 1; }
        if command -v node &>/dev/null; then
            success "Node.js (LTS) 安装/更新成功。版本: $(node -v)"
            return 0
        else
            err "Node.js 在 Termux 中安装后仍未找到。"; return 1
        fi
    fi

    if ! _request_sudo_privileges; then return 1; fi
    check_and_install_deps "curl" "gnupg" || { err "安装Node.js需要curl和gnupg，但安装失败。"; return 1; }

    info "将使用 NodeSource 官方源进行安装..."
    if command -v apt-get &>/dev/null; then
        $SUDO_CMD apt-get update
        $SUDO_CMD apt-get install -y ca-certificates
        
        info "正在配置 NodeSource apt 源..."
        if [[ -n "$SUDO_CMD" ]]; then
            curl -fsSL "https://deb.nodesource.com/setup_${REQUIRED_NODE_VERSION}.x" | $SUDO_CMD -E bash -
        else
            curl -fsSL "https://deb.nodesource.com/setup_${REQUIRED_NODE_VERSION}.x" | bash -
        fi

        info "正在安装 Node.js..."
        $SUDO_CMD apt-get install -y nodejs
    elif command -v yum &>/dev/null; then
        info "正在配置 NodeSource yum 源..."
        if [[ -n "$SUDO_CMD" ]]; then
            curl -fsSL "https://rpm.nodesource.com/setup_${REQUIRED_NODE_VERSION}.x" | $SUDO_CMD -E bash -
        else
            curl -fsSL "https://rpm.nodesource.com/setup_${REQUIRED_NODE_VERSION}.x" | bash -
        fi
        info "正在安装 Node.js..."
        $SUDO_CMD yum install -y nodejs
    else
        err "不支持的包管理器。请手动安装 Node.js v${MIN_NODE_VERSION} 或更高版本。"
        return 1
    fi
    
    if ! command -v node &>/dev/null; then
        err "Node.js 安装失败！请检查上面的错误信息。"; return 1
    fi
    local new_version=$(node -v)
    local new_major_version=$(echo "$new_version" | sed 's/v//' | cut -d'.' -f1)
    if [[ "$new_major_version" -lt "$MIN_NODE_VERSION" ]]; then
        err "尝试安装后，Node.js 版本 ($new_version) 仍然过低！"
        return 1
    fi
    success "Node.js 已成功安装/更新到版本: $new_version"
    return 0
}

check_and_install_deps() {
    local required_deps=("$@")
    if [ ${#required_deps[@]} -eq 0 ]; then return 0; fi
    info "正在检查所需依赖: ${required_deps[*]}..."
    if [[ -n "$TERMUX_VERSION" ]]; then
        info "正在检查 Termux 包管理器状态..."
        local lock_file="/data/data/com.termux/files/usr/var/lib/dpkg/lock"
        local lock_file_frontend="/data/data/com.termux/files/usr/var/lib/dpkg/lock-frontend"
        local max_wait_seconds=60; local count=0
        while fuser "$lock_file" >/dev/null 2>&1 || fuser "$lock_file_frontend" >/dev/null 2>&1; do
            if (( count >= max_wait_seconds )); then
                err "Termux 包管理器(apt/pkg)已被另一个进程锁定超过 ${max_wait_seconds} 秒。"; return 1
            fi
            warn "检测到另一个包管理进程正在运行，等待其完成... (${count}s / ${max_wait_seconds}s)"; sleep 1; ((count++))
        done
        success "包管理器已就绪。"
    fi
    local missing_deps=(); local pkg_manager=""; local sudo_cmd=""
    if [[ -n "$TERMUX_VERSION" ]]; then pkg_manager="pkg"
    elif command -v apt-get >/dev/null; then
        pkg_manager="apt-get"; if [[ "$EUID" -ne 0 ]]; then
            if ! command -v sudo >/dev/null; then err "需要 sudo 权限来安装依赖，但未找到 sudo 命令。"; return 1; fi
            sudo_cmd="sudo"; fi
    elif command -v yum >/dev/null; then
        pkg_manager="yum"; if [[ "$EUID" -ne 0 ]]; then
            if ! command -v sudo >/dev/null; then err "需要 sudo 权限来安装依赖，但未找到 sudo 命令。"; return 1; fi
            sudo_cmd="sudo"; fi
    else
        for dep in "${required_deps[@]}"; do
            if ! command -v "$dep" >/dev/null; then
                err "依赖 '$dep' 未找到。无法识别您的包管理器，请手动安装。"; return 1
            fi
        done
        success "所有依赖项均已就绪。"; return 0
    fi
    for dep in "${required_deps[@]}"; do
        if [[ "$dep" == "dnsutils" ]] && (command -v "dig" >/dev/null || command -v "nslookup" >/dev/null) ; then continue; fi
        if ! command -v "$dep" >/dev/null; then missing_deps+=("$dep"); fi
    done
    if [ ${#missing_deps[@]} -gt 0 ]; then
        warn "检测到以下依赖缺失: ${missing_deps[*]}"
        info "正在尝试自动安装..."
        local packages_to_install=()
        for dep in "${missing_deps[@]}"; do
             case "$pkg_manager" in
                "apt-get")
                    if [[ "$dep" == "dnsutils" ]]; then packages_to_install+=("dnsutils"); else packages_to_install+=("$dep"); fi ;;
                "yum")
                    if [[ "$dep" == "dnsutils" ]]; then packages_to_install+=("bind-utils"); else packages_to_install+=("$dep"); fi ;;
                "pkg")
                    if [[ "$dep" == "dnsutils" ]]; then packages_to_install+=("dnsutils"); else packages_to_install+=("$dep"); fi ;;
             esac
        done
        if [ ${#packages_to_install[@]} -gt 0 ]; then
            info "将要执行: ${sudo_cmd}${pkg_manager} install -y ${packages_to_install[*]}"
            if [[ "$pkg_manager" == "apt-get" ]]; then
                $sudo_cmd apt-get update
                ${sudo_cmd}${pkg_manager} install -y -o Dpkg::Options::="--force-confnew" "${packages_to_install[@]}"
            else
                ${sudo_cmd}${pkg_manager} install -y "${packages_to_install[@]}"
            fi
        fi
        for dep in "${missing_deps[@]}"; do
             if ! command -v "$dep" >/dev/null; then
                if [[ "$dep" == "dnsutils" ]] && (command -v "dig" >/dev/null || command -v "nslookup" >/dev/null) ; then continue; fi
                err "依赖 '$dep' 自动安装失败！"; return 1
            fi
        done
        success "所有缺失的依赖已安装成功。"
    else
        success "所有依赖项均已就绪。"
    fi
    return 0
}

# (这里省略了其他函数，它们保持不变，无需修改)
# ... diagnose_and_fix_network, _attempt_clone, manage_sillytavern, 等等...
diagnose_and_fix_network() {
    info "操作失败，正在启动网络诊断与修复程序...";
    if ! ping -c 1 1.1.1.1 > /dev/null 2>&1 && ! ping -c 1 223.5.5.5 > /dev/null 2>&1; then err "基础网络连接失败。请检查您的网络连接、路由器状态或系统防火墙设置。"; return 1; fi; success "基础网络连接正常。"
    if nslookup github.com > /dev/null 2>&1 || dig github.com > /dev/null 2>&1; then success "DNS解析正常。"; return 0; fi
    warn "DNS解析可能存在问题。正在尝试添加公共DNS..."
    if ! _request_sudo_privileges; then return 1; fi;
    local resolv_conf="/etc/resolv.conf"
    info "正在备份当前的DNS配置文件到 ${resolv_conf}.bak..."; $SUDO_CMD cp "$resolv_conf" "${resolv_conf}.bak-$(date +%F-%T)"
    info "正在向 ${resolv_conf} 添加公共DNS...";
    if ! $SUDO_CMD sed -i '1i nameserver 8.8.8.8\nnameserver 1.1.1.1' "$resolv_conf"; then err "修改 ${resolv_conf} 失败！请手动添加。"; return 1; fi
    success "DNS配置已更新，将在3秒后重试"; sleep 3; return 0;
}
_attempt_clone() {
    local git_url_direct="https://github.com/SillyTavern/SillyTavern.git"; local git_url_proxy="${PROXY_URL}https://github.com/SillyTavern/SillyTavern.git"; local git_urls=()
    if [[ "$PROXY_ENABLED" == true ]]; then git_urls+=("$git_url_proxy" "$git_url_direct"); else git_urls+=("$git_url_direct" "$git_url_proxy"); fi
    for url in "${git_urls[@]}"; do
        local mode_desc="直连模式"; [[ "$url" == "$git_url_proxy" ]] && mode_desc="代理模式"
        info "正在尝试使用 ${mode_desc} 克隆..."
        if git clone --depth 1 --branch release "$url" "$ST_DIR"; then
            if [[ "$url" != "${git_urls[0]}" ]]; then
                info "已自动切换下载模式并成功: 当前为 ${mode_desc}"
                [[ "$mode_desc" == "代理模式" ]] && PROXY_ENABLED=true || PROXY_ENABLED=false
            fi
            return 0
        fi;
    done; return 1
}
manage_sillytavern() {
    install_or_update_nodejs || { err "Node.js 环境配置失败，操作中止。"; return 1; }
    check_and_install_deps "git" "curl" "jq" || { err "核心依赖检查或安装失败，操作中止。"; return 1; }
    handle_proxy_logic "install"; local local_ver; local_ver=$(get_local_st_ver)
    if [[ "$local_ver" != "未安装" ]]; then
        info "检测到SillyTavern已安装 (版本: $local_ver)，即将开始更新..."; info "为保证数据安全，将先进行备份。"
        _create_backup_instance || { err "更新前备份失败，操作中止。"; return 1; }
        cd "$ST_DIR" || { err "无法进入SillyTavern目录: $ST_DIR"; return 1; }
        info "正在拉取最新代码..."; local GIT_COMMAND="git fetch --all && git reset --hard origin/release && git pull"
        if [[ "$PROXY_ENABLED" == true ]]; then git config --local http.proxy "${PROXY_URL}"; else git config --local --unset http.proxy; fi
        if ! eval "$GIT_COMMAND"; then
            warn "Git更新失败，正在尝试切换代理模式后重试..."
            if [[ "$PROXY_ENABLED" == true ]]; then info "当前为代理模式，切换到直连模式重试..."; git config --local --unset http.proxy; PROXY_ENABLED=false; else info "当前为直连模式，切换到代理模式重试..."; git config --local http.proxy "${PROXY_URL}"; PROXY_ENABLED=true; fi
            if ! eval "$GIT_COMMAND"; then err "切换模式后Git更新依然失败，请检查网络或手动处理。"; git config --local --unset http.proxy; return 1; fi; success "切换模式后Git更新成功！"
        fi
        git config --local --unset http.proxy; info "正在更新NPM依赖..."
        npm config set registry "https://registry.npmmirror.com/"; if ! npm install --omit=dev; then err "NPM依赖更新失败。"; return 1; fi; success "SillyTavern 更新完成！"
    else
        info "SillyTavern未安装，即将开始全新安装..."; if ! _attempt_clone; then
            if diagnose_and_fix_network; then info "网络修复后，正在重试克隆操作..."; if ! _attempt_clone; then err "重试操作后依然失败。请检查防火墙、系统TLS/SSL库或GitHub状态。"; return 1; fi
            else err "网络诊断与修复失败，无法继续安装。"; return 1; fi
        fi
        cd "$ST_DIR" || { err "无法进入新创建的目录: $ST_DIR"; return 1; }
        info "正在安装NPM依赖..."; npm config set registry "https://registry.npmmirror.com/"; if ! npm install --omit=dev; then err "NPM依赖安装失败。"; return 1; fi; success "SillyTavern 安装完成！"
    fi
    if [[ "$EUID" -eq 0 && -n "$SUDO_USER" ]]; then chown -R "$SUDO_USER:${SUDO_GID:-$SUDO_USER}" "$ST_DIR"; success "文件权限修正完成！"; fi
}
handle_proxy_logic() {
    local mode="$1"; if [[ "$mode" == "install" && "$PROXY_CONFIGURED_MANUALLY" == true ]]; then info "已检测到代理配置，将继续使用当前设置。"; return 0; fi
    check_and_install_deps "curl" || return 1; local country; country=$(curl -s --connect-timeout 5 ipinfo.io/country 2>/dev/null)
    if [[ "$country" == "CN" ]]; then
        info "检测到您可能位于中国大陆(CN)。推荐开启代理以加速GitHub和依赖安装。"; read -rp "是否启用加速代理? [Y/n]: " yn
        if [[ ! "$yn" =~ ^[Nn]$ ]]; then PROXY_ENABLED=true; else PROXY_ENABLED=false; fi
    else
        info "检测到您位于海外地区 (${country:-未知})。"; read -rp "您是否需要启用加速代理? [y/N]: " yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then PROXY_ENABLED=true; success "已根据您的选择启用代理。"; else PROXY_ENABLED=false; info "已根据您的选择禁用代理。"; fi
    fi
    if [[ "$PROXY_ENABLED" == true && -n "$TERMUX_VERSION" ]]; then local T_PREFIX="/data/data/com.termux/files/usr";
        sed -i 's@^\(deb.*\) https://mirrors.*@\1 https://mirrors.tuna.tsinghua.edu.cn/termux/termux-packages-24@' $T_PREFIX/etc/apt/sources.list; sed -i 's@^\(deb.*\) https://mirrors.*@\1 https://mirrors.tuna.tsinghua.edu.cn/termux/science@' $T_PREFIX/etc/apt/sources.list.d/science.list; sed -i 's@^\(deb.*\) https://mirrors.*@\1 https://mirrors.tuna.tsinghua.edu.cn/termux/game@' $T_PREFIX/etc/apt/sources.list.d/game.list;
        pkg update --fix-missing -y || warn "更新软件源列表失败。"; success "Termux镜像源已切换至清华源。"
    fi
    PROXY_CONFIGURED_MANUALLY=true; [[ "$PROXY_ENABLED" == true ]] && info "当前访问模式: ${GREEN}代理模式${NC}" || info "当前访问模式: ${YELLOW}直连模式${NC}"
}
get_local_st_ver() { [ -f "$ST_DIR/package.json" ] && jq -r .version "$ST_DIR/package.json" || echo "未安装"; }
check_st_running() { if screen -list | grep -q "\.$SCREEN_NAME"; then echo -e "${GREEN}(后台运行中 - Screen)${NC}"; elif systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then echo -e "${GREEN}(后台运行中 - Systemd)${NC}"; elif pgrep -f "$ST_DIR/start.sh" >/dev/null||pgrep -f "$ST_DIR/server.js" >/dev/null; then echo -e "${GREEN}(前台运行中)${NC}"; else echo -e "${YELLOW}(未运行)${NC}"; fi; }
update_script() {
    check_and_install_deps "curl" "dnsutils" || return 1; info "正在检查脚本更新...";
    local raw_host="raw.githubusercontent.com"; local proxy_domain=$(echo "$PROXY_URL" | cut -d'/' -f3); local curl_opts="-sLk --connect-timeout 8"
    resolve_host() { local host_to_resolve=$1; local resolved_ip=""; for dns in "1.1.1.1" "8.8.8.8" "114.114.114.114" "223.5.5.5"; do if command -v dig &> /dev/null; then resolved_ip=$(dig @${dns} +short A ${host_to_resolve} | head -1); elif command -v nslookup &> /dev/null; then resolved_ip=$(nslookup ${host_to_resolve} ${dns} | awk '/^Address: / { print $2 }' | tail -n 1); fi; if [[ -n "$resolved_ip" && "$resolved_ip" != "can't" && "$resolved_ip" != "find" ]]; then curl_opts="${curl_opts} --resolve ${host_to_resolve}:443:${resolved_ip}"; return 0; fi; done; return 1; }; resolve_host "$raw_host"; resolve_host "$proxy_domain"
    local raw_url="https://${raw_host}/Akane328/akane-st-manage/main/${SCRIPT_NAME}"; local proxy_url="${PROXY_URL}${raw_url}"; local timestamp="?t=$(date +%s)"; local urls_to_try=("${raw_url}${timestamp}" "${proxy_url}${timestamp}"); local remote_script_content=""; local successful_url=""
    for url in "${urls_to_try[@]}"; do remote_script_content=$(curl ${curl_opts} "$url"); if [[ -n "$remote_script_content" && "$remote_script_content" == *'#!/bin/bash'* ]]; then successful_url="$url"; break; fi; done
    if [[ -z "$successful_url" ]]; then err "所有更新路径均尝试失败，无法检查更新。"; return 1; fi
    local remote_version; remote_version=$(echo "$remote_script_content" | grep 'SCRIPT_VERSION=' | head -1 | sed -e 's/.*"\(.*\)"/\1/' -e 's/\r//g' | xargs); if [[ -z "$remote_version" ]]; then err "无法从远程脚本解析版本号。"; return 1; fi
    local local_version=$(grep 'SCRIPT_VERSION=' "$0" | head -1 | sed -e 's/.*"\(.*\)"/\1/' -e 's/\r//g' | xargs); info "远程版本: ${remote_version}"
    if [[ -z "$local_version" ]]; then
        warn "无法检测到当前脚本的本地版本号。"; read -rp "是否要强制更新到最新版本 (${remote_version})? (Y/n): " yn
        if [[ "$yn" =~ ^[Nn]$ ]]; then info "已取消更新。"; return; fi
    else
        info "本地版本: ${local_version}"; local highest_version; highest_version=$(printf '%s\n%s' "$local_version" "$remote_version" | sort -V | tail -n 1)
        if [[ "$highest_version" == "$local_version" && "$local_version" != "$remote_version" ]]; then success "您的脚本版本高于远程版本，无需降级。"; return;
        elif [[ "$local_version" == "$remote_version" ]]; then success "您的脚本已是最新版本。"; return; fi
        warn "发现新版本 (${remote_version})！"; read -rp "是否立即更新? (Y/n): " yn
        if [[ "$yn" =~ ^[Nn]$ ]]; then info "已取消更新。"; return; fi
    fi
    info "正在下载最新脚本..."; if curl ${curl_opts} -o "$0.tmp" "$successful_url" && mv "$0.tmp" "$0"; then chmod +x "$0"; success "脚本更新成功！"; info "脚本将在2秒后自动重新启动以应用更新..."; sleep 2; exec bash "$0" "$@"; else err "下载最新脚本失败！"; rm -f "$0.tmp"; fi
}
show_start_message() { check_and_install_deps "curl" || return 1; info "正在获取公网IP地址..."; local public_ip; public_ip=$(curl -s --connect-timeout 5 ip.sb); if [[ -z "$public_ip" ]]; then public_ip=$(curl -s --connect-timeout 5 ifconfig.me); fi; echo -e "${GREEN}--------------------------------------------------${NC}"; echo -e "${YELLOW}酒馆已启动！请通过以下地址访问：${NC}"; echo -e "${WHITE}  - 本地访问: ${GREEN}http://127.0.0.1:8000${NC}"; if [[ -n "$public_ip" ]]; then echo -e "${WHITE}  - 公网访问: ${GREEN}http://${public_ip}:8000${NC} (需放行端口)"; else warn "  - 未能获取到公网IP，请手动查询。"; fi; echo -e "${GREEN}--------------------------------------------------${NC}"; }
rotate_backups() {
    info "正在检查并轮替备份..."
    mkdir -p "$BACKUP_PARENT_DIR"
    local backups=($(ls -dt "$BACKUP_PARENT_DIR"/sillytavern_backup_* 2>/dev/null))
    local num_backups=${#backups[@]}
    local max_backups=5
    if (( num_backups > max_backups )); then
        local to_delete_count=$((num_backups - max_backups))
        warn "备份数量 ($num_backups) 超出限制 ($max_backups)，将删除 $to_delete_count 个最旧的备份。"
        local backups_to_delete=("${backups[@]:max_backups}")
        local all_deleted_successfully=true
        for backup_path in "${backups_to_delete[@]}"; do
            info "正在删除旧备份: $(basename "$backup_path")"
            if ! rm -rf "$backup_path"; then
                if _request_sudo_privileges; then
                    if ! $SUDO_CMD rm -rf "$backup_path"; then
                        err "使用 sudo 删除备份 '$(basename "$backup_path")' 仍然失败。"
                        all_deleted_successfully=false
                    fi
                else
                    err "无法获取sudo权限，删除备份 '$(basename "$backup_path")' 失败。"
                    all_deleted_successfully=false
                fi
            fi
        done
        if [[ "$all_deleted_successfully" == true ]]; then success "备份轮替完成。"; else err "部分旧备份未能成功删除，请检查以上错误信息。"; fi
    else
        info "备份数量 ($num_backups) 未超出限制，无需轮替。"
    fi
}
_create_backup_instance() {
    [[ ! -d "$ST_DIR" ]] && { err "SillyTavern目录不存在，无法创建备份。"; return 1; }
    check_and_install_deps "jq" || return 1
    local backup_dir="$BACKUP_PARENT_DIR/sillytavern_backup_$(date +%Y%m%d_%H%M%S)"
    info "正在创建备份到: $(basename "$backup_dir")"
    if ! mkdir -p "$backup_dir"; then
        if ! _request_sudo_privileges; then return 1; fi
        $SUDO_CMD mkdir -p "$backup_dir" || { err "使用 sudo 创建目录仍然失败。请检查系统配置。"; return 1; }
        local owner=${SUDO_USER:-$(logname)}; local group=${SUDO_GID:-$(id -gn "$owner")}
        info "修正备份文件权限归属给用户: $owner"; $SUDO_CMD chown -R "$owner:$group" "$backup_dir"
    fi
     info "正在复制 'public' 和 'data' 目录..."
    [ -d "$ST_DIR/public" ] && cp -rp "$ST_DIR/public" "$backup_dir/"
    [ -d "$ST_DIR/data" ] && cp -rp "$ST_DIR/data" "$backup_dir/"
    if [ ! -d "$backup_dir" ] || [ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]; then
        err "备份失败，创建的备份目录为空或不存在。"
        rm -rf "$backup_dir" 2>/dev/null
        if [[ -n "$SUDO_CMD" ]]; then $SUDO_CMD rm -rf "$backup_dir" 2>/dev/null; fi
        return 1
    fi
    success "备份创建成功！"; rotate_backups; return 0
}
uninstall_sillytavern() {
    check_and_install_deps "jq" || return 1; [[ "$(get_local_st_ver)" == "未安装" ]] && { err "SillyTavern 未安装。"; return; }
    warn "此操作将永久删除位于 '$ST_DIR' 的 SillyTavern 及其所有数据！"
    read -rp "如果您确定要删除，请输入 'DELETE' 并按回车: " confirm
    if [[ "$confirm" == "DELETE" ]]; then
        info "正在停止所有相关服务..."; screen -X -S "$SCREEN_NAME" quit 2>/dev/null
        if [[ -f "$SERVICE_FILE" ]]; then
            if ! _request_sudo_privileges; then err "无法获取sudo权限，无法停止或禁用systemd服务。"; else
                $SUDO_CMD systemctl stop "$SERVICE_NAME" 2>/dev/null; $SUDO_CMD systemctl disable "$SERVICE_NAME" 2>/dev/null
            fi
        fi
        info "正在删除 SillyTavern 目录: $ST_DIR"; rm -rf "$ST_DIR"; info "正在清理相关服务文件..."
        if [[ -f "$SERVICE_FILE" ]]; then if _request_sudo_privileges; then $SUDO_CMD rm -f "$SERVICE_FILE"; $SUDO_CMD systemctl daemon-reload; fi; fi
        success "SillyTavern 已被彻底卸载。"
    else info "操作已取消。"; fi
}
start_menu() {
    check_and_install_deps "screen" "jq" || return 1
    [[ "$(get_local_st_ver)" == "未安装" ]] && { err "请先安装SillyTavern。"; return; }
    local screen_is_running=false; screen -list | grep -q "\.$SCREEN_NAME" && screen_is_running=true
    local service_exists=false; [[ -f "$SERVICE_FILE" ]] && service_exists=true
    local service_enabled=false; [[ "$service_exists" == true ]] && systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null && service_enabled=true
    clear; echo -e "${CYAN}--- 启动管理 ---${NC}"
    echo -e "  ${GREEN}1)${NC} 前台启动\n  ${GREEN}2)${NC} 启动 Screen 后台服务\n  ${GREEN}3)${NC} 查看 Screen 日志\n  ${RED}4)${NC} 停止 Screen 服务\n"
    echo -e "${CYAN}--- 开机自启管理 ---${NC}"
    if [[ "$service_enabled" == true ]]; then echo -e "  ${RED}5)${NC} 取消开机自启"; else echo -e "  ${GREEN}5)${NC} 设置开机自启"; fi
    echo -e "  ${BLUE}6)${NC} 查看 Systemd 日志\n\n  ${WHITE}0)${NC} 返回主菜单"
    read -rp "请选择操作: " choice
    case "$choice" in
        1) show_start_message; info "启动 SillyTavern (前台)..."; warn "按 Ctrl+C 停止。"; (cd "$ST_DIR" && bash ./start.sh);;
        2) if [[ "$screen_is_running" == true ]]; then err "Screen服务已在运行。"; else info "正在后台启动..."; screen -dmS "$SCREEN_NAME" bash -c "cd '$ST_DIR' && bash ./start.sh"; sleep 1; if screen -list | grep -q "\.$SCREEN_NAME"; then success "Screen服务已启动。"; show_start_message; else err "Screen服务启动失败。"; fi; fi;;
        3) if [[ "$screen_is_running" == true ]]; then info "正在附加... Ctrl+A, D 分离。"; screen -r "$SCREEN_NAME"; else err "Screen服务未运行。"; fi;;
        4) if [[ "$screen_is_running" == true ]]; then info "正在停止后台服务..."; screen -X -S "$SCREEN_NAME" quit; success "Screen服务已停止。"; else err "Screen服务未运行。"; fi;;
        5 | 6)
            if [[ -n "$TERMUX_VERSION" ]]; then err "此功能不适用于 Termux。"; return; fi
            if ! _request_sudo_privileges; then return 1; fi
            case "$choice" in
                5)
                    if [[ "$service_enabled" == true ]]; then
                        info "正在取消开机自启并停止服务..."; $SUDO_CMD systemctl disable "$SERVICE_NAME" && $SUDO_CMD systemctl stop "$SERVICE_NAME"
                        success "服务已取消开机自启并停止。"
                    else
                        info "正在设置开机自启并启动服务..."
                        if ! command -v node &>/dev/null; then 
                           err "无法找到'node'命令。请先运行安装/更新选项。"
                           return 1
                        fi
                        local node_path=$(command -v node)
                        local node_dir=$(dirname "$node_path")
                        cat <<EOF | $SUDO_CMD tee "$SERVICE_FILE" > /dev/null
[Unit]
Description=SillyTavern Service for installation at $ST_DIR
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=${SUDO_USER:-$(logname)}
WorkingDirectory=$ST_DIR
Environment="PATH=${node_dir}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/bin/bash $ST_DIR/start.sh
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
                        $SUDO_CMD systemctl daemon-reload; $SUDO_CMD systemctl enable "$SERVICE_NAME" && $SUDO_CMD systemctl start "$SERVICE_NAME"
                        info "正在验证服务状态..."; sleep 3
                        if $SUDO_CMD systemctl is-active --quiet "$SERVICE_NAME"; then success "服务已设为开机自启并成功启动。"; show_start_message; else err "服务注册成功，但启动失败！"; info "请使用选项 6 查看日志进行诊断。"; fi
                    fi
                    ;;
                6)
                    if [[ ! -f "$SERVICE_FILE" ]]; then err "Systemd服务尚未创建。"; else
                        info "正在显示最新的200条Systemd日志..."; $SUDO_CMD journalctl -u "$SERVICE_NAME" -n 200 --no-pager
                        info "日志显示完毕。"
                    fi
                    ;;
            esac
            ;;
        0) return ;;
        *) err "无效选项" ;;
    esac
}
backup_menu() {
    while true; do
        clear; echo -e "${CYAN}--- 备份管理 ---${NC}"
        echo -e "${WHITE}备份存储路径: ${CYAN}$BACKUP_PARENT_DIR${NC}"; echo -e "${CYAN}--------------------------------------------------${NC}"
        echo -e "  ${GREEN}1)${NC} 查看所有备份\n  ${GREEN}2)${NC} 手动创建新备份\n  ${YELLOW}3)${NC} 从备份恢复\n  ${RED}4)${NC} 删除指定备份\n\n  ${WHITE}0)${NC} 返回主菜单"
        read -rp "请选择操作 [0-4]: " choice
        case "$choice" in
            1) info "当前所有备份:"; if [ -d "$BACKUP_PARENT_DIR" ] && [ -n "$(ls -A "$BACKUP_PARENT_DIR" 2>/dev/null)" ]; then ls -1 --color=never "$BACKUP_PARENT_DIR" | grep "sillytavern_backup_" | sed 's/^/  - /'; else warn "没有找到任何备份。"; fi ;;
            2) _create_backup_instance ;;
            3) local backups=($(ls -dt "$BACKUP_PARENT_DIR"/sillytavern_backup_* 2>/dev/null)); if (( ${#backups[@]} == 0 )); then err "没有可用的备份来恢复。"; else
                   info "请选择要恢复的备份:"; for i in "${!backups[@]}"; do echo -e "  ${GREEN}$((i+1)))${NC} $(basename "${backups[i]}")"; done
                   read -rp "请输入编号 [1-${#backups[@]}] 或输入0取消: " r_choice
                   if [[ "$r_choice" =~ ^[1-9][0-9]*$ && "$r_choice" -le ${#backups[@]} ]]; then local chosen_backup="${backups[$((r_choice-1))]}"; warn "这将覆盖当前的 public 和 data 目录！此操作不可逆！"; read -rp "确定要从 '$(basename "$chosen_backup")' 恢复吗? (Y/n): " confirm
                       if [[ ! "$confirm" =~ ^[Nn]$ ]]; then info "正在停止所有服务..."; screen -X -S "$SCREEN_NAME" quit 2>/dev/null; if _request_sudo_privileges; then $SUDO_CMD systemctl stop "$SERVICE_NAME" 2>/dev/null; fi; info "正在恢复文件..."; rm -rf "$ST_DIR/public" "$ST_DIR/data"; cp -rp "$chosen_backup/public" "$ST_DIR/" 2>/dev/null; cp -rp "$chosen_backup/data" "$ST_DIR/" 2>/dev/null; success "恢复完成！请手动重启服务。"; else info "恢复操作已取消。"; fi
                   else info "无效选择或已取消。"; fi
               fi ;;
            4) local backups=($(ls -dt "$BACKUP_PARENT_DIR"/sillytavern_backup_* 2>/dev/null)); if (( ${#backups[@]} == 0 )); then err "没有可用的备份来删除。"; else
                   info "请选择要删除的备份:"; for i in "${!backups[@]}"; do echo -e "  ${GREEN}$((i+1)))${NC} $(basename "${backups[i]}")"; done
                   read -rp "请输入编号 [1-${#backups[@]}] 或输入0取消: " d_choice
                   if [[ "$d_choice" =~ ^[1-9][0-9]*$ && "$d_choice" -le ${#backups[@]} ]]; then local chosen_backup="${backups[$((d_choice-1))]}"; read -rp "确定要永久删除备份 '$(basename "$chosen_backup")'? (Y/n): " confirm
                       if [[ ! "$confirm" =~ ^[Nn]$ ]]; then info "正在删除..."; rm -rf "$chosen_backup"; success "备份已删除。"; else info "删除操作已取消。"; fi
                   else info "无效选择或已取消。"; fi
               fi ;;
            0) return ;;
            *) err "无效选项" ;;
        esac
        echo ""; read -n1 -s -r -p "按任意键返回..."
    done
}


# ==============================================================================
# ==================== [核心修改] 新增的启动预检与主菜单 ====================
# ==============================================================================

initial_setup_check() {
    info "正在进行环境预检..."
    local deps_ok=true
    local essential_deps=("git" "curl" "jq" "screen")

    # 检查基础依赖
    for dep in "${essential_deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            deps_ok=false
            break
        fi
    done

    # 检查Node.js版本
    if [[ "$deps_ok" == true ]]; then
        if command -v node &>/dev/null; then
            local major_version=$(node -v | sed 's/v//' | cut -d'.' -f1)
            if [[ "$major_version" -lt 18 ]]; then
                deps_ok=false
            fi
        else
            deps_ok=false
        fi
    fi

    if [[ "$deps_ok" == true ]]; then
        success "环境完整，无需初始化。"
        return 0
    fi

    # 如果环境不完整，则执行初始化流程
    echo
    warn "首次运行或环境不完整，需要进行初始化设置。"
    info "此过程将安装或更新运行本脚本及SillyTavern所需的核心组件。"
    echo

    # 1. 询问代理设置
    handle_proxy_logic "interactive"

    # 2. 安装/更新Node.js
    install_or_update_nodejs || { err "Node.js 环境配置失败，无法继续。"; exit 1; }

    # 3. 安装其他依赖
    check_and_install_deps "${essential_deps[@]}" || { err "基础依赖安装失败，无法继续。"; exit 1; }
    
    echo
    success "所有依赖已配置完毕！"
    info "正在进入主菜单..."
    sleep 2
}

main_menu() {
    while true; do
        # [修改] 移除了这里的后台依赖检查
        local st_ver; st_ver=$(get_local_st_ver); local st_status=""; [[ "$st_ver" != "未安装" ]] && st_status=$(check_st_running);
        clear; echo -e "${CYAN}==================================================${NC}"
        echo -e "${WHITE}\n    ___    __ __ ___    _   ________\n   /   |  / //_//   |  / | / / ____/\n  / /| | / ,<  / /| | /  |/ / **/   \n / | |/ /| |/   |/ /|  / /**_   \n/_/  |_/_/ |_/_/  |_/_/ |_/_____/   \n${WHITE}           SillyTavern酒馆管理脚本            ${NC}"
        echo -e "                                     ${CYAN}v${SCRIPT_VERSION}${NC}\n${WHITE}作者：${AUTHOR}            更新日期:${UPDATE_DATE}${NC}\n${WHITE}${CONTACT_INFO_LINE1}${NC}\n${WHITE}${CONTACT_INFO_LINE2}${NC}"
        echo -e "${CYAN}==================================================${NC}"
        if [[ "$st_ver" != "未安装" ]]; then echo -e "${WHITE}酒馆目录: ${CYAN}$ST_DIR${NC}"; fi
        echo -e "${WHITE}SillyTavern 状态: ${GREEN}${st_ver}${NC} ${st_status}"; echo -e "${WHITE}GitHub 代理模式 : $(if [[ "$PROXY_ENABLED" == true ]]; then echo -e "${GREEN}开启${NC}"; else echo -e "${RED}关闭${NC}"; fi)"
        echo -e "${CYAN}--------------------------------------------------${NC}\n  ${GREEN}1)${NC} 安装 / 更新\n  ${GREEN}2)${NC} 启动 / 停止 / 管理\n  ${BLUE}3)${NC} 备份管理\n  ${YELLOW}4)${NC} 代理设置\n  ${RED}5)${NC} 卸载SillyTavern\n\n  ${CYAN}9)${NC} 检查脚本更新\n  ${WHITE}0)${NC} 退出\n${CYAN}==================================================${NC}"
        read -rp "请选择操作 [0-9]: " opt
        case "$opt" in
            1) manage_sillytavern ;; 2) start_menu ;; 3) backup_menu ;; 4) handle_proxy_logic "interactive" ;;
            5) uninstall_sillytavern ;; 9) update_script ;; 0) exit 0 ;; *) err "无效选项，请重试。" ;;
        esac
        if [[ "$opt" != "0" ]]; then echo ""; read -n1 -s -r -p "按任意键返回主菜单..."; fi
    done
}

# ==================== [核心修改] 调整启动顺序 ====================
# 1. 首先执行环境预检和自动安装
initial_setup_check

# 2. 然后进入主菜单循环
main_menu
