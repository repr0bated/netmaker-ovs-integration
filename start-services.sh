#!/bin/bash

# Manual Service Startup Script for GhostBridge Container
# This script runs INSIDE the LXC container to start services and troubleshoot issues

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }

# Check if running inside a container
check_container_environment() {
    if [[ ! -f /.dockerenv ]] && [[ ! -f /run/.containerenv ]] && [[ ! -d /proc/vz ]]; then
        print_warning "This script is designed to run inside an LXC container"
        print_info "If you're on the Proxmox host, use: pct exec <container_id> -- /path/to/start-services.sh"
    fi
}

# Function to check service status
check_service() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        print_status "$service is running"
        return 0
    else
        print_warning "$service is not running"
        return 1
    fi
}

# Function to show logs
show_logs() {
    local service="$1"
    print_info "Last 10 log entries for $service:"
    journalctl -u "$service" --no-pager -n 10 || true
    echo
}

# Function to test EMQX config
test_emqx_config() {
    print_info "Testing EMQX configuration..."
    if emqx chkconfig 2>/dev/null; then
        print_status "EMQX configuration is valid"
        return 0
    else
        print_error "EMQX configuration has errors"
        print_info "Configuration file contents:"
        cat /etc/emqx/emqx.conf | head -20 2>/dev/null || print_warning "Could not read EMQX config file"
        return 1
    fi
}

# Function to check listening ports
check_ports() {
    print_info "Checking listening ports in container:"
    ss -tlnp | grep -E ":(1883|8081|9001)" || print_warning "No expected ports listening"
}

echo "=== GhostBridge Service Startup ==="
echo

# Check if running in container
check_container_environment

# Check current status
print_info "Current service status:"
check_service emqx || true
check_service netmaker || true
echo

# Step 1: Test and start EMQX
print_info "=== Step 1: Starting EMQX ==="
test_emqx_config

if ! check_service emqx; then
    print_info "Starting EMQX..."
    if systemctl start emqx; then
        sleep 3
        if check_service emqx; then
            print_status "✅ EMQX started successfully"
        else
            print_error "❌ EMQX failed to start"
            show_logs emqx
            exit 1
        fi
    else
        print_error "❌ Failed to start EMQX"
        show_logs emqx
        exit 1
    fi
fi

# Step 2: Test EMQX connectivity
print_info "=== Step 2: Testing EMQX Connectivity ==="
if which emqx_ctl >/dev/null 2>&1; then
    print_info "Testing EMQX cluster status..."
    if emqx_ctl status; then
        print_status "EMQX cluster status OK"
    else
        print_warning "EMQX cluster status check failed"
    fi
    
    print_info "Testing MQTT connectivity..."
    # Test with credentials if available
    if [[ -f "/etc/netmaker/mqtt-credentials.env" ]]; then
        print_info "Testing with stored credentials..."
        # Could add mosquitto client test here if needed
        print_status "EMQX connectivity test completed"
    else
        print_warning "No MQTT credentials found for testing"
    fi
else
    print_warning "emqx_ctl not available for testing"
fi

# Step 3: Start Netmaker
print_info "=== Step 3: Starting Netmaker ==="
if ! check_service netmaker; then
    print_info "Starting Netmaker..."
    if systemctl start netmaker; then
        print_info "Waiting for Netmaker to initialize..."
        sleep 5
        if check_service netmaker; then
            print_status "✅ Netmaker started successfully"
        else
            print_error "❌ Netmaker failed to start"
            show_logs netmaker
            print_info "Checking Netmaker configuration:"
            cat /etc/netmaker/config.yaml | head -20 2>/dev/null || print_warning "Could not read Netmaker config"
            exit 1
        fi
    else
        print_error "❌ Failed to start Netmaker"
        show_logs netmaker
        exit 1
    fi
fi

# Step 4: Final validation
print_info "=== Step 4: Final Validation ==="
check_ports
echo

print_info "Service status summary:"
check_service emqx && print_status "✅ EMQX: Running"
check_service netmaker && print_status "✅ Netmaker: Running"

print_info "Next steps:"
print_info "  • Check Netmaker API: curl http://$(hostname -I | tr -d ' '):8081/api/server/health"
print_info "  • Configure networking and nginx proxy on Proxmox host"
print_info "  • Set up SSL certificates and domain configuration"

print_status "🎉 Service startup completed!"