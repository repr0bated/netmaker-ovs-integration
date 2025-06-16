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
    
    # Download template if needed
    if ! pveam list local | grep -q "debian-12-standard"; then
        print_info "Downloading Debian template..."
        pveam update
        pveam download local debian-12-standard_12.2-1_amd64.tar.zst
    fi
    
    # Build container creation command
    local create_cmd="pct create $CONTAINER_ID local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst"
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