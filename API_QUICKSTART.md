# RadTik RADIUS API Server - Quick Start Guide

## Prerequisites

- FreeRADIUS 3.0+ installed and configured with SQLite
- Python 3.6+
- pip3 installed
- Laravel RADTik v4 application ready

## Installation Steps

### 1. Install Python Dependencies

```bash
cd /opt/radtik-radius
pip3 install -r requirements.txt
```

Expected packages:

- Flask 3.0+
- Gunicorn 21.2+
- Requests 2.31+

### 2. Configure API Server

```bash
cd scripts
cp config.ini.example config.ini
nano config.ini
```

**Critical settings**:

```ini
[api]
host = 0.0.0.0
port = 5000
auth_token = YOUR-SECURE-TOKEN-HERE  # ⚠️ MUST CHANGE!
debug = false

[radius]
db_path = /var/lib/freeradius/radius.db
```

### 3. Generate Secure Token

```bash
# Generate 64-character token
openssl rand -hex 32
```

Copy this token to:

1. `config.ini` → `[api]` → `auth_token`
2. Laravel admin panel → RADIUS Server → auth_token field

### 4. Test API Server

```bash
cd /opt/radtik-radius/scripts
python3 sync-vouchers.py
```

You should see:

```
============================================================
RadTik RADIUS API Server Starting
============================================================
Database: /var/lib/freeradius/radius.db
Listening on: 0.0.0.0:5000
```

In another terminal, test:

```bash
curl -H "Authorization: Bearer YOUR-TOKEN" http://localhost:5000/health
```

Expected response:

```json
{ "status": "healthy", "database": "connected", "radcheck_records": 0 }
```

Press `Ctrl+C` to stop the test server.

### 5. Install as Systemd Service

```bash
# Copy service file
sudo cp /opt/radtik-radius/radtik-radius-api.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable and start service
sudo systemctl enable radtik-radius-api
sudo systemctl start radtik-radius-api

# Check status
sudo systemctl status radtik-radius-api
```

### 6. Configure Firewall

```bash
# Allow port 5000
sudo ufw allow 5000/tcp
sudo ufw reload
```

### 7. Configure Laravel

In Laravel admin panel or database:

```php
// Create/Update RADIUS Server
RadiusServer::updateOrCreate(
    ['id' => 1],
    [
        'name' => 'Main RADIUS Server',
        'host' => '192.168.1.100',  // Your RADIUS server IP
        'auth_token' => 'YOUR-SECURE-TOKEN',  // Same as config.ini
        'installation_status' => 'running',
        'is_active' => true,
    ]
);
```

### 8. Link Router to RADIUS Server

```php
Router::where('id', 1)->update([
    'radius_server_id' => 1,
]);
```

## Testing End-to-End

### 1. Start Queue Worker (Laravel)

```bash
cd /path/to/laravel
php artisan queue:work
```

### 2. Generate Vouchers

Via Laravel admin panel:

- Go to Vouchers → Generate
- Select router (with RADIUS server linked)
- Generate 10 vouchers
- Click "Generate"

### 3. Watch Logs

**RADIUS Server**:

```bash
sudo journalctl -u radtik-radius-api -f
```

You should see:

```
Received sync request for 10 vouchers from 192.168.x.x
Sync completed: 10 synced, 0 failed
```

**Laravel Queue Worker**:

```
[YYYY-MM-DD HH:MM:SS][job_id] Processing: App\Jobs\SyncVouchersToRadiusJob
[YYYY-MM-DD HH:MM:SS][job_id] Processed: App\Jobs\SyncVouchersToRadiusJob
```

### 4. Verify Database

```bash
sqlite3 /var/lib/freeradius/radius.db

# Check vouchers were inserted
SELECT COUNT(*) FROM radcheck;  -- Should show 20 (2 per voucher)
SELECT COUNT(*) FROM radreply;  -- Should show 10 (1 per voucher)

# View sample voucher
SELECT * FROM radcheck WHERE username LIKE '%' LIMIT 4;
SELECT * FROM radreply WHERE username LIKE '%' LIMIT 2;
```

## Verification Checklist

- [ ] API server responds to health check
- [ ] Bearer token authentication works
- [ ] Firewall allows port 5000
- [ ] Laravel can connect to RADIUS API
- [ ] Queue worker processes jobs
- [ ] Vouchers sync to RADIUS database
- [ ] radcheck has 2 rows per voucher (password + NAS)
- [ ] radreply has 1 row per voucher (rate limit)

## Common Issues

### Issue: "Connection refused"

**Solution**: Check firewall and verify API server is running

```bash
sudo systemctl status radtik-radius-api
sudo ufw status | grep 5000
```

### Issue: "Invalid authentication token"

**Solution**: Verify tokens match

```bash
grep auth_token /opt/radtik-radius/scripts/config.ini
# Compare with Laravel RadiusServer.auth_token (decrypted value)
```

### Issue: "Database not found"

**Solution**: Check FreeRADIUS SQLite path

```bash
ls -l /var/lib/freeradius/radius.db
# Update config.ini if path is different
```

### Issue: Queue job fails

**Solution**: Check Laravel logs

```bash
tail -f storage/logs/laravel.log
```

## Next Steps

1. **Monitor Performance**: Check `/stats` endpoint
2. **Set Up Alerts**: Monitor API health with cron
3. **Enable HTTPS**: Use nginx reverse proxy
4. **Rotate Tokens**: Update auth_token periodically
5. **Backup Database**: Regular SQLite backups

## Support

For issues:

1. Check logs: `journalctl -u radtik-radius-api -f`
2. Test endpoints with curl
3. Verify configuration in both Laravel and config.ini
4. Consult `/opt/radtik-radius/scripts/README.md`

## Architecture Summary

```
┌─────────────┐
│   Laravel   │
│  (RADTik)   │
└──────┬──────┘
       │ Queue Job (SyncVouchersToRadiusJob)
       │
       ▼ POST /sync/vouchers (Bearer Token)
┌─────────────┐
│   Flask API │
│   (Python)  │
└──────┬──────┘
       │ SQLite Insert
       │
       ▼
┌─────────────┐
│ FreeRADIUS  │
│   Database  │
│  (SQLite)   │
└─────────────┘
```

**Flow**:

1. User generates vouchers in Laravel UI
2. Vouchers saved to RADTik database
3. Job dispatched to queue
4. Queue worker sends batch to RADIUS API
5. RADIUS API inserts to SQLite
6. FreeRADIUS authenticates users from SQLite

**Success!** 🎉
