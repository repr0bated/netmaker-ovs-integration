#!/bin/bash
# move-ct-bridge.sh
# Usage: ./move-ct-bridge.sh <CTID>
set -euo pipefail

CT="$1"
BRIDGE="ovsbr0"

echo "➡️ Stopping container $CT..."
pct stop "$CT"

echo "🔁 Updating network interfaces on CT $CT..."
# Get existing netX lines and update bridge, keep IP/gw same
for net in $(pct config "$CT" | grep '^net' | awk -F: '{print $1}'); do
  cfg=$(pct config "$CT" | grep "^${net}:" | cut -d' ' -f2-)
  # replace bridge value
  newcfg=$(echo "$cfg" | sed -E "s/bridge=[^,]+/bridge=$BRIDGE/")
  pct set "$CT" -"${net}" "$newcfg"
  echo "• Updated $net: $newcfg"
done

echo "🎬 Starting container $CT..."
pct start "$CT"

echo "✅ Verifying config..."
pct config "$CT" | grep '^net' || {
  echo "⚠️ No net entries found in config!"
  exit 1
}

echo "🌐 Testing network connectivity from CT..."
# Test first gateway
gw=$(pct config "$CT" | grep '^net0:' | grep -o 'gw=[^,]*' | cut -d= -f2)
pct exec "$CT" -- ping -c2 "$gw" >/dev/null && echo "✔️ Reachable gateway $gw" || echo "❌ Cannot reach gateway $gw"

echo "✅ Move complete. Container $CT is now attached to bridge $BRIDGE."
