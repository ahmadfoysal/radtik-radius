#!/usr/bin/env bash
#
# Applies the files of /opt/radtik-radius to the running system after an update.
# Idempotent. Run as root. Used by update.sh and by the panel's "Apply update".
#
# It does NOT touch server-specific files: scripts/config.ini, clients.conf, sqlite/radius.db.
# The caller restarts the services afterwards.
#
# Usage: post-update.sh [service-user]            (default service user: freerad)
# Environment (for tests): INSTALL_DIR, FREERADIUS_DIR, CRON_FILE, SKIP_SYSTEM=1
#   (SKIP_SYSTEM=1 skips python packages, the API certificate, the systemd unit and the config check)
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/radtik-radius}"
FREERADIUS_DIR="${FREERADIUS_DIR:-/etc/freeradius/3.0}"
CRON_FILE="${CRON_FILE:-/etc/cron.d/radtik-sync}"
SERVICE_USER="${1:-freerad}"

if [ ! -d "$INSTALL_DIR/scripts" ]; then
    echo "Installation directory $INSTALL_DIR not found (or incomplete)." >&2
    exit 1
fi

# 1. FreeRADIUS configuration that ships with RADTik (same files install.sh deploys).
for file in mods-available/sql mods-config/sql/main/sqlite/queries.conf sites-enabled/default; do
    if [ -f "$INSTALL_DIR/$file" ]; then
        mkdir -p "$(dirname "$FREERADIUS_DIR/$file")"
        if ! cmp -s "$INSTALL_DIR/$file" "$FREERADIUS_DIR/$file" 2>/dev/null; then
            cp "$INSTALL_DIR/$file" "$FREERADIUS_DIR/$file"
            echo "  -> Updated FreeRADIUS file: $file"
        fi
    fi
done

# 2. Scheduled jobs
if [ -f "$INSTALL_DIR/cron/radtik-sync" ] && ! cmp -s "$INSTALL_DIR/cron/radtik-sync" "$CRON_FILE" 2>/dev/null; then
    install -m 644 "$INSTALL_DIR/cron/radtik-sync" "$CRON_FILE"
    echo "  -> Updated scheduled jobs: $CRON_FILE"
fi

chmod +x "$INSTALL_DIR"/scripts/*.py "$INSTALL_DIR"/scripts/*.sh 2>/dev/null || true

if [ "${SKIP_SYSTEM:-0}" = "1" ]; then
    exit 0
fi

# 3. Python packages
if command -v pip3 > /dev/null; then
    pip3 install -r "$INSTALL_DIR/requirements.txt" --upgrade --quiet
    echo "  -> Python packages are up to date"
fi

# 4. API certificate (permissions are reset after every update), then the systemd unit
bash "$INSTALL_DIR/scripts/ensure-api-tls.sh" "$SERVICE_USER"
cp "$INSTALL_DIR/radtik-radius-api.service" /etc/systemd/system/radtik-radius-api.service
systemctl daemon-reload

# 5. Never restart FreeRADIUS into a broken configuration
if command -v freeradius > /dev/null; then
    if ! freeradius -Cx -lstdout -d "$FREERADIUS_DIR" > /dev/null 2>&1; then
        echo "FreeRADIUS rejects the new configuration. Run: freeradius -CX -d $FREERADIUS_DIR" >&2
        exit 1
    fi
    echo "  -> FreeRADIUS configuration is valid"
fi
