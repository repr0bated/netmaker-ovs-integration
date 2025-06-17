#!/bin/bash

# EMQX Configuration Script for GhostBridge
# Configures EMQX MQTT broker for Netmaker integration

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

# Configuration
CONTAINER_ID="${1:-}"
MQTT_USERNAME="${2:-netmaker}"
MQTT_PASSWORD="${3:-$(openssl rand -base64 32 | tr -d '/+' | cut -c1-25)}"

if [[ -z "$CONTAINER_ID" ]]; then
    print_error "Usage: $0 <container_id> [username] [password]"
    exit 1
fi

print_info "Configuring EMQX in container $CONTAINER_ID"
print_info "MQTT credentials: $MQTT_USERNAME / $MQTT_PASSWORD"

# Create directories
print_info "Creating EMQX directories..."
pct exec "$CONTAINER_ID" -- mkdir -p /etc/emqx /var/lib/emqx /var/log/emqx
pct exec "$CONTAINER_ID" -- chown emqx:emqx /var/lib/emqx /var/log/emqx

# Create simple EMQX configuration (compatible with EMQX 5.x)
print_info "Creating EMQX configuration..."

# Remove any existing config first
pct exec "$CONTAINER_ID" -- rm -f /etc/emqx/emqx.conf

# Create minimal working config to avoid syntax issues
pct exec "$CONTAINER_ID" -- tee /etc/emqx/emqx.conf > /dev/null << 'EOF'
## EMQX Configuration for GhostBridge
node.name = emqx@127.0.0.1
node.cookie = ghostbridge_emqx_cluster

listeners.tcp.default.bind = 0.0.0.0:1883
listeners.tcp.default.max_connections = 10240

listeners.ws.default.bind = 0.0.0.0:8083
listeners.ws.default.mqtt_path = /mqtt
listeners.ws.default.max_connections = 10240

dashboard.listeners.http.bind = 18083
dashboard.default_username = admin
dashboard.default_password = public

authentication.1.mechanism = password_based
authentication.1.backend = built_in_database
authentication.1.user_id_type = username

authorization.no_match = allow

log.file.default.level = warning
log.file.default.file = /var/log/emqx/emqx.log
EOF

# For EMQX 5.x, we'll configure users via API after startup instead of config file
print_info "EMQX user configuration will be done via API after startup"

# Store credentials for Netmaker
print_info "Storing MQTT credentials..."
pct exec "$CONTAINER_ID" -- bash -c "echo 'MQTT_USERNAME=$MQTT_USERNAME' > /etc/netmaker/mqtt-credentials.env"
pct exec "$CONTAINER_ID" -- bash -c "echo 'MQTT_PASSWORD=$MQTT_PASSWORD' >> /etc/netmaker/mqtt-credentials.env"
pct exec "$CONTAINER_ID" -- chmod 600 /etc/netmaker/mqtt-credentials.env

# Set proper ownership
pct exec "$CONTAINER_ID" -- chown -R emqx:emqx /etc/emqx /var/lib/emqx /var/log/emqx

print_status "✅ EMQX configuration completed"
print_info "MQTT TCP: 1883"
print_info "MQTT WebSocket: 8083/mqtt"
print_info "Dashboard: 18083 (admin/public)"
print_info "Credentials: $MQTT_USERNAME / $MQTT_PASSWORD"

# Test configuration
print_info "Testing EMQX configuration..."
if pct exec "$CONTAINER_ID" -- emqx chkconfig; then
    print_status "EMQX configuration is valid"
else
    print_warning "EMQX configuration test failed - check manually"
fi

echo "Done!"