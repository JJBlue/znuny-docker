#!/bin/bash

# Stop on Error
set -e

# Setup Znuny
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/znuny.sh"

cd "/opt/znuny"
exec gosu znuny "$@"
