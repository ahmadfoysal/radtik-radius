#!/bin/bash

###############################################################################
# RadTik FreeRADIUS + SQLite One-Command Installer
# For Ubuntu 22.04 LTS
###############################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run with sudo${NC}"
   exit 1
fi

echo -e "${GREEN}===== RadTik FreeRADIUS + SQLite Installer =====${NC}"
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FREERADIUS_DIR="/etc/freeradius/3.0"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

###############################################################################
# Step 1: Install required packages
###############################################################################
echo -e "${YELLOW}[1/10] Installing required packages...${NC}"
apt-get update -qq
apt-get install -y freeradius freeradius-utils sqlite3 python3 python3-pip
echo -e "${GREEN}✓ Packages installed${NC}"
echo ""

###############################################################################
# Step 2: Install Python dependencies
###############################################################################
echo -e "${YELLOW}[2/10] Installing Python dependencies...${NC}"
pip3 install requests --quiet
echo -e "${GREEN}✓ Python dependencies installed${NC}"
echo ""

###############################################################################
# Step 3: Stop FreeRADIUS service
###############################################################################
echo -e "${YELLOW}[3/10] Stopping FreeRADIUS service...${NC}"
systemctl stop freeradius || true
echo -e "${GREEN}✓ Service stopped${NC}"
echo ""

###############################################################################
# Step 4: Backup existing files and copy new configuration
###############################################################################
echo -e "${YELLOW}[4/10] Backing up and copying configuration files...${NC}"

# Function to safely copy with backup
safe_copy() {
    local src="$1"
    local dest="$2"

    if [ -f "$dest" ]; then
        echo "  → Backing up existing $(basename $dest) to ${dest}.bak.${TIMESTAMP}"
        cp "$dest" "${dest}.bak.${TIMESTAMP}"
    fi

    # Create parent directory if needed
    mkdir -p "$(dirname $dest)"

    echo "  → Copying $(basename $src) to $dest"
    cp "$src" "$dest"
}

# Copy configuration files
safe_copy "$SCRIPT_DIR/clients.conf" "$FREERADIUS_DIR/clients.conf"
safe_copy "$SCRIPT_DIR/mods-available/sql" "$FREERADIUS_DIR/mods-available/sql"
safe_copy "$SCRIPT_DIR/mods-config/sql/main/sqlite/queries.conf" "$FREERADIUS_DIR/mods-config/sql/main/sqlite/queries.conf"
safe_copy "$SCRIPT_DIR/sites-enabled/default" "$FREERADIUS_DIR/sites-enabled/default"

# Copy SQLite database
mkdir -p "$FREERADIUS_DIR/sqlite"
safe_copy "$SCRIPT_DIR/sqlite/radius.db" "$FREERADIUS_DIR/sqlite/radius.db"

echo -e "${GREEN}✓ Configuration files copied${NC}"
echo ""

###############################################################################
# Step 5: Enable SQL module
###############################################################################
echo -e "${YELLOW}[5/10] Enabling SQL module...${NC}"

if [ ! -L "$FREERADIUS_DIR/mods-enabled/sql" ]; then
    echo "  → Creating symlink for SQL module"
    ln -s "$FREERADIUS_DIR/mods-available/sql" "$FREERADIUS_DIR/mods-enabled/sql"
    echo -e "${GREEN}✓ SQL module enabled${NC}"
else
    echo -e "${GREEN}✓ SQL module already enabled${NC}"
fi
echo ""

###############################################################################
# Step 6: Fix permissions
###############################################################################
echo -e "${YELLOW}[6/10] Setting correct permissions...${NC}"

# Ensure freerad user exists
if ! id -u freerad > /dev/null 2>&1; then
    echo -e "${RED}✗ freerad user does not exist. Package installation may have failed.${NC}"
    exit 1
fi

# Set ownership and permissions for SQLite directory and database
echo "  → Setting owner freerad:freerad on $FREERADIUS_DIR/sqlite"
chown -R freerad:freerad "$FREERADIUS_DIR/sqlite"

echo "  → Setting directory permissions to 775"
chmod 775 "$FREERADIUS_DIR/sqlite"

echo "  → Setting database file permissions to 664"
chmod 664 "$FREERADIUS_DIR/sqlite/radius.db"

echo -e "${GREEN}✓ Permissions set correctly${NC}"
echo ""

###############################################################################
# Step 7: Apply SQLite tuning and schema modifications
###############################################################################
echo -e "${YELLOW}[7/10] Applying SQLite optimizations and schema updates...${NC}"

echo "  → Enabling WAL mode"
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "PRAGMA journal_mode=WAL;" > /dev/null

echo "  → Setting busy_timeout to 30000ms"
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "PRAGMA busy_timeout=30000;" > /dev/null

echo "  → Adding 'processed' column to radpostauth table"
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "ALTER TABLE radpostauth ADD COLUMN processed INTEGER DEFAULT 0;" 2>/dev/null || echo "    (Column may already exist, skipping)"

echo "  → Creating indexes for performance"
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "CREATE INDEX IF NOT EXISTS idx_radpostauth_processed ON radpostauth(processed, authdate);" > /dev/null
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "CREATE INDEX IF NOT EXISTS idx_radpostauth_username ON radpostauth(username);" > /dev/null
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "CREATE INDEX IF NOT EXISTS idx_radcheck_username ON radcheck(username);" > /dev/null
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "CREATE INDEX IF NOT EXISTS idx_radreply_username ON radreply(username);" > /dev/null
8: Setup RadTik synchronization scripts
###############################################################################
echo -e "${YELLOW}[8/10] Setting up RadTik synchronization scripts...${NC}"

SYNC_DIR="/opt/radtik-sync"

# Create sync directory
echo "  → Creating $SYNC_DIR directory"
mkdir -p "$SYNC_DIR"

# Copy Python scripts
echo "  → Copying synchronization scripts"
cp "$SCRIPT_DIR/sync-vouchers.py" "$SYNC_DIR/"
cp "$SCRIPT_DIR/check-activations.py" "$SYNC_DIR/"
cp "$SCRIPT_DIR/sync-deleted.py" "$SYNC_DIR/"

# Copy config example
cp "$SCRIPT_DIR/config.ini.example" "$SYNC_DIR/"

# Create config.ini if it doesn't exist
if [ ! -f "$SYNC_DIR/config.ini" ]; then
    echo "  → Creating config.ini from template"
    cp "$SYNC_DIR/config.ini.example" "$SYNC_DIR/config.ini"
    echo ""
    echo -e "${YELLOW}IMPORTANT: Complete these steps before use:${NC}"
    echo ""
    echo "1. Configure Laravel synchronization:"
    echo "   sudo nano /opt/radtik-sync/config.ini"
    echo ""
    echo "   Set the following values:"
    echo "   - api_url = https://your-radtik-domain.com/api/radius"
    echo "   - api_secret = <token from Laravel RADIUS server management>"
    echo ""
    echo "2. Test synchronization manually:"
    echo "   sudo python3 /opt/radtik-sync/sync-vouchers.py"
    echo ""
    echo "3. Test FreeRADIUS authentication:"
    echo "   radtest testuser testpass localhost 0 testing123"
    echo ""
    echo "4. Monitor logs:"
    echo "   - FreeRADIUS: sudo tail -f /var/log/freeradius/radius.log"
    echo "   - Sync logs: sudo tail -f /var/log/radtik-sync/sync.log"
    echo "   - Activations: sudo tail -f /var/log/radtik-sync/activations.log"
    echo ""
    echo "5. Check cron jobs are running:"
    echo "   sudo grep CRON /var/log/syslog | grep radtik-synction URL"
    echo "  2. api_secret - The RADIUS server API token from Laravel"
    echo ""
    echo "Example:"
    echo "  api_url = https://radtik.yourdomain.com/api/radius"
    echo "  api_secret = your-generated-token-from-laravel"
    echo ""
else
    echo "  → config.ini already exists, skipping"
fi

# Make scripts executable
echo "  → Making scripts executable"
chmod +x "$SYNC_DIR/sync-vouchers.py"
chmod +x "$SYNC_DIR/check-activations.py"
chmod +x "$SYNC_DIR/sync-deleted.py"

# Create log directory
mkdir -p /var/log/radtik-sync
touch /var/log/radtik-sync/sync.log
touch /var/log/radtik-sync/activations.log
touch /var/log/radtik-sync/deleted.log
chmod 644 /var/log/radtik-sync/*.log

echo -e "${GREEN}✓ Synchronization scripts installed${NC}"
echo ""

###############################################################################
# Step 9: Setup cron jobs for synchronization
###############################################################################
echo -e "${YELLOW}[9/10] Setting up cron jobs for synchronization...${NC}"

CRON_FILE="/etc/cron.d/radtik-sync"

# Create cron file
cat > "$CRON_FILE" << 'EOF'
# RadTik FreeRADIUS Synchronization Cron Jobs
# Syncs vouchers between Laravel and FreeRADIUS

# Sync vouchers from Laravel to FreeRADIUS every 2 minutes
*/2 * * * * root /usr/bin/python3 /opt/radtik-sync/sync-vouchers.py >> /var/log/radtik-sync/sync.log 2>&1

# Check for new activations (MAC binding) every minute
* * * * * root /usr/bin/python3 /opt/radtik-sync/check-activations.py >> /var/log/radtik-sync/activations.log 2>&1

# Sync deleted users every 5 minutes
*/5 * * * * root /usr/bin/python3 /opt/radtik-sync/sync-deleted.py >> /var/log/radtik-sync/deleted.log 2>&1

EOF

chmod 644 "$CRON_FILE"

echo "  → Cron jobs installed in $CRON_FILE"
echo "  → Sync schedule:"
echo "      - Voucher sync: Every 2 minutes"
echo "      - Activation check: Every 1 minute"
echo "      - Deleted users: Every 5 minutes"
echo ""
echo -e "${GREEN}✓ Cron jobs configured${NC}"
echo ""

###############################################################################
# Step 10: Restart FreeRADIUS and verify
###############################################################################
echo -e "${YELLOW}[10/10ad "$FREERADIUS_DIR/sqlite"
chmod 664 "$FREERADIUS_DIR/sqlite/radius.db"* 2>/dev/null || true

echo -e "${GREEN}✓ SQLite optimizations and schema updates applied${NC}"
echo ""

###############################################################################
# Step 7: Restart FreeRADIUS and verify
###############################################################################
echo -e "${YELLOW}[7/7] Restarting FreeRADIUS service...${NC}"

systemctl restart freeradius

# Wait a moment for service to fully start
sleep 2

# Check service status
if systemctl is-active --quiet freeradius; then
    echo -e "${GREEN}✓ FreeRADIUS is running successfully!${NC}"
    echo ""
    echo -e "${GREEN}===== Installation Complete! =====${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Test authentication: radtest testuser testpass localhost 0 testing123"
    echo "  2. Check logs: sudo tail -f /var/log/freeradius/radius.log"
    echo "  3. Debug mode: sudo freeradius -X"
    echo ""
    echo "See README.md for more details and testing instructions."
    echo ""
else
    echo -e "${RED}✗ FreeRADIUS failed to start${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check logs: sudo journalctl -u freeradius -n 50"
    echo "  2. Run in debug mode: sudo freeradius -X"
    echo "  3. Check permissions: ls -la $FREERADIUS_DIR/sqlite/"
    exit 1
fi
