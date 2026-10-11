#!/bin/bash

# Stop on Error
# Terminate if not all variables are set
set -eu

# A stale PID file from a previous run of the same container (docker restart)
# makes Apache refuse to start ("already running"), because the PID is reused.
rm -f "${APACHE_PID_FILE:-/var/run/apache2/apache2.pid}"

# Set Terminination Handler
term_handler() {
    echo "Termination signal received"
    echo "Apache is being stopped..."
    apachectl stop || true
    exit 0
}

trap term_handler INT TERM

# Starting Apache
echo "Apache is starting..."

apache2 -DFOREGROUND