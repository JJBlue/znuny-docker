#!/bin/bash
# Znuny docker installer
#
#   ./install.sh [--env-file FILE] [--with-db] [--no-daemon] [--build]

set -euo pipefail
die() { echo "ERROR: $*" >&2; exit 1; }

# Check previous
command -v docker >/dev/null 2>&1 || die "docker is not installed"
docker compose version >/dev/null 2>&1 || die "'docker compose' (v2 plugin) is not available"

# Variables
ENV_FILE=".env"
WITH_DB=0
WITH_DAEMON=1
BUILD=0



#############
# Functions #
#############

usage() {
    cat <<USAGE
Usage: $0 [options]

  -e, --env-file FILE   env file in ./src (default: .env), f.e. .env.instance1
      --with-db         also start the MariaDB container (docker-compose-db.yml)
      --no-daemon       do not start the Znuny daemon container
      --build           rebuild the images (f.e. after changing ZNUNY_VERSION)
  -h, --help            this help
USAGE
}

# Reads VAR from the env file without sourcing it (tolerates CRLF line endings, quotes, spaces)
env_get() {
    local name="$1" default="${2:-}" val
    val="$(grep -E "^[[:space:]]*${name}=" "$ENV_FILE" | tail -n1 | cut -d= -f2- || true)"
    val="$(printf '%s' "$val" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/")"
    printf '%s' "${val:-$default}"
}



##########
# Script #
##########

# Read Lines
while [ $# -gt 0 ]; do
    case "$1" in
        -e|--env-file) [ $# -ge 2 ] || die "$1 needs a file name"; ENV_FILE="$2"; shift 2 ;;
        --with-db)     WITH_DB=1; shift ;;
        --no-daemon)   WITH_DAEMON=0; shift ;;
        --build)       BUILD=1; shift ;;
        -h|--help)     usage; exit 0 ;;
        *)             usage >&2; die "unknown option: $1" ;;
    esac
done

# Change to src directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/src" || exit 1

# Check configuration
[ -f "$ENV_FILE" ] || die "env file '$ENV_FILE' not found in $(pwd)"


# Get & set variables
INSTANCE="$(env_get ZNUNY_INSTANCE default)"
BASE="$(env_get ZNUNY_PERSISTENT_FOLDER /opt/znuny)"

# Check variables
[[ "$INSTANCE" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die "ZNUNY_INSTANCE '$INSTANCE' is invalid: use lower case letters, digits, '-' and '_' only"
[[ "$WITH_DB" -eq 1 && "$WITH_DAEMON" -eq 0 ]] && die "Database without daemon makes no sense"



################
# Host folders #
################

# OS Folders
for d in ca-certificates; do
    mkdir -p "${BASE}/os/${d}" || die "cannot create ${BASE}/os/${d} (permissions? run with sudo or change ZNUNY_PERSISTENT_FOLDER in $ENV_FILE)"
done

# Znuny Folders
for d in app persistent log article htdocs_custom smime; do
    mkdir -p "${BASE}/instances/${INSTANCE}/${d}" || die "cannot create ${BASE}/instances/${INSTANCE}/${d} (permissions? run with sudo or change ZNUNY_PERSISTENT_FOLDER in $ENV_FILE)"
done

for d in certs private; do
    mkdir -p "${BASE}/instances/${INSTANCE}/smime/${d}" || die "cannot create ${BASE}/instances/${INSTANCE}/smime/${d} (permissions? run with sudo or change ZNUNY_PERSISTENT_FOLDER in $ENV_FILE)"
done



###########
# Secrets #
###########

mkdir -p secrets

if [ "$WITH_DB" = 1 ]; then
    [ -f "secrets/db_root_password" ] || die "secrets/db_root_password not found"
fi

[ -f "secrets/db_password_${INSTANCE}" ] || die "secrets/db_password_${INSTANCE} not found"
[ -f "secrets/znuny_admin_password_${INSTANCE}" ] || die "secrets/znuny_admin_password_${INSTANCE} not found"



#########
# Start #
#########

COMPOSE_FILES=(-f docker-compose.yml)
[ "$WITH_DAEMON" = 1 ] && COMPOSE_FILES+=(-f docker-compose-daemon.yml)
[ "$WITH_DB" = 1 ]     && COMPOSE_FILES+=(-f docker-compose-db.yml)

UP_ARGS=(-d)
[ "$BUILD" = 1 ] && UP_ARGS+=(--build)

echo "Starting project with: ${COMPOSE_FILES[*]}"
docker compose --env-file "$ENV_FILE" "${COMPOSE_FILES[@]}" up "${UP_ARGS[@]}"