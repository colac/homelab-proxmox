#!/bin/bash

# Install make
#sudo apt update && sudo apt install build-essential

REQUIRED_PYTHON_VERSION="3.8.0"

PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))'); \
	if [ "$(printf '%s\n' $REQUIRED_PYTHON_VERSION $PYTHON_VERSION | sort -V | head -n1)" != "$REQUIRED_PYTHON_VERSION" ]; then \
		echo "❌ Python $PYTHON_VERSION is too old. Required: $REQUIRED_PYTHON_VERSION or higher."; \
		exit 1; \
	else \
		echo "✅ Python $PYTHON_VERSION meets requirement."; \
	fi

# NODE_VERSION=$(node -v | sed 's/v//'); \
# if [ "$(printf '%s\n' $REQUIRED_NODE_VERSION $NODE_VERSION | sort -V | head -n1)" != "$REQUIRED_NODE_VERSION" ]; then \
# 	echo "❌ Node.js $NODE_VERSION is too old. Required: $REQUIRED_NODE_VERSION or higher."; \
# 	exit 1; \
# else \
# 	echo "✅ Node.js $NODE_VERSION meets requirement."; \
# fi

# if type node >/dev/null 2>&1; then
#   echo "node exists"
# else
#   echo "node missing"
# fi

# --- 1. Check if node exists ---
if ! command -v node >/dev/null 2>&1; then
    echo "❌ Node.js is not installed or not found in PATH."
    exit 1
else
    echo "✅ node exists"
fi

# --- 2. Extract version without 'v' prefix ---
NODE_VERSION="$(node -v | sed 's/^v//')"

# --- 3. Compare with required version ---
if [ "$(printf '%s\n' "$REQUIRED_NODE_VERSION" "$NODE_VERSION" | sort -V | head -n1)" != "$REQUIRED_NODE_VERSION" ]; then
    echo "❌ Node.js $NODE_VERSION is too old. Required: $REQUIRED_NODE_VERSION+"
    exit 1
else
    echo "✅ Node.js $NODE_VERSION meets requirement (>= $REQUIRED_NODE_VERSION)" 
fi
