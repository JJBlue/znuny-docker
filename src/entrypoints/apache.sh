#!/bin/bash

# Stop on Error
set -e

if [[ -n ${WEB_PORT:-} ]]; then
    echo "WEB_PORT is not set"
    exit 1
fi

# Setup Znuny
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/znuny.sh"

# Welcome message
echo Listening on port ${WEB_PORT}

# Move to Main process
# Apache must start as root (to bind ports and open files)
# For worker processes, it drops to the user www-data via APACHE_RUN_USER
exec "$@"