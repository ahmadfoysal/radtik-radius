# RadTik FreeRADIUS - Quick Setup Guide

## 🚀 One-Line Installation (New!)

Run this command on your Ubuntu 22.04 LTS server for fully automated installation:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadfoysal/radtik-radius/main/bootstrap-install.sh | sudo bash
```

This will automatically:
1. Clone the repository
2. Install FreeRADIUS 3.0 + SQLite
3. Install Flask API Server
4. Configure and start all services
5. **Takes 5-10 minutes** ⏱️

After installation, add the server in your Laravel admin panel and click "Configure" to set secrets remotely via SSH.

---

## Overview

This guide walks you through setting up FreeRADIUS with Laravel integration for RADTik hotspot management. The installer offers two integration methods: **API Server** (recommended, push-based) or **Legacy Sync** (cron-based polling).

## What Gets Installed

**Core (Always Installed):**

- ✅ FreeRADIUS 3.0 with SQLite backend
- ✅ Complete schema with indexes and optimizations
- ✅ MAC address binding support
- ✅ Production-ready configuration

**Optional Laravel Integration:**

- 🆕 **API Server** (Recommended) - Flask-based real-time push sync via Laravel queue jobs
- 📦 **Legacy Sync** - Python cron scripts for polling-based sync

## Prerequisites

- Ubuntu 22.04 LTS (or compatible)
- Root/sudo access
- RADTik Laravel application (v4.0+) running
- Internet connection
- Port 5000 open on firewall (if using API Server)

## Installation Steps

### 1. Clone and Run Installer

```bash
# Clone the repository
git clone https://github.com/ahmadfoysal/radtik-radius.git
cd radtik-radius

# Run the interactive installer
sudo bash install.sh
```

### 2. Choose Installation Options

The installer will display a welcome screen and ask:

**Option 1: Install API Server?** (Recommended for Laravel v4.0+)

```
Install API Server for Laravel integration? (Y/n): Y
```

- **Yes** → Installs Flask API server on port 5000 for real-time push sync
- **No** → Proceeds to ask about legacy sync

**Option 2: Install legacy cron-based sync?** (Only if you said No to API Server)

```
Install legacy cron-based sync scripts? (Y/n): Y
```

- **Yes** → Installs Python cron scripts that poll Laravel every 2-5 minutes
- **No** → Installs only FreeRADIUS without Laravel integration

### 3. What the Installer Does

The installer will automatically:

- ✅ Install FreeRADIUS, Python3, and dependencies
- ✅ Configure SQLite database with optimizations
- ✅ Set up SQL module and permissions
- ✅ Install chosen integration method (API Server or Legacy Sync)
- ✅ Generate secure authentication token (for API Server)
- ✅ Configure firewall (opens port 5000 if needed)
- ✅ Test and verify the installation

### 4. Installation Complete - Save the Token!

**If you installed the API Server**, the installer will display:

```
API Authentication Token:
a1b2c3d4e5f6789012345678901234567890123456789012345678901234

IMPORTANT: Add this token to Laravel RadiusServer configuration
```

**⚠️ SAVE THIS TOKEN** - You'll need it for Laravel configuration!

### 4. Installation Complete - Save the Token!

**If you installed the API Server**, the installer will display:

```
API Authentication Token:
a1b2c3d4e5f6789012345678901234567890123456789012345678901234

IMPORTANT: Add this token to Laravel RadiusServer configuration
```

**⚠️ SAVE THIS TOKEN** - You'll need it for Laravel configuration!

---

## Configuration by Integration Method

Choose the section that matches what you installed:

### Option A: API Server Configuration (Recommended)

**Step 1: Configure Laravel RadiusServer**

In your Laravel RADTik admin panel:

1. Navigate to **Admin → RADIUS Servers**
2. Click **Add RADIUS Server** (or edit existing)
3. Fill in the details:
    - **Name**: `Main FreeRADIUS Server`
    - **Host**: `192.168.1.100` (your RADIUS server IP)
    - **Auth Token**: Paste the token from installation
    - **Installation Status**: `running`
    - **Is Active**: ✓ Check this
4. Click **Save**

**Step 2: Link Router to RADIUS Server**

1. Go to **Routers** → Select your router
2. Set **RADIUS Server**: Select the server you just created
3. Click **Save**

**Step 3: Start Laravel Queue Worker**

The API server uses Laravel queue jobs, so you need a queue worker running:

```bash
cd /path/to/laravel
php artisan queue:work
```

For production, set up a supervisor or systemd service for the queue worker.

**Step 4: Test API Server**

Check if the API server is running:

```bash
# Get the token from config
TOKEN=$(grep "auth_token" /opt/radtik-radius/scripts/config.ini | cut -d'=' -f2 | xargs)

# Test health endpoint
curl -H "Authorization: Bearer $TOKEN" http://localhost:5000/health
```

Expected response:

```json
{ "status": "healthy", "database": "connected", "radcheck_records": 0 }
```

**Step 5: Generate Test Vouchers**

1. In Laravel admin → **Vouchers** → **Generate**
2. Select the router (with RADIUS server linked)
3. Generate 5 vouchers
4. Watch the queue worker output - should process the job
5. Check API logs:
    ```bash
    sudo journalctl -u radtik-radius-api -f
    ```

Done! Vouchers sync instantly via queue jobs. 🎉

---

### Option B: Legacy Sync Configuration

**Step 1: Configure Laravel API Connection**

Edit the sync configuration file:

```bash
sudo nano /opt/radtik-sync/config.ini
```

**Update these settings:**

```ini
[laravel]
# Your Laravel RADTik URL (no trailing slash)
api_url = https://radtik.yourdomain.com/api/radius

# API token from Laravel RADIUS Server management
api_secret = paste-your-radius-server-token-here

[radius]
# Leave this as default (unless you changed it)
db_path = /etc/freeradius/3.0/sqlite/radius.db
```

**Step 2: Get Laravel API Token**

In your Laravel RADTik admin panel:

1. Navigate to **RADIUS Servers**
2. Add/Edit RADIUS server
3. Copy the generated API token
4. Paste it in `config.ini` as `api_secret`

**Step 3: Test Legacy Sync**

Run the sync scripts manually:

```bash
# Test activation monitoring
sudo python3 /opt/radtik-sync/check-activations.py

# Test deleted users sync
sudo python3 /opt/radtik-sync/sync-deleted.py
```

The voucher sync is done by Laravel pushing to API Server (if you have API Server),or you need to implement a pull endpoint in Laravel for legacy vouchers.

Done! Cron jobs will run automatically. 🎉

---

## Common Testing Steps (Both Methods)

### Test FreeRADIUS Authentication

```bash
sudo systemctl status freeradius
```

## Common Testing Steps (Both Methods)

### Test FreeRADIUS Authentication

**Check FreeRADIUS is running:**

```bash
sudo systemctl status freeradius
```

**Add a test user to database:**

```bash
sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db
```

Inside SQLite prompt:

```sql
INSERT INTO radcheck (username, attribute, op, value)
VALUES ('testuser', 'Cleartext-Password', ':=', 'testpass');
.quit
```

**Test authentication:**

```bash
radtest testuser testpass localhost 0 testing123
```

Expected output: `Access-Accept` ✅

### Verify Vouchers in Database

After generating vouchers in Laravel, check if they're in RADIUS:

```bash
sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db \
  "SELECT username, attribute, value FROM radcheck LIMIT 10;"
```

Should show:

- Username entries with `Cleartext-Password` attribute
- Username entries with `NAS-Identifier` attribute (for router binding)

### Check Synchronization Worked

**For API Server:**

```bash
# Check API service logs
sudo journalctl -u radtik-radius-api -n 50

# Should show:
# Received sync request for X vouchers
# Sync completed: X synced, 0 failed
```

**For Legacy Sync:**

```bash
# Check cron execution
sudo grep radtik-sync /var/log/syslog | tail -20
```

---

## Monitor Logs

### FreeRADIUS Logs

## Monitor Logs

### FreeRADIUS Logs

```bash
sudo tail -f /var/log/freeradius/radius.log
```

### API Server Logs (If Using API Method)

```bash
# Real-time logs
sudo journalctl -u radtik-radius-api -f

# Last 100 lines
sudo journalctl -u radtik-radius-api -n 100

# With timestamps
sudo journalctl -u radtik-radius-api -f --since "10 minutes ago"
```

### Legacy Sync Logs (If Using Legacy Method)

```bash
# MAC binding & activation
sudo tail -f /var/log/radtik-sync/activations.log

# Deleted users
sudo tail -f /var/log/radtik-sync/deleted.log
```

### Cron Execution Logs (Legacy Method)

```bash
sudo grep radtik-sync /var/log/syslog | tail -20
```

---

## Synchronization Methods Comparison

### API Server Method (Push-Based) ✅ Recommended

**How it works:**

```
Laravel → Queue Job → POST /sync/vouchers → Flask API → SQLite
```

**Timing:**

- **Instant** - Vouchers sync immediately when generated
- No polling delay
- Uses Laravel queue worker

**Benefits:**

- ⚡ Real-time synchronization
- 📊 Observable (track sync status per voucher)
- 🔄 Automatic retry on failure
- 📈 Scalable (handles 1000+ vouchers)

**Requirements:**

- Port 5000 open on firewall
- Laravel queue worker running
- systemd service: `radtik-radius-api`

### Legacy Cron Method (Pull-Based)

**How it works:**

```
Cron → Python Script → Poll Laravel API → Update SQLite
```

**Schedule:**

| Task                 | Frequency       | Script                 |
| -------------------- | --------------- | ---------------------- |
| **Activation Check** | Every 1 minute  | `check-activations.py` |
| **Deleted Users**    | Every 5 minutes | `sync-deleted.py`      |

**Note:** Voucher sync not included in legacy method - use API Server for vouchers.

**Benefits:**

- 🔧 No additional ports required
- 📦 Simple setup
- 🔙 Fallback option

**Limitations:**

- ⏱️ 1-5 minute sync delay
- 🔄 No automatic retry
- 📊 Limited observability

To modify the cron schedule:

```bash
sudo nano /etc/cron.d/radtik-sync
```

---

## Complete User Flow

### Example: Voucher with MAC Binding (API Server Method)

1. **Admin creates voucher in Laravel:**
    - Username: `HOTSPOT123`
    - Password: `HOTSPOT123`
    - Profile: 10Mbps, 24h validity, MAC binding enabled

2. **Instant sync to FreeRADIUS:**
    - Laravel dispatches queue job: `SyncVouchersToRadiusJob`
    - Job sends POST request to Flask API server
    - API inserts 3 rows into SQLite:
        - `radcheck`: Password entry
        - `radcheck`: NAS-Identifier binding
        - `radreply`: Rate limit (10Mbps)
    - **Total time: < 5 seconds** ⚡

3. **Customer connects:**
    - Opens browser → Hotspot login page
    - Enters: `HOTSPOT123` / `HOTSPOT123`
    - MikroTik sends RADIUS request
    - FreeRADIUS authenticates ✅
    - MAC address captured: `AA:BB:CC:DD:EE:FF`
    - Login recorded in `radpostauth` table

4. **Activation (Legacy Cron or Custom Implementation):**
    - Monitoring script detects first login in `radpostauth`
    - Calls Laravel API with MAC address
    - Laravel updates voucher:
        - `status` = `active`
        - `mac_address` = `AA:BB:CC:DD:EE:FF`
        - `activated_at` = `2026-02-17 12:30:00`
        - `expires_at` = `2026-02-18 12:30:00`
    - MAC binding added to FreeRADIUS (if configured)
    - User can only connect from device `AA:BB:CC:DD:EE:FF`

5. **Subsequent logins:**
    - Different device tries to use voucher → Rejected ❌
    - Original device → Accepted ✅

6. **Expiry/Deletion:**
    - After 24 hours OR admin deletes voucher in Laravel
    - Queue job sends DELETE request to API server
    - User removed from FreeRADIUS immediately
    - Authentication fails → User disconnected

---

## Troubleshooting

### API Server Issues

#### Issue: API server not responding

**Check service status:**

```bash
sudo systemctl status radtik-radius-api
```

**Start/restart service:**

```bash
sudo systemctl restart radtik-radius-api
```

**View detailed logs:**

```bash
sudo journalctl -u radtik-radius-api -n 100 --no-pager
```

**Test health endpoint:**

```bash
TOKEN=$(grep "auth_token" /opt/radtik-radius/scripts/config.ini | cut -d'=' -f2 | xargs)
curl -H "Authorization: Bearer $TOKEN" http://localhost:5000/health
```

#### Issue: Laravel can't connect to API server

**Test from Laravel server:**

```bash
curl -H "Authorization: Bearer YOUR-TOKEN" http://RADIUS-IP:5000/health
```

**Check firewall:**

```bash
sudo ufw status | grep 5000
# If blocked:
sudo ufw allow 5000/tcp
```

**Verify token matches:**

- Check `/opt/radtik-radius/scripts/config.ini` → `auth_token`
- Compare with Laravel RadiusServer → `auth_token` field

#### Issue: Queue job fails

**Check Laravel logs:**

```bash
tail -f /path/to/laravel/storage/logs/laravel.log
```

**Verify queue worker is running:**

```bash
ps aux | grep "queue:work"
```

**Start queue worker:**

```bash
cd /path/to/laravel
php artisan queue:work
```

### Legacy Sync Issues

#### Issue: Sync not working

**Check configuration:**

```bash
cat /opt/radtik-sync/config.ini
```

**Test Laravel API manually:**

```bash
curl -X POST https://your-domain.com/api/radius/check-activations \
  -H "X-RADIUS-SECRET: your-token" \
  -H "Content-Type: application/json"
```

**Check Python dependencies:**

```bash
pip3 list | grep requests
# If missing:
sudo pip3 install requests
```

#### Issue: Cron not running

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
sudo grep CRON /var/log/syslog | grep radtik | tail -20
```

**Run scripts manually to see errors:**

```bash
sudo python3 /opt/radtik-sync/check-activations.py
sudo python3 /opt/radtik-sync/sync-deleted.py
```

### General FreeRADIUS Issues

### General FreeRADIUS Issues

#### Issue: MAC binding not working

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

#### Issue: Authentication fails

**Run FreeRADIUS in debug mode:**

```bash
sudo systemctl stop freeradius
sudo freeradius -X
```

Look for errors in the output. Press `Ctrl+C` to stop.

**Check user exists:**

```bash
sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db \
  "SELECT * FROM radcheck WHERE username='YOUR_USERNAME';"
```

**Check MikroTik shared secret:**

Must match in:

- `/etc/freeradius/3.0/clients.conf` (FreeRADIUS side)
- MikroTik RADIUS configuration (client side)

**Restart FreeRADIUS:**

```bash
sudo systemctl restart freeradius
```

#### Issue: Database locked

**Check WAL mode:**

```bash
sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db "PRAGMA journal_mode;"
# Should return: wal
```

**Fix permissions:**

```bash
sudo chown -R freerad:freerad /etc/freeradius/3.0/sqlite
sudo chmod 775 /etc/freeradius/3.0/sqlite
sudo chmod 664 /etc/freeradius/3.0/sqlite/radius.db*
```

---

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

### View Active Sessions

```bash
sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db \
  "SELECT username, nasipaddress, acctstarttime FROM radacct WHERE acctstoptime IS NULL;"
```

### Database Statistics

**Using API Server:**

```bash
TOKEN=$(grep "auth_token" /opt/radtik-radius/scripts/config.ini | cut -d'=' -f2 | xargs)
curl -H "Authorization: Bearer $TOKEN" http://localhost:5000/stats
```

**Using SQLite:**

```bash
sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db << EOF
SELECT 'Total users:' as stat, COUNT(DISTINCT username) as count FROM radcheck WHERE attribute='Cleartext-Password';
SELECT 'radcheck rows:' as stat, COUNT(*) as count FROM radcheck;
SELECT 'radreply rows:' as stat, COUNT(*) as count FROM radreply;
SELECT 'Active sessions:' as stat, COUNT(*) as count FROM radacct WHERE acctstoptime IS NULL;
EOF
```

### Clear Old Logs

**FreeRADIUS logs:**

```bash
sudo find /var/log/freeradius/ -name "*.log" -mtime +30 -delete
```

**API Server logs (if using systemd):**

```bash
sudo journalctl --vacuum-time=30d
```

**Legacy sync logs:**

```bash
sudo find /var/log/radtik-sync/ -name "*.log" -mtime +30 -delete
```

### Update Installation

To update Python scripts or configuration:

```bash
cd /path/to/radtik-radius
git pull
sudo bash install.sh  # Re-run installer (preserves config)
```

The installer will detect existing configuration and ask before overwriting.

---

## Getting Help

### Diagnostic Commands

**FreeRADIUS:**

- Debug mode: `sudo freeradius -X`
- Service status: `sudo systemctl status freeradius`
- Logs: `sudo tail -f /var/log/freeradius/radius.log`

**API Server:**

- Service status: `sudo systemctl status radtik-radius-api`
- Real-time logs: `sudo journalctl -u radtik-radius-api -f`
- Test endpoint: `curl -H "Authorization: Bearer TOKEN" http://localhost:5000/health`

**Legacy Sync:**

- Activation logs: `sudo tail -f /var/log/radtik-sync/activations.log`
- Deleted users: `sudo tail -f /var/log/radtik-sync/deleted.log`
- Cron status: `sudo grep radtik-sync /var/log/syslog | tail -20`

**Database:**

- Direct access: `sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db`
- Check users: `.tables` then `SELECT * FROM radcheck LIMIT 10;`

### Documentation

- **API Server Setup:** `API_QUICKSTART.md`
- **Full Installation Guide:** `README.md`
- **Scripts Reference:** `scripts/README.md`
- **RADIUS Sync Plan:** `docs/RADIUS_SYNC_IMPLEMENTATION_PLAN.md` (Laravel side)

### Common Commands Reference

```bash
# FreeRADIUS
sudo systemctl restart freeradius
sudo systemctl status freeradius
sudo freeradius -X

# API Server
sudo systemctl restart radtik-radius-api
sudo journalctl -u radtik-radius-api -f

# Database
sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db

# Test auth
radtest username password localhost 0 testing123

# Check logs
sudo tail -f /var/log/freeradius/radius.log
```

---

## Summary

You now have a complete FreeRADIUS setup with Laravel integration!

### What You Have:

**Core:**

- ✅ FreeRADIUS 3.0 with SQLite backend
- ✅ Optimized database (WAL mode, indexes)
- ✅ MAC address tracking and binding support
- ✅ Production-ready configuration

**Laravel Integration (depending on what you chose):**

**If you installed API Server:**

- ✅ Real-time voucher synchronization via Flask API
- ✅ Queue-based job processing
- ✅ Instant sync when vouchers are generated
- ✅ Observable sync status per voucher
- ✅ Automatic retry on failure
- 🔧 Service: `systemctl status radtik-radius-api`

**If you installed Legacy Sync:**

- ✅ Cron-based activation monitoring
- ✅ Automated deleted user cleanup
- 🔧 Cron jobs: `/etc/cron.d/radtik-sync`

### Next Steps:

1. **Configure Laravel:**
    - Add RADIUS server with auth token
    - Link router to RADIUS server
    - Start queue worker (for API method)

2. **Test thoroughly:**
    - Generate test vouchers
    - Verify sync to FreeRADIUS
    - Test authentication
    - Monitor logs

3. **Production readiness:**
    - Change shared secret in `clients.conf`
    - Restrict client IPs (replace `0.0.0.0/0`)
    - Use HTTPS for Laravel
    - Set up automated backups
    - Configure queue worker as service (for API method)

4. **Documentation:**
    - API Server: See `API_QUICKSTART.md`
    - Full guide: See `README.md`
    - Scripts reference: See `scripts/README.md`

### Quick Reference:

**FreeRADIUS:**

```bash
sudo systemctl status freeradius
sudo freeradius -X  # Debug mode
```

**API Server (if installed):**

```bash
sudo systemctl status radtik-radius-api
sudo journalctl -u radtik-radius-api -f
```

**Database:**

```bash
sudo sqlite3 /etc/freeradius/3.0/sqlite/radius.db
```

**Test Authentication:**

```bash
radtest username password localhost 0 testing123
```

The system is production-ready! 🎉
