# RADIUS Activation Sync System

## Overview

This system automatically syncs voucher activation data from FreeRADIUS to Laravel every 5 minutes using a cron job.

## Architecture

### Components

1. **Python Script**: `scripts/activation-sync.py` (runs via cron)
2. **Laravel API**: `/api/radius/activations` (POST endpoint)
3. **Queue Job**: `App\Jobs\ProcessVoucherActivations`
4. **Cron Job**: Configured in `/etc/cron.d/radtik-sync` via install.sh

### Flow

```
FreeRADIUS (radpostauth table)
    ↓ (cron every 5 mins)
Python Script (reads config.ini, queries SQLite)
    ↓ (HTTP POST with Bearer token)
Laravel API (validates token against radius_servers table)
    ↓ (dispatches)
Queue Job (updates vouchers conditionally)
    ↓
Vouchers updated with activation time & MAC address
```

## Authentication

Each RADIUS server has a unique `auth_token`:

- **Stored in Laravel**: `radius_servers.auth_token` column
- **Configured on server**: `/opt/radtik-radius/config.ini` [api] section
- **Used by Python script**: Reads from config.ini, sends as Bearer token
- **Validated by Laravel**: Checks against `radius_servers` table

## Data Sync

### Query (Python)

```sql
SELECT 
    username,
    COALESCE(nasidentifier, nasipaddress) as nas,
    callingstationid as mac,
    MIN(authdate) as first_auth
FROM radpostauth
WHERE reply = 'Access-Accept'
    AND authdate > datetime('now', '-24 hours')
GROUP BY username, COALESCE(nasidentifier, nasipaddress), callingstationid
ORDER BY first_auth DESC
```

**Key Points**:
- Only sends **unique** activations (GROUP BY username, NAS, MAC)
- Gets **first authentication time** for each unique combination
- Looks back **24 hours** to catch any missed activations
- Only successful authentications (Access-Accept)

### Update (Laravel)

The `ProcessVoucherActivations` job updates vouchers with these rules:

1. **Activation Time**: Only updates if `activated_at` is NULL
2. **MAC Address**: Only updates if `mac_address` is NULL
3. **No Overrides**: Never overwrites existing values
4. **Expiry Calculation**: Sets expiry based on profile validity when first activated

## Installation

The cron job is automatically configured by `install.sh`:

```bash
*/5 * * * * root /usr/bin/python3 /opt/radtik-radius/scripts/activation-sync.py >> /var/log/radtik-activation-sync.log 2>&1
```

**Schedule**: Every 5 minutes  
**Log**: `/var/log/radtik-activation-sync.log`

## Multi-Server Support

Each RADIUS server:
- Has its own unique `auth_token` in Laravel database
- Gets configured with that token via SSH when created/updated
- Uses that token to authenticate API requests
- Laravel validates the token and identifies which server sent the data

## Monitoring

### Check Cron Job
```bash
crontab -l | grep activation-sync
```

### View Logs
```bash
tail -f /var/log/radtik-activation-sync.log
```

### Test Manually
```bash
/usr/bin/python3 /opt/radtik-radius/scripts/activation-sync.py
```

### Laravel Queue Logs
```bash
tail -f storage/logs/laravel.log | grep "Processing activation"
```

## Troubleshooting

### 401 Unauthorized
- Check token in `/opt/radtik-radius/config.ini` [api] section
- Verify token matches in Laravel `radius_servers` table
- Ensure RADIUS server is marked as `is_active = 1`

### No Activations Syncing
- Check cron is running: `systemctl status cron`
- Verify Python script executes: `python3 scripts/activation-sync.py`
- Check radpostauth table has data
- Review log file for errors

### Duplicate Activations
- Shouldn't happen due to conditional updates
- Check `activated_at` and `mac_address` are properly set
- Review ProcessVoucherActivations job logic

## Configuration Files

### Python Script
- **Path**: `/opt/radtik-radius/scripts/activation-sync.py`
- **Config**: Reads from `/opt/radtik-radius/config.ini`
- **Database**: `/etc/freeradius/3.0/sqlite/radius.db`

### Laravel
- **API Route**: `routes/web.php` → `/api/radius/activations`
- **Controller**: `app/Http/Controllers/Api/RadiusActivationController.php`
- **Job**: `app/Jobs/ProcessVoucherActivations.php`
- **Model**: `app/Models/RadiusServer.php`

## Security

- Uses Bearer token authentication
- Token validation against database (not .env)
- Only processes active RADIUS servers
- Logs all authentication attempts
- SQL injection protection via parameterized queries
