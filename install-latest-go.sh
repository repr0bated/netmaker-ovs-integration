#!/bin/bash
set -e

echo "[*] Fetching latest Go version info..."

GO_JSON=$(curl -s https://go.dev/dl/?mode=json)
GO_URL=$(echo "$GO_JSON" | grep -Eo 'https://go.dev/dl/go[0-9.]+\.linux-amd64\.tar\.gz' | head -n1)
GO_TARBALL=$(basename "$GO_URL")

echo "[*] Downloading $GO_TARBALL ..."
curl -LO "$GO_URL"

echo "[*] Removing previous Go installation..."
sudo rm -rf /usr/local/go

echo "[*] Extracting Go to /usr/local ..."
sudo tar -C /usr/local -xzf "$GO_TARBALL"

echo "[*] Cleaning up..."
rm -f "$GO_TARBALL"

# Add to PATH if missing
PROFILE="$HOME/.bashrc"
if [ -n "$ZSH_VERSION" ]; then
  PROFILE="$HOME/.zshrc"
fi

if ! grep -q '/usr/local/go/bin' "$PROFILE"; then
  echo 'export PATH=$PATH:/usr/local/go/bin' >> "$PROFILE"
  echo "[*] Added Go to PATH in $PROFILE"
fi

echo "[*] Reloading profile..."
source "$PROFILE" || true

echo "[*] Installed Go version:"
go version
