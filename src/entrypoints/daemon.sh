#!/bin/bash

ZNUNY_HOME=${ZNUNY_HOME}

# Stop on Error
set -e

# Setup Znuny
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/znuny.sh"

cd ${ZNUNY_HOME}
exec gosu znuny "$@"
