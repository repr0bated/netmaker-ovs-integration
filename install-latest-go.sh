#!/bin/bash
set -e

echo "[*] Fetching latest Go version..."
GO_URL=$(curl -sSL https://go.dev/dl/ | grep -Eo 'https://go.dev/dl/go[0-9.]+\.linux-amd64\.tar\.gz' | head -n1)
GO_TARBALL=$(basename "$GO_URL")

echo "[*] Downloading $GO_TARBALL ..."
curl -LO "$GO_URL"

echo "[*] Removing previous Go installation (if any)..."
sudo rm -rf /usr/local/go

echo "[*] Extracting Go to /usr/local ..."
sudo tar -C /usr/local -xzf "$GO_TARBALL"

echo "[*] Cleaning up..."
rm -f "$GO_TARBALL"

# Setup environment
PROFILE="$HOME/.bashrc"
if [ -n "$ZSH_VERSION" ]; then
  PROFILE="$HOME/.zshrc"
fi

if ! grep -q '/usr/local/go/bin' "$PROFILE"; then
  echo 'export PATH=$PATH:/usr/local/go/bin' >> "$PROFILE"
  echo "[*] Added Go to PATH in $PROFILE"
fi

echo "[*] Reloading shell profile..."
source "$PROFILE"

echo "[*] Go installed successfully:"
go version
