#!/usr/bin/env bash

set -Eeuo pipefail
export LC_ALL=C.UTF-8

usage() {
    cat <<'HELP'
本机服务管理器（中文）

用法：
  service-manager-cn.sh                 打开交互菜单
  service-manager-cn.sh all             查看服务、端口和容器
  service-manager-cn.sh list            查看运行中的系统服务
  service-manager-cn.sh list-all        查看全部系统服务
  service-manager-cn.sh user-list       查看运行中的用户服务
  service-manager-cn.sh ports           查看监听端口
  service-manager-cn.sh docker          查看 Docker 容器
  service-manager-cn.sh 操作 服务名     管理系统服务
  service-manager-cn.sh user-操作 服务名
                                       管理当前用户的服务

支持的操作：start、stop、restart、status、enable、disable、logs

示例：
  service-manager-cn.sh status nginx
  service-manager-cn.sh restart ssh
  service-manager-cn.sh logs fail2ban
  service-manager-cn.sh user-restart hermes-gateway
HELP
}

die() {
    printf '错误：%s\n' "$*" >&2
    exit 1
}

need_command() {
    command -v "$1" >/dev/null 2>&1 || die "找不到命令：$1"
}

set_scope() {
    CTL=(systemctl)
    if [[ "$1" == user ]]; then
        CTL+=(--user)
    fi
}

normalize_service() {
    local scope="$1"
    local service="$2"
    local load_state

    [[ -n "$service" ]] || die '服务名不能为空'
    [[ "$service" =~ ^[[:alnum:]_.@:-]+$ ]] || die "无效的服务名：$service"
    [[ "$service" == *.service ]] || service="${service}.service"

    set_scope "$scope"
    load_state="$("${CTL[@]}" show "$service" -p LoadState --value 2>/dev/null || true)"
    [[ "$load_state" == loaded ]] || die "找不到服务：$service"
    printf '%s\n' "$service"
}

load_properties() {
    local scope="$1"
    local service="$2"
    local key value

    SERVICE_ACTIVE=''
    SERVICE_ENABLED=''
    SERVICE_DESCRIPTION=''
    SERVICE_PID=''
    SERVICE_SINCE=''
    set_scope "$scope"

    while IFS='=' read -r key value; do
        case "$key" in
            ActiveState) SERVICE_ACTIVE="$value" ;;
            UnitFileState) SERVICE_ENABLED="$value" ;;
            Description) SERVICE_DESCRIPTION="$value" ;;
            MainPID) SERVICE_PID="$value" ;;
            ActiveEnterTimestamp) SERVICE_SINCE="$value" ;;
        esac
    done < <("${CTL[@]}" show "$service" \
        -p ActiveState -p UnitFileState -p Description -p MainPID \
        -p ActiveEnterTimestamp 2>/dev/null)
}

service_description_zh() {
    local unit="${1%.service}"
    local original="$2"

    case "$unit" in
        nginx)                 printf 'Web 服务器和反向代理' ;;
        ssh|sshd)              printf 'SSH 远程登录服务' ;;
        docker)                printf 'Docker 容器管理引擎' ;;
        containerd)            printf '容器运行时' ;;
        fail2ban)              printf '登录攻击防护服务' ;;
        komari-agent)          printf 'Komari 服务器监控代理' ;;
        hermes-gateway)        printf 'Hermes 消息平台网关' ;;
        caddy)                 printf 'Caddy Web 服务器' ;;
        caddy-api)             printf 'Caddy 管理接口' ;;
        avahi-daemon)          printf '局域网设备发现服务' ;;
        cron)                  printf '定时任务调度服务' ;;
        dbus)                  printf '系统进程消息总线' ;;
        apparmor)              printf '应用程序安全防护' ;;
        networking)            printf '系统网络管理服务' ;;
        NetworkManager)        printf '网络连接管理服务' ;;
        systemd-journald)      printf '系统日志管理服务' ;;
        systemd-logind)        printf '用户登录会话管理' ;;
        systemd-udevd)         printf '硬件设备事件管理' ;;
        systemd-timesyncd)     printf '系统时间同步服务' ;;
        systemd-resolved)      printf '域名解析服务' ;;
        rsyslog)               printf '系统日志收集服务' ;;
        certbot)               printf 'HTTPS 证书自动续期' ;;
        unattended-upgrades)  printf '系统安全更新服务' ;;
        apt-daily)             printf '软件包索引定时更新' ;;
        apt-daily-upgrade)     printf '软件包定时升级' ;;
        getty@*)               printf '本地终端登录服务' ;;
        serial-getty@*)        printf '串口终端登录服务' ;;
        user@*)                printf '用户级服务管理器' ;;
        *)
            if [[ -n "$original" ]]; then
                printf '其他系统组件（%s）' "$original"
            else
                printf '其他系统组件'
            fi
            ;;
    esac
}

active_state_zh() {
    case "$1" in
        active)       printf '运行中' ;;
        inactive)     printf '已停止' ;;
        failed)       printf '启动失败' ;;
        activating)  printf '正在启动' ;;
        deactivating) printf '正在停止' ;;
        reloading)    printf '正在重载' ;;
        *)            printf '%s' "${1:-未知}" ;;
    esac
}

enable_state_zh() {
    case "$1" in
        enabled)         printf '已启用' ;;
        enabled-runtime) printf '临时启用' ;;
        disabled)        printf '未启用' ;;
        static)          printf '静态依赖' ;;
        indirect)        printf '间接启用' ;;
        masked)          printf '已屏蔽' ;;
        generated)       printf '自动生成' ;;
        transient)       printf '临时服务' ;;
        *)               printf '%s' "${1:-未知}" ;;
    esac
}

show_services() {
    local scope="$1"
    local mode="$2"
    local unit
    local -a units=()

    need_command systemctl
    set_scope "$scope"
    if [[ "$mode" == running ]]; then
        mapfile -t units < <("${CTL[@]}" list-units --type=service --state=running \
            --no-legend --no-pager --plain | awk '{print $1}')
    else
        mapfile -t units < <("${CTL[@]}" list-unit-files --type=service \
            --no-legend --no-pager | awk '{print $1}')
    fi

    ((${#units[@]} > 0)) || { printf '没有找到服务。\n'; return; }

    printf '%-36s | %-10s | %-10s | %s\n' '服务名称' '运行状态' '开机状态' '中文说明'
    printf '%s\n' '-------------------------------------+------------+------------+----------------------------------------'
    for unit in "${units[@]}"; do
        load_properties "$scope" "$unit"
        printf '%-36s | %-10s | %-10s | %s\n' \
            "$unit" \
            "$(active_state_zh "$SERVICE_ACTIVE")" \
            "$(enable_state_zh "$SERVICE_ENABLED")" \
            "$(service_description_zh "$unit" "$SERVICE_DESCRIPTION")"
    done
}

show_ports() {
    local netid state recvq sendq local_addr peer_addr process state_zh

    need_command ss
    printf '%-6s | %-8s | %-28s | %s\n' '协议' '状态' '本地监听地址' '进程'
    printf '%s\n' '-------+----------+------------------------------+------------------------------'
    while read -r netid state recvq sendq local_addr peer_addr process; do
        case "$state" in
            LISTEN) state_zh='监听' ;;
            UNCONN) state_zh='无连接' ;;
            *) state_zh="$state" ;;
        esac
        printf '%-6s | %-8s | %-28s | %s\n' \
            "$netid" "$state_zh" "$local_addr" "${process:--}"
    done < <(ss -lntupH)
}

show_docker() {
    local ids

    if ! command -v docker >/dev/null 2>&1; then
        printf 'Docker 未安装。\n'
        return
    fi
    if ! docker info >/dev/null 2>&1; then
        printf 'Docker 服务未运行或当前用户无权访问。\n'
        return
    fi

    ids="$(docker ps -aq)"
    if [[ -z "$ids" ]]; then
        printf '当前没有 Docker 容器。\n'
    else
        docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
    fi
}

show_status() {
    local scope="$1"
    local service="$2"

    load_properties "$scope" "$service"
    printf '服务名称：%s\n' "$service"
    printf '中文说明：%s\n' "$(service_description_zh "$service" "$SERVICE_DESCRIPTION")"
    printf '运行状态：%s\n' "$(active_state_zh "$SERVICE_ACTIVE")"
    printf '开机状态：%s\n' "$(enable_state_zh "$SERVICE_ENABLED")"
    [[ -n "$SERVICE_PID" && "$SERVICE_PID" != 0 ]] && printf '主进程号：%s\n' "$SERVICE_PID"
    [[ -n "$SERVICE_SINCE" ]] && printf '启动时间：%s\n' "$SERVICE_SINCE"
}

manage_service() {
    local scope="$1"
    local action="$2"
    local requested="$3"
    local service action_zh

    need_command systemctl
    if [[ "$scope" == system && "$action" != status && "$action" != logs ]]; then
        [[ "$(id -u)" -eq 0 ]] || die '管理系统服务需要 root 权限，请使用 sudo'
    fi

    service="$(normalize_service "$scope" "$requested")"
    set_scope "$scope"
    case "$action" in
        status)
            show_status "$scope" "$service"
            return
            ;;
        logs)
            printf '正在显示 %s 最近 50 行日志：\n\n' "$service"
            if [[ "$scope" == user ]]; then
                journalctl --user -u "$service" -n 50 --no-pager
            else
                journalctl -u "$service" -n 50 --no-pager
            fi
            return
            ;;
        start) action_zh='启动' ;;
        stop) action_zh='停止' ;;
        restart) action_zh='重启' ;;
        enable) action_zh='设置开机启动' ;;
        disable) action_zh='取消开机启动' ;;
        *) die "不支持的操作：$action" ;;
    esac

    printf '正在%s %s……\n' "$action_zh" "$service"
    "${CTL[@]}" "$action" "$service" || die '操作失败，请查看服务日志'
    printf '操作成功。\n\n'
    show_status "$scope" "$service"
}

show_all() {
    printf '=== 运行中的系统服务 ===\n'
    show_services system running
    printf '\n=== 运行中的用户服务 ===\n'
    show_services user running
    printf '\n=== 监听端口 ===\n'
    show_ports
    printf '\n=== Docker 容器 ===\n'
    show_docker
}

interactive_action() {
    local action="$1"
    local service scope=system answer

    printf '服务名（用户服务加 user: 前缀）：'
    read -r service
    [[ -n "$service" ]] || { printf '未输入服务名。\n'; return; }
    if [[ "$service" == user:* ]]; then
        scope=user
        service="${service#user:}"
    fi

    if [[ "$action" == stop || "$action" == restart || "$action" == disable ]]; then
        printf '确认操作 %s？[y/N] ' "$service"
        read -r answer
        [[ "$answer" =~ ^[Yy]$ ]] || { printf '已取消。\n'; return; }
    fi
    manage_service "$scope" "$action" "$service"
}

pause_menu() {
    printf '\n按回车键返回菜单……'
    read -r _
}

interactive_menu() {
    local choice

    while true; do
        printf '\n========== 本机服务管理器 ==========\n'
        printf ' 1. 运行中的系统服务    2. 全部系统服务\n'
        printf ' 3. 监听端口            4. Docker 容器\n'
        printf ' 5. 启动服务            6. 停止服务\n'
        printf ' 7. 重启服务            8. 服务状态\n'
        printf ' 9. 设置开机启动       10. 取消开机启动\n'
        printf '11. 查看服务日志       12. 用户级服务\n'
        printf ' 0. 退出\n'
        printf '请选择：'
        read -r choice

        case "$choice" in
            1) show_services system running; pause_menu ;;
            2) show_services system all; pause_menu ;;
            3) show_ports; pause_menu ;;
            4) show_docker; pause_menu ;;
            5) interactive_action start; pause_menu ;;
            6) interactive_action stop; pause_menu ;;
            7) interactive_action restart; pause_menu ;;
            8) interactive_action status; pause_menu ;;
            9) interactive_action enable; pause_menu ;;
            10) interactive_action disable; pause_menu ;;
            11) interactive_action logs; pause_menu ;;
            12) show_services user running; pause_menu ;;
            0) printf '已退出。\n'; return ;;
            *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

main() {
    local command="${1:-}"
    local action

    if [[ -z "$command" ]]; then
        if [[ -t 0 ]]; then
            interactive_menu
        else
            show_all
        fi
        return
    fi

    case "$command" in
        all) [[ $# -eq 1 ]] || die 'all 不接受额外参数'; show_all ;;
        list) [[ $# -eq 1 ]] || die 'list 不接受额外参数'; show_services system running ;;
        list-all) [[ $# -eq 1 ]] || die 'list-all 不接受额外参数'; show_services system all ;;
        user-list) [[ $# -eq 1 ]] || die 'user-list 不接受额外参数'; show_services user running ;;
        user-list-all) [[ $# -eq 1 ]] || die 'user-list-all 不接受额外参数'; show_services user all ;;
        ports) [[ $# -eq 1 ]] || die 'ports 不接受额外参数'; show_ports ;;
        docker) [[ $# -eq 1 ]] || die 'docker 不接受额外参数'; show_docker ;;
        start|stop|restart|status|enable|disable|logs)
            [[ $# -eq 2 ]] || die "$command 命令需要一个服务名"
            manage_service system "$command" "$2"
            ;;
        user-start|user-stop|user-restart|user-status|user-enable|user-disable|user-logs)
            [[ $# -eq 2 ]] || die "$command 命令需要一个服务名"
            action="${command#user-}"
            manage_service user "$action" "$2"
            ;;
        -h|--help|help) usage ;;
        *) usage >&2; die "未知命令：$command" ;;
    esac
}

main "$@"
