# RadTik FreeRADIUS + SQLite Installer

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20LTS-orange.svg)](https://ubuntu.com/)
[![FreeRADIUS](https://img.shields.io/badge/FreeRADIUS-3.0-blue.svg)](https://freeradius.org/)
[![Python](https://img.shields.io/badge/Python-3.6%2B-green.svg)](https://www.python.org/)

A one-command installer for setting up FreeRADIUS with SQLite backend on Ubuntu 22.04 LTS, pre-configured for RadTik hotspot authentication.

## Repository Structure

```
radtik-radius/
├── install.sh                  # Main installation script
├── validate.sh                 # Installation validation script
├── README.md                   # This file
├── QUICKSTART.md              # Quick start guide
├── CONTRIBUTING.md            # Contribution guidelines
├── LICENSE                    # MIT License
├── CHANGELOG.md               # Version history
├── VERSION                    # Current version number
├── requirements.txt           # Python dependencies
├── .gitignore                 # Git ignore rules
├── clients.conf               # RADIUS clients configuration
├── scripts/                   # Python synchronization scripts
│   ├── sync-vouchers.py       # Voucher sync from Laravel
│   ├── check-activations.py   # Activation monitoring
│   ├── sync-deleted.py        # Deleted users cleanup
│   ├── config.ini.example     # Configuration template
│   └── README.md              # Scripts documentation
├── mods-available/
│   └── sql                    # SQL module configuration
├── mods-config/
│   └── sql/main/sqlite/
│       └── queries.conf       # SQL queries
├── sites-enabled/
│   └── default                # Virtual server config
└── sqlite/
    └── radius.db              # Pre-initialized database
```

## What This Installer Does

This repository contains a complete FreeRADIUS configuration bundle that:

- ✅ Installs FreeRADIUS 3.0 with SQLite support
- ✅ Configures SQL module for user authentication
- ✅ Sets up SQLite database with proper schema (radcheck, radreply, radacct, radpostauth)
- ✅ Configures clients for MikroTik/RadTik integration
- ✅ Applies SQLite optimizations (WAL mode, busy timeout)
- ✅ Sets correct permissions for freerad user
- ✅ Stores authentication logs including MAC address and NAS identity

## Quick Installation

### Prerequisites

- Fresh Ubuntu 22.04 LTS server (or compatible)
- Root/sudo access
- Internet connection

### Install Steps

```bash
# 1. Clone this repository
git clone https://github.com/ahmadfoysal/radtik-radius.git
cd radtik-radius

# 2. Run the installer
sudo bash install.sh
```

That's it! The installer will:

- Install required packages
- Copy all configuration files
- Set up permissions
- Enable SQL module
- Optimize SQLite
- Restart FreeRADIUS

## Validating Installation

After installation, run the validation script to verify everything is configured correctly:

```bash
sudo bash validate.sh
```

The validator will check:
- ✅ FreeRADIUS service status
- ✅ Configuration files
- ✅ Database setup and permissions
- ✅ Python environment and dependencies
- ✅ Synchronization scripts
- ✅ Cron jobs
- ✅ Log files
- ✅ RADIUS ports (1812, 1813)
- ⚠️ Security warnings (default secrets, open IPs)

**Sample output:**
```
===== RadTik FreeRADIUS Installation Validator =====

[1/10] Checking FreeRADIUS installation...
✓ FreeRADIUS is installed
✓ FreeRADIUS service is running
✓ FreeRADIUS service is enabled on boot

...

===== Validation Summary =====
✓ All checks passed! Installation is complete and healthy.
```

## Testing After Installation

### 1. Add a Test User

Add a test user to the SQLite database:

```bash
sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db
```

Inside SQLite prompt:

```sql
INSERT INTO radcheck (username, attribute, op, value)
VALUES ('testuser', 'Cleartext-Password', ':=', 'testpass');
```

Exit with `.quit`

### 2. Test Authentication

Use the `radtest` utility to verify authentication:

```bash
radtest testuser testpass localhost 0 testing123
```

**Expected output:**

```
Sent Access-Request Id 123 from 0.0.0.0:12345 to 127.0.0.1:1812 length 77
Received Access-Accept Id 123 from 127.0.0.1:1812 to 0.0.0.0:0 length 20
```

If you see `Access-Accept`, authentication is working! ✅

### 3. Check Authentication Logs

View recent authentication attempts:

```bash
sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db "SELECT * FROM radpostauth ORDER BY authdate DESC LIMIT 5;"
```

## Database Schema

This setup uses the standard FreeRADIUS SQLite schema with these key tables:

### `radcheck`

Stores user credentials and check items

- **username**: User login name
- **attribute**: Attribute name (e.g., `Cleartext-Password`, `MD5-Password`)
- **op**: Operator (`:=`, `==`, etc.)
- **value**: Attribute value

### `radreply`

Stores reply attributes sent after successful authentication

- Used for bandwidth limits, session timeouts, etc.

### `radacct`

Stores accounting records (session start/stop, data usage)

- **username**: Authenticated user
- **acctsessionid**: Unique session ID
- **acctinputoctets** / **acctoutputoctets**: Data usage
- **acctstarttime** / **acctstoptime**: Session timing

### `radpostauth`

Stores post-authentication logs including:

- **username**: Authenticated user
- **reply**: Accept or Reject
- **authdate**: Timestamp
- **calledstationid**: MAC address of the AP (Calling-Station-Id)
- **nasidentifier**: MikroTik router identity (NAS-Identifier)

**This is critical for RadTik:** The `radpostauth` table captures the MAC address and MikroTik identity for each authentication attempt.

## Configuration Files

The repository includes these pre-configured files:

- **clients.conf**: Defines RADIUS clients (MikroTik routers) with shared secrets
- **mods-available/sql**: SQL module configuration (SQLite driver, connection settings)
- **mods-config/sql/main/sqlite/queries.conf**: SQL queries for auth, accounting, and post-auth
- **sites-enabled/default**: Virtual server configuration (enables SQL for auth/accounting)
- **sqlite/radius.db**: Pre-initialized SQLite database with schema

## Troubleshooting

### FreeRADIUS Won't Start

**Check service status:**

```bash
sudo systemctl status freeradius
```

**Run in debug mode** to see detailed errors:

```bash
sudo systemctl stop freeradius
sudo freeradius -X
```

Press `Ctrl+C` to stop debug mode.

### Permission Issues

If you see "unable to open database file" errors:

```bash
# Check ownership
ls -la /etc/freeradius/3.0/sqlite/

# Should show: freerad freerad
# If not, fix it:
sudo chown -R freerad:freerad /etc/freeradius/3.0/sqlite/
sudo chmod 775 /etc/freeradius/3.0/sqlite/
sudo chmod 664 /etc/freeradius/3.0/sqlite/radius.db*
```

### Authentication Fails

1. **Check the user exists in radcheck:**

   ```bash
   sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db "SELECT * FROM radcheck WHERE username='testuser';"
   ```

2. **Verify the shared secret** matches in both:
   - `/etc/freeradius/3.0/clients.conf` (RADIUS server side)
   - MikroTik configuration (client side)

3. **Check recent auth logs:**

   ```bash
   sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db "SELECT username, reply, authdate FROM radpostauth ORDER BY authdate DESC LIMIT 10;"
   ```

4. **Check FreeRADIUS logs:**
   ```bash
   sudo tail -f /var/log/freeradius/radius.log
   ```

### Database Locked Errors

If you see "database is locked" errors:

- The installer already enables WAL mode and sets `busy_timeout=30000`
- Verify WAL mode is active:
  ```bash
  sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db "PRAGMA journal_mode;"
  ```
  Should return: `wal`

## Security Notes

⚠️ **IMPORTANT: This is a development/testing configuration**

### Before Production Deployment:

1. **Change the shared secret** in `clients.conf`:
   - Replace `testing123` with a strong random secret (20+ characters)
   - Use different secrets for each client in production

2. **Restrict client access**:
   - Replace `0.0.0.0/0` with specific IP addresses or subnets
   - Example: `192.168.1.1/32` for a single MikroTik router

3. **Use strong passwords**:
   - Never use simple passwords like `testpass` for real users
   - Consider using MD5-Password or other hashed methods instead of Cleartext-Password

4. **Firewall configuration**:
   - If using `0.0.0.0/0` in clients.conf, ensure your firewall blocks external access to UDP ports 1812 (auth) and 1813 (accounting)
   - Only allow RADIUS traffic from trusted networks

5. **Regular backups**:
   - Back up `/etc/freeradius/3.0/sqlite/radius.db` regularly
   - Consider implementing automated backups

### Example Production Client Configuration:

```conf
client mikrotik-branch1 {
    ipaddr = 192.168.1.1
    secret = your-very-strong-secret-here-use-pwgen
    require_message_authenticator = yes
    nas_type = mikrotik
}
```

## Laravel Integration & Synchronization

This FreeRADIUS setup includes **automatic synchronization** with Laravel RADTik application for seamless voucher management.

### How It Works

The installation includes Python scripts that synchronize data between Laravel and FreeRADIUS:

```
┌─────────────┐      Cron Jobs      ┌──────────────┐
│   Laravel   │ ◄─────────────────► │  FreeRADIUS  │
│   (MySQL)   │   Python Scripts    │   (SQLite)   │
└─────────────┘                     └──────────────┘
```

### Synchronization Features

1. **Voucher Sync** (Every 2 minutes)
   - Pulls vouchers from Laravel → Updates FreeRADIUS `radcheck` and `radreply` tables
   - Applies profile settings: rate limits, validity, shared users
   - Handles MAC binding configurations

2. **Activation Monitoring** (Every 1 minute)
   - Monitors `radpostauth` for first successful logins
   - Sends MAC address and activation time to Laravel
   - Applies MAC binding if profile requires it

3. **Deleted Users Sync** (Every 5 minutes)
   - Removes deleted vouchers from FreeRADIUS
   - Keeps historical data in `radacct` and `radpostauth` for auditing

### Configuration

After installation, configure the synchronization:

```bash
# Edit configuration file
sudo nano /opt/radtik-sync/config.ini
```

**Required settings:**

```ini
[laravel]
api_url = https://your-radtik-domain.com/api/radius
api_secret = your-radius-server-token-from-laravel

[radius]
db_path = /etc/freeradius/3.0/sqlite/radius.db
```

**Getting the API token:**

1. Log in to your Laravel RADTik admin panel
2. Go to RADIUS Server Management
3. Add/Edit RADIUS server
4. Copy the generated API token

### Testing Synchronization

**Test voucher sync manually:**

```bash
sudo python3 /opt/radtik-sync/sync-vouchers.py
```

Expected output:

```
[2026-02-14 12:30:00] Starting voucher sync...
✅ Successfully synced 10/10 vouchers
```

**Test activation check:**

```bash
sudo python3 /opt/radtik-sync/check-activations.py
```

**View synchronization logs:**

```bash
# Voucher sync logs
sudo tail -f /var/log/radtik-sync/sync.log

# Activation monitoring logs
sudo tail -f /var/log/radtik-sync/activations.log

# Deleted users logs
sudo tail -f /var/log/radtik-sync/deleted.log
```

**Check cron jobs are running:**

```bash
sudo grep CRON /var/log/syslog | grep radtik-sync
```

### Complete User Flow Example

1. **Admin generates voucher in Laravel:**
   - Username: `VOUCHER001`
   - Profile: 10Mbps, 24h validity, MAC binding enabled

2. **Cron syncs to FreeRADIUS** (within 2 minutes):
   - Creates entry in `radcheck` with password
   - Creates entries in `radreply` with bandwidth limits and timeouts

3. **User connects to WiFi:**
   - Enters credentials
   - FreeRADIUS authenticates
   - Records MAC address in `radpostauth`

4. **Activation monitor detects login** (within 1 minute):
   - Calls Laravel API with username, MAC, timestamp
   - Laravel activates voucher and sets expiry
   - If profile requires MAC binding, adds check to FreeRADIUS
   - User is now locked to that device

5. **Admin deletes voucher in Laravel:**
   - Cron removes user from FreeRADIUS (within 5 minutes)
   - User can no longer authenticate

### Troubleshooting Sync Issues

**Sync not working:**

```bash
# Check Python dependencies
pip3 list | grep requests

# Test API connectivity
curl -X POST https://your-domain.com/api/radius/sync/vouchers \
  -H "X-RADIUS-SECRET: your-token" \
  -H "Content-Type: application/json"

# Check script permissions
ls -la /opt/radtik-sync/
```

**Cron jobs not running:**

```bash
# Check cron file exists
cat /etc/cron.d/radtik-sync

# Restart cron service
sudo systemctl restart cron

# Check cron logs
sudo grep CRON /var/log/syslog | tail -20
```

**API authentication errors:**

- Verify `api_secret` in `/opt/radtik-sync/config.ini` matches Laravel
- Check Laravel logs: `tail -f /path/to/laravel/storage/logs/laravel.log`
- Ensure RADIUS server is registered in Laravel with correct token

### Manual Sync Commands

```bash
# Force full voucher sync
sudo python3 /opt/radtik-sync/sync-vouchers.py

# Process pending activations
sudo python3 /opt/radtik-sync/check-activations.py

# Clean up deleted users
sudo python3 /opt/radtik-sync/sync-deleted.py
```

### Files Installed

```
/opt/radtik-sync/
├── sync-vouchers.py         # Voucher synchronization
├── check-activations.py     # Activation monitoring
├── sync-deleted.py          # Deleted users cleanup
├── config.ini              # Configuration (you create this)
└── config.ini.example      # Configuration template

/etc/cron.d/
└── radtik-sync             # Cron job definitions

/var/log/radtik-sync/
├── sync.log                # Voucher sync logs
├── activations.log         # Activation monitoring logs
└── deleted.log             # Deleted users logs
```

## Support & Documentation

- **FreeRADIUS Documentation**: https://freeradius.org/documentation/
- **FreeRADIUS Wiki**: https://wiki.freeradius.org/
- **RadTik Documentation**: See `docs/FREERADIUS_LARAVEL_INTEGRATION_PLAN.md`
