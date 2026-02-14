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
echo -e "${YELLOW}[1/7] Installing required packages...${NC}"
apt-get update -qq
apt-get install -y freeradius freeradius-utils sqlite3
echo -e "${GREEN}✓ Packages installed${NC}"
echo ""

###############################################################################
# Step 2: Stop FreeRADIUS service
###############################################################################
echo -e "${YELLOW}[2/7] Stopping FreeRADIUS service...${NC}"
systemctl stop freeradius || true
echo -e "${GREEN}✓ Service stopped${NC}"
echo ""

###############################################################################
# Step 3: Backup existing files and copy new configuration
###############################################################################
echo -e "${YELLOW}[3/7] Backing up and copying configuration files...${NC}"

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
# Step 4: Enable SQL module
###############################################################################
echo -e "${YELLOW}[4/7] Enabling SQL module...${NC}"

if [ ! -L "$FREERADIUS_DIR/mods-enabled/sql" ]; then
    echo "  → Creating symlink for SQL module"
    ln -s "$FREERADIUS_DIR/mods-available/sql" "$FREERADIUS_DIR/mods-enabled/sql"
    echo -e "${GREEN}✓ SQL module enabled${NC}"
else
    echo -e "${GREEN}✓ SQL module already enabled${NC}"
fi
echo ""

###############################################################################
# Step 5: Fix permissions
###############################################################################
echo -e "${YELLOW}[5/7] Setting correct permissions...${NC}"

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
# Step 6: Apply SQLite tuning (WAL mode + busy_timeout)
###############################################################################
echo -e "${YELLOW}[6/7] Applying SQLite optimizations...${NC}"

echo "  → Enabling WAL mode"
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "PRAGMA journal_mode=WAL;" > /dev/null

echo "  → Setting busy_timeout to 30000ms"
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "PRAGMA busy_timeout=30000;" > /dev/null

# Fix permissions again after SQLite operations (WAL creates additional files)
chown -R freerad:freerad "$FREERADIUS_DIR/sqlite"
chmod 664 "$FREERADIUS_DIR/sqlite/radius.db"* 2>/dev/null || true

echo -e "${GREEN}✓ SQLite optimizations applied${NC}"
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
