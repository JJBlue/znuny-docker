#!/bin/bash

# Stop on Error
set -e

# TODO own Downgrade: FAIL --> Change Version File manually to continue

# Create Folder # TODO once
chown -R www-data:www-data /persistent

PERSISTENT_CFG="/persistent/Config.pm"
ZNUNY_HOME="/opt/znuny"
ZNUNY_CFG="${ZNUNY_HOME}/Kernel/Config.pm"
ZNUNY_USER="${ZNUNY_USER}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_NAME="${DB_NAME:-znuny}"
DB_USER="${DB_USER:-znuny}"

# Create Config.pm if it doesn't already exist
if [ ! -f "$PERSISTENT_CFG" ]; then
    echo "Persistent Config.pm not found, seeding it"
    cp "${ZNUNY_CFG}.dist" "$PERSISTENT_CFG"

    sed -i "s/\(\$Self->{DatabaseHost}\s*=\s*\)'[^']*';/\1'$DB_HOST';/" "$PERSISTENT_CFG"
    sed -i "s/\(\$Self->{Database}\s*=\s*\)'[^']*';/\1'$DB_NAME';/"     "$PERSISTENT_CFG"
    sed -i "s/\(\$Self->{DatabaseUser}\s*=\s*\)'[^']*';/\1'$DB_USER';/" "$PERSISTENT_CFG"
    sed -i "s/\(\$Self->{DatabasePw}\s*=\s*\)'[^']*';/\1'$(cat /run/secrets/db_password)';/" "$PERSISTENT_CFG"

    chown znuny:www-data "$PERSISTENT_CFG"
    chmod 770 "$PERSISTENT_CFG"
else
    echo "Using persistent Config.pm"
fi

# Create Config.pm symlink if not exist
if [ ! -L ${ZNUNY_HOME}/Kernel/Config.pm ]; then
    ln -sf "$PERSISTENT_CFG" "$ZNUNY_CFG"
    $ZNUNY_HOME/bin/znuny.SetPermissions.pl --znuny-user ${ZNUNY_USER}
fi

echo "For initial setup, visit http://hostname:port/znuny/installer.pl"


# TODO Upgrade / Update Command: Only if Version changed