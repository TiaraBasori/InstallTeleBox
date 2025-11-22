#!/usr/bin/env bash

# TeleBox Docker 一键安装脚本
# Version: 2.0.0

if [[ $EUID -ne 0 ]]; then
    echo "错误：本脚本需要 root 权限执行。" 1>&2
    exit 1
fi

welcome() {
    echo
    echo "TeleBox Docker 安装即将开始"
    echo "如果您想取消安装，"
    echo "请在 5 秒钟内按 Ctrl+C 终止此脚本。"
    echo
    sleep 5
}

validate_container_name() {
    local name=$1
    # 检查是否只包含字母和数字
    if [[ ! "$name" =~ ^[a-zA-Z0-9]+$ ]]; then
        return 1
    fi
    return 0
}

list_telebox_containers() {
    echo
    echo "=========================================="
    echo "  当前系统中的 TeleBox 容器"
    echo "=========================================="
    
    # 查找所有容器（包括停止的）
    containers=$(docker ps -a --format "{{.Names}}" 2>/dev/null)
    
    if [ -z "$containers" ]; then
        echo "未找到任何容器"
    else
        echo
        echo "容器名称          状态"
        echo "----------------------------------------"
        while IFS= read -r container; do
            status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
            case $status in
                running)
                    status_cn="运行中"
                    ;;
                exited)
                    status_cn="已停止"
                    ;;
                paused)
                    status_cn="已暂停"
                    ;;
                restarting)
                    status_cn="重启中"
                    ;;
                *)
                    status_cn="$status"
                    ;;
            esac
            printf "%-16s  %s\n" "$container" "$status_cn"
        done <<< "$containers"
    fi
    echo "=========================================="
    echo
}

docker_check() {
    echo "正在检查 Docker 安装情况 . . ."
    if command -v docker >> /dev/null 2>&1; then
        echo "Docker 已安装，安装过程继续 . . ."
    else
        echo "Docker 未安装在此系统上"
        printf "是否现在安装 Docker? [Y/n]: "
        read -r install_docker <&1
        case $install_docker in
            [nN][oO] | [nN])
                echo "用户选择不安装 Docker，退出脚本。"
                exit 0
                ;;
            *)
                echo "开始安装 Docker . . ."
                install_docker_package
                ;;
        esac
    fi
}

install_docker_package() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo "无法检测操作系统类型"
        exit 1
    fi

    case $OS in
        ubuntu | debian)
            echo "检测到 Ubuntu/Debian 系统，开始安装 Docker..."
            apt-get update
            apt-get install -y ca-certificates curl gnupg lsb-release
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        centos | rhel | fedora)
            echo "检测到 CentOS/RHEL/Fedora 系统，开始安装 Docker..."
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            systemctl start docker
            systemctl enable docker
            ;;
        *)
            echo "不支持的操作系统: $OS"
            echo "请手动安装 Docker 后重新运行此脚本"
            exit 1
            ;;
    esac

    if command -v docker >> /dev/null 2>&1; then
        echo "Docker 安装成功！"
    else
        echo "Docker 安装失败，请手动安装"
        exit 1
    fi
}

access_check() {
    echo "测试 Docker 环境 . . ."
    if [ -w /var/run/docker.sock ]; then
        echo "该用户可以使用 Docker，安装过程继续 . . ."
    else
        echo "该用户无权访问 Docker，或者 Docker 没有运行。"
        echo "尝试启动 Docker 服务 . . ."
        systemctl start docker 2>/dev/null || service docker start 2>/dev/null
        sleep 2
        if [ -w /var/run/docker.sock ]; then
            echo "Docker 服务已启动"
        else
            echo "请添加自己到 Docker 组并重新运行此脚本。"
            echo "运行命令: usermod -aG docker $USER"
            exit 1
        fi
    fi
}

get_telegram_config() {
    echo
    echo "=========================================="
    echo "请输入 Telegram 配置信息"
    echo "=========================================="
    echo
    
    printf "请输入您的 Telegram API ID: "
    read -r api_id <&1
    
    printf "请输入您的 Telegram API Hash: "
    read -r api_hash <&1
    
    if [ -z "$api_id" ] || [ -z "$api_hash" ]; then
        echo "错误：API ID 和 API Hash 不能为空"
        exit 1
    fi
    
    echo
    echo "配置信息已保存"
    echo "API ID: $api_id"
    echo "API Hash: $api_hash"
    echo
}

build_docker() {
    while true; do
        printf "请输入 TeleBox 容器的名称（仅限字母和数字）[默认: telebox]: "
        read -r container_name <&1
        
        if [ -z "$container_name" ]; then
            container_name="telebox"
            break
        fi
        
        if validate_container_name "$container_name"; then
            break
        else
            echo "错误：容器名称只能包含字母和数字，请重新输入"
            echo
        fi
    done
    
    echo "容器名称: $container_name"
    
    # 创建宿主机数据目录
    data_dir="/root/Docker_Telebox/$container_name"
    mkdir -p "$data_dir"
    
    echo "数据目录: $data_dir"
    echo "正在准备 Docker 环境 . . ."
    
    # 删除同名容器（如果存在）
    if docker inspect "$container_name" &>/dev/null; then
        echo "检测到同名容器，正在删除 . . ."
        docker rm -f "$container_name" > /dev/null 2>&1
    fi
}

start_docker_interactive() {
    echo
    echo "=========================================="
    echo "第一阶段：交互式安装 TeleBox"
    echo "=========================================="
    echo
    echo "正在启动容器进行配置 . . ."
    echo "请注意：接下来需要您登录 Telegram 账号"
    echo
    sleep 3
    
    # 第一步：交互式安装
    docker run -it --name "$container_name" --restart unless-stopped \
        -v "/root/Docker_Telebox/$container_name":/root --pull always debian:12 \
        bash -lc "set -e; \
        apt-get update; \
        apt-get install -y curl ca-certificates gnupg sudo; \
        update-ca-certificates; \
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -; \
        apt-get install -y nodejs; \
        npm i -g pm2; \
        curl -fsSL https://github.com/EAlyce/conf/raw/refs/heads/main/Linux/installTeleBox.sh -o /root/installTeleBox.sh; \
        chmod +x /root/installTeleBox.sh; \
        /root/installTeleBox.sh; \
        echo ''; \
        echo '安装完成，正在保存 PM2 配置...'; \
        pm2 ls; \
        pm2 save; \
        echo ''; \
        echo '按 Ctrl+C 继续下一步...'; \
        exec pm2-runtime /root/telebox/ecosystem.config.js"
    
    echo
    echo "配置完成，正在进入后台运行模式 . . ."
    sleep 2
}

start_docker_daemon() {
    echo
    echo "=========================================="
    echo "第二阶段：启动后台服务"
    echo "=========================================="
    echo
    
    # 删除交互式容器
    docker rm -f "$container_name" > /dev/null 2>&1
    
    # 第三步：后台运行
    echo "正在以后台模式启动 TeleBox . . ."
    docker run -d --name "$container_name" --restart unless-stopped \
        -v "/root/Docker_Telebox/$container_name":/root --pull always debian:12 \
        bash -lc "set -e; \
        apt-get update; \
        apt-get install -y curl ca-certificates gnupg sudo; \
        update-ca-certificates; \
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -; \
        apt-get install -y nodejs; \
        npm i -g pm2; \
        [ -f /root/telebox/ecosystem.config.js ] || (curl -fsSL https://github.com/EAlyce/conf/raw/refs/heads/main/Linux/installTeleBox.sh -o /root/installTeleBox.sh; \
        chmod +x /root/installTeleBox.sh; \
        /root/installTeleBox.sh); \
        exec pm2-runtime /root/telebox/ecosystem.config.js"
    
    echo
    echo "=========================================="
    echo "TeleBox 安装完成！"
    echo "=========================================="
    echo
    echo "容器名称: $container_name"
    echo "数据目录: /root/Docker_Telebox/$container_name"
    echo
    echo "TeleBox 文件位置："
    echo "  宿主机: /root/Docker_Telebox/$container_name/telebox"
    echo "  容器内: /root/telebox"
    echo
    echo "常用命令："
    echo "  查看日志: docker logs -f $container_name"
    echo "  进入容器: docker exec -it $container_name bash"
    echo "  重启容器: docker restart $container_name"
    echo "  停止容器: docker stop $container_name"
    echo "  查看文件: ls -la /root/Docker_Telebox/$container_name/telebox"
    echo
}

start_installation() {
    welcome
    docker_check
    access_check
    build_docker
    start_docker_interactive
    start_docker_daemon
}

cleanup() {
    list_telebox_containers
    
    while true; do
        printf "请输入要卸载的 TeleBox 容器名称（仅限字母和数字）[默认: telebox]: "
        read -r container_name <&1
        
        if [ -z "$container_name" ]; then
            container_name="telebox"
            break
        fi
        
        if validate_container_name "$container_name"; then
            break
        else
            echo "错误：容器名称只能包含字母和数字，请重新输入"
            echo
        fi
    done
    
    echo "开始卸载 TeleBox . . ."
    
    if docker inspect "$container_name" &>/dev/null; then
        docker rm -f "$container_name" &>/dev/null
        echo "容器 $container_name 已删除"
        
        data_dir="/root/Docker_Telebox/$container_name"
        if [ -d "$data_dir" ]; then
            printf "是否删除数据目录 $data_dir? 这将删除所有数据 [y/N]: "
            read -r remove_data <&1
            case $remove_data in
                [yY][eE][sS] | [yY])
                    rm -rf "$data_dir"
                    echo "数据目录已删除"
                    ;;
                *)
                    echo "数据目录已保留在: $data_dir"
                    ;;
            esac
        fi
        
        echo
        echo "=========================================="
        echo "TeleBox 卸载完成！"
        echo "=========================================="
        echo
        exit 0
    else
        echo "不存在名为 $container_name 的容器"
        exit 1
    fi
}

stop_telebox() {
    list_telebox_containers
    
    while true; do
        printf "请输入要关闭的 TeleBox 容器名称（仅限字母和数字）[默认: telebox]: "
        read -r container_name <&1
        
        if [ -z "$container_name" ]; then
            container_name="telebox"
            break
        fi
        
        if validate_container_name "$container_name"; then
            break
        else
            echo "错误：容器名称只能包含字母和数字，请重新输入"
            echo
        fi
    done
    
    echo "正在关闭 TeleBox 容器 . . ."
    
    if docker inspect "$container_name" &>/dev/null; then
        docker stop "$container_name" &>/dev/null
        echo
        echo "TeleBox 已关闭"
        echo
    else
        echo "不存在名为 $container_name 的容器"
        exit 1
    fi
    
    show_menu
}

start_telebox() {
    list_telebox_containers
    
    while true; do
        printf "请输入要启动的 TeleBox 容器名称（仅限字母和数字）[默认: telebox]: "
        read -r container_name <&1
        
        if [ -z "$container_name" ]; then
            container_name="telebox"
            break
        fi
        
        if validate_container_name "$container_name"; then
            break
        else
            echo "错误：容器名称只能包含字母和数字，请重新输入"
            echo
        fi
    done
    
    echo "正在启动 TeleBox 容器 . . ."
    
    if docker inspect "$container_name" &>/dev/null; then
        docker start "$container_name" &>/dev/null
        echo
        echo "TeleBox 启动完成"
        echo
    else
        echo "不存在名为 $container_name 的容器"
        exit 1
    fi
    
    show_menu
}

restart_telebox() {
    list_telebox_containers
    
    while true; do
        printf "请输入要重启的 TeleBox 容器名称（仅限字母和数字）[默认: telebox]: "
        read -r container_name <&1
        
        if [ -z "$container_name" ]; then
            container_name="telebox"
            break
        fi
        
        if validate_container_name "$container_name"; then
            break
        else
            echo "错误：容器名称只能包含字母和数字，请重新输入"
            echo
        fi
    done
    
    echo "正在重启 TeleBox 容器 . . ."
    
    if docker inspect "$container_name" &>/dev/null; then
        docker restart "$container_name" &>/dev/null
        echo
        echo "TeleBox 重启完成"
        echo
    else
        echo "不存在名为 $container_name 的容器"
        exit 1
    fi
    
    show_menu
}

reinstall_telebox() {
    list_telebox_containers
    
    while true; do
        printf "请输入要重装的 TeleBox 容器名称（仅限字母和数字）[默认: telebox]: "
        read -r container_name <&1
        
        if [ -z "$container_name" ]; then
            container_name="telebox"
            break
        fi
        
        if validate_container_name "$container_name"; then
            break
        else
            echo "错误：容器名称只能包含字母和数字，请重新输入"
            echo
        fi
    done
    
    echo "开始重装 TeleBox . . ."
    echo
    
    printf "是否保留原有数据? [Y/n]: "
    read -r keep_data <&1
    
    if docker inspect "$container_name" &>/dev/null; then
        docker rm -f "$container_name" &>/dev/null
        echo "旧容器已删除"
    fi
    
    data_dir="/root/Docker_Telebox/$container_name"
    case $keep_data in
        [nN][oO] | [nN])
            if [ -d "$data_dir" ]; then
                rm -rf "$data_dir"
                echo "数据已清除，将进行全新安装"
            fi
            ;;
        *)
            echo "将保留原有数据在: $data_dir"
            ;;
    esac
    
    echo
    build_docker
    start_docker_interactive
    start_docker_daemon
}

view_logs() {
    list_telebox_containers
    
    while true; do
        printf "请输入要查看日志的 TeleBox 容器名称（仅限字母和数字）[默认: telebox]: "
        read -r container_name <&1
        
        if [ -z "$container_name" ]; then
            container_name="telebox"
            break
        fi
        
        if validate_container_name "$container_name"; then
            break
        else
            echo "错误：容器名称只能包含字母和数字，请重新输入"
            echo
        fi
    done
    
    if docker inspect "$container_name" &>/dev/null; then
        echo "正在查看日志 (按 Ctrl+C 退出)..."
        echo
        docker logs -f "$container_name"
    else
        echo "不存在名为 $container_name 的容器"
        exit 1
    fi
    
    show_menu
}

enter_container() {
    list_telebox_containers
    
    while true; do
        printf "请输入要进入的 TeleBox 容器名称（仅限字母和数字）[默认: telebox]: "
        read -r container_name <&1
        
        if [ -z "$container_name" ]; then
            container_name="telebox"
            break
        fi
        
        if validate_container_name "$container_name"; then
            break
        else
            echo "错误：容器名称只能包含字母和数字，请重新输入"
            echo
        fi
    done
    
    if docker inspect "$container_name" &>/dev/null; then
        echo "正在进入容器..."
        echo "提示：TeleBox 文件位于 /root/telebox 目录"
        echo "      输入 'exit' 退出容器"
        echo
        docker exec -it "$container_name" bash
    else
        echo "不存在名为 $container_name 的容器"
        exit 1
    fi
    
    show_menu
}

show_container_info() {
    list_telebox_containers
    
    while true; do
        printf "请输入要查看信息的 TeleBox 容器名称（仅限字母和数字）[默认: telebox]: "
        read -r container_name <&1
        
        if [ -z "$container_name" ]; then
            container_name="telebox"
            break
        fi
        
        if validate_container_name "$container_name"; then
            break
        else
            echo "错误：容器名称只能包含字母和数字，请重新输入"
            echo
        fi
    done
    
    if docker inspect "$container_name" &>/dev/null; then
        echo
        echo "=========================================="
        echo "  容器信息"
        echo "=========================================="
        echo
        
        # 容器状态
        status=$(docker inspect -f '{{.State.Status}}' "$container_name")
        echo "容器状态: $status"
        
        # 容器 ID
        container_id=$(docker inspect -f '{{.Id}}' "$container_name" | cut -c1-12)
        echo "容器 ID: $container_id"
        
        # 数据目录
        data_dir="/root/Docker_Telebox/$container_name"
        echo "数据目录: $data_dir"
        
        # TeleBox 文件位置
        echo "TeleBox 目录:"
        echo "  - 宿主机: $data_dir/telebox"
        echo "  - 容器内: /root/telebox"
        
        echo
        echo "=========================================="
        echo "  数据目录信息"
        echo "=========================================="
        echo
        
        if [ -d "$data_dir" ]; then
            echo "目录大小: $(du -sh $data_dir 2>/dev/null | cut -f1)"
            echo
            echo "目录内容:"
            ls -lh "$data_dir" 2>/dev/null || echo "无法访问目录"
        else
            echo "数据目录不存在"
        fi
        
        echo
        echo "=========================================="
        echo "  TeleBox 文件结构"
        echo "=========================================="
        echo
        
        if [ -d "$data_dir/telebox" ]; then
            echo "宿主机路径: $data_dir/telebox"
            ls -la "$data_dir/telebox" 2>/dev/null | head -20
        else
            echo "TeleBox 目录不存在"
        fi
        
        echo
        echo "=========================================="
        echo "  访问文件的方法"
        echo "=========================================="
        echo
        echo "方法 1: 直接在宿主机访问（推荐）"
        echo "  cd $data_dir/telebox"
        echo "  nano config.json"
        echo
        echo "方法 2: 进入容器"
        echo "  docker exec -it $container_name bash"
        echo "  cd /root/telebox"
        echo
        
    else
        echo "不存在名为 $container_name 的容器"
        exit 1
    fi
    
    show_menu
}

backup_telebox() {
    list_telebox_containers
    
    while true; do
        printf "请输入要备份的 TeleBox 容器名称（仅限字母和数字）[默认: telebox]: "
        read -r container_name <&1
        
        if [ -z "$container_name" ]; then
            container_name="telebox"
            break
        fi
        
        if validate_container_name "$container_name"; then
            break
        else
            echo "错误：容器名称只能包含字母和数字，请重新输入"
            echo
        fi
    done
    
    data_dir="/root/Docker_Telebox/$container_name"
    
    if [ ! -d "$data_dir" ]; then
        echo "数据目录不存在: $data_dir"
        exit 1
    fi
    
    backup_file="telebox-backup-$container_name-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    echo "正在备份 TeleBox 数据..."
    echo "数据目录: $data_dir"
    echo "备份文件: $backup_file"
    echo
    
    # 直接打包宿主机目录
    tar czf "$backup_file" -C /root/Docker_Telebox "$container_name"
    
    echo
    echo "备份完成！"
    echo "备份文件: $(pwd)/$backup_file"
    echo
    echo "恢复方法："
    echo "  tar xzf $backup_file -C /root/Docker_Telebox/"
    echo "  然后重新创建容器"
    echo
    
    show_menu
}

restore_telebox() {
    list_telebox_containers
    
    while true; do
        printf "请输入要恢复的 TeleBox 容器名称（仅限字母和数字）[默认: telebox]: "
        read -r container_name <&1
        
        if [ -z "$container_name" ]; then
            container_name="telebox"
            break
        fi
        
        if validate_container_name "$container_name"; then
            break
        else
            echo "错误：容器名称只能包含字母和数字，请重新输入"
            echo
        fi
    done
    
    printf "请输入备份文件路径: "
    read -r backup_file <&1
    
    if [ ! -f "$backup_file" ]; then
        echo "备份文件不存在: $backup_file"
        exit 1
    fi
    
    echo "正在恢复 TeleBox 数据..."
    echo
    
    # 停止容器（如果正在运行）
    if docker inspect "$container_name" &>/dev/null; then
        docker stop "$container_name" 2>/dev/null
        echo "容器已停止"
    fi
    
    # 解压到目标目录
    tar xzf "$backup_file" -C /root/Docker_Telebox/
    
    echo "数据已恢复到: /root/Docker_Telebox/$container_name"
    
    # 启动容器（如果存在）
    if docker inspect "$container_name" &>/dev/null; then
        docker start "$container_name"
        echo "容器已重启"
    else
        echo "请使用菜单选项 1 创建新容器"
    fi
    
    echo
    echo "恢复完成！"
    echo
    
    show_menu
}

show_menu() {
    echo
    echo "=========================================="
    echo "  TeleBox Docker 一键管理脚本"
    echo "=========================================="
    echo
    echo "请选择您需要进行的操作:"
    echo "  1) 安装 TeleBox"
    echo "  2) 卸载 TeleBox"
    echo "  3) 关闭 TeleBox"
    echo "  4) 启动 TeleBox"
    echo "  5) 重启 TeleBox"
    echo "  6) 重装 TeleBox"
    echo "  7) 查看日志"
    echo "  8) 进入容器"
    echo "  9) 查看容器信息"
    echo "  10) 备份 TeleBox"
    echo "  11) 恢复 TeleBox"
    echo "  0) 退出脚本"
    echo
    echo "  版本: 2.0.0"
    echo "  项目地址: https://github.com/Seikolove/TeleBox"
    echo
    echo -n "请输入编号: "
    read -r choice <&1
    
    case $choice in
        1)
            start_installation
            ;;
        2)
            cleanup
            ;;
        3)
            stop_telebox
            ;;
        4)
            start_telebox
            ;;
        5)
            restart_telebox
            ;;
        6)
            reinstall_telebox
            ;;
        7)
            view_logs
            ;;
        8)
            enter_container
            ;;
        9)
            show_container_info
            ;;
        10)
            backup_telebox
            ;;
        11)
            restore_telebox
            ;;
        0)
            echo "感谢使用，再见！"
            exit 0
            ;;
        *)
            echo "输入错误，请重新选择"
            sleep 2
            show_menu
            ;;
    esac
}

# 主程序入口
show_menu
