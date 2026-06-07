#!/bin/bash

# Stop on Error
set -e

# Setup Znuny
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/znuny.sh"

# You can do some boot checks, like initial setup steps here.
# Vars
external_port="${external_port:-80}"

# Welcome message
echo Listening on port ${external_port}

# Move to Main process
exec gosu www-data "$@"