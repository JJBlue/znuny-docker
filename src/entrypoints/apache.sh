#!/bin/bash

# Stop on Error
set -e

# Setup Znuny
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/znuny.sh"

# You can do some boot checks, like initial setup steps here.
# Vars
WEB_PORT="${WEB_PORT:-80}"

# Welcome message
echo Listening on port ${WEB_PORT}

# Move to Main process
exec gosu www-data "$@"