#!/bin/bash

# Stop on Error
set -euo pipefail

: "${ZNUNY_HOME:?ZNUNY_HOME is not set}"
: "${ZNUNY_USER:?ZNUNY_USER is not set}"

# Setup Znuny
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/znuny.sh"

cd "${ZNUNY_HOME}"
exec gosu "${ZNUNY_USER}" "$@"
