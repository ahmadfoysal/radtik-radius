#!/bin/bash

###############################################################################
# RadTik FreeRADIUS Installation Validator
# Validates that FreeRADIUS and sync scripts are properly installed
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

echo -e "${BLUE}===== RadTik FreeRADIUS Installation Validator =====${NC}"
echo ""

# Function to check success
check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

# Function to check failure
check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((ERRORS++))
}

# Function to check warning
check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

###############################################################################
# Check 1: FreeRADIUS Installation
###############################################################################
echo -e "${BLUE}[1/10] Checking FreeRADIUS installation...${NC}"

if command -v freeradius &> /dev/null || command -v radiusd &> /dev/null; then
    check_pass "FreeRADIUS is installed"
else
    check_fail "FreeRADIUS is not installed"
fi

if systemctl is-active --quiet freeradius; then
    check_pass "FreeRADIUS service is running"
else
    check_fail "FreeRADIUS service is not running"
fi

if systemctl is-enabled --quiet freeradius; then
    check_pass "FreeRADIUS service is enabled on boot"
else
    check_warn "FreeRADIUS service is not enabled on boot"
fi

echo ""

###############################################################################
# Check 2: Configuration Files
###############################################################################
echo -e "${BLUE}[2/10] Checking configuration files...${NC}"

FREERADIUS_DIR="/etc/freeradius/3.0"

if [ -f "$FREERADIUS_DIR/clients.conf" ]; then
    check_pass "clients.conf exists"
else
    check_fail "clients.conf not found"
fi

if [ -f "$FREERADIUS_DIR/mods-available/sql" ]; then
    check_pass "SQL module configuration exists"
else
    check_fail "SQL module configuration not found"
fi

if [ -L "$FREERADIUS_DIR/mods-enabled/sql" ]; then
    check_pass "SQL module is enabled"
else
    check_fail "SQL module is not enabled"
fi

echo ""

###############################################################################
# Check 3: SQLite Database
###############################################################################
echo -e "${BLUE}[3/10] Checking SQLite database...${NC}"

DB_PATH="$FREERADIUS_DIR/sqlite/radius.db"

if [ -f "$DB_PATH" ]; then
    check_pass "Database file exists"
    
    # Check file permissions
    DB_OWNER=$(stat -c '%U' "$DB_PATH" 2>/dev/null || stat -f '%Su' "$DB_PATH" 2>/dev/null)
    if [ "$DB_OWNER" == "freerad" ]; then
        check_pass "Database owned by freerad user"
    else
        check_fail "Database not owned by freerad user (owner: $DB_OWNER)"
    fi
    
    # Check if database is accessible
    if sqlite3 "$DB_PATH" "SELECT 1" &> /dev/null; then
        check_pass "Database is accessible"
    else
        check_fail "Database is not accessible"
    fi
    
    # Check tables exist
    TABLES=$(sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table'" 2>/dev/null)
    if echo "$TABLES" | grep -q "radcheck"; then
        check_pass "radcheck table exists"
    else
        check_fail "radcheck table not found"
    fi
    
    if echo "$TABLES" | grep -q "radreply"; then
        check_pass "radreply table exists"
    else
        check_fail "radreply table not found"
    fi
    
    if echo "$TABLES" | grep -q "radpostauth"; then
        check_pass "radpostauth table exists"
    else
        check_fail "radpostauth table not found"
    fi
    
    # Check WAL mode
    JOURNAL_MODE=$(sqlite3 "$DB_PATH" "PRAGMA journal_mode" 2>/dev/null)
    if [ "$JOURNAL_MODE" == "wal" ]; then
        check_pass "WAL mode is enabled"
    else
        check_warn "WAL mode is not enabled (current: $JOURNAL_MODE)"
    fi
else
    check_fail "Database file not found"
fi

echo ""

###############################################################################
# Check 4: Python Installation
###############################################################################
echo -e "${BLUE}[4/10] Checking Python installation...${NC}"

if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
    check_pass "Python 3 is installed (version: $PYTHON_VERSION)"
else
    check_fail "Python 3 is not installed"
fi

if python3 -c "import requests" 2>/dev/null; then
    check_pass "Python requests library is installed"
else
    check_fail "Python requests library is not installed"
fi

echo ""

###############################################################################
# Check 5: Sync Scripts
###############################################################################
echo -e "${BLUE}[5/10] Checking synchronization scripts...${NC}"

SYNC_DIR="/opt/radtik-sync"

if [ -d "$SYNC_DIR" ]; then
    check_pass "Sync directory exists"
else
    check_fail "Sync directory not found"
fi

for script in sync-vouchers.py check-activations.py sync-deleted.py; do
    if [ -f "$SYNC_DIR/$script" ]; then
        check_pass "$script exists"
        
        if [ -x "$SYNC_DIR/$script" ]; then
            check_pass "$script is executable"
        else
            check_warn "$script is not executable"
        fi
    else
        check_fail "$script not found"
    fi
done

if [ -f "$SYNC_DIR/config.ini" ]; then
    check_pass "config.ini exists"
    
    # Check if configured
    if grep -q "your-radius-server-api-token-here" "$SYNC_DIR/config.ini" 2>/dev/null; then
        check_warn "config.ini has not been configured (still has default values)"
    else
        check_pass "config.ini appears to be configured"
    fi
else
    check_warn "config.ini not found (needs configuration)"
fi

echo ""

###############################################################################
# Check 6: Cron Jobs
###############################################################################
echo -e "${BLUE}[6/10] Checking cron jobs...${NC}"

CRON_FILE="/etc/cron.d/radtik-sync"

if [ -f "$CRON_FILE" ]; then
    check_pass "Cron file exists"
    
    if grep -q "sync-vouchers.py" "$CRON_FILE"; then
        check_pass "Voucher sync cron job configured"
    else
        check_fail "Voucher sync cron job not found"
    fi
    
    if grep -q "check-activations.py" "$CRON_FILE"; then
        check_pass "Activation check cron job configured"
    else
        check_fail "Activation check cron job not found"
    fi
    
    if grep -q "sync-deleted.py" "$CRON_FILE"; then
        check_pass "Deleted users sync cron job configured"
    else
        check_fail "Deleted users sync cron job not found"
    fi
else
    check_fail "Cron file not found"
fi

echo ""

###############################################################################
# Check 7: Log Files
###############################################################################
echo -e "${BLUE}[7/10] Checking log files...${NC}"

LOG_DIR="/var/log/radtik-sync"

if [ -d "$LOG_DIR" ]; then
    check_pass "Log directory exists"
    
    for log in sync.log activations.log deleted.log; do
        if [ -f "$LOG_DIR/$log" ]; then
            check_pass "$log exists"
        else
            check_warn "$log not found"
        fi
    done
else
    check_warn "Log directory not found"
fi

if [ -f "/var/log/freeradius/radius.log" ]; then
    check_pass "FreeRADIUS log file exists"
else
    check_warn "FreeRADIUS log file not found"
fi

echo ""

###############################################################################
# Check 8: Port Accessibility
###############################################################################
echo -e "${BLUE}[8/10] Checking RADIUS ports...${NC}"

if netstat -tuln 2>/dev/null | grep -q ":1812 " || ss -tuln 2>/dev/null | grep -q ":1812 "; then
    check_pass "RADIUS authentication port (1812) is listening"
else
    check_fail "RADIUS authentication port (1812) is not listening"
fi

if netstat -tuln 2>/dev/null | grep -q ":1813 " || ss -tuln 2>/dev/null | grep -q ":1813 "; then
    check_pass "RADIUS accounting port (1813) is listening"
else
    check_warn "RADIUS accounting port (1813) is not listening"
fi

echo ""

###############################################################################
# Check 9: Test Authentication
###############################################################################
echo -e "${BLUE}[9/10] Testing authentication capability...${NC}"

if command -v radtest &> /dev/null; then
    check_pass "radtest utility is available"
else
    check_warn "radtest utility not found (install freeradius-utils)"
fi

echo ""

###############################################################################
# Check 10: Security
###############################################################################
echo -e "${BLUE}[10/10] Security checks...${NC}"

# Check if using default shared secret
if grep -q "testing123" "$FREERADIUS_DIR/clients.conf" 2>/dev/null; then
    check_warn "Default shared secret 'testing123' detected - change for production!"
fi

# Check if allowing all IP addresses
if grep -q "0.0.0.0/0" "$FREERADIUS_DIR/clients.conf" 2>/dev/null; then
    check_warn "Client configuration allows all IPs (0.0.0.0/0) - restrict for production!"
fi

echo ""

###############################################################################
# Summary
###############################################################################
echo -e "${BLUE}===== Validation Summary =====${NC}"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! Installation is complete and healthy.${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Installation is functional but has $WARNINGS warning(s).${NC}"
    echo -e "  Review warnings above and address them for production use."
    exit 0
else
    echo -e "${RED}✗ Installation has $ERRORS error(s) and $WARNINGS warning(s).${NC}"
    echo -e "  Please review errors above and fix them before using the system."
    exit 1
fi
