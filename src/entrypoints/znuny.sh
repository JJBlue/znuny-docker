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

DB_HOST="${DB_HOST:-znuny-db}"
DB_NAME="${DB_NAME:-znuny}"
DB_USER="${DB_USER:-znuny}"
DB_ROOT_PASSWORD_FILE="/run/secrets/db_root_password"
DB_PASSWORD_FILE="/run/secrets/db_password"

WEB_PORT="${WEB_PORT:-port}"


################
# Setup Config #
################

# Create Config.pm if it doesn't already exist
if [ ! -f "$PERSISTENT_CFG" ]; then
    echo "Persistent Config.pm not found, seeding it"
    cp "${ZNUNY_CFG}.dist" "$PERSISTENT_CFG"

    sed -i "s/\(\$Self->{DatabaseHost}\s*=\s*\)'[^']*';/\1'$DB_HOST';/" "$PERSISTENT_CFG"
    sed -i "s/\(\$Self->{Database}\s*=\s*\)'[^']*';/\1'$DB_NAME';/"     "$PERSISTENT_CFG"
    sed -i "s/\(\$Self->{DatabaseUser}\s*=\s*\)'[^']*';/\1'$DB_USER';/" "$PERSISTENT_CFG"
    sed -i "s/\(\$Self->{DatabasePw}\s*=\s*\)'[^']*';/\1'$(cat "$DB_PASSWORD_FILE")';/" "$PERSISTENT_CFG"

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


##################
# Database Check #
##################

# Database Type
DB_TYPE="$(sed -n '/^[[:space:]]*#/!s/.*DBI:\([^:]*\):.*/\1/p' /opt/znuny/Kernel/Config.pm)"

# Check and Create $DB_USER
case "${DB_TYPE,,}" in
    mysql)
        # Check $DB_USER
        if mysqladmin -h "$DB_HOST" -u "$DB_USER" -p"$(cat "$DB_PASSWORD_FILE")" ping --silent 2>/dev/null | grep -q "is alive"; then
            echo "SQL user can authenticate"
        else
            echo "SQL authentication failed"

            # Create $DB_USER if root Password is valid and exist
            if [[ -f "$DB_ROOT_PASSWORD_FILE" ]]; then
                if mysqladmin -h "$DB_HOST" -u "root" -p"$(cat "$DB_ROOT_PASSWORD_FILE")" ping --silent 2>/dev/null | grep -q "is alive"; then

SQL=$(cat <<EOF
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '$(cat "$DB_PASSWORD_FILE")';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
EOF
)

                    mysql -h "$DB_HOST" -u "root" -p"$(cat "$DB_ROOT_PASSWORD_FILE")" -e "${SQL}" >/dev/null 2>&1

                    if [ $? -eq 0 ]; then
                        echo "User created and privileges granted successfully."
                    else
                        echo "SQL operation failed." >&2
                    fi

                fi
            fi
        fi
        ;;
    pq)
        echo "Database Pq is not checked"
        ;;
    oracle)
        echo "Database Oracle is not checked"
        ;;
    *)
        echo "Database is unknown"
        ;;
esac

### TODO Check Version
# TODO if fist install
echo "For initial setup, visit http://hostname:port/znuny/installer.pl"
# TODO if Upgrade:
#   su -c 'scripts/MigrateToZnuny7_3.pl --verbose' - znuny
#   su -c 'bin/znuny.Console.pl Admin::Package::UpgradeAll' - znuny
#   su -c 'scripts/MigrateToZnuny7_3.pl --verbose' - znuny
# TODO if update:
#   su -c 'bin/znuny.Console.pl Admin::Package::ReinstallAll' - znuny
#   su -c 'scripts/MigrateToZnuny7_3.pl --verbose' - znuny
# TODO else

# if not first install
# Welcome message
echo "Agent Site http://hostname:${WEB_PORT}/znuny/index.pl"
echo "Customer Site http://hostname:${WEB_PORT}/znuny/custom.pl"