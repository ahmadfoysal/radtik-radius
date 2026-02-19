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
# Done
###############################################################################
echo ""
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║            Installation Completed Successfully!          ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo ""
echo -e "FreeRADIUS and API Server are now running!"
echo -e "API Server: http://$(hostname -I | awk '{print $1}'):5000"
echo ""
