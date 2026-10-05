#!/bin/bash

# Stop on Error
# Terminate if not all variables are set
set -eu

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