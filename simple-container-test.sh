#!/bin/bash

# Simple container creation test with minimal parameters
echo "Testing basic container creation with local-btrfs..."

# Find an available container ID
CONTAINER_ID=997
while pct list | grep -q "^$CONTAINER_ID "; do
    ((CONTAINER_ID++))
done

echo "Using container ID: $CONTAINER_ID"

# Get available template
TEMPLATE=$(pveam list local-btrfs 2>/dev/null | grep "debian-12-standard" | head -1 | awk '{print $2}' || echo "")
if [[ -z "$TEMPLATE" ]]; then
    echo "No template found, using default"
    TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
fi

echo "Using template: $TEMPLATE"

# Test basic command
echo "Testing command:"
echo "pct create $CONTAINER_ID local-btrfs:vztmpl/$TEMPLATE --hostname testbtrfs --memory 1024 --storage local-btrfs --rootfs 8"

# Create a minimal test container
echo "Executing..."
if pct create $CONTAINER_ID local-btrfs:vztmpl/$TEMPLATE --hostname testbtrfs --memory 1024 --storage local-btrfs --rootfs 8; then
    echo "✅ Success! BTRFS container created with ID $CONTAINER_ID"
    echo "Cleaning up test container..."
    pct destroy $CONTAINER_ID --force
else
    echo "❌ Failed - trying without --storage parameter..."
    if pct create $CONTAINER_ID local-btrfs:vztmpl/$TEMPLATE --hostname testbtrfs --memory 1024 --rootfs local-btrfs:8; then
        echo "✅ Success with alternative format!"
        echo "Cleaning up test container..."
        pct destroy $CONTAINER_ID --force
    else
        echo "❌ Both formats failed"
    fi
fi