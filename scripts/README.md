# RadTik FreeRADIUS Python Scripts

This folder contains Python synchronization scripts for integrating FreeRADIUS with Laravel RadTik application.

## Overview

The RADIUS server now uses a **push-based architecture** where Laravel sends vouchers directly to the RADIUS server via API instead of the RADIUS server polling Laravel.

## Architecture

```
Laravel (RADTik v4)
    ↓ (Queue Job)
    POST /sync/vouchers
    ↓ (Bearer Token Auth)
RADIUS API Server (Flask)
    ↓ (SQLite Insert)
FreeRADIUS Database
```

## Scripts

### Primary Script

- **sync-vouchers.py**: Flask API server that receives voucher sync requests from Laravel and inserts them into FreeRADIUS database (radcheck/radreply tables)

### Legacy Scripts (Optional)

- **check-activations.py**: Monitors radpostauth for new activations and updates Laravel with MAC addresses
- **sync-deleted.py**: Removes deleted vouchers from FreeRADIUS database

## Configuration

### 1. Copy Configuration File

```bash
cd /opt/radtik-radius/scripts
cp config.ini.example config.ini
```

### 2. Edit Configuration

Edit `config.ini` with your settings:

```ini
[api]
# API Server Configuration
host = 0.0.0.0          # Listen on all interfaces
port = 5000              # API port
auth_token = YOUR-SECURE-RANDOM-TOKEN-HERE  # IMPORTANT: Change this!
debug = false            # Set to true only for development

[radius]
db_path = /var/lib/freeradius/radius.db  # Path to RADIUS SQLite database

[laravel]
# Only needed for legacy sync scripts
api_url = https://your-radtik-domain.com/api/radius
api_secret = your-radius-server-token-from-laravel
```

### 3. Generate Secure Token

Generate a secure authentication token:

```bash
# Option 1: OpenSSL
openssl rand -hex 32

# Option 2: Python
python3 -c "import secrets; print(secrets.token_hex(32))"
```

Copy this token to:

1. `config.ini` → `[api]` → `auth_token`
2. Laravel RadiusServer model → `auth_token` field (will be auto-encrypted)

## Installation

### 1. Install Python Dependencies

```bash
cd /opt/radtik-radius
pip3 install -r requirements.txt
```

This installs:

- **Flask**: Web framework for API server
- **Gunicorn**: Production WSGI server
- **Requests**: HTTP library (for legacy scripts)

### 2. Set Permissions

```bash
# Make script executable
chmod +x scripts/sync-vouchers.py

# Set proper ownership (if running as freerad user)
chown -R freerad:freerad /opt/radtik-radius/scripts
```

### 3. Configure Firewall

Allow port 5000 for Laravel to connect:

```bash
# UFW (Ubuntu/Debian)
ufw allow 5000/tcp

# Firewalld (CentOS/RHEL)
firewall-cmd --permanent --add-port=5000/tcp
firewall-cmd --reload
```

## Running the API Server

### Development Mode (Testing)

```bash
cd /opt/radtik-radius/scripts
python3 sync-vouchers.py
```

Output:

```
============================================================
RadTik RADIUS API Server Starting
============================================================
Database: /var/lib/freeradius/radius.db
Listening on: 0.0.0.0:5000
Debug mode: False
Endpoints:
  - GET  /health          (Health check)
  - POST /sync/vouchers   (Sync vouchers)
  - DELETE /delete/voucher (Delete voucher)
  - GET  /stats           (Database stats)
============================================================
 * Running on http://0.0.0.0:5000
```

### Production Mode (Systemd Service)

#### Install Service

```bash
# Copy service file
sudo cp /opt/radtik-radius/radtik-radius-api.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable service (start on boot)
sudo systemctl enable radtik-radius-api

# Start service
sudo systemctl start radtik-radius-api
```

#### Manage Service

```bash
# Check status
sudo systemctl status radtik-radius-api

# View logs
sudo journalctl -u radtik-radius-api -f

# Restart service
sudo systemctl restart radtik-radius-api

# Stop service
sudo systemctl stop radtik-radius-api
```

## API Endpoints

### 1. Health Check

**Endpoint**: `GET /health`

**Authentication**: Bearer token required

**Example**:

```bash
curl -H "Authorization: Bearer YOUR-TOKEN" http://localhost:5000/health
```

**Response**:

```json
{
    "status": "healthy",
    "timestamp": "2026-02-17T10:30:00",
    "database": "connected",
    "radcheck_records": 1250
}
```

### 2. Sync Vouchers (Main Endpoint)

**Endpoint**: `POST /sync/vouchers`

**Authentication**: Bearer token required

**Request Body**:

```json
{
    "vouchers": [
        {
            "username": "ABC12345",
            "password": "pass123",
            "mikrotik_rate_limit": "512k/512k",
            "nas_identifier": "mikrotik-router-1"
        }
    ]
}
```

**Response**:

```json
{
    "success": true,
    "synced": 250,
    "failed": 0,
    "errors": []
}
```

**Database Operations**:
Each voucher creates **3 database rows**:

- `radcheck` table: 2 rows (password + NAS identifier)
- `radreply` table: 1 row (rate limit)

### 3. Delete Voucher

**Endpoint**: `DELETE /delete/voucher`

**Authentication**: Bearer token required

**Request Body**:

```json
{
    "username": "ABC12345"
}
```

**Response**:

```json
{
    "success": true,
    "message": "Voucher deleted successfully",
    "deleted": {
        "radcheck": 2,
        "radreply": 1
    }
}
```

### 4. Database Statistics

**Endpoint**: `GET /stats`

**Authentication**: Bearer token required

**Response**:

```json
{
    "total_users": 1250,
    "radcheck_records": 2500,
    "radreply_records": 1250,
    "nas_identifiers": ["mikrotik-router-1", "mikrotik-router-2"],
    "timestamp": "2026-02-17T10:30:00"
}
```

## Testing

### Test Authentication

```bash
# Should return 401 Unauthorized
curl http://localhost:5000/health

# Should return 200 OK
curl -H "Authorization: Bearer YOUR-TOKEN" http://localhost:5000/health
```

### Test Voucher Sync

```bash
curl -X POST http://localhost:5000/sync/vouchers \
  -H "Authorization: Bearer YOUR-TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "vouchers": [
      {
        "username": "TEST001",
        "password": "testpass",
        "mikrotik_rate_limit": "1M/1M",
        "nas_identifier": "test-router"
      }
    ]
  }'
```

### Verify Database

```bash
sqlite3 /var/lib/freeradius/radius.db "SELECT * FROM radcheck WHERE username='TEST001';"
sqlite3 /var/lib/freeradius/radius.db "SELECT * FROM radreply WHERE username='TEST001';"
```

## Logs

### Application Logs

```bash
# Systemd journal (recommended)
sudo journalctl -u radtik-radius-api -f

# Log file (if configured)
tail -f /var/log/radtik-radius-api.log
```

### Gunicorn Logs (Production)

```bash
# Access log
tail -f /var/log/radtik-radius-access.log

# Error log
tail -f /var/log/radtik-radius-error.log
```

## Troubleshooting

### API Server Won't Start

1. **Check configuration**:

    ```bash
    cat /opt/radtik-radius/scripts/config.ini
    ```

2. **Verify auth_token is set**:

    ```bash
    grep auth_token /opt/radtik-radius/scripts/config.ini
    ```

3. **Check database exists**:

    ```bash
    ls -l /var/lib/freeradius/radius.db
    ```

4. **Check port is not in use**:
    ```bash
    netstat -tuln | grep 5000
    ```

### Laravel Can't Connect

1. **Test from Laravel server**:

    ```bash
    curl -H "Authorization: Bearer YOUR-TOKEN" http://RADIUS-IP:5000/health
    ```

2. **Check firewall**:

    ```bash
    sudo ufw status | grep 5000
    ```

3. **Verify token matches**:
    - Compare token in `config.ini`
    - With token in Laravel `radius_servers.auth_token` (encrypted)

### Database Permission Errors

```bash
# Fix ownership
sudo chown freerad:freerad /var/lib/freeradius/radius.db

# Fix permissions
sudo chmod 644 /var/lib/freeradius/radius.db
```

## Security Considerations

1. **Authentication Token**:
    - Use a secure random token (minimum 32 characters)
    - Never commit token to version control
    - Rotate tokens periodically

2. **Network Security**:
    - Use firewall rules to restrict access
    - Consider using VPN or private network
    - For internet exposure, use HTTPS with reverse proxy (nginx/Apache)

3. **File Permissions**:
    - `config.ini` should be readable only by service user
    - Database should be owned by `freerad` user

4. **HTTPS Setup (Optional)**:
   Use nginx/Apache as reverse proxy for SSL/TLS:
    ```nginx
    server {
        listen 443 ssl;
        server_name radius.example.com;

        ssl_certificate /etc/ssl/certs/radius.crt;
        ssl_certificate_key /etc/ssl/private/radius.key;

        location / {
            proxy_pass http://127.0.0.1:5000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
    ```

## Laravel Configuration

In Laravel, configure the RadiusServer model:

```php
RadiusServer::create([
    'name' => 'Main RADIUS Server',
    'host' => '192.168.1.100',  // RADIUS server IP
    'auth_token' => 'YOUR-SECURE-TOKEN', // Same as config.ini
    'installation_status' => 'running',
    'is_active' => true,
]);
```

Laravel will automatically construct the endpoint:

- API URL: `http://{host}:5000`
- Sync endpoint: `http://{host}:5000/sync/vouchers`

## Performance

- **Batch size**: Laravel sends up to 250 vouchers per request
- **Workers**: Gunicorn uses 4 workers by default
- **Timeout**: 30 seconds per request
- **Database**: SQLite handles ~50k inserts/second

For 1000 vouchers:

- 4 API calls (250 each)
- 3000 database inserts
- ~5-10 seconds total

## Monitoring

Monitor API health from Laravel:

```php
$radiusApi = new RadiusApiService($radiusServer);
if ($radiusApi->testConnection()) {
    // Server is healthy
}
```

Or via cron job:

```bash
# /etc/cron.d/radtik-radius-health
*/5 * * * * root curl -sf -H "Authorization: Bearer TOKEN" http://localhost:5000/health > /dev/null || systemctl restart radtik-radius-api
```
