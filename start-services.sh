#!/bin/bash

# Manual Service Startup Script
# Use this to start services one by one and troubleshoot issues

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

# Find container
CONTAINER_ID=""
if [[ $# -eq 1 ]]; then
    CONTAINER_ID="$1"
else
    # Auto-detect latest container
    CONTAINER_ID=$(pct list | tail -n +2 | sort -k1 -n | tail -1 | awk '{print $1}' || echo "")
    if [[ -z "$CONTAINER_ID" ]]; then
        print_error "No container found. Please specify container ID as argument."
        exit 1
    fi
fi

print_info "Using container ID: $CONTAINER_ID"

# Function to check service status
check_service() {
    local service="$1"
    if pct exec "$CONTAINER_ID" -- systemctl is-active --quiet "$service"; then
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
    pct exec "$CONTAINER_ID" -- journalctl -u "$service" --no-pager -n 10 || true
    echo
}

# Function to test EMQX config
test_emqx_config() {
    print_info "Testing EMQX configuration..."
    if pct exec "$CONTAINER_ID" -- emqx chkconfig; then
        print_status "EMQX configuration is valid"
        return 0
    else
        print_error "EMQX configuration has errors"
        print_info "Configuration file contents:"
        pct exec "$CONTAINER_ID" -- cat /etc/emqx/emqx.conf | head -20
        return 1
    fi
}

# Function to check listening ports
check_ports() {
    print_info "Checking listening ports in container:"
    pct exec "$CONTAINER_ID" -- ss -tlnp | grep -E ":(1883|8081|9001)" || print_warning "No expected ports listening"
}

echo "=== GhostBridge Service Startup ==="
echo

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
    if pct exec "$CONTAINER_ID" -- systemctl start emqx; then
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
if pct exec "$CONTAINER_ID" -- which emqx_ctl >/dev/null 2>&1; then
    print_info "Testing EMQX cluster status..."
    if pct exec "$CONTAINER_ID" -- emqx_ctl status; then
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
    if pct exec "$CONTAINER_ID" -- systemctl start netmaker; then
        print_info "Waiting for Netmaker to initialize..."
        sleep 5
        if check_service netmaker; then
            print_status "✅ Netmaker started successfully"
        else
            print_error "❌ Netmaker failed to start"
            show_logs netmaker
            print_info "Checking Netmaker configuration:"
            pct exec "$CONTAINER_ID" -- cat /etc/netmaker/config.yaml | head -20
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
print_info "  • Check Netmaker API: curl http://$(pct exec $CONTAINER_ID -- hostname -I | tr -d ' '):8081/api/server/health"
print_info "  • Configure networking and nginx proxy on Proxmox host"
print_info "  • Set up SSL certificates and domain configuration"

print_status "🎉 Service startup completed!"