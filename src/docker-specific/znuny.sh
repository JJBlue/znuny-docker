#!/bin/bash

# Stop on Error
set -euo pipefail
die() { echo "ERROR: $*" >&2; exit 1; }

PERSISTENT_DIR="/persistent"
PERSISTENT_CFG="${PERSISTENT_DIR}/Config.pm"

export ZNUNY_HOME=${ZNUNY_HOME}
export ZNUNY_CFG="${ZNUNY_HOME}/Kernel/Config.pm"
export ZNUNY_USER="${ZNUNY_USER}"
ZNUNY_NodeID=${ZNUNY_NodeID:-1}

export ZNUNY_STAGING=${ZNUNY_STAGING}
export ZNUNY_STAGING_CFG="${ZNUNY_STAGING}/Kernel/Config.pm"
ZNUNY_VOLUMES="/opt/znuny_volumes"

APACHE_USER=${APACHE_RUN_USER:-www-data}

export DB_HOST="${DB_HOST:-znuny-db}"
export DB_PORT="${DB_PORT:-3306}"
export DB_NAME="${DB_NAME:-znuny}"
export DB_USER="${DB_USER:-znuny}"
export DB_PASSWORD_FILE="/run/secrets/db_password"
export ZNUNY_ADMIN_PASSWORD_FILE="/run/secrets/znuny_admin_password"

FQDN="$(hostname -f)"

# Input validation (these values end up in Config.pm)
[[ "$ZNUNY_NodeID" =~ ^[0-9]+$ ]] || die "ZNUNY_NodeID must be a number (got '$ZNUNY_NodeID')"
[[ "$DB_PORT" =~ ^[0-9]+$ ]]      || die "DB_PORT must be a number (got '$DB_PORT')"

# Read a secret file. Strips CR/LF, so files edited on Windows work as well.
read_secret() {
    [ -r "$1" ] || die "Secret file $1 is missing or not readable"
    tr -d '\r\n' < "$1"
}

####################
# Setup Persistent #
####################

# Set rights on the persistent folder
[ "$(stat -c '%U:%G' "$PERSISTENT_DIR")" = "${ZNUNY_USER}:${APACHE_USER}" ] || chown -R "${ZNUNY_USER}:${APACHE_USER}" "$PERSISTENT_DIR"

if [ ! -f "${ZNUNY_HOME}/bin/znuny.SetPermissions.pl" ]; then
    echo "Setting folder permissions"
    mkdir -p "${ZNUNY_HOME}/bin"
    cp "${ZNUNY_STAGING}/bin/znuny.SetPermissions.pl" "${ZNUNY_HOME}/bin/znuny.SetPermissions.pl"
    "$ZNUNY_HOME/bin/znuny.SetPermissions.pl" --znuny-user "${ZNUNY_USER}"
fi

if [ "$(stat -c '%U:%G' "$ZNUNY_VOLUMES")" != "${ZNUNY_USER}:${APACHE_USER}" ]; then
    chown -R "${ZNUNY_USER}:${APACHE_USER}" "$ZNUNY_VOLUMES"
    chmod 775 -R "$ZNUNY_VOLUMES"
fi

# Create Config.pm if it doesn't already exist
if [ ! -f "$PERSISTENT_CFG" ]; then
    echo "Persistent Config.pm not found, seeding it"
    cp "${ZNUNY_STAGING_CFG}.dist" "$PERSISTENT_CFG"

    sed -i "s/\(\$Self->{DatabaseHost}\s*=\s*\)'[^']*';/\1'$DB_HOST';/" "$PERSISTENT_CFG"
    sed -i "s/\(\$Self->{Database}\s*=\s*\)'[^']*';/\1'$DB_NAME';/"     "$PERSISTENT_CFG"
    sed -i "s/\(\$Self->{DatabaseUser}\s*=\s*\)'[^']*';/\1'$DB_USER';/" "$PERSISTENT_CFG"
    sed -i "s/\(\$Self->{DatabasePw}\s*=\s*\)'[^']*';/\1'$(read_secret "$DB_PASSWORD_FILE")';/" "$PERSISTENT_CFG"

    if grep -qE '\$Self->\{NodeID\}\s*=' "$PERSISTENT_CFG"; then
        sed -i "s/\(\$Self->{NodeID}\s*=\s*\)[0-9]\+/\1${ZNUNY_NodeID}/" "$PERSISTENT_CFG"
    else
        sed -i "s/^\s*return 1;/\\\$Self->{NodeID} = ${ZNUNY_NodeID};\n    return 1;/" "$PERSISTENT_CFG"
    fi

    chown "${ZNUNY_USER}:${APACHE_USER}" "$PERSISTENT_CFG"
    chmod 660 "$PERSISTENT_CFG"
fi

# Create Config.pm symlink if not exist
if [ ! -L "${ZNUNY_HOME}/Kernel/Config.pm" ]; then
    echo "Linking Persistent Config.pm"

    mkdir -p "${ZNUNY_HOME}/Kernel"
    chown "${ZNUNY_USER}:${APACHE_USER}" "${ZNUNY_HOME}/Kernel"

    ln -sf "$PERSISTENT_CFG" "$ZNUNY_CFG"
fi

###############
# Setup Linux #
###############

# Update certificate truststore upon change
update-ca-certificates

###############
# Setup Znuny #
###############

if [[ -v WEB_PORT ]]; then
    ZNUNY_DEFAULT_INTERFACE="${ZNUNY_DEFAULT_INTERFACE}"
    WEB_REMOTE_USER="${WEB_REMOTE_USER}"
    APACHE_CONFIG_FILE="${ZNUNY_HOME}/scripts/apache2-httpd.include.conf"
    APACHE_CONFIG_FILE_DST="/etc/apache2/conf-available/zzz_znuny.conf"

    gosu "${ZNUNY_USER}" /usr/local/bin/znuny_setup.sh 2>&1 || exit $?

    # Setup Apache Znuny config
    if [ ! -f ${APACHE_CONFIG_FILE_DST} ]; then
        ln -s ${APACHE_CONFIG_FILE} ${APACHE_CONFIG_FILE_DST}
        a2enconf zzz_znuny
    fi

    # Use OS Truststore in Znuny (needed for some functions for example package management - own repository)
    # SetEnv PERL_LWP_SSL_CA_FILE /etc/ssl/certs/ca-certificates.crt
    if ! grep -Eq '^[[:space:]]*SetEnv[[:space:]]+PERL_LWP_SSL_CA_FILE[[:space:]]+/etc/ssl/certs/ca-certificates\.crt[[:space:]]*$' "$APACHE_CONFIG_FILE"; then
        # Create unique tmp file and remove it later
        TMP_FILE=$(mktemp)
        trap 'rm -f "$TMP_FILE"' EXIT

        # Remove all existing lines
        awk '
            !/^[[:space:]]*#[[:space:]]*SetEnv[[:space:]]+PERL_LWP_SSL_CA_FILE[[:space:]]+\/etc\/ssl\/certs\/ca-certificates\.crt[[:space:]]*$/
        ' "$APACHE_CONFIG_FILE" > "$TMP_FILE"

        # Create the new file content
        {
            printf '%s\n' 'SetEnv PERL_LWP_SSL_CA_FILE /etc/ssl/certs/ca-certificates.crt'
            cat "$TMP_FILE"
        } | tee "$APACHE_CONFIG_FILE" > /dev/null
    fi

    # ACCEPT X-Forwarded-User HTTP-Header
    if [ "${WEB_REMOTE_USER}" = "true" ]; then
        # Enable Apache Module
        if ! apache2ctl -M 2>/dev/null | grep -q 'setenvif_module'; then
            a2enmod setenvif
        fi

        # Add needing lines to the file
        if ! grep -Eq '^[[:space:]]*SetEnvIf[[:space:]]+X-Forwarded-User[[:space:]]+\(\.\*\)[[:space:]]+REMOTE_USER=\$1[[:space:]]*$' "$APACHE_CONFIG_FILE"; then
            # Create unique tmp file and remove it later
            TMP_FILE=$(mktemp)
            trap 'rm -f "$TMP_FILE"' EXIT

            # Remove all existing lines
            awk '
                !/^[[:space:]]*#[[:space:]]*SetEnvIf[[:space:]]+X-Forwarded-User[[:space:]]+\(\.\*\)[[:space:]]+REMOTE_USER=\$1[[:space:]]*$/
            ' "$APACHE_CONFIG_FILE" > "$TMP_FILE"

            # Create the new file content
            {
                printf '%s\n' 'SetEnvIf X-Forwarded-User (.*) REMOTE_USER=$1'
                cat "$TMP_FILE"
            } | tee "$APACHE_CONFIG_FILE" > /dev/null
        fi
    fi

    # Redirect ... to the default interface
    case "$ZNUNY_DEFAULT_INTERFACE" in
        customer)
            DEFAULT_PAGE="customer.pl" ;;
        agent)
            DEFAULT_PAGE="index.pl" ;;
        *)
            echo "WARNING: unknown ZNUNY_DEFAULT_INTERFACE '${ZNUNY_DEFAULT_INTERFACE}', using 'agent'" >&2
            DEFAULT_PAGE="index.pl"
            ;;
    esac

    # Redirect "/znuny-web/" to the default interface
    sed -i "s|URL=/znuny/[a-z_]*\.pl|URL=/znuny/${DEFAULT_PAGE}|" ${ZNUNY_HOME}/var/httpd/htdocs/index.html


    # Redirect "/" to the default interface
    if ! grep -Eq '^[[:space:]]*RedirectMatch[[:space:]]+^/$[[:space:]]+' "$APACHE_CONFIG_FILE"; then
        # Create unique tmp file and remove it later
        TMP_FILE=$(mktemp)
        trap 'rm -f "$TMP_FILE"' EXIT

        # Remove all existing lines
        awk '!/RedirectMatch[[:space:]]+\^\/\$/' "$APACHE_CONFIG_FILE" > "$TMP_FILE"

        # Create the new file content
        {
            printf 'RedirectMatch ^/$ /znuny/%s\n' "${DEFAULT_PAGE}"
            cat "$TMP_FILE"
        } | tee "$APACHE_CONFIG_FILE" > /dev/null
    fi

    # Redirect "/znuny/" to the default interface
    if ! grep -Eq '^[[:space:]]*RedirectMatch[[:space:]]+^/znuny/$[[:space:]]+' "$APACHE_CONFIG_FILE"; then
        # Create unique tmp file and remove it later
        TMP_FILE=$(mktemp)
        trap 'rm -f "$TMP_FILE"' EXIT

        # Remove all existing lines
        awk '!/RedirectMatch[[:space:]]+\^\/znuny\/\$/' "$APACHE_CONFIG_FILE" > "$TMP_FILE"

        # Create the new file content
        {
            printf 'RedirectMatch ^/znuny/$ /znuny/%s\n' "${DEFAULT_PAGE}"
            cat "$TMP_FILE"
        } | tee "$APACHE_CONFIG_FILE" > /dev/null
    fi

    # Welcome message
    echo "Agent Site    http://${FQDN}:${WEB_PORT}/znuny/index.pl"
    echo "Customer Site http://${FQDN}:${WEB_PORT}/znuny/customer.pl"
fi