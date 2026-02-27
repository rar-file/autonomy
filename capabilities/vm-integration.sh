#!/bin/bash
# VM Integration Module — Deep System Access
# Provides autonomy with full VM introspection and control capabilities

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"

source "$AUTONOMY_DIR/lib/logging.sh" 2>/dev/null || true

# ── Process Management ──────────────────────────────────────

vm_process_list() {
    ps aux --forest 2>/dev/null || ps aux
}

vm_process_tree() {
    pstree -p 2>/dev/null || echo "pstree not available"
}

vm_process_details() {
    local pid="$1"
    [[ -z "$pid" ]] && { echo "Usage: vm_process_details <pid>"; return 1; }
    cat "/proc/$pid/status" 2>/dev/null || echo "Process $pid not found"
}

vm_process_kill() {
    local pid="$1"
    local signal="${2:-TERM}"
    [[ -z "$pid" ]] && { echo "Usage: vm_process_kill <pid> [signal]"; return 1; }
    kill -"$signal" "$pid" 2>&1
}

vm_process_memory() {
    local pid="$1"
    [[ -z "$pid" ]] && { echo "Usage: vm_process_memory <pid>"; return 1; }
    cat "/proc/$pid/smaps_rollup" 2>/dev/null || cat "/proc/$pid/status" | grep -i vmrss
}

vm_top_cpu() {
    ps aux --sort=-%cpu | head -20
}

vm_top_memory() {
    ps aux --sort=-%mem | head -20
}

# ── Service Management (systemd) ─────────────────────────────

vm_service_list() {
    systemctl list-units --type=service --state=running --no-pager 2>/dev/null || echo "systemd not available"
}

vm_service_status() {
    local service="$1"
    [[ -z "$service" ]] && { echo "Usage: vm_service_status <service>"; return 1; }
    systemctl status "$service" --no-pager 2>&1
}

vm_service_logs() {
    local service="$1"
    local lines="${2:-50}"
    [[ -z "$service" ]] && { echo "Usage: vm_service_logs <service> [lines]"; return 1; }
    journalctl -u "$service" -n "$lines" --no-pager 2>&1
}

vm_service_restart() {
    local service="$1"
    [[ -z "$service" ]] && { echo "Usage: vm_service_restart <service>"; return 1; }
    systemctl restart "$service" 2>&1
}

vm_service_enable() {
    local service="$1"
    [[ -z "$service" ]] && { echo "Usage: vm_service_enable <service>"; return 1; }
    systemctl enable "$service" 2>&1
}

# ── Resource Monitoring ─────────────────────────────────────

vm_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1
}

vm_memory_usage() {
    free -h
}

vm_disk_usage() {
    df -h
}

vm_disk_io() {
    iostat -x 1 1 2>/dev/null || echo "iostat not available (install sysstat)"
}

vm_network_io() {
    cat /proc/net/dev | tail -n +3 | awk '{print $1 ": RX=" $2 " bytes, TX=" $10 " bytes"}'
}

vm_load_average() {
    cat /proc/loadavg
}

vm_uptime() {
    uptime
}

# ── Network ─────────────────────────────────────────────────

vm_network_connections() {
    ss -tuln 2>/dev/null || netstat -tuln 2>/dev/null || echo "Neither ss nor netstat available"
}

vm_network_routes() {
    ip route 2>/dev/null || route -n
}

vm_network_interfaces() {
    ip addr 2>/dev/null || ifconfig
}

vm_dns_lookup() {
    local host="$1"
    [[ -z "$host" ]] && { echo "Usage: vm_dns_lookup <hostname>"; return 1; }
    nslookup "$host" 2>&1 || dig "$host" +short 2>&1
}

vm_ping() {
    local host="$1"
    local count="${2:-3}"
    [[ -z "$host" ]] && { echo "Usage: vm_ping <host> [count]"; return 1; }
    ping -c "$count" "$host" 2>&1
}

# ── Storage ─────────────────────────────────────────────────

vm_storage_list() {
    lsblk 2>/dev/null || fdisk -l 2>/dev/null | head -20
}

vm_storage_mounts() {
    mount | column -t
}

vm_storage_df() {
    df -hT
}

vm_storage_du() {
    local path="${1:-.}"
    du -sh "$path" 2>/dev/null || du -sk "$path"
}

vm_storage_largest_files() {
    local path="${1:-.}"
    find "$path" -type f -exec du -h {} + 2>/dev/null | sort -rh | head -20
}

# ── Docker Integration ─────────────────────────────────────

vm_docker_ps() {
    docker ps -a 2>&1
}

vm_docker_images() {
    docker images 2>&1
}

vm_docker_logs() {
    local container="$1"
    local lines="${2:-50}"
    [[ -z "$container" ]] && { echo "Usage: vm_docker_logs <container> [lines]"; return 1; }
    docker logs --tail "$lines" "$container" 2>&1
}

vm_docker_stats() {
    docker stats --no-stream 2>&1
}

vm_docker_inspect() {
    local container="$1"
    [[ -z "$container" ]] && { echo "Usage: vm_docker_inspect <container>"; return 1; }
    docker inspect "$container" 2>&1 | jq . 2>/dev/null || docker inspect "$container" 2>&1
}

vm_docker_exec() {
    local container="$1"
    local cmd="${2:-sh}"
    [[ -z "$container" ]] && { echo "Usage: vm_docker_exec <container> [command]"; return 1; }
    docker exec -it "$container" "$cmd" 2>&1
}

vm_docker_networks() {
    docker network ls 2>&1
}

vm_docker_volumes() {
    docker volume ls 2>&1
}

vm_docker_compose_ps() {
    docker compose ps 2>&1 || docker-compose ps 2>&1
}

vm_docker_compose_logs() {
    local lines="${1:-50}"
    docker compose logs --tail="$lines" 2>&1 || docker-compose logs --tail="$lines" 2>&1
}

# ── Package Management ─────────────────────────────────────

vm_packages_list() {
    if command -v dpkg &>/dev/null; then
        dpkg -l | tail -n +6
    elif command -v rpm &>/dev/null; then
        rpm -qa
    elif command -v pacman &>/dev/null; then
        pacman -Q
    else
        echo "Unknown package manager"
    fi
}

vm_packages_search() {
    local query="$1"
    [[ -z "$query" ]] && { echo "Usage: vm_packages_search <query>"; return 1; }
    if command -v apt &>/dev/null; then
        apt search "$query" 2>&1 | head -20
    elif command -v dnf &>/dev/null; then
        dnf search "$query" 2>&1 | head -20
    else
        echo "Package search not available"
    fi
}

# ── User & Permissions ─────────────────────────────────────

vm_users_list() {
    cat /etc/passwd | cut -d: -f1
}

vm_groups_list() {
    cat /etc/group | cut -d: -f1
}

vm_current_user() {
    id
}

vm_sudoers_check() {
    sudo -l 2>&1
}

# ── Kernel & Hardware ──────────────────────────────────────

vm_kernel_info() {
    uname -a
}

vm_kernel_modules() {
    lsmod | head -20
}

vm_cpu_info() {
    cat /proc/cpuinfo | head -30
}

vm_memory_info() {
    cat /proc/meminfo | head -20
}

vm_pci_devices() {
    lspci 2>/dev/null || echo "lspci not available"
}

vm_usb_devices() {
    lsusb 2>/dev/null || echo "lsusb not available"
}

# ── Logs & Journal ─────────────────────────────────────────

vm_logs_journal() {
    local lines="${1:-50}"
    journalctl -n "$lines" --no-pager 2>&1
}

vm_logs_dmesg() {
    dmesg | tail -50
}

vm_logs_syslog() {
    tail -50 /var/log/syslog 2>/dev/null || tail -50 /var/log/messages 2>/dev/null || echo "Syslog not found"
}

vm_logs_auth() {
    tail -50 /var/log/auth.log 2>/dev/null || echo "Auth log not found"
}

# ── Security ────────────────────────────────────────────────

vm_firewall_status() {
    ufw status 2>/dev/null || iptables -L -n 2>/dev/null | head -20 || echo "Firewall tool not found"
}

vm_selinux_status() {
    getenforce 2>/dev/null || echo "SELinux not available"
}

vm_open_ports() {
    ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null
}

vm_listening_processes() {
    ss -tlnp 2>/dev/null | grep LISTEN || netstat -tlnp 2>/dev/null | grep LISTEN
}

# ── Command Router ──────────────────────────────────────────

case "${1:-}" in
    process_list) vm_process_list ;;
    process_tree) vm_process_tree ;;
    process_details) vm_process_details "$2" ;;
    process_kill) vm_process_kill "$2" "$3" ;;
    top_cpu) vm_top_cpu ;;
    top_memory) vm_top_memory ;;
    service_list) vm_service_list ;;
    service_status) vm_service_status "$2" ;;
    service_logs) vm_service_logs "$2" "$3" ;;
    cpu) vm_cpu_usage ;;
    memory) vm_memory_usage ;;
    disk) vm_disk_usage ;;
    load) vm_load_average ;;
    uptime) vm_uptime ;;
    network_connections) vm_network_connections ;;
    network_interfaces) vm_network_interfaces ;;
    dns) vm_dns_lookup "$2" ;;
    ping) vm_ping "$2" "$3" ;;
    storage_list) vm_storage_list ;;
    storage_mounts) vm_storage_mounts ;;
    storage_df) vm_storage_df ;;
    storage_du) vm_storage_du "$2" ;;
    docker_ps) vm_docker_ps ;;
    docker_images) vm_docker_images ;;
    docker_logs) vm_docker_logs "$2" "$3" ;;
    docker_stats) vm_docker_stats ;;
    docker_inspect) vm_docker_inspect "$2" ;;
    docker_networks) vm_docker_networks ;;
    docker_volumes) vm_docker_volumes ;;
    packages_list) vm_packages_list ;;
    users_list) vm_users_list ;;
    current_user) vm_current_user ;;
    kernel_info) vm_kernel_info ;;
    cpu_info) vm_cpu_info ;;
    memory_info) vm_memory_info ;;
    logs_journal) vm_logs_journal "$2" ;;
    logs_dmesg) vm_logs_dmesg ;;
    firewall) vm_firewall_status ;;
    open_ports) vm_open_ports ;;
    *)
        echo "VM Integration Module"
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Process: process_list, process_tree, process_details <pid>, process_kill <pid> [signal], top_cpu, top_memory"
        echo "Services: service_list, service_status <svc>, service_logs <svc> [lines]"
        echo "Resources: cpu, memory, disk, load, uptime"
        echo "Network: network_connections, network_interfaces, dns <host>, ping <host> [count]"
        echo "Storage: storage_list, storage_mounts, storage_df, storage_du [path]"
        echo "Docker: docker_ps, docker_images, docker_logs <c> [n], docker_stats, docker_inspect <c>"
        echo "System: packages_list, users_list, current_user, kernel_info, cpu_info, memory_info"
        echo "Logs: logs_journal [lines], logs_dmesg"
        echo "Security: firewall, open_ports"
        ;;
esac
