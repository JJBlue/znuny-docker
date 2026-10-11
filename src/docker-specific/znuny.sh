#!/bin/bash

# Stop on Error
set -eu

# TODO own Downgrade: FAIL --> Change Version File manually to continue

PERSISTENT_CFG="/persistent/Config.pm"
export ZNUNY_HOME=${ZNUNY_HOME}
export ZNUNY_CFG="${ZNUNY_HOME}/Kernel/Config.pm"
export ZNUNY_USER="${ZNUNY_USER}"
ZNUNY_NodeID=${ZNUNY_NodeID:-1}

export ZNUNY_STAGING=${ZNUNY_STAGING}
export ZNUNY_STAGING_CFG="${ZNUNY_STAGING}/Kernel/Config.pm"

APACHE_USER=${APACHE_RUN_USER:-www-data}

export DB_HOST="${DB_HOST:-znuny-db}"
export DB_PORT="${DB_PORT:-3306}"
export DB_NAME="${DB_NAME:-znuny}"
export DB_USER="${DB_USER:-znuny}"
export DB_PASSWORD_FILE="/run/secrets/db_password"

FQDN="$(hostname -f)"


####################
# Setup Persistent #
####################

# Create Folder # TODO once
chown -R ${ZNUNY_USER}:${APACHE_USER} /persistent

# Create Config.pm if it doesn't already exist
if [ ! -f "$PERSISTENT_CFG" ]; then
    echo "Persistent Config.pm not found, seeding it"
    cp "${ZNUNY_STAGING_CFG}.dist" "$PERSISTENT_CFG"

    sed -i "s/\(\$Self->{DatabaseHost}\s*=\s*\)'[^']*';/\1'$DB_HOST';/" "$PERSISTENT_CFG"
    sed -i "s/\(\$Self->{Database}\s*=\s*\)'[^']*';/\1'$DB_NAME';/"     "$PERSISTENT_CFG"
    sed -i "s/\(\$Self->{DatabaseUser}\s*=\s*\)'[^']*';/\1'$DB_USER';/" "$PERSISTENT_CFG"
    sed -i "s/\(\$Self->{DatabasePw}\s*=\s*\)'[^']*';/\1'$(cat "$DB_PASSWORD_FILE")';/" "$PERSISTENT_CFG"

    if grep -qE '\$Self->\{NodeID\}\s*=' "$PERSISTENT_CFG"; then
        sed -i "s/\(\$Self->{NodeID}\s*=\s*\)[0-9]\+/\1${ZNUNY_NodeID}/" "$PERSISTENT_CFG"
    else
        sed -i "s/^\s*return 1;/\\\$Self->{NodeID} = ${ZNUNY_NodeID};\n    return 1;/" "$PERSISTENT_CFG"
    fi

    chown ${ZNUNY_USER}:${APACHE_USER} "$PERSISTENT_CFG"
    chmod 770 "$PERSISTENT_CFG"
fi

# Create Config.pm symlink if not exist
if [ ! -L "${ZNUNY_HOME}/Kernel/Config.pm" ]; then
    echo "Linking Persistent Config.pm"
    mkdir -p "${ZNUNY_HOME}/Kernel"
    ln -sf "$PERSISTENT_CFG" "$ZNUNY_CFG"
fi

###############
# Setup Znuny #
###############

if [[ -v WEB_PORT ]]; then
    gosu ${ZNUNY_USER} /usr/local/bin/znuny_setup.sh 2>&1 || exit $?

    # Welcome message
    echo "Agent Site http://${FQDN}:${WEB_PORT}/znuny/index.pl"
    echo "Customer Site http://${FQDN}:${WEB_PORT}/znuny/custom.pl"
fi

######################
# Setup Znuny Config #
######################

# Setup Apache Znuny config (shared volume is now available)
if [ ! -f /etc/apache2/conf-available/zzz_znuny.conf ]; then
    ln -s ${ZNUNY_HOME}/scripts/apache2-httpd.include.conf /etc/apache2/conf-available/zzz_znuny.conf
    a2enconf zzz_znuny
fi

# Set default interface redirect
ZNUNY_DEFAULT_INTERFACE="${ZNUNY_DEFAULT_INTERFACE:-agent}"
if [ "$ZNUNY_DEFAULT_INTERFACE" = "customer" ]; then
    DEFAULT_PAGE="customer.pl"
else
    DEFAULT_PAGE="index.pl"
fi
sed -i "s|URL=/znuny/[a-z_]*\.pl|URL=/znuny/${DEFAULT_PAGE}|" ${ZNUNY_HOME}/var/httpd/htdocs/index.html