#!/bin/bash
set -euo pipefail

REQUIRED_PACKER_VERSION="1.9.0"

# ── Idempotency check ─────────────────────────────────────────────────────────

if command -v packer >/dev/null 2>&1; then
    PACKER_VERSION=$(packer version 2>/dev/null | head -1 | sed 's/^Packer v//')
    if [ "$(printf '%s\n' "$REQUIRED_PACKER_VERSION" "$PACKER_VERSION" | sort -V | head -n1)" = "$REQUIRED_PACKER_VERSION" ]; then
        echo "✅ Packer $PACKER_VERSION already installed and meets requirement (>= $REQUIRED_PACKER_VERSION)."
        exit 0
    fi
    echo "Packer $PACKER_VERSION is installed but too old (required >= $REQUIRED_PACKER_VERSION). Reinstalling..."
fi

# ── Prerequisites ─────────────────────────────────────────────────────────────

for cmd in curl gpg lsb_release; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "❌ '$cmd' not found. Install with: sudo apt-get install -y ${cmd/lsb_release/lsb-release}"
        exit 1
    }
done

# ── HashiCorp APT repository ──────────────────────────────────────────────────

echo "Adding HashiCorp APT repository..."

curl -sSfL https://apt.releases.hashicorp.com/gpg | \
    sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "Verifying key fingerprint..."
gpg --no-default-keyring \
    --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    --fingerprint

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

# ── Install ───────────────────────────────────────────────────────────────────

echo "Installing Packer..."
sudo apt-get update -q
sudo apt-get install -y packer

# ── Verify ────────────────────────────────────────────────────────────────────

INSTALLED_VERSION=$(packer version 2>/dev/null | head -1 | sed 's/^Packer v//')
if [ "$(printf '%s\n' "$REQUIRED_PACKER_VERSION" "$INSTALLED_VERSION" | sort -V | head -n1)" != "$REQUIRED_PACKER_VERSION" ]; then
    echo "❌ Installed Packer $INSTALLED_VERSION does not meet requirement (>= $REQUIRED_PACKER_VERSION)."
    exit 1
fi

echo "✅ Packer $INSTALLED_VERSION installed at $(command -v packer)."
