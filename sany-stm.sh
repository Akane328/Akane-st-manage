#!/bin/bash

# SillyTavern Manager (STM)
# 酒馆管理脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# 脚本信息
SCRIPT_VERSION="1.1.4"
AUTHOR="Akane"
GROUP_ID="1067487432"
ST_INSTALL_DIR="$HOME/SillyTavern"
ST_PORT=8000
ST_SCREEN_NAME="SillyTavern"
ST_LOG_FILE="$HOME/.sillytavern.log"
SCRIPT_REPO_URL="https://raw.githubusercontent.com/Akane328/Akane-st-manage/main/sany-stm.sh"

# 确保当前工作目录有效（防止从已删除目录启动导致 uv_cwd 错误）
cd "$HOME" 2>/dev/null || cd / 2>/dev/null

# 确保 screen socket 目录可用（修复 WSL 等环境下 /run/screen 权限问题）
if [ ! -w "${SCREENDIR:-/run/screen}" ] 2>/dev/null; then
    export SCREENDIR="$HOME/.screen"
    mkdir -p "$SCREENDIR" && chmod 700 "$SCREENDIR"
fi

# 获取当前脚本的真实绝对路径
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# ============================================================
# 环境检测辅助函数
# ============================================================

# 检测是否在 Termux 环境下
is_termux() {
    [ -n "$TERMUX_VERSION" ] || [[ "${PREFIX:-}" == *"com.termux"* ]]
}

# 注册 tavern 快捷命令（脚本启动时自动注册）
register_tavern_command() {
    # 已经注册过则跳过
    if command -v tavern > /dev/null 2>&1; then
        return 0
    fi

    if is_termux; then
        local bin_dir="$PREFIX/bin"
    else
        local bin_dir="$HOME/.local/bin"
        mkdir -p "$bin_dir"
        if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
            local shell_rc=""
            if [ -f "$HOME/.bashrc" ]; then
                shell_rc="$HOME/.bashrc"
            elif [ -f "$HOME/.zshrc" ]; then
                shell_rc="$HOME/.zshrc"
            fi
            if [ -n "$shell_rc" ] && ! grep -q 'local/bin' "$shell_rc" 2>/dev/null; then
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$shell_rc"
            fi
            export PATH="$bin_dir:$PATH"
        fi
    fi

    ln -sf "$SCRIPT_PATH" "$bin_dir/tavern" 2>/dev/null

    if [ -L "$bin_dir/tavern" ]; then
        echo -e "  ${GREEN}  ✓ 已注册快捷命令: ${CYAN}tavern${NC}"
        echo -e "  ${GRAY}    下次可直接输入 tavern 启动管理脚本${NC}"
        echo ""
    fi
}

# 脚本启动时静默注册
register_tavern_command

# 确保 screen 已安装，未安装则自动安装
ensure_screen() {
    if command -v screen > /dev/null 2>&1; then
        return 0
    fi

    echo -e "  ${CYAN}  screen 未安装，正在自动安装...${NC}"

    if is_termux; then
        if run_with_spinner "安装 screen" pkg install -y screen; then
            echo -e "  ${GREEN}  ✓ screen 安装成功${NC}"
            return 0
        fi
    elif command -v apt-get > /dev/null 2>&1; then
        if run_with_spinner "安装 screen" sudo apt-get install -y screen; then
            echo -e "  ${GREEN}  ✓ screen 安装成功${NC}"
            return 0
        fi
    elif command -v yum > /dev/null 2>&1; then
        if run_with_spinner "安装 screen" sudo yum install -y screen; then
            echo -e "  ${GREEN}  ✓ screen 安装成功${NC}"
            return 0
        fi
    elif command -v pacman > /dev/null 2>&1; then
        if run_with_spinner "安装 screen" sudo pacman -S --noconfirm screen; then
            echo -e "  ${GREEN}  ✓ screen 安装成功${NC}"
            return 0
        fi
    fi

    echo -e "  ${RED}  ✗ screen 安装失败，请手动安装${NC}"
    return 1
}

# 确保 git 已安装，未安装则自动安装
ensure_git() {
    if command -v git > /dev/null 2>&1; then
        return 0
    fi

    echo -e "  ${CYAN}  git 未安装，正在自动安装...${NC}"

    if is_termux; then
        if run_with_spinner "安装 git" pkg install -y git; then
            echo -e "  ${GREEN}  ✓ git 安装成功${NC}"
            return 0
        fi
    elif command -v apt-get > /dev/null 2>&1; then
        if run_with_spinner "安装 git" sudo apt-get install -y git; then
            echo -e "  ${GREEN}  ✓ git 安装成功${NC}"
            return 0
        fi
    elif command -v yum > /dev/null 2>&1; then
        if run_with_spinner "安装 git" sudo yum install -y git; then
            echo -e "  ${GREEN}  ✓ git 安装成功${NC}"
            return 0
        fi
    elif command -v pacman > /dev/null 2>&1; then
        if run_with_spinner "安装 git" sudo pacman -S --noconfirm git; then
            echo -e "  ${GREEN}  ✓ git 安装成功${NC}"
            return 0
        fi
    fi

    echo -e "  ${RED}  ✗ git 安装失败，请手动安装${NC}"
    return 1
}

# ============================================================
# 进度显示工具函数
# ============================================================

# 旋转动画执行命令（用于无法预估总量的操作）
# 用法: run_with_spinner "提示文字" command args...
# 返回值: 命令的退出码
run_with_spinner() {
    local msg="$1"
    shift

    local tmp_out
    tmp_out=$(mktemp)
    local spinner_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local spin_len=${#spinner_chars}

    # 后台执行命令
    "$@" > "$tmp_out" 2>&1 &
    local cmd_pid=$!
    local start_time=$SECONDS
    local i=0

    # 前台显示旋转动画
    while kill -0 "$cmd_pid" 2>/dev/null; do
        local elapsed=$(( SECONDS - start_time ))
        local min=$((elapsed / 60))
        local sec=$((elapsed % 60))
        local time_str
        if [ "$min" -gt 0 ]; then
            time_str="${min}m${sec}s"
        else
            time_str="${sec}s"
        fi
        local char="${spinner_chars:$((i % spin_len)):1}"
        printf "\r  ${CYAN}  %s${NC} %s ${GRAY}(%s)${NC}  " "$char" "$msg" "$time_str"
        i=$((i + 1))
        sleep 0.1
    done

    # 获取退出码
    wait "$cmd_pid"
    local exit_code=$?

    # 清除动画行
    printf "\r\033[K"

    if [ $exit_code -ne 0 ]; then
        # 失败时显示最后几行输出
        echo -e "  ${RED}  ✗ ${msg} 失败${NC}"
        tail -3 "$tmp_out" | sed 's/^/    /'
    fi

    rm -f "$tmp_out"
    return $exit_code
}

# 带进度条执行 git 命令（解析 git 的 progress 输出显示百分比进度条 + 速度）
# 用法: run_git_with_progress "提示文字" git_command args...
run_git_with_progress() {
    local msg="$1"
    shift

    local tmp_out
    tmp_out=$(mktemp)
    local tmp_err
    tmp_err=$(mktemp)

    # 后台执行 git 命令，stderr 包含进度信息
    "$@" --progress > "$tmp_out" 2>"$tmp_err" &
    local cmd_pid=$!

    # 解析 git 进度输出
    while kill -0 "$cmd_pid" 2>/dev/null; do
        # 从 stderr 读取最新进度（git 用 \r 覆盖行）
        local last_line
        last_line=$(tail -c 300 "$tmp_err" 2>/dev/null | tr '\r' '\n' | tail -1)

        local percent=""
        percent=$(echo "$last_line" | grep -oE '[0-9]+%' | tail -1)

        if [ -n "$percent" ]; then
            local pct="${percent%\%}"

            # 提取 git 输出中的速度信息（如 1.20 MiB/s）
            local speed=""
            speed=$(echo "$last_line" | grep -oE '[0-9]+(\.[0-9]+)? [KMG]iB/s' | tail -1)

            # 绘制进度条
            local bar_width=20
            local filled=$((pct * bar_width / 100))
            local empty=$((bar_width - filled))
            local bar=""
            for ((bi=0; bi<filled; bi++)); do bar+="█"; done
            for ((bi=0; bi<empty; bi++)); do bar+="░"; done

            # 获取当前阶段名
            local stage
            stage=$(echo "$last_line" | grep -oE '(Cloning|Counting|Compressing|Receiving|Resolving|Updating|Enumerating)[^:]*' | tail -1)
            [ -z "$stage" ] && stage="$msg"

            local speed_str=""
            [ -n "$speed" ] && speed_str="($speed)"

            printf "\r  ${CYAN}  [%s] %3d%%${NC} ${GRAY}%s %s${NC}  " "$bar" "$pct" "$stage" "$speed_str"
        else
            # 还没有百分比输出，显示旋转动画
            local spinner_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
            local elapsed=$(( SECONDS - start_time ))
            local idx=$(( elapsed % 10 ))
            local char="${spinner_chars:$idx:1}"
            printf "\r  ${CYAN}  %s${NC} %s...  " "$char" "$msg"
        fi
        sleep 0.3
    done

    wait "$cmd_pid"
    local exit_code=$?

    printf "\r\033[K"

    if [ $exit_code -ne 0 ]; then
        echo -e "  ${RED}  ✗ ${msg} 失败${NC}"
        tail -3 "$tmp_err" | sed 's/^/    /'
    fi

    rm -f "$tmp_out" "$tmp_err"
    return $exit_code
}

# 绘制进度条
# 用法: draw_progress_bar current total "提示文字"
draw_progress_bar() {
    local current="$1"
    local total="$2"
    local msg="$3"
    local bar_width=20

    if [ "$total" -le 0 ]; then
        return
    fi

    local percent=$((current * 100 / total))
    [ "$percent" -gt 100 ] && percent=100
    local filled=$((percent * bar_width / 100))
    local empty=$((bar_width - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    printf "\r  ${CYAN}  [%s] %3d%%${NC} ${GRAY}(%d/%d) %s${NC}  " "$bar" "$percent" "$current" "$total" "$msg"
}

# 带进度条的 tar 压缩
# 用法: tar_compress_with_progress "提示文字" archive_path source_dir dir1 [dir2...]
tar_compress_with_progress() {
    local msg="$1"
    local archive="$2"
    local source_dir="$3"
    shift 3
    local -a dirs=("$@")

    # 计算文件总数
    local total=0
    for d in "${dirs[@]}"; do
        local count
        count=$(find "$source_dir/$d" 2>/dev/null | wc -l)
        total=$((total + count))
    done

    if [ "$total" -eq 0 ]; then
        tar -czf "$archive" -C "$source_dir" "${dirs[@]}" 2>/dev/null
        return $?
    fi

    # 使用 verbose 模式，输出到 stdout 用于计数
    local current=0
    tar -cvzf "$archive" -C "$source_dir" "${dirs[@]}" 2>/dev/null | \
    while IFS= read -r _line; do
        current=$((current + 1))
        if (( current % 10 == 0 )) || [ "$current" -eq "$total" ]; then
            draw_progress_bar "$current" "$total" "$msg"
        fi
    done

    printf "\r\033[K"
    [ -f "$archive" ]
    return $?
}

# 带进度条的 tar 解压
# 用法: tar_extract_with_progress "提示文字" archive_path dest_dir
tar_extract_with_progress() {
    local msg="$1"
    local archive="$2"
    local dest_dir="$3"

    # 计算压缩包内条目总数
    local total
    total=$(tar -tzf "$archive" 2>/dev/null | wc -l)

    if [ "$total" -eq 0 ]; then
        tar -xzf "$archive" -C "$dest_dir" 2>/dev/null
        return $?
    fi

    # verbose 解压并计数
    local current=0
    tar -xvzf "$archive" -C "$dest_dir" 2>/dev/null | \
    while IFS= read -r _line; do
        current=$((current + 1))
        if (( current % 10 == 0 )) || [ "$current" -eq "$total" ]; then
            draw_progress_bar "$current" "$total" "$msg"
        fi
    done

    printf "\r\033[K"
    return 0
}

# ============================================================
# 镜像测速与环境安装
# ============================================================

# 通用镜像测速函数（并行测速，支持延迟/吞吐量两种模式）
# 用法: speed_test_mirrors [-t] "name1" "url1" "name2" "url2" ...
#   -t: 吞吐量模式 — 实际下载测速（KB/s），适合选择 git clone 等大文件下载源
#   默认: 延迟模式 — 测量 HTTP 首字节时间（ms），适合选择 API/npm 镜像
# 输出: 最快镜像的名称（stdout），测速过程打印到 stderr
# 返回值: 0=成功找到可用镜像, 1=全部超时
speed_test_mirrors() {
    local mode="latency"
    if [ "$1" = "-t" ]; then
        mode="throughput"
        shift
    fi

    local -a names=()
    local -a urls=()

    # 解析参数
    while [ $# -ge 2 ]; do
        names+=("$1")
        urls+=("$2")
        shift 2
    done

    if [ "$mode" = "throughput" ]; then
        echo -e "\n  ${CYAN}正在测速选择最快的下载源（实际下载测速）...${NC}" >&2
    else
        echo -e "\n  ${CYAN}正在测速选择最快的镜像源...${NC}" >&2
    fi

    # 创建临时目录存放并行测速结果
    local tmpdir
    tmpdir=$(mktemp -d)

    # 并行启动所有测速任务
    for i in "${!names[@]}"; do
        (
            local name="${names[$i]}"
            local url="${urls[$i]}"

            if [ "$mode" = "throughput" ]; then
                # 吞吐量模式：实际下载最多 8 秒，测量平均下载速度
                local stats
                stats=$(curl -o /dev/null -s -w '%{speed_download}\t%{http_code}\t%{size_download}' \
                    -L --connect-timeout 5 --max-time 8 "$url" 2>/dev/null)
                local speed http_code size
                speed=$(echo "$stats" | cut -f1)
                http_code=$(echo "$stats" | cut -f2)
                size=$(echo "$stats" | cut -f3)

                # 校验：HTTP 2xx/3xx 且下载速度 > 0
                if echo "$http_code" | grep -qE '^[23]' && \
                   awk "BEGIN{exit ($speed > 0) ? 0 : 1}" 2>/dev/null; then
                    echo "ok $speed $name" > "$tmpdir/result_$i"
                else
                    echo "fail 0 $name" > "$tmpdir/result_$i"
                fi
            else
                # 延迟模式：测量首字节到达时间（TTFB）
                local stats
                stats=$(curl -o /dev/null -s -w '%{time_starttransfer}\t%{http_code}' \
                    -L --connect-timeout 5 --max-time 10 "$url" 2>/dev/null)
                local time_s http_code
                time_s=$(echo "$stats" | cut -f1)
                http_code=$(echo "$stats" | cut -f2)
                local time_ms
                time_ms=$(awk "BEGIN{printf \"%.0f\", $time_s * 1000}" 2>/dev/null)

                if echo "$http_code" | grep -qE '^[23]' && [ "${time_ms:-0}" -gt 0 ] 2>/dev/null; then
                    echo "ok $time_ms $name" > "$tmpdir/result_$i"
                else
                    echo "fail 999999 $name" > "$tmpdir/result_$i"
                fi
            fi
        ) &
    done

    # 等待所有并行任务完成
    wait

    # 收集结果并显示
    local best_name=""

    if [ "$mode" = "throughput" ]; then
        local best_speed=0
        for i in "${!names[@]}"; do
            if [ -f "$tmpdir/result_$i" ]; then
                local status speed name
                read -r status speed name < "$tmpdir/result_$i"
                if [ "$status" = "ok" ]; then
                    # 格式化显示速度
                    local display_speed
                    display_speed=$(awk "BEGIN{
                        s = $speed;
                        if (s >= 1048576) printf \"%.1f MB/s\", s/1048576;
                        else if (s >= 1024) printf \"%.0f KB/s\", s/1024;
                        else printf \"%.0f B/s\", s
                    }" 2>/dev/null)
                    printf "    ${GREEN}[%-12s] ✓ %s${NC}\n" "$name" "$display_speed" >&2
                    if awk "BEGIN{exit ($speed > $best_speed) ? 0 : 1}" 2>/dev/null; then
                        best_speed="$speed"
                        best_name="$name"
                    fi
                else
                    printf "    ${RED}[%-12s] ✗ 失败${NC}\n" "$name" >&2
                fi
            fi
        done

        if [ -n "$best_name" ]; then
            local best_display
            best_display=$(awk "BEGIN{
                s = $best_speed;
                if (s >= 1048576) printf \"%.1f MB/s\", s/1048576;
                else if (s >= 1024) printf \"%.0f KB/s\", s/1024;
                else printf \"%.0f B/s\", s
            }" 2>/dev/null)
            echo -e "    ${GREEN}→ 选择: ${best_name} (${best_display})${NC}\n" >&2
        fi
    else
        local best_ms=999999
        for i in "${!names[@]}"; do
            if [ -f "$tmpdir/result_$i" ]; then
                local status ms name
                read -r status ms name < "$tmpdir/result_$i"
                if [ "$status" = "ok" ]; then
                    printf "    ${GREEN}[%-12s] ✓ %dms${NC}\n" "$name" "$ms" >&2
                    if [ "$ms" -lt "$best_ms" ]; then
                        best_ms="$ms"
                        best_name="$name"
                    fi
                else
                    printf "    ${RED}[%-12s] ✗ 超时${NC}\n" "$name" >&2
                fi
            fi
        done

        if [ -n "$best_name" ]; then
            echo -e "    ${GREEN}→ 选择: ${best_name} (${best_ms}ms)${NC}\n" >&2
        fi
    fi

    # 清理临时文件
    rm -rf "$tmpdir"

    if [ -z "$best_name" ]; then
        echo -e "  ${RED}所有镜像源均不可用${NC}" >&2
        return 1
    fi

    echo "$best_name"
    return 0
}

# 检测 Node.js 环境
# 返回值: 0=环境就绪, 1=安装失败
check_nodejs() {
    echo -e "\n  ${CYAN}[环境检测] 检查 Node.js...${NC}"

    if command -v node > /dev/null 2>&1; then
        local node_version
        node_version=$(node -v | sed 's/v//')
        local major_version
        major_version=$(echo "$node_version" | cut -d. -f1)

        if [ "$major_version" -ge 18 ]; then
            echo -e "  ${GREEN}  ✓ Node.js v${node_version} 已安装，版本满足要求${NC}"
            return 0
        else
            echo -e "  ${YELLOW}  Node.js v${node_version} 版本过低（需要 >= 18）${NC}"
        fi
    else
        echo -e "  ${YELLOW}  未检测到 Node.js${NC}"
    fi

    install_nodejs
    return $?
}

# 安装 Node.js
# Termux 环境使用 pkg 安装（nvm 下载的官方二进制不兼容 Android Bionic libc）
# 其他环境通过 nvm 安装
install_nodejs() {
    if is_termux; then
        install_nodejs_termux
    else
        install_nodejs_nvm
    fi
    return $?
}

# Termux 环境：通过 pkg 安装 Node.js
install_nodejs_termux() {
    echo -e "\n  ${CYAN}[环境安装] 通过 pkg 安装 Node.js...${NC}"

    if run_with_spinner "安装 Node.js" pkg install -y nodejs-lts; then
        if command -v node > /dev/null 2>&1; then
            local installed_version
            installed_version=$(node -v)
            echo -e "  ${GREEN}  ✓ Node.js ${installed_version} 安装成功${NC}"
            return 0
        fi
    fi

    echo -e "  ${RED}  ✗ Node.js 安装失败${NC}"
    return 1
}

# 非 Termux 环境：通过 nvm 安装 Node.js
install_nodejs_nvm() {
    echo -e "\n  ${CYAN}[环境安装] 准备通过 nvm 安装 Node.js...${NC}"

    # 检查 nvm 是否已安装
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    local nvm_installed=false

    if [ -s "$NVM_DIR/nvm.sh" ]; then
        source "$NVM_DIR/nvm.sh"
        if command -v nvm > /dev/null 2>&1; then
            nvm_installed=true
            echo -e "  ${GREEN}  ✓ nvm 已安装${NC}"
        fi
    fi

    # 安装 nvm
    if [ "$nvm_installed" = false ]; then
        echo -e "  ${CYAN}  正在安装 nvm...${NC}"

        # 确保 profile 文件存在（nvm 安装脚本需要写入初始化代码）
        if [ ! -f "$HOME/.bashrc" ]; then
            touch "$HOME/.bashrc"
        fi

        # 测速选择 nvm 安装源
        local best_nvm_mirror
        best_nvm_mirror=$(speed_test_mirrors \
            "npmmirror" "https://npmmirror.com/mirrors/nvm/v0.40.1/install.sh" \
            "gitee" "https://gitee.com/mirrors/nvm/raw/master/install.sh" \
            "GitHub" "https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh"
        )

        if [ $? -ne 0 ]; then
            echo -e "  ${RED}  ✗ 无法访问任何 nvm 安装源${NC}"
            return 1
        fi

        # 根据最快镜像选择安装方式
        local install_url=""
        case "$best_nvm_mirror" in
            "npmmirror")
                install_url="https://npmmirror.com/mirrors/nvm/v0.40.1/install.sh"
                ;;
            "gitee")
                install_url="https://gitee.com/mirrors/nvm/raw/master/install.sh"
                ;;
            "GitHub")
                install_url="https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh"
                ;;
        esac

        echo -e "  ${CYAN}  从 ${best_nvm_mirror} 下载 nvm 安装脚本...${NC}"
        if ! curl -sSf --connect-timeout 30 --max-time 120 "$install_url" | bash 2>/dev/null; then
            echo -e "  ${RED}  ✗ nvm 安装失败${NC}"
            return 1
        fi

        # 加载 nvm
        export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
        if [ -s "$NVM_DIR/nvm.sh" ]; then
            source "$NVM_DIR/nvm.sh"
        else
            echo -e "  ${RED}  ✗ nvm 安装后无法加载${NC}"
            return 1
        fi

        echo -e "  ${GREEN}  ✓ nvm 安装成功${NC}"
    fi

    # 测速选择 Node.js 二进制下载镜像
    local best_node_mirror
    best_node_mirror=$(speed_test_mirrors \
        "npmmirror" "https://npmmirror.com/mirrors/node/index.json" \
        "官方" "https://nodejs.org/dist/index.json"
    )

    if [ "$best_node_mirror" = "npmmirror" ]; then
        export NVM_NODEJS_ORG_MIRROR="https://npmmirror.com/mirrors/node"
    else
        unset NVM_NODEJS_ORG_MIRROR
        best_node_mirror="官方"
    fi

    echo -e "  ${CYAN}  正在通过 nvm 安装 Node.js LTS...${NC}"
    echo -e "  ${GRAY}  (使用镜像: ${best_node_mirror})${NC}"

    if ! run_with_spinner "安装 Node.js LTS" nvm install --lts; then
        echo -e "  ${RED}  ✗ Node.js 安装失败${NC}"
        return 1
    fi

    nvm use --lts > /dev/null 2>&1

    # 验证安装
    if command -v node > /dev/null 2>&1; then
        local installed_version
        installed_version=$(node -v)
        echo -e "  ${GREEN}  ✓ Node.js ${installed_version} 安装成功${NC}"
        return 0
    else
        echo -e "  ${RED}  ✗ Node.js 安装验证失败${NC}"
        return 1
    fi
}

# 配置 npm 镜像源
setup_npm_mirror() {
    echo -e "\n  ${CYAN}[环境配置] 配置 npm 镜像源...${NC}"

    # 测速选择 npm registry
    local best_npm_mirror
    best_npm_mirror=$(speed_test_mirrors \
        "npmmirror" "https://registry.npmmirror.com/-/ping" \
        "华为云" "https://mirrors.huaweicloud.com/repository/npm/-/ping" \
        "官方" "https://registry.npmjs.org/-/ping"
    )

    if [ $? -ne 0 ]; then
        echo -e "  ${YELLOW}  测速失败，使用默认 npmmirror${NC}"
        best_npm_mirror="npmmirror"
    fi

    local registry_url=""
    case "$best_npm_mirror" in
        "npmmirror")
            registry_url="https://registry.npmmirror.com"
            ;;
        "华为云")
            registry_url="https://mirrors.huaweicloud.com/repository/npm/"
            ;;
        "官方")
            registry_url="https://registry.npmjs.org"
            ;;
    esac

    npm config set registry "$registry_url"
    echo -e "  ${GREEN}  ✓ npm 镜像已设置为 ${best_npm_mirror} (${registry_url})${NC}"
}

# 安装/更新 SillyTavern（入口函数）
install_or_update_st() {
    echo -e "\n  ${WHITE}── 安装 / 更新 SillyTavern ───────────────────${NC}"

    # 第一步：确保 Node.js 环境就绪
    if ! check_nodejs; then
        echo -e "\n  ${RED}Node.js 环境准备失败，无法继续安装${NC}"
        return 1
    fi

    # 确保 git 可用
    if ! ensure_git; then
        return 1
    fi

    # 第二步：配置 npm 镜像
    setup_npm_mirror

    # 第三步：安装酒馆
    echo -e "\n  ${GREEN}  ✓ 环境准备完成${NC}"

    if [ -d "$ST_INSTALL_DIR" ]; then
        echo -e "\n  ${CYAN}[更新] 正在更新 SillyTavern...${NC}"

        # 更新前自动备份
        echo -e "  ${CYAN}  更新前自动备份数据...${NC}"
        create_backup "auto-update"

        # 测速选择 git pull 源
        cd "$ST_INSTALL_DIR" || return 1
        local current_remote
        current_remote=$(git remote get-url origin 2>/dev/null)

        # 如果当前 remote 是代理地址，先测速选最快的再更新
        local best_pull_mirror
        best_pull_mirror=$(speed_test_mirrors -t \
            "gh-proxy" "https://gh-proxy.com/https://github.com/SillyTavern/SillyTavern/archive/refs/heads/release.tar.gz" \
            "ghps" "https://ghps.cc/https://github.com/SillyTavern/SillyTavern/archive/refs/heads/release.tar.gz" \
            "GitHub" "https://github.com/SillyTavern/SillyTavern/archive/refs/heads/release.tar.gz"
        )

        local pull_url=""
        case "$best_pull_mirror" in
            "gh-proxy") pull_url="https://gh-proxy.com/https://github.com/SillyTavern/SillyTavern.git" ;;
            "ghps") pull_url="https://ghps.cc/https://github.com/SillyTavern/SillyTavern.git" ;;
            *) pull_url="https://github.com/SillyTavern/SillyTavern.git" ;;
        esac

        git remote set-url origin "$pull_url" 2>/dev/null
        if ! run_git_with_progress "拉取更新" git pull; then
            echo -e "  ${RED}  ✗ 更新失败${NC}"
            return 1
        fi
        echo -e "  ${GREEN}  ✓ 代码更新完成${NC}"
    else
        echo -e "\n  ${CYAN}[安装] 正在安装 SillyTavern...${NC}"

        # 测速选择 git clone 源（吞吐量模式：实际下载测速）
        # 通过下载仓库压缩包测量真实下载带宽，而非仅测延迟
        local best_git_mirror
        best_git_mirror=$(speed_test_mirrors -t \
            "gh-proxy" "https://gh-proxy.com/https://github.com/SillyTavern/SillyTavern/archive/refs/heads/release.tar.gz" \
            "gitclone" "https://gitclone.com/github.com/SillyTavern/SillyTavern/archive/refs/heads/release.tar.gz" \
            "ghps" "https://ghps.cc/https://github.com/SillyTavern/SillyTavern/archive/refs/heads/release.tar.gz" \
            "gh.noki.icu" "https://gh.noki.icu/https://github.com/SillyTavern/SillyTavern/archive/refs/heads/release.tar.gz" \
            "ghfast" "https://ghfast.top/https://github.com/SillyTavern/SillyTavern/archive/refs/heads/release.tar.gz" \
            "GitHub" "https://github.com/SillyTavern/SillyTavern/archive/refs/heads/release.tar.gz"
        )

        if [ $? -ne 0 ]; then
            echo -e "  ${RED}  ✗ 无法访问任何 Git 镜像源${NC}"
            return 1
        fi

        local clone_url=""
        case "$best_git_mirror" in
            "gh-proxy")
                clone_url="https://gh-proxy.com/https://github.com/SillyTavern/SillyTavern.git"
                ;;
            "gitclone")
                clone_url="https://gitclone.com/github.com/SillyTavern/SillyTavern.git"
                ;;
            "ghps")
                clone_url="https://ghps.cc/https://github.com/SillyTavern/SillyTavern.git"
                ;;
            "gh.noki.icu")
                clone_url="https://gh.noki.icu/https://github.com/SillyTavern/SillyTavern.git"
                ;;
            "ghfast")
                clone_url="https://ghfast.top/https://github.com/SillyTavern/SillyTavern.git"
                ;;
            "GitHub")
                clone_url="https://github.com/SillyTavern/SillyTavern.git"
                ;;
        esac

        echo -e "  ${CYAN}  从 ${best_git_mirror} 克隆仓库...${NC}"
        if ! run_git_with_progress "克隆仓库" git clone -b release "$clone_url" "$ST_INSTALL_DIR"; then
            echo -e "  ${RED}  ✗ 克隆失败${NC}"
            return 1
        fi
        echo -e "  ${GREEN}  ✓ 代码下载完成${NC}"
    fi

    # 安装依赖
    cd "$ST_INSTALL_DIR" || return 1
    if ! run_with_spinner "安装依赖 (npm install)" npm install; then
        echo -e "  ${RED}  ✗ 依赖安装失败${NC}"
        return 1
    fi

    echo -e "\n  ${GREEN}  ✓ SillyTavern 安装完成！${NC}"
    echo -e "  ${GRAY}  安装路径: ${ST_INSTALL_DIR}${NC}"

    # 短暂启动一次以生成 config.yaml
    if [ ! -f "$ST_INSTALL_DIR/config.yaml" ]; then
        echo -e "\n  ${CYAN}  正在初始化配置文件...${NC}"
        cd "$ST_INSTALL_DIR" || return 1
        timeout 10 node server.js > /dev/null 2>&1 &
        local init_pid=$!
        sleep 5
        kill "$init_pid" 2>/dev/null
        wait "$init_pid" 2>/dev/null
        if [ -f "$ST_INSTALL_DIR/config.yaml" ]; then
            echo -e "  ${GREEN}  ✓ 配置文件已生成${NC}"
        else
            # 回退：从默认模板复制
            [ -f "$ST_INSTALL_DIR/default/config.yaml" ] && cp "$ST_INSTALL_DIR/default/config.yaml" "$ST_INSTALL_DIR/config.yaml"
            echo -e "  ${GREEN}  ✓ 配置文件已创建${NC}"
        fi
    fi

    # 询问是否开启监听
    echo ""
    echo -ne "  ${CYAN}是否开启远程监听？（局域网内其他设备访问）[y/N]: ${NC}"
    read -r enable_listen
    if [[ "$enable_listen" =~ ^[Yy] ]]; then
        echo -ne "  ${CYAN}请设置认证用户名: ${NC}"
        read -r new_user
        echo -ne "  ${CYAN}请设置认证密码: ${NC}"
        read -rs new_pass
        echo ""
        if [ -n "$new_user" ] && [ -n "$new_pass" ]; then
            write_yaml_value "listen" "true"
            write_yaml_value "whitelistMode" "false"
            write_yaml_value "basicAuthMode" "true"
            write_yaml_value "basicAuthUser" "username" "\"${new_user}\""
            write_yaml_value "basicAuthUser" "password" "\"${new_pass}\""
            echo -e "  ${GREEN}  ✓ 已开启监听，认证已配置，白名单已关闭${NC}"
        else
            echo -e "  ${YELLOW}  用户名或密码为空，跳过监听配置${NC}"
        fi
    fi

    echo -e "\n  ${GRAY}  运行方式: 返回主菜单选择「运行 / 停止 SillyTavern」${NC}"
}

# ============================================================
# 启动管理
# ============================================================

# 前台运行 SillyTavern
start_st_foreground() {
    if [ ! -d "$ST_INSTALL_DIR" ]; then
        echo -e "  ${RED}  酒馆未安装，请先安装${NC}"
        return 1
    fi

    echo -e "  ${CYAN}  正在前台运行 SillyTavern...${NC}"
    echo -e "  ${GRAY}  按 Ctrl+C 停止${NC}\n"
    cd "$ST_INSTALL_DIR" && node server.js
    echo -e "\n  ${YELLOW}  酒馆已停止${NC}"
}

# 后台运行 SillyTavern（通过 screen）
start_st_background() {
    if [ ! -d "$ST_INSTALL_DIR" ]; then
        echo -e "  ${RED}  酒馆未安装，请先安装${NC}"
        return 1
    fi

    # 确保 screen 可用
    if ! ensure_screen; then
        return 1
    fi

    # 清理无效 screen 会话
    cleanup_dead_screen

    # 检查是否已有活跃的会话且 node 在运行
    if screen -ls 2>/dev/null | grep -q "$ST_SCREEN_NAME" && is_node_running; then
        echo -e "  ${YELLOW}  酒馆已在后台运行中${NC}"
        echo -e "  ${GRAY}  输入 screen -r ${ST_SCREEN_NAME} 可进入查看${NC}"
        return 0
    fi

    # 如果有残留 screen 但 node 没跑，清理掉
    if screen -ls 2>/dev/null | grep -q "$ST_SCREEN_NAME"; then
        screen -S "$ST_SCREEN_NAME" -X quit > /dev/null 2>&1
        screen -wipe > /dev/null 2>&1
    fi

    echo -e "  ${CYAN}  正在后台运行 SillyTavern (screen)...${NC}"
    : > "$ST_LOG_FILE"
    screen -dmS "$ST_SCREEN_NAME" bash -c "cd \"$ST_INSTALL_DIR\" && node server.js 2>&1 | tee \"$ST_LOG_FILE\""
    sleep 3

    # 验证启动
    if is_node_running; then
        echo -e "  ${GREEN}  ✓ SillyTavern 已在后台运行${NC}"
        echo -e "  ${GRAY}  访问地址: http://localhost:${ST_PORT}${NC}"
        echo -e "  ${GRAY}  查看日志: screen -r ${ST_SCREEN_NAME}${NC}"
    else
        echo -e "  ${RED}  ✗ 运行失败，请尝试前台运行查看错误信息${NC}"
        # 显示日志帮助排查
        if [ -s "$ST_LOG_FILE" ]; then
            echo -e "  ${GRAY}  最近日志:${NC}"
            tail -5 "$ST_LOG_FILE" | sed 's/^/    /'
        fi
        return 1
    fi
}

# 检测 node server.js 是否在运行（兼容 Termux）
is_node_running() {
    if command -v pgrep > /dev/null 2>&1 && pgrep -f "node.*server.js" > /dev/null 2>&1; then
        return 0
    elif ps aux 2>/dev/null | grep -v grep | grep -q "node.*server.js"; then
        return 0
    elif ps -ef 2>/dev/null | grep -v grep | grep -q "node.*server.js"; then
        return 0
    fi
    return 1
}

# 停止 SillyTavern
stop_st() {
    echo -e "  ${CYAN}  正在停止 SillyTavern...${NC}"

    # 清理无效会话 + 停止活跃会话
    cleanup_dead_screen
    if screen -ls 2>/dev/null | grep -q "$ST_SCREEN_NAME"; then
        screen -S "$ST_SCREEN_NAME" -X quit > /dev/null 2>&1
        sleep 1
        screen -wipe > /dev/null 2>&1
    fi

    # 兜底：kill 残余进程
    pkill -f "node.*server.js" 2>/dev/null
    sleep 1

    if ! is_node_running; then
        echo -e "  ${GREEN}  ✓ 酒馆已停止${NC}"
    else
        echo -e "  ${RED}  ✗ 停止失败，请手动终止进程${NC}"
        return 1
    fi
}

# 重启 SillyTavern（以当前运行方式重启）
restart_st() {
    # 判断当前运行方式
    local run_mode="foreground"
    cleanup_dead_screen
    if screen -ls 2>/dev/null | grep -q "$ST_SCREEN_NAME"; then
        run_mode="screen"
    elif systemctl --user is-active sillytavern > /dev/null 2>&1; then
        run_mode="systemd"
    fi

    echo -e "  ${CYAN}  正在重启 SillyTavern...${NC}"
    stop_st || return 1

    case "$run_mode" in
        "screen")
            start_st_background
            ;;
        "systemd")
            systemctl --user restart sillytavern 2>/dev/null
            echo -e "  ${GREEN}  ✓ 系统服务已重启${NC}"
            ;;
        *)
            start_st_foreground
            ;;
    esac
}

# 查看酒馆日志（实时滚动，按回车退出）
view_st_log() {
    if [ ! -f "$ST_LOG_FILE" ] || [ ! -s "$ST_LOG_FILE" ]; then
        echo -e "  ${YELLOW}  暂无日志${NC}"
        return 0
    fi

    echo -e "  ${GRAY}  实时日志输出中，按 回车 返回...${NC}\n"

    # 后台启动 tail -f，主进程等待回车后终止它
    tail -n +1 -f "$ST_LOG_FILE" 2>/dev/null &
    local tail_pid=$!

    # 等待用户按回车
    read -r

    kill "$tail_pid" 2>/dev/null
    wait "$tail_pid" 2>/dev/null
    echo ""
}

# 开机自启动管理（systemd user service）
setup_autostart() {
    local service_dir="$HOME/.config/systemd/user"
    local service_file="${service_dir}/sillytavern.service"
    local node_bin
    node_bin=$(command -v node)

    # 检测当前状态
    local is_enabled=false
    if systemctl --user is-enabled sillytavern > /dev/null 2>&1; then
        is_enabled=true
    fi

    echo -e "\n  ${WHITE}── 开机自启动 ────────────────────────────────${NC}"

    if [ "$is_enabled" = true ]; then
        echo -e "\n  ${GREEN}●${NC} 当前状态: ${GREEN}已启用${NC}"
        echo ""
        echo -ne "  ${YELLOW}是否关闭开机自启动？[y/N]: ${NC}"
        read -r confirm
        if [[ "$confirm" =~ ^[Yy] ]]; then
            systemctl --user disable sillytavern 2>/dev/null
            echo -e "  ${GREEN}  ✓ 已关闭开机自启动${NC}"
        else
            echo -e "  ${GRAY}  保持不变${NC}"
        fi
    else
        echo -e "\n  ${YELLOW}●${NC} 当前状态: ${YELLOW}未启用${NC}"
        echo ""
        echo -ne "  ${CYAN}是否开启开机自启动？[Y/n]: ${NC}"
        read -r confirm
        confirm="${confirm:-Y}"
        if [[ "$confirm" =~ ^[Yy] ]]; then
            # 生成 service 文件
            mkdir -p "$service_dir"
            local node_dir
            node_dir=$(dirname "$node_bin")
            cat > "$service_file" << SVCEOF
[Unit]
Description=SillyTavern Server
After=network.target

[Service]
Type=simple
Environment=PATH=${node_dir}:/usr/local/bin:/usr/bin:/bin
Environment=NODE_ENV=production
WorkingDirectory=${ST_INSTALL_DIR}
ExecStart=${node_bin} ${ST_INSTALL_DIR}/server.js
StandardOutput=append:${ST_LOG_FILE}
StandardError=append:${ST_LOG_FILE}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
SVCEOF
            systemctl --user daemon-reload 2>/dev/null
            if systemctl --user enable sillytavern 2>/dev/null; then
                echo -e "  ${GREEN}  ✓ 已开启开机自启动${NC}"
                # 提示 loginctl enable-linger 以支持开机无需登录即启动
                if ! loginctl show-user "$(whoami)" 2>/dev/null | grep -q "Linger=yes"; then
                    echo -e "  ${YELLOW}  提示: 执行以下命令可让服务在未登录时也能启动:${NC}"
                    echo -e "  ${GRAY}  sudo loginctl enable-linger $(whoami)${NC}"
                fi
                # 如果酒馆未运行，立即启动
                local cur_status
                cur_status=$(get_st_status)
                if [[ "$cur_status" != running_* ]]; then
                    echo -e "  ${CYAN}  正在运行 SillyTavern...${NC}"
                    systemctl --user start sillytavern 2>/dev/null
                    sleep 2
                    if systemctl --user is-active sillytavern > /dev/null 2>&1; then
                        echo -e "  ${GREEN}  ✓ SillyTavern 已通过系统服务运行${NC}"
                        echo -e "  ${GRAY}  访问地址: http://localhost:${ST_PORT}${NC}"
                    else
                        echo -e "  ${YELLOW}  系统服务启动失败，请尝试其他方式运行${NC}"
                    fi
                fi
            else
                echo -e "  ${RED}  ✗ 启用失败${NC}"
                return 1
            fi
        else
            echo -e "  ${GRAY}  已取消${NC}"
        fi
    fi
}

# 启动管理子菜单
start_management() {
    if [ ! -d "$ST_INSTALL_DIR" ]; then
        echo -e "\n  ${RED}  酒馆未安装，请先安装${NC}"
        return 1
    fi

    while true; do
        local status
        status=$(get_st_status)

        echo -e "\n  ${WHITE}── 运行管理 ──────────────────────────────────${NC}"
        echo ""

        if [[ "$status" == running_* ]]; then
            echo -e "  ${GREEN}●${NC} 酒馆运行中  ${GRAY}http://localhost:${ST_PORT}${NC}"
            echo ""
            echo -e "  ${RED}1)${NC} 停止 SillyTavern"
            echo -e "  ${CYAN}2)${NC} 重启 SillyTavern"
            echo -e "  ${GREEN}3)${NC} 查看酒馆日志"
            if ! is_termux; then
                echo -e "  ${GREEN}4)${NC} 开机时自动运行酒馆"
            fi
            echo -e "  ${GRAY}0)${NC} 返回主菜单"
            echo ""
            echo -ne "  ${CYAN}请选择操作: ${NC}"
            read -r sub_choice

            case "$sub_choice" in
                1)
                    stop_st
                    ;;
                2)
                    restart_st
                    ;;
                3)
                    view_st_log
                    ;;
                4)
                    if ! is_termux; then
                        setup_autostart
                    else
                        echo -e "\n  ${RED}无效选项${NC}"
                    fi
                    ;;
                0)
                    return 0
                    ;;
                *)
                    echo -e "\n  ${RED}无效选项${NC}"
                    ;;
            esac
        else
            echo -e "  ${YELLOW}●${NC} 酒馆未运行"
            echo ""
            echo -e "  ${GREEN}1)${NC} 前台运行 SillyTavern"
            echo -e "  ${GREEN}2)${NC} 后台运行 SillyTavern (screen)"
            if ! is_termux; then
                echo -e "  ${GREEN}3)${NC} 开机时自动运行酒馆"
            fi
            echo -e "  ${GRAY}0)${NC} 返回主菜单"
            echo ""
            echo -ne "  ${CYAN}请选择操作: ${NC}"
            read -r sub_choice

            case "$sub_choice" in
                1)
                    start_st_foreground
                    ;;
                2)
                    start_st_background
                    ;;
                3)
                    if ! is_termux; then
                        setup_autostart
                    else
                        echo -e "\n  ${RED}无效选项${NC}"
                    fi
                    ;;
                0)
                    return 0
                    ;;
                *)
                    echo -e "\n  ${RED}无效选项${NC}"
                    ;;
            esac
        fi

        echo ""
        echo -ne "  ${GRAY}按回车键继续...${NC}"
        read -r
    done
}

# ============================================================
# 配置管理
# ============================================================

ST_CONFIG_FILE="$ST_INSTALL_DIR/config.yaml"
ST_DEFAULT_CONFIG="$ST_INSTALL_DIR/default/config.yaml"

# 确保用户 config.yaml 存在
ensure_config() {
    if [ ! -f "$ST_CONFIG_FILE" ]; then
        if [ -f "$ST_DEFAULT_CONFIG" ]; then
            cp "$ST_DEFAULT_CONFIG" "$ST_CONFIG_FILE"
        else
            echo -e "  ${RED}  ✗ 未找到配置文件模板${NC}"
            return 1
        fi
    fi
    return 0
}

# 读取 YAML 值
# 用法: read_yaml_value "key"              — 顶层 key
#       read_yaml_value "parent" "child"   — 嵌套 key（一层缩进）
read_yaml_value() {
    local file="$ST_CONFIG_FILE"
    if [ "$#" -eq 1 ]; then
        # 顶层 key: 匹配行首 key: value
        sed -n "s/^${1}: *//p" "$file" | head -1 | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/"
    elif [ "$#" -eq 2 ]; then
        # 嵌套 key: 找到 parent 块后，在缩进行中匹配 child
        sed -n "/^${1}:/,/^[^ ]/{ s/^  *${2}: *//p; }" "$file" | head -1 | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/"
    fi
}

# 写入 YAML 值
# 用法: write_yaml_value "key" "value"              — 顶层 key
#       write_yaml_value "parent" "child" "value"   — 嵌套 key
write_yaml_value() {
    local file="$ST_CONFIG_FILE"
    if [ "$#" -eq 2 ]; then
        # 顶层 key
        sed -i "s/^${1}: .*/${1}: ${2}/" "$file"
    elif [ "$#" -eq 3 ]; then
        # 嵌套 key: 在 parent 块内替换 child 行
        sed -i "/^${1}:/,/^[^ ]/ s/^\(  *\)${2}: .*/\1${2}: ${3}/" "$file"
    fi
}

# 配置修改后自动重启（仅在酒馆运行中时）
auto_restart_if_running() {
    local status
    status=$(get_st_status)
    if [[ "$status" == running_* ]]; then
        echo -e "  ${CYAN}  正在自动重启以应用配置...${NC}"
        restart_st
    fi
}

# 配置管理子菜单
config_management() {
    if [ ! -d "$ST_INSTALL_DIR" ]; then
        echo -e "\n  ${RED}  酒馆未安装，请先安装${NC}"
        return 1
    fi

    ensure_config || return 1

    while true; do
        local cur_listen cur_port cur_auth_user

        cur_listen=$(read_yaml_value "listen")
        cur_port=$(read_yaml_value "port")
        cur_auth_user=$(read_yaml_value "basicAuthUser" "username")

        echo -e "\n  ${WHITE}── 配置管理 ──────────────────────────────────${NC}"
        echo ""
        echo -e "  ${WHITE}  当前配置:${NC}"

        if [ "$cur_listen" = "true" ]; then
            echo -e "  ${GREEN}●${NC} 监听模式: ${GREEN}开启${NC} ${GRAY}(允许远程访问)${NC}"
        else
            echo -e "  ${YELLOW}●${NC} 监听模式: ${YELLOW}关闭${NC} ${GRAY}(仅本机访问)${NC}"
        fi
        echo -e "  ${CYAN}●${NC} 端口: ${CYAN}${cur_port}${NC}"
        if [ "$cur_listen" = "true" ]; then
            echo -e "  ${CYAN}●${NC} 认证账号: ${CYAN}${cur_auth_user}${NC}"
        fi
        echo ""

        if [ "$cur_listen" = "true" ]; then
            echo -e "  ${YELLOW}1)${NC} 关闭监听 (仅本机访问)"
            echo -e "  ${GREEN}2)${NC} 修改端口"
            echo -e "  ${GREEN}3)${NC} 修改认证账号密码"
            echo -e "  ${GRAY}0)${NC} 返回主菜单"
            echo ""
            echo -ne "  ${CYAN}请选择操作: ${NC}"
            read -r sub_choice

            case "$sub_choice" in
                1)
                    write_yaml_value "listen" "false"
                    write_yaml_value "basicAuthMode" "false"
                    echo -e "  ${GREEN}  ✓ 已关闭监听，认证已自动关闭${NC}"
                    auto_restart_if_running
                    ;;
                2)
                    echo -ne "\n  ${CYAN}请输入新端口 [1-65535]: ${NC}"
                    read -r new_port
                    if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
                        write_yaml_value "port" "$new_port"
                        echo -e "  ${GREEN}  ✓ 端口已修改为 ${new_port}${NC}"
                        auto_restart_if_running
                    else
                        echo -e "  ${RED}  无效端口${NC}"
                    fi
                    ;;
                3)
                    echo -ne "\n  ${CYAN}请输入新用户名: ${NC}"
                    read -r new_user
                    echo -ne "  ${CYAN}请输入新密码: ${NC}"
                    read -rs new_pass
                    echo ""
                    if [ -n "$new_user" ] && [ -n "$new_pass" ]; then
                        write_yaml_value "basicAuthUser" "username" "\"${new_user}\""
                        write_yaml_value "basicAuthUser" "password" "\"${new_pass}\""
                        echo -e "  ${GREEN}  ✓ 认证账号已更新${NC}"
                        auto_restart_if_running
                    else
                        echo -e "  ${RED}  用户名和密码不能为空${NC}"
                    fi
                    ;;
                0)
                    return 0
                    ;;
                *)
                    echo -e "\n  ${RED}无效选项${NC}"
                    ;;
            esac
        else
            echo -e "  ${GREEN}1)${NC} 开启监听 (允许远程访问)"
            echo -e "  ${GREEN}2)${NC} 修改端口"
            echo -e "  ${GRAY}0)${NC} 返回主菜单"
            echo ""
            echo -ne "  ${CYAN}请选择操作: ${NC}"
            read -r sub_choice

            case "$sub_choice" in
                1)
                    echo -ne "\n  ${CYAN}请设置认证用户名: ${NC}"
                    read -r new_user
                    echo -ne "  ${CYAN}请设置认证密码: ${NC}"
                    read -rs new_pass
                    echo ""
                    if [ -n "$new_user" ] && [ -n "$new_pass" ]; then
                        write_yaml_value "listen" "true"
                        write_yaml_value "whitelistMode" "false"
                        write_yaml_value "basicAuthMode" "true"
                        write_yaml_value "basicAuthUser" "username" "\"${new_user}\""
                        write_yaml_value "basicAuthUser" "password" "\"${new_pass}\""
                        echo -e "  ${GREEN}  ✓ 已开启监听，认证已配置，白名单已关闭${NC}"
                        echo -e "  ${GRAY}    用户名: ${new_user}${NC}"
                        auto_restart_if_running
                    else
                        echo -e "  ${RED}  用户名和密码不能为空，已取消${NC}"
                    fi
                    ;;
                2)
                    echo -ne "\n  ${CYAN}请输入新端口 [1-65535]: ${NC}"
                    read -r new_port
                    if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
                        write_yaml_value "port" "$new_port"
                        echo -e "  ${GREEN}  ✓ 端口已修改为 ${new_port}${NC}"
                        auto_restart_if_running
                    else
                        echo -e "  ${RED}  无效端口${NC}"
                    fi
                    ;;
                0)
                    return 0
                    ;;
                *)
                    echo -e "\n  ${RED}无效选项${NC}"
                    ;;
            esac
        fi

        echo ""
        echo -ne "  ${GRAY}按回车键继续...${NC}"
        read -r
    done
}

# ============================================================
# 脚本更新
# ============================================================

# 检查并更新脚本
check_update() {
    echo -e "\n  ${WHITE}── 检查脚本更新 ──────────────────────────────${NC}"
    echo -e "\n  ${CYAN}  正在检查最新版本...${NC}"

    # 下载远程脚本到临时文件
    local tmp_file
    tmp_file=$(mktemp)

    if ! curl -sSf --connect-timeout 10 --max-time 30 -L "$SCRIPT_REPO_URL" -o "$tmp_file" 2>/dev/null; then
        rm -f "$tmp_file"
        echo -e "  ${RED}  ✗ 无法连接到更新服务器${NC}"

        # 尝试通过代理
        echo -e "  ${CYAN}  正在尝试镜像源...${NC}"
        local proxy_url
        proxy_url=$(speed_test_mirrors -t \
            "gh-proxy" "https://gh-proxy.com/${SCRIPT_REPO_URL}" \
            "ghps" "https://ghps.cc/${SCRIPT_REPO_URL}" \
            "GitHub" "$SCRIPT_REPO_URL"
        )

        local download_url="$SCRIPT_REPO_URL"
        case "$proxy_url" in
            "gh-proxy") download_url="https://gh-proxy.com/${SCRIPT_REPO_URL}" ;;
            "ghps") download_url="https://ghps.cc/${SCRIPT_REPO_URL}" ;;
        esac

        if ! curl -sSf --connect-timeout 10 --max-time 60 -L "$download_url" -o "$tmp_file" 2>/dev/null; then
            rm -f "$tmp_file"
            echo -e "  ${RED}  ✗ 更新检查失败，请稍后重试${NC}"
            return 1
        fi
    fi

    # 从远程脚本提取版本号
    local remote_version
    remote_version=$(grep -m1 '^SCRIPT_VERSION=' "$tmp_file" 2>/dev/null | sed 's/SCRIPT_VERSION="//;s/"//')

    if [ -z "$remote_version" ]; then
        rm -f "$tmp_file"
        echo -e "  ${RED}  ✗ 无法解析远程版本号${NC}"
        return 1
    fi

    echo -e "  ${GRAY}  本地版本: v${SCRIPT_VERSION}${NC}"
    echo -e "  ${GRAY}  远程版本: v${remote_version}${NC}"

    if [ "$remote_version" = "$SCRIPT_VERSION" ]; then
        rm -f "$tmp_file"
        echo -e "\n  ${GREEN}  ✓ 已是最新版本${NC}"
        return 0
    fi

    echo ""
    echo -ne "  ${CYAN}发现新版本，是否更新？[Y/n]: ${NC}"
    read -r confirm
    confirm="${confirm:-Y}"

    if [[ "$confirm" =~ ^[Yy] ]]; then
        # 覆盖当前脚本
        cp "$tmp_file" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        rm -f "$tmp_file"
        echo -e "  ${GREEN}  ✓ 更新完成 (v${SCRIPT_VERSION} → v${remote_version})${NC}"
        echo -e "  ${CYAN}  正在重新启动脚本...${NC}"
        sleep 1
        exec "$SCRIPT_PATH"
    else
        rm -f "$tmp_file"
        echo -e "  ${GRAY}  已跳过更新${NC}"
    fi
}

# 卸载酒馆
uninstall_st() {
    echo -e "\n  ${WHITE}── 卸载 SillyTavern ──────────────────────────${NC}"

    if [ ! -d "$ST_INSTALL_DIR" ]; then
        echo -e "\n  ${YELLOW}  酒馆未安装，无需卸载${NC}"
        return 0
    fi

    # 检查是否正在运行
    if pgrep -f "node.*server.js" > /dev/null 2>&1 || \
       pgrep -f "SillyTavern" > /dev/null 2>&1; then
        echo -e "\n  ${YELLOW}  检测到酒馆正在运行，正在停止...${NC}"
        pkill -f "node.*server.js" 2>/dev/null
        pkill -f "SillyTavern" 2>/dev/null
        sleep 1
        echo -e "  ${GREEN}  ✓ 已停止${NC}"
    fi

    echo -e "\n  ${GRAY}  安装路径: ${ST_INSTALL_DIR}${NC}"
    echo ""

    # 询问是否保留用户数据
    local keep_data=""
    echo -ne "  ${YELLOW}是否保留用户数据（角色卡、聊天记录、设置）？[Y/n]: ${NC}"
    read -r keep_data
    keep_data="${keep_data:-Y}"

    if [[ "$keep_data" =~ ^[Yy] ]]; then
        echo -e "  ${CYAN}  正在备份用户数据...${NC}"
        create_backup "pre-uninstall"
    fi

    # 二次确认
    echo ""
    echo -ne "  ${RED}确认卸载 SillyTavern？此操作不可恢复 [y/N]: ${NC}"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        echo -e "\n  ${GRAY}  已取消卸载${NC}"
        return 0
    fi

    # 执行卸载
    echo -e "\n  ${CYAN}  正在删除 ${ST_INSTALL_DIR}...${NC}"
    rm -rf "$ST_INSTALL_DIR"

    if [ ! -d "$ST_INSTALL_DIR" ]; then
        echo -e "  ${GREEN}  ✓ SillyTavern 已成功卸载${NC}"
        echo -e "  ${GRAY}  备份位于: ${ST_BACKUP_DIR}${NC}"
    else
        echo -e "  ${RED}  ✗ 卸载失败，请检查权限${NC}"
        return 1
    fi
}

# ============================================================
# 备份管理
# ============================================================

ST_BACKUP_DIR="$HOME/SillyTavern-backups"
ST_MAX_BACKUPS=7

# 创建备份（压缩为 tar.gz）
# 参数: $1 = 备份标签（可选，默认为 manual）
create_backup() {
    local label="${1:-manual}"

    if [ ! -d "$ST_INSTALL_DIR/data" ] && [ ! -d "$ST_INSTALL_DIR/public" ]; then
        echo -e "  ${YELLOW}  未找到酒馆数据目录，无需备份${NC}"
        return 1
    fi

    mkdir -p "$ST_BACKUP_DIR"

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="backup_${timestamp}_${label}.tar.gz"
    local backup_path="${ST_BACKUP_DIR}/${backup_name}"

    echo -e "  ${CYAN}  正在创建备份: ${backup_name}...${NC}"

    # 收集需要备份的目录
    local -a tar_dirs=()
    [ -d "$ST_INSTALL_DIR/data" ] && tar_dirs+=("data")
    [ -d "$ST_INSTALL_DIR/public" ] && tar_dirs+=("public")

    # 压缩打包
    if tar_compress_with_progress "备份中" "$backup_path" "$ST_INSTALL_DIR" "${tar_dirs[@]}"; then
        local size
        size=$(du -sh "$backup_path" 2>/dev/null | cut -f1)
        echo -e "  ${GREEN}  ✓ 备份完成 (${size})${NC}"
        echo -e "  ${GRAY}    路径: ${backup_path}${NC}"

        # 清理超出上限的旧备份
        cleanup_old_backups
        return 0
    else
        rm -f "$backup_path"
        echo -e "  ${RED}  ✗ 备份失败${NC}"
        return 1
    fi
}

# 清理超出上限的旧备份（保留最近7份）
cleanup_old_backups() {
    if [ ! -d "$ST_BACKUP_DIR" ]; then
        return
    fi

    local count
    count=$(ls -1 "$ST_BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | wc -l)

    if [ "$count" -gt "$ST_MAX_BACKUPS" ]; then
        local to_delete=$((count - ST_MAX_BACKUPS))
        echo -e "  ${GRAY}  清理旧备份（保留最近 ${ST_MAX_BACKUPS} 份）...${NC}"
        ls -1 "$ST_BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | head -n "$to_delete" | while read -r f; do
            rm -f "$f"
            echo -e "  ${GRAY}    删除: $(basename "$f")${NC}"
        done
    fi
}

# 列出所有备份
list_backups() {
    if [ ! -d "$ST_BACKUP_DIR" ] || [ -z "$(ls -1 "$ST_BACKUP_DIR"/backup_*.tar.gz 2>/dev/null)" ]; then
        echo -e "\n  ${YELLOW}  暂无备份${NC}"
        return 1
    fi

    echo -e "\n  ${WHITE}  可用备份:${NC}\n"
    local index=1
    while IFS= read -r f; do
        local name
        name=$(basename "$f" .tar.gz)
        local size
        size=$(du -sh "$f" 2>/dev/null | cut -f1)
        # 从文件名解析时间和标签: backup_YYYYMMDD_HHMMSS_label
        local date_part="${name#backup_}"
        local ts="${date_part%%_*}"
        date_part="${date_part#*_}"
        local time_part="${date_part%%_*}"
        local label="${date_part#*_}"
        local display_date="${ts:0:4}-${ts:4:2}-${ts:6:2} ${time_part:0:2}:${time_part:2:2}:${time_part:4:2}"
        printf "  ${GREEN}  %2d)${NC} %s [%s] (%s)\n" "$index" "$display_date" "$label" "$size"
        index=$((index + 1))
    done < <(ls -1 "$ST_BACKUP_DIR"/backup_*.tar.gz 2>/dev/null)

    return 0
}

# 选择一个备份（交互式），结果存入 SELECTED_BACKUP
select_backup() {
    list_backups || return 1

    local count
    count=$(ls -1 "$ST_BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | wc -l)

    echo ""
    echo -ne "  ${CYAN}请选择备份编号 [1-${count}]: ${NC}"
    read -r num

    if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "$count" ]; then
        echo -e "  ${RED}  无效选择${NC}"
        return 1
    fi

    SELECTED_BACKUP=$(ls -1 "$ST_BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | sed -n "${num}p")
    return 0
}

# 删除备份
delete_backup() {
    echo -e "\n  ${WHITE}── 删除备份 ──────────────────────────────────${NC}"

    select_backup || return 1

    local name
    name=$(basename "$SELECTED_BACKUP")
    echo -ne "\n  ${YELLOW}确认删除 ${name}？[y/N]: ${NC}"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        echo -e "  ${GRAY}  已取消${NC}"
        return 0
    fi

    rm -f "$SELECTED_BACKUP"
    echo -e "  ${GREEN}  ✓ 已删除${NC}"
}

# 恢复备份
restore_backup() {
    echo -e "\n  ${WHITE}── 恢复备份 ──────────────────────────────────${NC}"

    if [ ! -d "$ST_INSTALL_DIR" ]; then
        echo -e "\n  ${RED}  酒馆未安装，请先安装${NC}"
        return 1
    fi

    select_backup || return 1

    local name
    name=$(basename "$SELECTED_BACKUP")
    echo -e "\n  ${YELLOW}  将恢复备份: ${name}${NC}"
    echo -e "  ${YELLOW}  当前数据将被覆盖（会先自动备份当前数据）${NC}"
    echo -ne "  ${YELLOW}  确认恢复？[y/N]: ${NC}"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        echo -e "  ${GRAY}  已取消${NC}"
        return 0
    fi

    # 先备份当前数据
    echo -e "\n  ${CYAN}  备份当前数据...${NC}"
    create_backup "pre-restore"

    # 恢复选中的备份（解压覆盖）
    echo -e "  ${CYAN}  正在恢复...${NC}"
    [ -d "$ST_INSTALL_DIR/data" ] && rm -rf "$ST_INSTALL_DIR/data"
    [ -d "$ST_INSTALL_DIR/public" ] && rm -rf "$ST_INSTALL_DIR/public"

    if tar_extract_with_progress "恢复中" "$SELECTED_BACKUP" "$ST_INSTALL_DIR"; then
        echo -e "  ${GREEN}  ✓ 恢复完成${NC}"
    else
        echo -e "  ${RED}  ✗ 恢复失败${NC}"
        return 1
    fi
}

# 备份管理菜单（入口，循环子菜单）
backup_management() {
    while true; do
        echo -e "\n  ${WHITE}── 备份管理 ──────────────────────────────────${NC}"
        echo ""
        echo -e "  ${GREEN}1)${NC} 创建备份"
        echo -e "  ${GREEN}2)${NC} 查看备份列表"
        echo -e "  ${GREEN}3)${NC} 恢复备份"
        echo -e "  ${RED}4)${NC} 删除备份"
        echo -e "  ${GRAY}0)${NC} 返回主菜单"
        echo ""
        echo -ne "  ${CYAN}请选择操作 [0-4]: ${NC}"
        read -r sub_choice

        case "$sub_choice" in
            1)
                echo -e "\n  ${WHITE}── 创建备份 ──────────────────────────────────${NC}"
                if [ ! -d "$ST_INSTALL_DIR" ]; then
                    echo -e "\n  ${RED}  酒馆未安装${NC}"
                else
                    create_backup "manual"
                fi
                ;;
            2)
                list_backups
                ;;
            3)
                restore_backup
                ;;
            4)
                delete_backup
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "\n  ${RED}无效选项${NC}"
                ;;
        esac

        echo ""
        echo -ne "  ${GRAY}按回车键继续...${NC}"
        read -r
    done
}

# 计算字符串显示宽度（中文字符占2列）
str_display_width() {
    local str="$1"
    if command -v python3 > /dev/null 2>&1; then
        printf '%s' "$str" | python3 -c "
import sys, unicodedata
s = sys.stdin.read()
print(sum(2 if unicodedata.east_asian_width(c) in ('W','F') else 1 for c in s))
"
    else
        printf '%s' "$str" | wc -L
    fi
}

# 打印方框内的一行（自动补齐右侧空格）
# box_inner_width = 框内可用显示宽度（不含左右边框和内边距）
print_box_line() {
    local text="$1"
    local inner_width="$2"
    local text_width
    text_width=$(str_display_width "$text")
    local spaces=$((inner_width - text_width))
    if [ "$spaces" -lt 0 ]; then
        spaces=0
    fi
    local pad=""
    for (( i=0; i<spaces; i++ )); do
        pad+=" "
    done
    echo -e "  ${CYAN}|${NC} ${WHITE}${text}${NC}${pad} ${CYAN}|${NC}"
}

# 清屏
clear_screen() {
    clear
}

# 显示Logo
show_logo() {
    echo -e "${PURPLE}"
    echo '  ____  _ _ _     _____                          '
    echo ' / ___|(_) | |_  |_   _|_ ___   _____ _ __ _ __  '
    echo ' \___ \| | | | | | | |/ _` \ \ / / _ \ `__| `_ \ '
    echo '  ___) | | | | |_| | | (_| |\ V /  __/ |  | | | |'
    echo ' |____/|_|_|_|\__, |_|\__,_| \_/ \___|_|  |_| |_|'
    echo '              |___/                               '
    echo -e "${NC}"
    local inner_width=44
    local border
    border=$(printf '%0.s-' $(seq 1 $((inner_width + 2))))
    echo -e "  ${CYAN}+${border}+${NC}"
    print_box_line "SillyTavern 管理脚本 v${SCRIPT_VERSION}" "$inner_width"
    print_box_line "By ${AUTHOR}" "$inner_width"
    print_box_line "交流群: ${GROUP_ID}" "$inner_width"
    echo -e "  ${CYAN}+${border}+${NC}"
}

# 清理无效的 screen 会话（Dead 或 Remote or dead）
cleanup_dead_screen() {
    screen -wipe > /dev/null 2>&1
    # screen -wipe 不能清理 "Remote or dead" 状态，需要手动强制清除
    if screen -ls 2>/dev/null | grep "$ST_SCREEN_NAME" | grep -qiE "dead|remote"; then
        screen -S "$ST_SCREEN_NAME" -X quit > /dev/null 2>&1
        screen -wipe > /dev/null 2>&1
    fi
}

# 检测酒馆状态（返回: not_installed / running_screen / running_foreground / running_systemd / stopped）
get_st_status() {
    if [ ! -d "$ST_INSTALL_DIR" ]; then
        echo "not_installed"
        return
    fi

    # 检查 screen 会话状态
    local screen_output
    screen_output=$(screen -ls 2>/dev/null)
    local screen_has_st=false
    local screen_is_dead=false

    if echo "$screen_output" | grep -q "$ST_SCREEN_NAME"; then
        screen_has_st=true
        if echo "$screen_output" | grep "$ST_SCREEN_NAME" | grep -qiE "dead|remote"; then
            screen_is_dead=true
        fi
    fi

    # 清理无效 screen 会话
    if [ "$screen_is_dead" = true ]; then
        screen -S "$ST_SCREEN_NAME" -X quit > /dev/null 2>&1
        screen -wipe > /dev/null 2>&1
        screen_has_st=false
    fi

    if is_node_running; then
        if [ "$screen_has_st" = true ]; then
            echo "running_screen"
        elif systemctl --user is-active sillytavern > /dev/null 2>&1; then
            echo "running_systemd"
        else
            echo "running_foreground"
        fi
    elif [ "$screen_has_st" = true ]; then
        # screen 存在但 node 没检测到 — 可能刚启动还没 fork
        sleep 1
        if is_node_running; then
            echo "running_screen"
        else
            screen -S "$ST_SCREEN_NAME" -X quit > /dev/null 2>&1
            screen -wipe > /dev/null 2>&1
            echo "stopped"
        fi
    else
        echo "stopped"
    fi
}

# 显示酒馆状态
show_status() {
    local status
    status=$(get_st_status)

    echo ""
    echo -e "  ${WHITE}── 酒馆状态 ──────────────────────────────────${NC}"
    echo ""

    case "$status" in
        "not_installed")
            echo -e "  ${RED}●${NC} 状态: ${RED}未安装${NC}"
            ;;
        "running_screen")
            echo -e "  ${GREEN}●${NC} 状态: ${GREEN}运行中${NC} ${GRAY}(后台 screen)${NC}"
            echo -e "  ${GRAY}  访问地址: http://localhost:${ST_PORT}${NC}"
            ;;
        "running_systemd")
            echo -e "  ${GREEN}●${NC} 状态: ${GREEN}运行中${NC} ${GRAY}(系统服务)${NC}"
            echo -e "  ${GRAY}  访问地址: http://localhost:${ST_PORT}${NC}"
            ;;
        "running_foreground")
            echo -e "  ${GREEN}●${NC} 状态: ${GREEN}运行中${NC} ${GRAY}(前台)${NC}"
            echo -e "  ${GRAY}  访问地址: http://localhost:${ST_PORT}${NC}"
            ;;
        "stopped")
            echo -e "  ${YELLOW}●${NC} 状态: ${YELLOW}未启动${NC}"
            ;;
    esac
    echo ""
}

# 显示菜单
show_menu() {
    echo -e "  ${WHITE}── 操作菜单 ──────────────────────────────────${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} 安装 / 更新 SillyTavern"
    echo -e "  ${GREEN}2)${NC} 运行 / 停止 SillyTavern"
    echo -e "  ${GREEN}3)${NC} 配置管理"
    echo -e "  ${GREEN}4)${NC} 备份管理"
    echo -e "  ${RED}5)${NC} 卸载酒馆"
    echo -e "  ${BLUE}6)${NC} 检查脚本更新"
    echo -e "  ${GRAY}0)${NC} 退出脚本"
    echo ""
    echo -e "  ${WHITE}──────────────────────────────────────────────${NC}"
    echo ""
}

# 处理用户输入
handle_input() {
    echo -ne "  ${CYAN}请选择操作 [0-6]: ${NC}"
    read -r choice

    case "$choice" in
        1)
            install_or_update_st
            ;;
        2)
            start_management
            ;;
        3)
            config_management
            ;;
        4)
            backup_management
            ;;
        5)
            uninstall_st
            ;;
        6)
            check_update
            ;;
        0)
            echo -e "\n  ${GRAY}再见！${NC}\n"
            exit 0
            ;;
        *)
            echo -e "\n  ${RED}无效选项，请重新选择${NC}"
            ;;
    esac

    echo ""
    echo -ne "  ${GRAY}按回车键返回主菜单...${NC}"
    read -r
}

# 主循环
main() {
    # 启动时清理无效 screen 会话
    cleanup_dead_screen

    while true; do
        clear_screen
        show_logo
        show_status
        show_menu
        handle_input
    done
}

main
