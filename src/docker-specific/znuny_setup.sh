#!/bin/bash
# Install / update logic. Runs as the znuny user (called from znuny.sh).

set -eu
die() { echo "ERROR: $*" >&2; exit 1; }

####################################################
# Variables - Some are used from the znuny.sh file #
####################################################

# INSTALL_STATE: install, update, upgrade, local (only if local Files are not up to date, for example second frontend server)
INSTALL_STATE=
UPDATE_TYPE=

INSTALLED_VERSION=$(grep 'VERSION' "${ZNUNY_HOME}/RELEASE" 2>/dev/null | head -1 | awk '{print $NF}')
if [ -z "$INSTALLED_VERSION" ]; then
    echo "Info: Could not determine release version from ${ZNUNY_HOME}/RELEASE" >&2
fi

NEW_VERSION=$(grep 'VERSION' "${ZNUNY_STAGING}/RELEASE" 2>/dev/null | head -1 | awk '{print $NF}')
if [ -z "$NEW_VERSION" ]; then
    echo "ERROR: Could not determine release version from ${ZNUNY_STAGING}/RELEASE" >&2
    exit 1
fi
NEW_MAJOR=$(echo "$NEW_VERSION" | cut -d. -f1)
NEW_MINOR=$(echo "$NEW_VERSION" | cut -d. -f2)

DATABASE_VERSION=
DATABASE_MAJOR=
DATABASE_MINOR=

#############
# Functions #
#############

# true if $1 is a higher version than $2
version_gt() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

# Read a secret file. Strips CR/LF, so files edited on Windows work as well.
read_secret() {
    [ -r "$1" ] || die "Secret file $1 is missing or not readable"
    tr -d '\r\n' < "$1"
}

# The password is passed via MYSQL_PWD (not -p<password>): it would be visible in "ps"
MYSQL_PWD="$(read_secret "$DB_PASSWORD_FILE")"
export MYSQL_PWD

mysql_command() {
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -D "$DB_NAME" "$@"
}

mysql_query() {
    mysql_command -Nse "$1" 2>/dev/null
}

mysql_import() {
    mysql_command < "$1"
}



##################
# Database Check #
##################

# Database Type
DB_TYPE="$(sed -n '/^[[:space:]]*#/!s/.*DBI:\([^:]*\):.*/\1/p' "${ZNUNY_CFG}" | head -1)"

# Search for Database Type and do stuff
case "${DB_TYPE,,}" in
    mysql)
        # Check $DB_USER
        if mysqladmin -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$(read_secret "$DB_PASSWORD_FILE")" ping --silent 2>/dev/null | grep -q "is alive"; then
            echo "SQL user can authenticate"

            # Check if Database contains table
            if mysql_query "SHOW TABLES" | grep -q .; then
                
                # Check if Table exists before
                if mysql_query "SHOW TABLES LIKE 'ZDocker'" | grep -q .; then

                    # Check Version in Database
                    DATABASE_VERSION=$(mysql_query "SELECT property_value FROM ZDocker WHERE property_name = 'Version' LIMIT 1")
                    if [ -n "$DATABASE_VERSION" ]; then
                        echo "Database Version: $DATABASE_VERSION"
                        DATABASE_MAJOR=$(echo "$DATABASE_VERSION" | cut -d. -f1)
                        DATABASE_MINOR=$(echo "$DATABASE_VERSION" | cut -d. -f2)
                    else
                        echo "Version not found in database"
                    fi

                else
                    echo "Table not found in database"
                fi
                
            else
                echo "No Tables found in database"
                echo "Start with installing Znuny"
                INSTALL_STATE="install"
            fi
        else
            die "SQL authentication failed"
        fi
        ;;
    pq)
        die "Database Pq is not checked"
        ;;
    oracle)
        die "Database Oracle is not checked"
        ;;
    *)
        die "Database is unknown"
        ;;
esac



###############################################
# Install, Update, Upgrade - Script Functions #
###############################################
znuny_install() {
    znuny_helper_sync_files

    for SQL in schema initial_insert schema-post
    do
    mysql_import "${ZNUNY_HOME}/scripts/database/${SQL}.mysql.sql"
    done
    "$ZNUNY_HOME/bin/znuny.Console.pl" Maint::Config::Rebuild
    "$ZNUNY_HOME/bin/znuny.Console.pl" Maint::Loader::CacheGenerate
    "$ZNUNY_HOME/bin/znuny.Console.pl" Maint::Log::Clear
    "$ZNUNY_HOME/bin/znuny.Console.pl" Admin::Config::Update --setting-name SecureMode --value 1
    "$ZNUNY_HOME/bin/znuny.Console.pl" Admin::Config::Update --setting-name SystemID --value "$(printf '%02d' $((RANDOM % 99 + 1)))"
    # The package repository is online: an outage must not abort the whole installation
    if ! "$ZNUNY_HOME/bin/znuny.Console.pl" Admin::Package::Install 'Znuny Open Source Add-ons:Znuny-ContainerHelper'; then
        echo "WARNING: package Znuny-ContainerHelper could not be installed - install it later manually" >&2
    fi
    "$ZNUNY_HOME/bin/znuny.Console.pl" Maint::Cache::Delete
    "$ZNUNY_HOME/bin/znuny.Console.pl" Admin::User::SetPassword root@localhost "$(read_secret "$ZNUNY_ADMIN_PASSWORD_FILE")"
}

znuny_upgrade() {
    znuny_helper_sync_files

    MIGRATE_SCRIPT="$ZNUNY_HOME/scripts/MigrateToZnuny${NEW_MAJOR}_${NEW_MINOR}.pl"

    if [ ! -f "$MIGRATE_SCRIPT" ]; then
        echo "ERROR: migration script not found: $MIGRATE_SCRIPT" >&2
        exit 1
    fi

    $ZNUNY_HOME/bin/znuny.Console.pl Maint::Cache::Delete
    echo "Running migration script: $MIGRATE_SCRIPT"
    "$MIGRATE_SCRIPT" --verbose --non-interactive

    case "${INSTALL_STATE,,}" in
        upgrade)
            $ZNUNY_HOME/bin/znuny.Console.pl Admin::Package::UpgradeAll
            ;;
        *)
            $ZNUNY_HOME/bin/znuny.Console.pl Admin::Package::ReinstallAll
            ;;
    esac

    "$MIGRATE_SCRIPT" --verbose --non-interactive
    $ZNUNY_HOME/bin/znuny.Console.pl Maint::Cache::Delete
    $ZNUNY_HOME/bin/znuny.Console.pl Maint::Log::Clear
}

znuny_local_update() {
    znuny_helper_sync_files

    $ZNUNY_HOME/bin/znuny.Console.pl Admin::Package::ReinstallAll
}

# Sync updated application files into the shared volume
# --delete removes files that no longer exist in the new version
# Excludes runtime data that should be preserved
znuny_helper_sync_files() {
    rsync -a --delete \
        --exclude='var/tmp/' \
        --exclude='var/log/' \
        --exclude='var/article/' \
        --exclude='var/sessions/' \
        --exclude='var/httpd/htdocs/custom/' \
        --exclude='Kernel/Config.pm' \
        "$ZNUNY_STAGING/" "$ZNUNY_HOME/" 2>&1 | grep -v "failed to set times on" || true

    # Note: Set Permission are not possible here - Bash is running with znuny User. rsync may fail, if permission are not set yet.
}



######################################
# Install, Update, Upgrade - Checker #
######################################

# Check Version changes: If INSTALL_STATE is not yet set
if [ -z "$INSTALL_STATE" ]; then
    if [ "$DATABASE_VERSION" != "$NEW_VERSION" ]; then
        # Database is not up to date

        # Downgrades are not supported by Znuny - the schema would not match the code
        if version_gt "$DATABASE_VERSION" "$NEW_VERSION"; then
            die "Database is at version $DATABASE_VERSION, the image only has $NEW_VERSION (downgrade is not supported). Use ZNUNY_VERSION >= $DATABASE_VERSION."
        fi

        if [ "$DATABASE_MAJOR" != "$NEW_MAJOR" ]; then
            UPDATE_TYPE="major"
            INSTALL_STATE="upgrade"
        elif [ "$DATABASE_MINOR" != "$NEW_MINOR" ]; then
            UPDATE_TYPE="minor"
            INSTALL_STATE="upgrade"
        else
            UPDATE_TYPE="patch"
            INSTALL_STATE="update"
        fi

        # Detect skipped minor versions by parsing CHANGES.md.
        # Only the migration script for the current image version is available,
        # so skipping a minor version would silently miss its schema changes.
        CHANGES_FILE="$ZNUNY_STAGING/CHANGES.md"
        if [ ! -f "$CHANGES_FILE" ]; then
            die "$CHANGES_FILE not found - cannot verify upgrade path"
        fi

        SKIPPED=$(grep '^# [0-9]' "$CHANGES_FILE" \
            | sed 's/^# \([0-9]*\)\.\([0-9]*\)\.\?[0-9]* .*/\1 \2/' \
            | sort -k1,1n -k2,2n -u \
            | while read -r maj min; do
                if { [ "$maj" -gt "$DATABASE_MAJOR" ] || \
                    { [ "$maj" -eq "$DATABASE_MAJOR" ] && [ "$min" -gt "$DATABASE_MINOR" ]; }; } && \
                { [ "$maj" -lt "$NEW_MAJOR" ] || \
                    { [ "$maj" -eq "$NEW_MAJOR" ] && [ "$min" -lt "$NEW_MINOR" ]; }; }; then
                    printf '%s.%s ' "$maj" "$min"
                fi
            done)

        if [ -n "$SKIPPED" ]; then
            echo "ERROR: upgrade from $DATABASE_VERSION to $NEW_VERSION skips minor versions: $SKIPPED" >&2
            die "upgrade step by step through each minor version."
        fi

    else
        # Database is up to date, but not the local files (for example second frontend server started)

        if [ "$INSTALLED_VERSION" != "$NEW_VERSION" ]; then
            INSTALL_STATE="local"
        else
            echo "Znuny $NEW_VERSION already installed, no action needed."
            exit 0
        fi

    fi
fi

# Install, Update, Upgrade
case "${INSTALL_STATE,,}" in
    install)
        echo "Installing Znuny ${NEW_VERSION}..."
        znuny_install
        echo "Installation complete"
        # echo "For initial setup, visit http://${FQDN}:${WEB_PORT}/znuny/installer.pl"
        ;;
    update)
        echo "Version change detected: $DATABASE_VERSION -> $NEW_VERSION (update - $UPDATE_TYPE)"
        echo "Updating Znuny..."
        znuny_upgrade
        echo "Update complete"
        ;;
    upgrade)
        echo "Version change detected: $DATABASE_VERSION -> $NEW_VERSION (upgrade - $UPDATE_TYPE)"
        echo "Upgrading Znuny..."
        znuny_upgrade
        echo "Upgrade complete"
        ;;
    local)
        echo "File change detected: $DATABASE_VERSION -> $NEW_VERSION (local)"
        echo "Update Znuny Files..."
        znuny_local_update
        echo "Update complete"
        ;;
esac


# Create or Set Version
case "${DB_TYPE,,}" in
    mysql)
        mysql_query "
            CREATE TABLE IF NOT EXISTS ZDocker (
                property_name VARCHAR(255) PRIMARY KEY,
                property_value TEXT
            )
        "

        # Set Version in Database
        mysql_query "
            INSERT INTO ZDocker (property_name, property_value)
            VALUES ('Version', '$NEW_VERSION')
            ON DUPLICATE KEY UPDATE property_value = VALUES(property_value)
        "

        ;;
    pq)
        echo "Database Pq is not updated"
        ;;
    oracle)
        echo "Database Oracle is not updated"
        ;;
    *)
        echo "Database is unknown"
        ;;
esac