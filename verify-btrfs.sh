#!/bin/bash

echo "=== BTRFS Storage Verification ==="
echo

echo "1. Available storage pools:"
pvesm status | grep -E "^(Storage|local-btrfs)"
echo

echo "2. Check if local-btrfs exists and type:"
pvesm status | grep "local-btrfs" || echo "local-btrfs not found!"
echo

echo "3. Available templates on local-btrfs:"
pveam list local-btrfs 2>/dev/null | head -5 || echo "Cannot list templates on local-btrfs"
echo

echo "4. Test basic pct syntax with minimal parameters:"
echo "pct create 998 local-btrfs:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst --hostname test --memory 1024 --rootfs local-btrfs:8"
echo

echo "5. Alternative rootfs formats to try:"
echo "Option A: --rootfs local-btrfs:8,mountoptions=compress=zstd"
echo "Option B: --rootfs local-btrfs:vm-998-disk-0:8,mountoptions=compress=zstd"  
echo "Option C: --rootfs 8,mp=/,volume=local-btrfs"
echo "Option D: --storage local-btrfs --rootfs 8,mountoptions=compress=zstd"
echo

echo "6. Check PVE version for compatibility:"
pveversion