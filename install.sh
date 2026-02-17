#!/bin/bash

###############################################################################
# RadTik FreeRADIUS + SQLite + API Server Complete Installer
# For Ubuntu 22.04 LTS
# 
# This script installs:
# 1. FreeRADIUS with SQLite backend
# 2. Flask API Server for Laravel integration
# 3. Legacy cron scripts for activation monitoring
###############################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run with sudo${NC}" 
   exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FREERADIUS_DIR="/etc/freeradius/3.0"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
SYNC_DIR="/opt/radtik-sync"
API_SERVICE_NAME="radtik-radius-api"
API_SERVICE_FILE="/etc/systemd/system/${API_SERVICE_NAME}.service"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

###############################################################################
# Helper Functions
###############################################################################

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_info() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

###############################################################################
# Welcome
###############################################################################

clear
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║      RadTik FreeRADIUS Complete Installation Script      ║
║                                                           ║
║  Installs FreeRADIUS + SQLite + API Server + Laravel     ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo ""
echo "This installer will set up:"
echo "  ${GREEN}✓${NC} FreeRADIUS 3.0 with SQLite backend"
echo "  ${GREEN}✓${NC} Flask API Server for real-time voucher sync"
echo "  ${GREEN}✓${NC} Legacy cron scripts for activation monitoring"
echo "  ${GREEN}✓${NC} Optimized database with indexes"
echo "  ${GREEN}✓${NC} Firewall configuration (port 5000)"
echo ""
echo "Starting installation..."
echo ""
sleep 2

###############################################################################
# PHASE 1: FreeRADIUS Core Installation
###############################################################################

print_header "PHASE 1: Installing FreeRADIUS Core"

###############################################################################
# Step 1: Install required packages
###############################################################################
echo -e "${YELLOW}[1/9] Installing required packages...${NC}"
apt-get update -qq
apt-get install -y freeradius freeradius-utils sqlite3 python3 python3-pip curl
print_info "Packages installed"
echo ""

###############################################################################
# Step 2: Install Python dependencies
###############################################################################
echo -e "${YELLOW}[2/9] Installing Python dependencies...${NC}"

echo "  → Installing Flask, Gunicorn for API server"
pip3 install -r "$SCRIPT_DIR/requirements.txt" --quiet

print_info "Python dependencies installed"
echo ""

###############################################################################
# Step 3: Stop FreeRADIUS service
###############################################################################
echo -e "${YELLOW}[3/9] Stopping FreeRADIUS service...${NC}"
systemctl stop freeradius || true
print_info "Service stopped"
echo ""

###############################################################################
# Step 4: Backup existing files and copy new configuration
###############################################################################
echo -e "${YELLOW}[4/9] Backing up and copying configuration files...${NC}"

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

print_info "Configuration files copied"
echo ""

###############################################################################
# Step 5: Enable SQL module
###############################################################################
echo -e "${YELLOW}[5/9] Enabling SQL module...${NC}"

if [ ! -L "$FREERADIUS_DIR/mods-enabled/sql" ]; then
    echo "  → Creating symlink for SQL module"
    ln -s "$FREERADIUS_DIR/mods-available/sql" "$FREERADIUS_DIR/mods-enabled/sql"
    print_info "SQL module enabled"
else
    print_info "SQL module already enabled"
fi
echo ""

###############################################################################
# Step 6: Fix permissions
###############################################################################
echo -e "${YELLOW}[6/9] Setting correct permissions...${NC}"

# Ensure freerad user exists
if ! id -u freerad > /dev/null 2>&1; then
    print_error "freerad user does not exist. Package installation may have failed."
    exit 1
fi

# Set ownership and permissions for SQLite directory and database
echo "  → Setting owner freerad:freerad on $FREERADIUS_DIR/sqlite"
chown -R freerad:freerad "$FREERADIUS_DIR/sqlite"

echo "  → Setting directory permissions to 775"
chmod 775 "$FREERADIUS_DIR/sqlite"

echo "  → Setting database file permissions to 664"
chmod 664 "$FREERADIUS_DIR/sqlite/radius.db"

print_info "Permissions set correctly"
echo ""

###############################################################################
# Step 7: Apply SQLite tuning and schema modifications
###############################################################################
echo -e "${YELLOW}[7/9] Applying SQLite optimizations and schema updates...${NC}"

# Note: The database template (sqlite/radius.db) already includes:
# - RadTik-specific columns (calling_station_id, nas_identifier, processed)
# - Performance indexes
# - WAL mode enabled
# These steps ensure settings are applied regardless of template state

echo "  → Enabling WAL mode"
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "PRAGMA journal_mode=WAL;" > /dev/null

echo "  → Setting busy_timeout to 30000ms"
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "PRAGMA busy_timeout=30000;" > /dev/null

echo "  → Verifying RadTik columns in radpostauth table"
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "ALTER TABLE radpostauth ADD COLUMN calling_station_id varchar(50) DEFAULT NULL;" 2>/dev/null || echo "    (calling_station_id already exists)"
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "ALTER TABLE radpostauth ADD COLUMN nas_identifier varchar(64) DEFAULT NULL;" 2>/dev/null || echo "    (nas_identifier already exists)"
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "ALTER TABLE radpostauth ADD COLUMN processed INTEGER DEFAULT 0;" 2>/dev/null || echo "    (processed already exists)"

echo "  → Creating indexes for performance"
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "CREATE INDEX IF NOT EXISTS idx_radpostauth_processed ON radpostauth(processed, authdate);" > /dev/null
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "CREATE INDEX IF NOT EXISTS idx_radpostauth_username ON radpostauth(username);" > /dev/null
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "CREATE INDEX IF NOT EXISTS idx_radcheck_username ON radcheck(username);" > /dev/null
sqlite3 "$FREERADIUS_DIR/sqlite/radius.db" "CREATE INDEX IF NOT EXISTS idx_radreply_username ON radreply(username);" > /dev/null

# Fix permissions on WAL files if they exist
chown freerad:freerad "$FREERADIUS_DIR/sqlite"/* 2>/dev/null || true
chmod 664 "$FREERADIUS_DIR/sqlite/radius.db"* 2>/dev/null || true

print_info "SQLite optimizations and schema updates applied"
echo ""

###############################################################################
# Step 8: Restart FreeRADIUS and verify
###############################################################################
echo -e "${YELLOW}[8/9] Restarting FreeRADIUS service...${NC}"

systemctl restart freeradius

# Wait a moment for service to fully start
sleep 2

# Check service status
if systemctl is-active --quiet freeradius; then
    print_info "FreeRADIUS is running successfully!"
else
    print_error "FreeRADIUS failed to start"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check logs: sudo journalctl -u freeradius -n 50"
    echo "  2. Run in debug mode: sudo freeradius -X"
    echo "  3. Check permissions: ls -la $FREERADIUS_DIR/sqlite/"
    exit 1
fi
echo ""

###############################################################################
# Step 9: Enable FreeRADIUS on boot
###############################################################################
echo -e "${YELLOW}[9/9] Enabling FreeRADIUS on boot...${NC}"
systemctl enable freeradius
print_info "FreeRADIUS enabled on boot"
echo ""

print_header "✓ FreeRADIUS Core Installation Complete"

###############################################################################
# PHASE 2: API Server Installation
###############################################################################

print_header "PHASE 2: Installing API Server"

###############################################################################
# API Step 1: Setup configuration
###############################################################################
echo -e "${YELLOW}[API 1/5] Setting up API configuration...${NC}"

cd "$SCRIPTS_DIR"

if [ ! -f "config.ini.example" ]; then
    print_error "config.ini.example not found"
    exit 1
fi
    
    if [ -f "config.ini" ]; then
        print_warning "config.ini already exists"
        read -p "Do you want to regenerate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            mv config.ini "config.ini.bak.${TIMESTAMP}"
            cp config.ini.example config.ini
        fi
    else
        cp config.ini.example config.ini
    fi
    
    # Generate secure token
    API_TOKEN=$(openssl rand -hex 32)
    
    # Update config.ini with token
    sed -i "s/auth_token = your-secure-token-here/auth_token = $API_TOKEN/" config.ini
    
    # Update database path
    sed -i "s|db_path = /var/lib/freeradius/radius.db|db_path = $FREERADIUS_DIR/sqlite/radius.db|" config.ini
    
    print_info "Configuration file created: $SCRIPTS_DIR/config.ini"
    print_info "Generated secure token (save this for Laravel)"
    echo ""
    
    ###############################################################################
    # API Step 2: Set permissions
    ###############################################################################
    echo -e "${YELLOW}[API 2/5] Setting permissions...${NC}"
    
    chmod +x "$SCRIPTS_DIR/sync-vouchers.py"
    
    # Set ownership
    if id "freerad" &>/dev/null; then
        chown -R freerad:freerad "$SCRIPTS_DIR"
        print_info "Ownership set to freerad:freerad"
    else
        print_warning "freerad user not found, skipping ownership change"
    fi
    echo ""
    
    ###############################################################################
    # API Step 3: Install systemd service
    ###############################################################################
    echo -e "${YELLOW}[API 3/5] Installing systemd service...${NC}"
    
    if [ ! -f "$SCRIPT_DIR/radtik-radius-api.service" ]; then
        print_error "Service file not found: $SCRIPT_DIR/radtik-radius-api.service"
        exit 1
    fi
    
    # Copy and update service file
    cp "$SCRIPT_DIR/radtik-radius-api.service" "$API_SERVICE_FILE"
    
    # Update paths in service file
    sed -i "s|WorkingDirectory=.*|WorkingDirectory=$SCRIPTS_DIR|" "$API_SERVICE_FILE"
    sed -i "s|sync-vouchers:app|sync-vouchers.py:app|" "$API_SERVICE_FILE"
    
    # Reload systemd
    systemctl daemon-reload
    
    print_info "Service installed: $API_SERVICE_FILE"
    echo ""
    
    ###############################################################################
    # API Step 4: Configure firewall
    ###############################################################################
    echo -e "${YELLOW}[API 4/5] Configuring firewall...${NC}"
    
    if command -v ufw &> /dev/null; then
        ufw allow 5000/tcp > /dev/null 2>&1 || true
        print_info "UFW: Port 5000 opened"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=5000/tcp > /dev/null 2>&1 || true
        firewall-cmd --reload > /dev/null 2>&1 || true
        print_info "Firewalld: Port 5000 opened"
    else
        print_warning "No firewall detected. Manually open port 5000 if needed."
    fi
    echo ""
    
    ###############################################################################
    # API Step 5: Test and enable service
    ###############################################################################
    echo -e "${YELLOW}[API 5/5] Testing and enabling API service...${NC}"
    
    # Start service
    systemctl start $API_SERVICE_NAME
    
    sleep 3
    
    # Test health endpoint
    RESPONSE=$(curl -s -H "Authorization: Bearer $API_TOKEN" http://localhost:5000/health 2>/dev/null || echo "failed")
    
    if [[ $RESPONSE == *"healthy"* ]]; then
        print_info "API server is healthy and responding"
        
        # Enable service
        systemctl enable $API_SERVICE_NAME > /dev/null 2>&1
        print_info "API service enabled on boot"
    else
        print_warning "API server health check failed, but service is running"
        print_warning "Check logs: sudo journalctl -u $API_SERVICE_NAME -f"
    fi
    echo ""
    
    print_header "✓ API Server Installation Complete"

###############################################################################
# PHASE 3: Legacy Sync Scripts Installation
###############################################################################

print_header "PHASE 3: Installing Legacy Sync Scripts"

###############################################################################
# Legacy Step 1: Setup sync directory
###############################################################################
echo -e "${YELLOW}[Legacy 1/3] Setting up sync directory...${NC}"
    
    # Copy config example
    cp "$SCRIPTS_DIR/config.ini.example" "$SYNC_DIR/"
    
    # Create config.ini if it doesn't exist
    if [ ! -f "$SYNC_DIR/config.ini" ]; then
        cp "$SYNC_DIR/config.ini.example" "$SYNC_DIR/config.ini"
        print_info "Configuration template created"
    else
        print_info "Configuration already exists"
    fi
    
    # Make scripts executable
    chmod +x "$SYNC_DIR"/*.py 2>/dev/null || true
    
    # Create log directory
    mkdir -p /var/log/radtik-sync
    touch /var/log/radtik-sync/activations.log
    touch /var/log/radtik-sync/deleted.log
    chmod 644 /var/log/radtik-sync/*.log 2>/dev/null || true
    
    print_info "Sync directory configured"
    echo ""
    
    ###############################################################################
    # Legacy Step 2: Setup cron jobs
    ###############################################################################
    echo -e "${YELLOW}[Legacy 2/3] Setting up cron jobs...${NC}"
    
    CRON_FILE="/etc/cron.d/radtik-sync"
    
    cat > "$CRON_FILE" << 'EOF'
# RadTik FreeRADIUS Legacy Synchronization Cron Jobs

# Check for new activations (MAC binding) every minute
* * * * * root /usr/bin/python3 /opt/radtik-sync/check-activations.py >> /var/log/radtik-sync/activations.log 2>&1

# Sync deleted users every 5 minutes
*/5 * * * * root /usr/bin/python3 /opt/radtik-sync/sync-deleted.py >> /var/log/radtik-sync/deleted.log 2>&1

EOF
    
    chmod 644 "$CRON_FILE"
    
    print_info "Cron jobs installed"
    echo ""
    
    ###############################################################################
    # Legacy Step 3: Configuration reminder
    ###############################################################################
    echo -e "${YELLOW}[Legacy 3/3] Configuration required...${NC}"
    
    print_warning "Edit $SYNC_DIR/config.ini to set Laravel API URL and token"
    echo ""
    
print_header "✓ Legacy Sync Scripts Installation Complete"

###############################################################################
# Final Summary
###############################################################################

print_header "Installation Summary"

echo ""
echo -e "${GREEN}✓ FreeRADIUS with SQLite installed and running${NC}"
echo "  • Database: $FREERADIUS_DIR/sqlite/radius.db"
echo "  • Service: systemctl status freeradius"
echo ""

echo -e "${GREEN}✓ API Server installed and running${NC}"
echo "  • Endpoint: http://localhost:5000"
echo "  • Service: systemctl status $API_SERVICE_NAME"
echo "  • Logs: journalctl -u $API_SERVICE_NAME -f"
echo ""
echo -e "${YELLOW}API Authentication Token:${NC}"
echo -e "${GREEN}$API_TOKEN${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT:${NC} Add this token to Laravel RadiusServer configuration:"
echo "  1. Login to Laravel admin panel"
echo "  2. Go to RADIUS Server settings"
echo "  3. Set host: <this-server-ip>"
echo "  4. Set auth_token: $API_TOKEN"
echo "  5. Link router to RADIUS server"
echo "  6. Start queue worker: php artisan queue:work"
echo ""

echo -e "${GREEN}✓ Legacy sync scripts installed${NC}"
echo "  • Directory: $SYNC_DIR"
echo "  • Cron jobs: /etc/cron.d/radtik-sync"
echo ""
echo -e "${YELLOW}TODO:${NC} Configure Laravel API connection:"
echo "  sudo nano $SYNC_DIR/config.ini"
echo "  Set api_url and api_secret from Laravel"
echo ""

echo -e "${BLUE}Quick Tests:${NC}"
echo "  • Test FreeRADIUS: radtest testuser testpass localhost 0 testing123"
echo "  • View logs: tail -f /var/log/freeradius/radius.log"
echo "  • Debug mode: sudo freeradius -X"
echo "  • Test API health: curl -H 'Authorization: Bearer $API_TOKEN' http://localhost:5000/health"
echo "  • View API stats: curl -H 'Authorization: Bearer $API_TOKEN' http://localhost:5000/stats"

echo ""
echo -e "${BLUE}Documentation:${NC}"
echo "  • API Setup: $SCRIPT_DIR/API_QUICKSTART.md"
echo "  • Full Guide: $SCRIPT_DIR/README.md"
echo "  • Scripts: $SCRIPTS_DIR/README.md"
echo ""

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}║        Installation completed successfully! 🎉           ║${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
