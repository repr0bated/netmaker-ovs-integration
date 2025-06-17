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

# Create EMQX configuration
print_info "Creating EMQX configuration..."
pct exec "$CONTAINER_ID" -- bash -c 'cat > /etc/emqx/emqx.conf << "EOF"
## EMQX Configuration for GhostBridge Netmaker

## Node name and clustering
node.name = emqx@127.0.0.1
node.cookie = ghostbridge_emqx_cluster
cluster.discovery = manual

## MQTT TCP Listener
listener.tcp.default = 1883
listener.tcp.default.bind = 0.0.0.0:1883
listener.tcp.default.max_connections = 10240
listener.tcp.default.acceptors = 16

## MQTT WebSocket Listener
listener.ws.default = 8083
listener.ws.default.bind = 0.0.0.0:8083
listener.ws.default.mqtt_path = /mqtt
listener.ws.default.max_connections = 10240

## Authentication
allow_anonymous = false
auth.user.1.username = '"$MQTT_USERNAME"'
auth.user.1.password = '"$MQTT_PASSWORD"'

## Session Settings
session.max_subscriptions = 0
session.upgrade_qos = off
session.max_inflight = 32
session.retry_interval = 30s
session.max_awaiting_rel = 100
session.await_rel_timeout = 300s
session.enable_stats = on

## Message Queue
mqueue.max_len = 1000
mqueue.low_watermark = 0.2
mqueue.high_watermark = 0.6
mqueue.store_qos0 = true

## Logging
log.level = warning
log.dir = /var/log/emqx
log.file = emqx.log
log.rotation.size = 10MB
log.rotation.count = 5

## Management API (Dashboard)
management.listener.http = 18083
management.listener.http.bind = 0.0.0.0:18083
management.default_application.id = admin
management.default_application.secret = public

## Zones
zone.external.idle_timeout = 15s
zone.external.enable_acl = off
zone.external.enable_ban = on
zone.external.enable_stats = on
zone.external.acl_deny_action = ignore
zone.external.force_gc_policy = 16000|16MB
zone.external.force_shutdown_policy = 8000|8MB
zone.external.max_packet_size = 1MB
zone.external.max_clientid_len = 65535
zone.external.max_topic_levels = 0
zone.external.max_topic_alias = 65535
zone.external.retain_available = true
zone.external.wildcard_subscription = true
zone.external.shared_subscription = true
zone.external.server_keepalive = 0
zone.external.keepalive_backoff = 0.75
zone.external.max_subscriptions = 0
zone.external.upgrade_qos = off
zone.external.max_inflight = 32
zone.external.retry_interval = 30s
zone.external.max_awaiting_rel = 100
zone.external.await_rel_timeout = 300s
zone.external.session_expiry_interval = 7200s
zone.external.max_mqueue_len = 1000
zone.external.mqueue_priorities = none
zone.external.mqueue_default_priority = lowest
zone.external.mqueue_store_qos0 = true
zone.external.enable_flapping_detect = off
zone.external.mountpoint = ""
zone.external.use_username_as_clientid = false
zone.external.ignore_loop_deliver = false
zone.external.strict_mode = false
EOF'

# Create loaded plugins file
print_info "Configuring EMQX plugins..."
pct exec "$CONTAINER_ID" -- bash -c 'cat > /etc/emqx/loaded_plugins << "EOF"
{emqx_management, true}.
{emqx_auth_username, true}.
{emqx_recon, true}.
{emqx_retainer, true}.
{emqx_dashboard, true}.
{emqx_rule_engine, true}.
EOF'

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