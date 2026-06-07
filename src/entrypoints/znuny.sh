# Stop on Error
set -e

# TODO run once

# TODO own Downgrade: FAIL --> Change Version File manually to continue

# TODO Get ${VERSION} from VERSION file in persistent folder
VERSION=latest
FILE_RELEASE=${ZNUNY_HOME}/RELEASE
FILE_KERNEL=${ZNUNY_HOME}/KERNEL

# Create Folder
chown -R www-data:www-data /persistent

# Create Config.pm if it doesn't already exist
if [ ! -f /persistent/Config.pm ]; then \
    cp /opt/znuny/Kernel/Config.pm.dist /persistent/Config.pm; \
fi
ln -s /persistent/Config.pm Kernel/Config.pm

# TODO Upgrade / Update Command: Only if Version changed