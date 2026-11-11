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
    echo -e "Current version: ${GREEN}$CURRENT_VERSION${NC}"
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
if [ "${1:-}" = "-y" ] || [ "${1:-}" = "--yes" ]; then
    REPLY="y"
else
    read -p "Continue with update? (y/N) " -n 1 -r
    echo
fi
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

# Server-specific files that an update must never overwrite
PROTECTED_DIR="$(mktemp -d)"
for file in scripts/config.ini clients.conf sqlite/radius.db; do
    if [ -f "$INSTALL_DIR/$file" ]; then
        mkdir -p "$PROTECTED_DIR/$(dirname "$file")"
        cp -p "$INSTALL_DIR/$file" "$PROTECTED_DIR/$file"
    fi
done
print_info "Configuration backed up"

# Copy all files from source to installation directory
if [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
    cp -r "$SCRIPT_DIR"/. "$INSTALL_DIR/"
    print_info "Files updated"
else
    print_warning "Running from installation directory, files already in place"
fi

# Restore the protected files
(cd "$PROTECTED_DIR" && find . -type f) | while read -r file; do
    cp -p "$PROTECTED_DIR/$file" "$INSTALL_DIR/$file"
done
rm -rf "$PROTECTED_DIR"
print_info "Configuration restored"

# Set proper permissions
echo -e "${YELLOW}Setting permissions...${NC}"
chown -R root:root "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/install.sh"
chmod +x "$INSTALL_DIR/update.sh"
chmod +x "$INSTALL_DIR/scripts/"*.py "$INSTALL_DIR/scripts/"*.sh
print_info "Permissions set"

echo ""

###############################################################################
# PHASE 4: Apply configuration
###############################################################################

print_header "PHASE 4: Applying Configuration"

# FreeRADIUS files, scheduled jobs, python packages, API certificate and systemd unit are
# applied by one script that the panel's "Apply update" uses too. It leaves config.ini,
# clients.conf and the database alone, and refuses a configuration FreeRADIUS rejects.
bash "$INSTALL_DIR/scripts/post-update.sh" freerad
print_info "Configuration applied"
echo ""

###############################################################################
# PHASE 5: Start Services
###############################################################################

print_header "PHASE 5: Starting Services"

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
# PHASE 6: Update Complete
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
