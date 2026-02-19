#!/bin/bash

###############################################################################
# RadTik FreeRADIUS Bootstrap Installer
# This script clones the repository and runs the complete installation
###############################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_URL="${RADTIK_REPO_URL:-https://github.com/ahmadfoysal/radtik-radius.git}"
REPO_BRANCH="${RADTIK_BRANCH:-main}"
TEMP_DIR="/tmp/radtik-install-$$"
INSTALL_DIR="/opt/radtik-radius"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run with sudo${NC}" 
   exit 1
fi

clear
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   RadTik FreeRADIUS Bootstrap Installation Script        ║
║                                                           ║
║  Automated installation from GitHub repository           ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo ""

###############################################################################
# Install Git if not available
###############################################################################
echo -e "${YELLOW}Checking dependencies...${NC}"
if ! command -v git &> /dev/null; then
    echo -e "${GREEN}✓${NC} Installing git..."
    apt-get update -qq
    apt-get install -y git
else
    echo -e "${GREEN}✓${NC} Git is already installed"
fi
echo ""

###############################################################################
# Clone or Update Repository
###############################################################################
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}Installation directory exists. Updating...${NC}"
    cd "$INSTALL_DIR"
    
    # Check if it's a git repository
    if [ -d .git ]; then
        echo -e "${GREEN}✓${NC} Pulling latest changes..."
        git pull origin $REPO_BRANCH || echo -e "${YELLOW}⚠${NC} Could not pull updates, continuing with existing files..."
    else
        echo -e "${YELLOW}⚠${NC} Not a git repository, backing up and cloning fresh..."
        mv "$INSTALL_DIR" "$INSTALL_DIR.backup.$(date +%s)"
        mkdir -p "$INSTALL_DIR"
        git clone -b $REPO_BRANCH "$REPO_URL" "$TEMP_DIR"
        cp -r "$TEMP_DIR"/* "$INSTALL_DIR/"
        rm -rf "$TEMP_DIR"
    fi
else
    echo -e "${YELLOW}Cloning repository...${NC}"
    mkdir -p "$INSTALL_DIR"
    git clone -b $REPO_BRANCH "$REPO_URL" "$TEMP_DIR"
    
    # Copy repository contents directly (no subdirectory)
    echo -e "${GREEN}✓${NC} Copying installation files..."
    cp -r "$TEMP_DIR"/* "$INSTALL_DIR/"
    
    rm -rf "$TEMP_DIR"
    echo -e "${GREEN}✓${NC} Repository cloned successfully"
fi
echo ""

###############################################################################
# Run Installation Script
###############################################################################
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Starting FreeRADIUS Installation${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [ ! -f "$INSTALL_DIR/install.sh" ]; then
    echo -e "${RED}✗${NC} Installation script not found at $INSTALL_DIR/install.sh"
    exit 1
fi

# Make install script executable
chmod +x "$INSTALL_DIR/install.sh"

# Run the installation
cd "$INSTALL_DIR"
bash "$INSTALL_DIR/install.sh"

###############################################################################
# Restart Services to Apply Configuration Changes
###############################################################################
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Restarting Services${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "${YELLOW}Restarting FreeRADIUS...${NC}"
systemctl restart freeradius
echo -e "${GREEN}✓${NC} FreeRADIUS restarted"

echo -e "${YELLOW}Restarting API Server...${NC}"
systemctl restart radtik-radius-api
sleep 2  # Give service time to start
echo -e "${GREEN}✓${NC} API Server restarted"

# Verify API service is running
if systemctl is-active --quiet radtik-radius-api; then
    echo -e "${GREEN}✓${NC} API Server is running"
else
    echo -e "${RED}✗${NC} API Server failed to start"
    echo -e "${YELLOW}Check logs:${NC} journalctl -u radtik-radius-api -n 50"
fi

###############################################################################
# Extract and Display Configuration
###############################################################################
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Reading Configuration${NC}"
echo -e "${BLUE}========================================${NC}"

# Extract API Token from config.ini
if [ -f "$INSTALL_DIR/scripts/config.ini" ]; then
    API_TOKEN=$(grep "^auth_token" "$INSTALL_DIR/scripts/config.ini" | cut -d'=' -f2 | xargs)
    if [ -z "$API_TOKEN" ]; then
        API_TOKEN="Not found in config.ini"
    fi
else
    API_TOKEN="config.ini not found"
fi

# Extract RADIUS Secret from clients.conf
if [ -f "/etc/freeradius/3.0/clients.conf" ]; then
    # Try to extract secret from 'client radtik' section (production client)
    RADIUS_SECRET=$(grep -A 10 "client radtik" /etc/freeradius/3.0/clients.conf | grep -E "^\s+secret\s*=" | head -1 | sed 's/.*secret\s*=\s*//' | xargs)
    
    # If not found, try localhost as fallback
    if [ -z "$RADIUS_SECRET" ]; then
        RADIUS_SECRET=$(grep -A 10 "client localhost" /etc/freeradius/3.0/clients.conf | grep -E "^\s+secret\s*=" | head -1 | sed 's/.*secret\s*=\s*//' | xargs)
    fi
    
    # Final fallback
    if [ -z "$RADIUS_SECRET" ]; then
        RADIUS_SECRET="Not found in clients.conf"
    fi
else
    RADIUS_SECRET="clients.conf not found"
fi

###############################################################################
# Done
###############################################################################
echo ""
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║       Bootstrap Installation Completed Successfully!     ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo ""

echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}              IMPORTANT CONFIGURATION VALUES              ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}✓ FreeRADIUS Server:${NC}"
echo -e "  • IP Address: $(hostname -I | awk '{print $1}')"
echo -e "  • RADIUS Secret (for NAS/Router): ${YELLOW}${RADIUS_SECRET}${NC}"
echo -e "  • Service: systemctl status freeradius"
echo ""
echo -e "${GREEN}✓ API Server:${NC}"
echo -e "  • Endpoint: ${BLUE}http://$(hostname -I | awk '{print $1}'):5000${NC}"
echo -e "  • API Token: ${YELLOW}${API_TOKEN}${NC}"
echo -e "  • Service: systemctl status radtik-radius-api"
echo ""
echo -e "${BLUE}Quick Test:${NC}"
echo -e "  curl -H 'Authorization: Bearer ${API_TOKEN}' http://localhost:5000/health"
echo ""

# Test API connection
echo -e "${YELLOW}Testing API connection...${NC}"
API_RESPONSE=$(curl -s -H "Authorization: Bearer ${API_TOKEN}" http://localhost:5000/health 2>/dev/null)
if echo "$API_RESPONSE" | grep -q "status"; then
    echo -e "${GREEN}✓${NC} API Server responding correctly"
else
    echo -e "${RED}✗${NC} API Server returned: $API_RESPONSE"
    echo -e "${YELLOW}⚠${NC} If you see 'Invalid authentication token', the service may need a moment to fully restart"
fi
echo ""

echo -e "${YELLOW}COPY THESE VALUES TO LARAVEL:${NC}"
echo -e "  1. Login to Laravel admin panel"
echo -e "  2. Go to RADIUS Server settings"
echo -e "  3. Add new RADIUS server:"
echo -e "     - Host: $(hostname -I | awk '{print $1}')"
echo -e "     - Secret: ${YELLOW}${RADIUS_SECRET}${NC} ${GREEN}(from 'client radtik' - for NAS/Router)${NC}"
echo -e "     - API Token: ${YELLOW}${API_TOKEN}${NC}"
echo ""
