#!/bin/bash

# Stop on Error
set -e

# Setup Znuny
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/znuny.sh"

service nullmailer start
service cron start

ZNUNY_HOME="/opt/znuny" # TODO needed? Or can I get this from znuny.sh?
cd "$ZNUNY_HOME"

exec gosu znuny "$@"
