#!/bin/bash

###############################################################################
# Ubuntu 26.04 Template Install Tailscale
# Purpose: Install the Tailscale package and enable the daemon.
#          The node is intentionally NOT authenticated here (`tailscale up`
#          is left for later configuration via Ansible or by hand), so the
#          template stays generic and credential-free.
# Usage: Run this script as root
# Expected env vars:
#   INSTALL_TAILSCALE: If true will install Tailscale (default: true)
###############################################################################

set -e

###############################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root"
    exit 1
fi

###############################################################################

if [[ "${INSTALL_TAILSCALE:-true}" != "true" ]]; then
  log_warn "Tailscale installation disabled by variable."
  exit 0
fi

log_info "Starting Tailscale installation..."

export DEBIAN_FRONTEND=noninteractive

CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"

# Add Tailscale's package signing key and repository (apt method, mirrors the
# Docker install approach used elsewhere in this template).
mkdir -p /usr/share/keyrings
curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${CODENAME}.noarmor.gpg" \
  -o /usr/share/keyrings/tailscale-archive-keyring.gpg
chmod a+r /usr/share/keyrings/tailscale-archive-keyring.gpg || true

curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${CODENAME}.tailscale-keyring.list" \
  -o /etc/apt/sources.list.d/tailscale.list

apt-get update -y
apt-get install -y tailscale

# Enable the daemon so it starts on boot, but do NOT run `tailscale up`.
# Authentication (auth key / login) is performed later as part of host config.
systemctl enable --now tailscaled || true

log_info "Tailscale $(tailscale version | head -n1 2>/dev/null || echo 'installed')."
log_warn "Node is NOT authenticated. Run 'tailscale up' (or use Ansible) to join a tailnet."
