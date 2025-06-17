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

# Function to test mosquitto config
test_mosquitto_config() {
    print_info "Testing Mosquitto configuration..."
    if pct exec "$CONTAINER_ID" -- mosquitto -c /etc/mosquitto/mosquitto.conf -t; then
        print_status "Mosquitto configuration is valid"
        return 0
    else
        print_error "Mosquitto configuration has errors"
        print_info "Configuration file contents:"
        pct exec "$CONTAINER_ID" -- cat /etc/mosquitto/mosquitto.conf | nl
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
check_service mosquitto || true
check_service netmaker || true
echo

# Step 1: Test and start Mosquitto
print_info "=== Step 1: Starting Mosquitto ==="
test_mosquitto_config

if ! check_service mosquitto; then
    print_info "Starting Mosquitto..."
    if pct exec "$CONTAINER_ID" -- systemctl start mosquitto; then
        sleep 2
        if check_service mosquitto; then
            print_status "✅ Mosquitto started successfully"
        else
            print_error "❌ Mosquitto failed to start"
            show_logs mosquitto
            exit 1
        fi
    else
        print_error "❌ Failed to start Mosquitto"
        show_logs mosquitto
        exit 1
    fi
fi

# Step 2: Test Mosquitto connectivity
print_info "=== Step 2: Testing Mosquitto Connectivity ==="
if pct exec "$CONTAINER_ID" -- which mosquitto_pub >/dev/null 2>&1; then
    print_info "Testing MQTT publish/subscribe..."
    # Simple MQTT test (if credentials exist, use them)
    if [[ -f "/tmp/mqtt-test.txt" ]]; then rm /tmp/mqtt-test.txt; fi
    pct exec "$CONTAINER_ID" -- bash -c 'echo "test-message-$(date)" | mosquitto_pub -h 127.0.0.1 -p 1883 -t test/topic -l' && \
    print_status "MQTT publish test successful" || print_warning "MQTT publish test failed"
else
    print_warning "mosquitto_pub not available for testing"
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
check_service mosquitto && print_status "✅ Mosquitto: Running"
check_service netmaker && print_status "✅ Netmaker: Running"

print_info "Next steps:"
print_info "  • Check Netmaker API: curl http://$(pct exec $CONTAINER_ID -- hostname -I | tr -d ' '):8081/api/server/health"
print_info "  • Configure networking and nginx proxy on Proxmox host"
print_info "  • Set up SSL certificates and domain configuration"

print_status "🎉 Service startup completed!"