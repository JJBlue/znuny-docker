#!/bin/bash

# Stop on Error
set -e

# TODO own Downgrade: FAIL --> Change Version File manually to continue

PERSISTENT_CFG="/persistent/Config.pm"
export ZNUNY_HOME="/opt/znuny"
ZNUNY_CFG="${ZNUNY_HOME}/Kernel/Config.pm"
ZNUNY_USER="${ZNUNY_USER}"
ZNUNY_NodeID=${ZNUNY_NodeID:-1}

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
    cp "${ZNUNY_CFG}.dist" "$PERSISTENT_CFG"

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
else
    echo "Using persistent Config.pm"
fi

######################
# Setup Znuny Config #
######################

# Create Config.pm symlink if not exist
if [ ! -L ${ZNUNY_HOME}/Kernel/Config.pm ]; then
    ln -sf "$PERSISTENT_CFG" "$ZNUNY_CFG"
    $ZNUNY_HOME/bin/znuny.SetPermissions.pl --znuny-user ${ZNUNY_USER}
fi


### TODO
# Setup Apache Znuny config (shared volume is now available)
#if [ ! -f /etc/apache2/conf-available/zzz_znuny.conf ]; then
#    ln -s ${ZNUNY_HOME}/scripts/apache2-httpd.include.conf /etc/apache2/conf-available/zzz_znuny.conf
#    a2enconf zzz_znuny
#fi

### TODO
# Set default interface redirect
ZNUNY_DEFAULT_INTERFACE="${ZNUNY_DEFAULT_INTERFACE:-agent}"
if [ "$ZNUNY_DEFAULT_INTERFACE" = "customer" ]; then
    DEFAULT_PAGE="customer.pl"
else
    DEFAULT_PAGE="index.pl"
fi
sed -i "s|URL=/znuny/[a-z_]*\.pl|URL=/znuny/${DEFAULT_PAGE}|" ${ZNUNY_HOME}/var/httpd/htdocs/index.html



###############
# Setup Znuny #
###############

### TODO
if [[ -v WEB_PORT ]]; then
    gosu ${ZNUNY_USER} /usr/local/bin/znuny_setup.sh
    # TODO znuny_helper_install.sh exit with error code --> exit too

    # Welcome message
    echo "Agent Site http://${FQDN}:${WEB_PORT}/znuny/index.pl"
    echo "Customer Site http://${FQDN}:${WEB_PORT}/znuny/custom.pl"
fi