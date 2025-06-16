#!/bin/bash
# 02-container-create.sh - LXC Container Creation with Network Dependencies
set -euo pipefail

LOG_FILE="/var/log/ghostbridge-container-create.log"
GREEN='\033[0;32m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
print_status() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
print_error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; }
print_info() { echo -e "${BLUE}[i]${NC} $1" | tee -a "$LOG_FILE"; }

# Configuration from environment or defaults
CONTAINER_ID="${CONTAINER_ID:-100}"
CONTAINER_IP="${CONTAINER_IP:-10.0.0.151}"
BRIDGE_NAME="${BRIDGE_NAME:-ovsbr0}"
ENABLE_DUAL_IP="${ENABLE_DUAL_IP:-false}"
PUBLIC_IP_2="${PUBLIC_IP_2:-}"

# Wait for network readiness (from Phase 1)
wait_for_network() {
    print_info "Waiting for network foundation from Phase 1..."
    
    # Check OVS bridge exists and is ready
    timeout=60; count=0
    while ! ovs-vsctl br-exists "$BRIDGE_NAME" && [[ $count -lt $timeout ]]; do
        sleep 2; ((count+=2))
    done
    
    if [[ $count -ge $timeout ]]; then
        print_error "Network foundation not ready - run 01-network-setup.sh first"
        exit 1
    fi
    
    # Check private gateway is configured
    if ! ip addr show "${BRIDGE_NAME}-private" | grep -q "10.0.0.1"; then
        print_error "Private network not configured - run 01-network-setup.sh first"
        exit 1
    fi
    
    print_status "Network foundation verified"
}

# Create LXC container with proper network config
create_container() {
    print_info "Creating LXC container ID $CONTAINER_ID..."
    
    # Find and download Debian 12 template if needed
    local template_name=""
    
    # Look for available Debian 12 templates
    pveam update
    local debian12_template=$(pveam available | grep "debian-12-standard" | head -1 | awk '{print $2}' || echo "")
    
    if [[ -n "$debian12_template" ]]; then
        template_name="$debian12_template"
        print_info "Found Debian 12 template: $template_name"
        
        # Download if not already available
        if ! pveam list local 2>/dev/null | grep -q "$template_name"; then
            print_info "Downloading template..."
            if ! pveam download local "$template_name" 2>/dev/null; then
                # Try other storage pools
                local storage=$(pvesm status | grep -E "^[a-zA-Z]" | grep -v "local" | head -1 | awk '{print $1}' || echo "")
                if [[ -n "$storage" ]]; then
                    pveam download "$storage" "$template_name" || {
                        print_error "Failed to download template"
                        exit 1
                    }
                    template_ref="$storage:vztmpl/$template_name"
                else
                    print_error "No available storage for template download"
                    exit 1
                fi
            else
                template_ref="local:vztmpl/$template_name"
            fi
        else
            template_ref="local:vztmpl/$template_name"
        fi
    else
        print_error "No Debian 12 templates available"
        exit 1
    fi
    
    # Build container creation command
    local create_cmd="pct create $CONTAINER_ID $template_ref"
    create_cmd="$create_cmd --hostname ghostbridge --memory 2048 --cores 2 --storage local-btrfs --rootfs local-btrfs:8"
    create_cmd="$create_cmd --net0 name=eth0,bridge=$BRIDGE_NAME,ip=$CONTAINER_IP/24,gw=10.0.0.1"
    
    # Add dual IP interface if enabled
    if [[ "$ENABLE_DUAL_IP" == "true" && -n "$PUBLIC_IP_2" ]]; then
        create_cmd="$create_cmd --net1 name=eth1,bridge=$BRIDGE_NAME,ip=$PUBLIC_IP_2/25"
        print_info "Dual IP mode: adding public interface"
    fi
    
    create_cmd="$create_cmd --nameserver 8.8.8.8 --features nesting=1 --unprivileged 1 --onboot 1"
    
    # Create container
    if $create_cmd; then
        print_status "Container $CONTAINER_ID created"
    else
        print_error "Container creation failed"
        exit 1
    fi
}

# Start and configure container
start_container() {
    print_info "Starting container..."
    pct start "$CONTAINER_ID"
    
    # Wait for container network
    timeout=30; count=0
    while ! pct exec "$CONTAINER_ID" -- ping -c 1 8.8.8.8 >/dev/null 2>&1 && [[ $count -lt $timeout ]]; do
        sleep 2; ((count+=2))
    done
    
    if [[ $count -ge $timeout ]]; then
        print_error "Container network not ready"
        exit 1
    fi
    
    print_status "Container network is ready"
    
    # Basic container setup
    pct exec "$CONTAINER_ID" -- apt update
    pct exec "$CONTAINER_ID" -- apt install -y curl wget unzip jq openssl systemd
    
    print_status "Container configured and ready for services"
}

main() {
    echo "GhostBridge Container Creation - Phase 2" | tee -a "$LOG_FILE"
    wait_for_network
    create_container  
    start_container
    print_status "🎯 Container ready! Next: 03-mqtt-install.sh"
}

main "$@"