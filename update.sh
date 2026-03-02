#!/bin/bash

###############################################################################
# RadTik FreeRADIUS Update Script
# For Ubuntu 22.04 LTS
# 
# This script updates an existing radtik-radius installation while:
# 1. Creating automatic backups
# 2. Preserving configuration files
# 3. Restarting services safely
###############################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Paths
INSTALL_DIR="/opt/radtik-radius"
FREERADIUS_DIR="/etc/freeradius/3.0"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/opt/radtik-radius-backup-${TIMESTAMP}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run with sudo${NC}" 
   exit 1
fi

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
║          RadTik FreeRADIUS Update Script                 ║
║                                                           ║
║  Updates existing installation while preserving config   ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check if installation exists
if [ ! -d "$INSTALL_DIR" ]; then
    print_error "Installation directory not found: $INSTALL_DIR"
    echo "Please run install.sh first."
    exit 1
fi

# Get current version
if [ -f "$INSTALL_DIR/VERSION" ]; then
    CURRENT_VERSION=$(cat "$INSTALL_DIR/VERSION")
    echo "Current version: ${GREEN}$CURRENT_VERSION${NC}"
else
    print_warning "Could not determine current version"
    CURRENT_VERSION="unknown"
fi

echo ""
echo "This update will:"
echo "  ${GREEN}✓${NC} Create backup at: $BACKUP_DIR"
echo "  ${GREEN}✓${NC} Preserve your configuration files"
echo "  ${GREEN}✓${NC} Update system files"
echo "  ${GREEN}✓${NC} Restart services"
echo ""
read -p "Continue with update? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Update cancelled."
    exit 0
fi

###############################################################################
# PHASE 1: Create Backup
###############################################################################

print_header "PHASE 1: Creating Backup"

echo -e "${YELLOW}Creating backup of current installation...${NC}"
cp -r "$INSTALL_DIR" "$BACKUP_DIR"
print_info "Backup created at: $BACKUP_DIR"
echo ""

###############################################################################
# PHASE 2: Stop Services
###############################################################################

print_header "PHASE 2: Stopping Services"

echo -e "${YELLOW}Stopping services...${NC}"
systemctl stop radtik-radius-api || true
systemctl stop freeradius || true
print_info "Services stopped"
echo ""

###############################################################################
# PHASE 3: Update Files
###############################################################################

print_header "PHASE 3: Updating Files"

# Get the directory where this script is located (update source)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -e "${YELLOW}Copying updated files...${NC}"

# Backup config.ini before overwriting
if [ -f "$INSTALL_DIR/scripts/config.ini" ]; then
    cp "$INSTALL_DIR/scripts/config.ini" /tmp/config.ini.backup
    print_info "Configuration backed up"
fi

# Copy all files from source to installation directory
if [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
    cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR/"
    print_info "Files updated"
else
    print_warning "Running from installation directory, files already in place"
fi

# Restore config.ini
if [ -f /tmp/config.ini.backup ]; then
    cp /tmp/config.ini.backup "$INSTALL_DIR/scripts/config.ini"
    rm /tmp/config.ini.backup
    print_info "Configuration restored"
fi

# Set proper permissions
echo -e "${YELLOW}Setting permissions...${NC}"
chown -R root:root "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/install.sh"
chmod +x "$INSTALL_DIR/update.sh"
chmod +x "$INSTALL_DIR/scripts/"*.py
print_info "Permissions set"
echo ""

###############################################################################
# PHASE 4: Update Python Dependencies
###############################################################################

print_header "PHASE 4: Updating Python Dependencies"

echo -e "${YELLOW}Installing/updating Python packages...${NC}"
pip3 install -r "$INSTALL_DIR/requirements.txt" --upgrade --quiet
print_info "Python dependencies updated"
echo ""

###############################################################################
# PHASE 5: Update FreeRADIUS Configuration (if needed)
###############################################################################

print_header "PHASE 5: Updating FreeRADIUS Configuration"

echo -e "${YELLOW}Checking FreeRADIUS configuration...${NC}"

# Copy updated module configurations (preserve clients.conf)
if [ -d "$INSTALL_DIR/mods-available" ]; then
    cp -r "$INSTALL_DIR/mods-available"/* "$FREERADIUS_DIR/mods-available/" 2>/dev/null || true
    print_info "Module configurations updated"
fi

if [ -d "$INSTALL_DIR/mods-config" ]; then
    cp -r "$INSTALL_DIR/mods-config"/* "$FREERADIUS_DIR/mods-config/" 2>/dev/null || true
    print_info "Module configs updated"
fi

if [ -d "$INSTALL_DIR/sites-enabled" ]; then
    cp -r "$INSTALL_DIR/sites-enabled"/* "$FREERADIUS_DIR/sites-enabled/" 2>/dev/null || true
    print_info "Site configurations updated"
fi

# Preserve clients.conf (contains user's secrets)
print_warning "Preserving existing clients.conf (not overwriting)"
echo ""

###############################################################################
# PHASE 6: Start Services
###############################################################################

print_header "PHASE 6: Starting Services"

echo -e "${YELLOW}Starting services...${NC}"
systemctl start radtik-radius-api
systemctl start freeradius
print_info "Services started"
echo ""

# Wait for services to stabilize
sleep 3

# Check service status
echo -e "${YELLOW}Verifying services...${NC}"
API_STATUS=$(systemctl is-active radtik-radius-api)
RADIUS_STATUS=$(systemctl is-active freeradius)

if [ "$API_STATUS" = "active" ]; then
    print_info "API Service: Active"
else
    print_error "API Service: $API_STATUS"
fi

if [ "$RADIUS_STATUS" = "active" ]; then
    print_info "FreeRADIUS Service: Active"
else
    print_error "FreeRADIUS Service: $RADIUS_STATUS"
fi

echo ""

###############################################################################
# PHASE 7: Update Complete
###############################################################################

print_header "Update Complete!"

# Get new version
if [ -f "$INSTALL_DIR/VERSION" ]; then
    NEW_VERSION=$(cat "$INSTALL_DIR/VERSION")
    echo -e "${GREEN}✓${NC} Updated from version ${YELLOW}$CURRENT_VERSION${NC} to ${GREEN}$NEW_VERSION${NC}"
else
    echo -e "${GREEN}✓${NC} Update completed successfully"
fi

echo ""
echo "Backup location: ${BLUE}$BACKUP_DIR${NC}"
echo ""
echo "If you experience any issues, you can restore the backup:"
echo "  ${YELLOW}sudo rm -rf $INSTALL_DIR${NC}"
echo "  ${YELLOW}sudo mv $BACKUP_DIR $INSTALL_DIR${NC}"
echo "  ${YELLOW}sudo systemctl restart radtik-radius-api freeradius${NC}"
echo ""
print_info "Update completed successfully!"
