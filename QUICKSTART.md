# RadTik FreeRADIUS - Quick Setup Guide

## Overview

This guide walks you through setting up FreeRADIUS with automatic Laravel synchronization for RADTik hotspot management.

## What Gets Installed

- ✅ FreeRADIUS 3.0 with SQLite backend
- ✅ Python synchronization scripts
- ✅ Automated cron jobs for sync
- ✅ Complete schema with indexes
- ✅ MAC address binding support

## Prerequisites

- Ubuntu 22.04 LTS (or compatible)
- Root/sudo access
- RADTik Laravel application running
- Internet connection

## Installation Steps

### 1. Clone and Run Installer

```bash
# Clone the repository
git clone https://github.com/ahmadfoysal/radtik-radius.git
cd radtik-radius

# Run the installer
sudo bash install.sh
```

The installer will:

- Install FreeRADIUS, Python3, and dependencies
- Configure SQLite database with optimizations
- Install synchronization scripts to `/opt/radtik-sync/`
- Set up cron jobs for automatic syncing
- Create log directories

### 2. Configure Laravel Integration

After installation completes, you MUST configure the synchronization:

```bash
sudo nano /opt/radtik-sync/config.ini
```

**Update these settings:**

```ini
[laravel]
# Your Laravel RADTik URL (no trailing slash)
api_url = https://radtik.yourdomain.com/api/radius

# API token from Laravel RADIUS Server management
api_secret = paste-your-token-here

[radius]
# Leave this as default (unless you changed it)
db_path = /etc/freeradius/3.0/sqlite/radius.db
```

### 3. Get API Token from Laravel

**In your Laravel RADTik admin panel:**

1. Navigate to **RADIUS Servers** (or create this feature)
2. Click **Add RADIUS Server**
3. Enter server details:
   - Name: `Main FreeRADIUS Server`
   - IP Address: Your server IP
   - Click **Generate Token**
4. Copy the generated token
5. Paste it in `/opt/radtik-sync/config.ini` as `api_secret`

### 4. Test the Setup

**Test FreeRADIUS is running:**

```bash
sudo systemctl status freeradius
```

**Test synchronization manually:**

```bash
# Test voucher sync
sudo python3 /opt/radtik-sync/sync-vouchers.py

# Expected output:
# [2026-02-14 12:30:00] Starting voucher sync...
# ✅ Successfully synced X vouchers
```

**Create a test voucher in Laravel:**

1. Go to Laravel admin → Vouchers → Generate
2. Create 1 test voucher
3. Wait 2 minutes (or run sync manually)
4. Check if user exists in FreeRADIUS:

```bash
sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db \
  "SELECT * FROM radcheck LIMIT 5;"
```

**Test authentication:**

```bash
radtest YOUR_VOUCHER_USERNAME YOUR_VOUCHER_PASSWORD localhost 0 testing123
```

Expected output: `Access-Accept` ✅

### 5. Monitor Logs

**FreeRADIUS logs:**

```bash
sudo tail -f /var/log/freeradius/radius.log
```

**Synchronization logs:**

```bash
# Voucher sync
sudo tail -f /var/log/radtik-sync/sync.log

# MAC binding & activation
sudo tail -f /var/log/radtik-sync/activations.log

# Deleted users
sudo tail -f /var/log/radtik-sync/deleted.log
```

**Cron execution logs:**

```bash
sudo grep radtik-sync /var/log/syslog | tail -20
```

## Synchronization Schedule

The cron jobs run automatically:

| Task                 | Frequency       | Script                 |
| -------------------- | --------------- | ---------------------- |
| **Voucher Sync**     | Every 2 minutes | `sync-vouchers.py`     |
| **Activation Check** | Every 1 minute  | `check-activations.py` |
| **Deleted Users**    | Every 5 minutes | `sync-deleted.py`      |

To modify the schedule:

```bash
sudo nano /etc/cron.d/radtik-sync
```

## Complete User Flow

### Example: Voucher with MAC Binding

1. **Admin creates voucher in Laravel:**
   - Username: `HOTSPOT123`
   - Password: `HOTSPOT123`
   - Profile: 10Mbps, 24h validity, MAC binding enabled

2. **Sync to FreeRADIUS** (within 2 minutes):
   - User credentials added to `radcheck`
   - Bandwidth/timeout added to `radreply`

3. **Customer connects:**
   - Opens browser → Hotspot login page
   - Enters: `HOTSPOT123` / `HOTSPOT123`
   - FreeRADIUS authenticates ✅
   - MAC address captured: `AA:BB:CC:DD:EE:FF`

4. **Activation** (within 1 minute):
   - Python script detects first login
   - Calls Laravel API with MAC address
   - Laravel updates voucher:
     - `status` = `active`
     - `mac_address` = `AA:BB:CC:DD:EE:FF`
     - `activated_at` = `2026-02-14 12:30:00`
     - `expires_at` = `2026-02-15 12:30:00`
   - MAC binding added to FreeRADIUS
   - User can only connect from device `AA:BB:CC:DD:EE:FF`

5. **Subsequent logins:**
   - Different device tries to use voucher → Rejected ❌
   - Original device → Accepted ✅

6. **Expiry/Deletion:**
   - After 24 hours OR admin deletes voucher
   - Sync removes user from FreeRADIUS (within 5 minutes)
   - Authentication fails → User disconnected

## Troubleshooting

### Issue: Sync not working

**Check configuration:**

```bash
cat /opt/radtik-sync/config.ini
```

**Test API manually:**

```bash
curl -X POST https://your-domain.com/api/radius/sync/vouchers \
  -H "X-RADIUS-SECRET: your-token" \
  -H "Content-Type: application/json" \
  -d '{}'
```

**Check Python dependencies:**

```bash
pip3 list | grep requests
# If missing: sudo pip3 install requests
```

### Issue: Cron not running

**Verify cron file:**

```bash
cat /etc/cron.d/radtik-sync
```

**Restart cron:**

```bash
sudo systemctl restart cron
```

**Check cron logs:**

```bash
sudo grep CRON /var/log/syslog | grep radtik
```

### Issue: MAC binding not working

**Check radpostauth table:**

```bash
sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db \
  "SELECT * FROM radpostauth ORDER BY authdate DESC LIMIT 5;"
```

Should show `calling_station_id` with MAC address.

**Check for processed column:**

```bash
sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db \
  "PRAGMA table_info(radpostauth);"
```

Should include `processed` column.

**Manually run activation check:**

```bash
sudo python3 /opt/radtik-sync/check-activations.py
```

### Issue: Authentication fails

**Run FreeRADIUS in debug mode:**

```bash
sudo systemctl stop freeradius
sudo freeradius -X
```

Look for errors in the output.

**Check user exists:**

```bash
sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db \
  "SELECT * FROM radcheck WHERE username='YOUR_USERNAME';"
```

**Check MikroTik shared secret:**
Must match in:

- `/etc/freeradius/3.0/clients.conf` (FreeRADIUS side)
- MikroTik RADIUS configuration (client side)

## Security Checklist

Before production use:

- [ ] Change shared secret in `clients.conf`
- [ ] Restrict client IPs (replace `0.0.0.0/0` with specific IPs)
- [ ] Use HTTPS for Laravel API (not HTTP)
- [ ] Secure API tokens (don't commit to git)
- [ ] Configure firewall (block external access to ports 1812, 1813)
- [ ] Set up automated backups of SQLite database
- [ ] Monitor logs regularly
- [ ] Use strong MikroTik admin passwords

## Backup & Restore

**Backup FreeRADIUS database:**

```bash
sudo cp /etc/freeradius/3.0/sqlite/radius.db \
  /backup/radius-$(date +%Y%m%d).db
```

**Restore database:**

```bash
sudo systemctl stop freeradius
sudo cp /backup/radius-20260214.db \
  /etc/freeradius/3.0/sqlite/radius.db
sudo chown freerad:freerad /etc/freeradius/3.0/sqlite/radius.db
sudo systemctl start freeradius
```

## Maintenance

**View active sessions:**

```bash
sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db \
  "SELECT username, nasipaddress, acctstarttime FROM radacct WHERE acctstoptime IS NULL;"
```

**Clear old logs:**

```bash
# Clear logs older than 30 days
sudo find /var/log/radtik-sync/ -name "*.log" -mtime +30 -delete
```

**Update Python scripts:**

```bash
cd /path/to/radtik/radtik-radius
sudo bash install.sh  # Re-run installer (preserves config.ini)
```

## Getting Help

- **FreeRADIUS debug:** `sudo freeradius -X`
- **Documentation:** See `README.md` and `docs/FREERADIUS_LARAVEL_INTEGRATION_PLAN.md`
- **Logs:** Check `/var/log/radtik-sync/` and `/var/log/freeradius/`
- **Test scripts:** Run Python scripts manually to see detailed errors

## Summary

You now have a complete FreeRADIUS setup that:

- ✅ Automatically syncs vouchers from Laravel
- ✅ Supports MAC address binding
- ✅ Tracks first login and activation
- ✅ Removes deleted users
- ✅ Enforces bandwidth limits and timeouts
- ✅ Runs entirely automated via cron jobs

The system is production-ready after you configure `config.ini` with your Laravel API details!
