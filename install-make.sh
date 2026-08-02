#!/bin/bash
set -euo pipefail

REQUIRED_PYTHON_VERSION="3.12.0"
REQUIRED_NODE_VERSION="26.4.0"

# ── Python ────────────────────────────────────────────────────────────────────

echo "Checking Python version..."
PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
if [ "$(printf '%s\n' "$REQUIRED_PYTHON_VERSION" "$PYTHON_VERSION" | sort -V | head -n1)" != "$REQUIRED_PYTHON_VERSION" ]; then
    echo "❌ Python $PYTHON_VERSION is too old. Required: $REQUIRED_PYTHON_VERSION or higher."
    exit 1
fi
echo "✅ Python $PYTHON_VERSION meets requirement."

# ── Node.js via NVM ───────────────────────────────────────────────────────────

install_node_via_nvm() {
    echo "Fetching latest NVM version..."
    NVM_VERSION=$(curl -sSf "https://api.github.com/repos/nvm-sh/nvm/releases/latest" | grep '"tag_name"' | cut -d'"' -f4)
    echo "Installing NVM ${NVM_VERSION}..."
    curl -sSfo- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash

    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    echo "Installing Node.js $REQUIRED_NODE_VERSION via NVM..."
    nvm install "$REQUIRED_NODE_VERSION"
    nvm use "$REQUIRED_NODE_VERSION"
    nvm alias default "$REQUIRED_NODE_VERSION"
    echo "✅ Node.js $(node -v) and npm $(npm -v) installed."
}

echo "Checking Node.js version..."
if ! command -v node >/dev/null 2>&1; then
    echo "Node.js not found. Installing via NVM..."
    install_node_via_nvm
else
    NODE_VERSION="$(node -v | sed 's/^v//')"
    if [ "$(printf '%s\n' "$REQUIRED_NODE_VERSION" "$NODE_VERSION" | sort -V | head -n1)" != "$REQUIRED_NODE_VERSION" ]; then
        echo "Node.js $NODE_VERSION is too old (required >= $REQUIRED_NODE_VERSION). Upgrading via NVM..."
        install_node_via_nvm
    else
        echo "✅ Node.js $NODE_VERSION meets requirement (>= $REQUIRED_NODE_VERSION)."
    fi
fi

echo ""
echo "✅ Prerequisites ready. Run 'make install' to continue."
