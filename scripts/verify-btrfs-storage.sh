#!/bin/bash
# verify-btrfs-storage.sh - Verify and monitor btrfs storage for GhostBridge deployment
set -euo pipefail

LOG_FILE="/var/log/ghostbridge-btrfs-check.log"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
print_error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; }
print_warning() { echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$LOG_FILE"; }
print_info() { echo -e "${BLUE}[i]${NC} $1" | tee -a "$LOG_FILE"; }

show_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║                 GhostBridge BTRFS Storage Verification                    ║
║                                                                           ║
║      Verifies btrfs storage pool and monitors utilization                ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Check if btrfs tools are available
check_btrfs_tools() {
    print_info "Checking btrfs tools availability..."
    
    if ! command -v btrfs >/dev/null 2>&1; then
        print_error "btrfs-progs package not installed"
        print_info "Installing btrfs-progs..."
        apt update && apt install -y btrfs-progs
    fi
    
    print_status "btrfs tools available"
}

# Verify local-btrfs storage pool exists
verify_storage_pool() {
    print_info "Verifying local-btrfs storage pool..."
    
    if ! pvesm status | grep -q "local-btrfs"; then
        print_error "local-btrfs storage pool not found in Proxmox"
        print_info "Available storage pools:"
        pvesm status | grep -E "^(local|btrfs)" || echo "  No btrfs pools found"
        
        print_info "Creating local-btrfs storage pool..."
        # Try to find btrfs filesystem
        local btrfs_mount=$(mount | grep btrfs | head -1 | awk '{print $3}' || echo "")
        
        if [[ -n "$btrfs_mount" ]]; then
            print_info "Found btrfs filesystem at: $btrfs_mount"
            # Add to Proxmox storage configuration
            pvesm add btrfs local-btrfs --path "$btrfs_mount/proxmox-storage" --content images,rootdir
            print_status "local-btrfs storage pool created"
        else
            print_error "No btrfs filesystem found - manual configuration required"
            return 1
        fi
    else
        print_status "local-btrfs storage pool exists"
    fi
}

# Check btrfs filesystem health
check_filesystem_health() {
    print_info "Checking btrfs filesystem health..."
    
    # Get btrfs mount points
    local btrfs_mounts=$(mount | grep btrfs | awk '{print $3}' | head -3)
    
    if [[ -z "$btrfs_mounts" ]]; then
        print_error "No btrfs filesystems found"
        return 1
    fi
    
    for mount_point in $btrfs_mounts; do
        print_info "Checking filesystem: $mount_point"
        
        # Check filesystem status
        if btrfs filesystem show "$mount_point" >/dev/null 2>&1; then
            print_status "Filesystem at $mount_point is healthy"
        else
            print_warning "Issues detected with filesystem at $mount_point"
        fi
        
        # Check for errors
        local error_count=$(btrfs device stats "$mount_point" 2>/dev/null | grep -v "0$" | wc -l || echo "0")
        if [[ "$error_count" -eq 0 ]]; then
            print_status "No device errors on $mount_point"
        else
            print_warning "$error_count device errors found on $mount_point"
            btrfs device stats "$mount_point" | grep -v "0$" || true
        fi
    done
}

# Monitor storage utilization
monitor_storage_utilization() {
    print_info "Monitoring btrfs storage utilization..."
    
    # Get storage pool info
    local storage_info=$(pvesm status local-btrfs 2>/dev/null || echo "")
    
    if [[ -n "$storage_info" ]]; then
        print_info "Proxmox storage pool status:"
        echo "$storage_info" | column -t
        echo
    fi
    
    # Get btrfs filesystem usage
    local btrfs_mounts=$(mount | grep btrfs | awk '{print $3}' | head -3)
    
    for mount_point in $btrfs_mounts; do
        print_info "Btrfs usage for $mount_point:"
        
        # Filesystem usage
        local fs_usage=$(btrfs filesystem usage "$mount_point" 2>/dev/null || echo "Error reading usage")
        echo "$fs_usage"
        echo
        
        # Check free space percentage
        local used_bytes=$(btrfs filesystem usage -b "$mount_point" 2>/dev/null | grep "Used:" | awk '{print $2}' | tr -d 'B' || echo "0")
        local total_bytes=$(btrfs filesystem usage -b "$mount_point" 2>/dev/null | grep "Device size:" | awk '{print $3}' | tr -d 'B' || echo "1")
        
        if [[ "$used_bytes" -gt 0 && "$total_bytes" -gt 0 ]]; then
            local usage_percent=$((used_bytes * 100 / total_bytes))
            
            if [[ $usage_percent -gt 90 ]]; then
                print_error "Storage usage critical: ${usage_percent}% used"
            elif [[ $usage_percent -gt 80 ]]; then
                print_warning "Storage usage high: ${usage_percent}% used"
            else
                print_status "Storage usage normal: ${usage_percent}% used"
            fi
        fi
    done
}

# Check container storage requirements
check_container_requirements() {
    print_info "Checking container storage requirements..."
    
    # Calculate space needed for containers
    local containers_count=${1:-3}  # Default 3 containers
    local container_size_gb=${2:-8}  # Default 8GB per container
    local total_needed_gb=$((containers_count * container_size_gb))
    
    print_info "Estimated storage needed: ${total_needed_gb}GB for $containers_count containers"
    
    # Check available space
    local available_gb=$(pvesm status local-btrfs 2>/dev/null | tail -1 | awk '{print int($4/1024/1024)}' || echo "0")
    
    if [[ $available_gb -gt $total_needed_gb ]]; then
        print_status "Sufficient space available: ${available_gb}GB free"
    else
        print_warning "Limited space: ${available_gb}GB available, ${total_needed_gb}GB needed"
    fi
}

# Create monitoring script for deployment
create_monitoring_script() {
    print_info "Creating btrfs monitoring script..."
    
    cat > /usr/local/bin/btrfs-monitor << 'EOF'
#!/bin/bash
# Continuous btrfs monitoring for GhostBridge deployment

LOG_FILE="/var/log/btrfs-monitor.log"
ALERT_THRESHOLD=85

check_usage() {
    local mount_point="$1"
    local used_bytes=$(btrfs filesystem usage -b "$mount_point" 2>/dev/null | grep "Used:" | awk '{print $2}' | tr -d 'B' || echo "0")
    local total_bytes=$(btrfs filesystem usage -b "$mount_point" 2>/dev/null | grep "Device size:" | awk '{print $3}' | tr -d 'B' || echo "1")
    
    if [[ "$used_bytes" -gt 0 && "$total_bytes" -gt 0 ]]; then
        local usage_percent=$((used_bytes * 100 / total_bytes))
        
        if [[ $usage_percent -gt $ALERT_THRESHOLD ]]; then
            echo "$(date): ALERT - $mount_point usage at ${usage_percent}%" | tee -a "$LOG_FILE"
            # Could add email notification here
        fi
        
        echo "$(date): $mount_point usage: ${usage_percent}%" >> "$LOG_FILE"
    fi
}

# Monitor all btrfs filesystems
for mount_point in $(mount | grep btrfs | awk '{print $3}'); do
    check_usage "$mount_point"
done
EOF
    
    chmod +x /usr/local/bin/btrfs-monitor
    
    # Create systemd timer for monitoring
    cat > /etc/systemd/system/btrfs-monitor.service << 'EOF'
[Unit]
Description=BTRFS Storage Monitor
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/btrfs-monitor
EOF

    cat > /etc/systemd/system/btrfs-monitor.timer << 'EOF'
[Unit]
Description=BTRFS Storage Monitor Timer
Requires=btrfs-monitor.service

[Timer]
OnCalendar=*:0/15
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    systemctl enable btrfs-monitor.timer
    systemctl start btrfs-monitor.timer
    
    print_status "BTRFS monitoring service configured"
}

# Validate deployment readiness
validate_deployment_readiness() {
    print_info "Validating deployment readiness..."
    
    local checks_passed=0
    local total_checks=4
    
    # Check 1: Storage pool exists
    if pvesm status | grep -q "local-btrfs"; then
        print_status "✓ local-btrfs storage pool available"
        ((checks_passed++))
    else
        print_error "✗ local-btrfs storage pool missing"
    fi
    
    # Check 2: Filesystem health
    local btrfs_healthy=true
    for mount_point in $(mount | grep btrfs | awk '{print $3}' | head -3); do
        if ! btrfs filesystem show "$mount_point" >/dev/null 2>&1; then
            btrfs_healthy=false
            break
        fi
    done
    
    if $btrfs_healthy; then
        print_status "✓ BTRFS filesystems healthy"
        ((checks_passed++))
    else
        print_error "✗ BTRFS filesystem issues detected"
    fi
    
    # Check 3: Sufficient space
    local available_gb=$(pvesm status local-btrfs 2>/dev/null | tail -1 | awk '{print int($4/1024/1024)}' || echo "0")
    if [[ $available_gb -gt 50 ]]; then
        print_status "✓ Sufficient storage space (${available_gb}GB)"
        ((checks_passed++))
    else
        print_error "✗ Insufficient storage space (${available_gb}GB)"
    fi
    
    # Check 4: Monitoring active
    if systemctl is-active --quiet btrfs-monitor.timer; then
        print_status "✓ BTRFS monitoring active"
        ((checks_passed++))
    else
        print_error "✗ BTRFS monitoring not active"
    fi
    
    echo
    if [[ $checks_passed -eq $total_checks ]]; then
        print_status "🎉 All BTRFS checks passed - deployment ready!"
        return 0
    else
        print_error "❌ $((total_checks - checks_passed)) checks failed - fix issues before deployment"
        return 1
    fi
}

# Main execution
main() {
    show_banner
    echo "BTRFS Storage Verification Started" | tee -a "$LOG_FILE"
    
    check_btrfs_tools
    verify_storage_pool
    check_filesystem_health
    monitor_storage_utilization
    check_container_requirements "$@"
    create_monitoring_script
    validate_deployment_readiness
    
    echo "BTRFS verification completed" | tee -a "$LOG_FILE"
}

main "$@"