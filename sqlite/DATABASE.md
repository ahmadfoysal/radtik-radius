# RadTik FreeRADIUS Database Setup

This document describes the SQLite database template used for RadTik FreeRADIUS authentication.

## Database File

**Location**: `sqlite/radius.db`

## Database Information

- **Type**: SQLite 3
- **Journal Mode**: WAL (Write-Ahead Logging)
- **Busy Timeout**: 30000ms (30 seconds)
- **State**: Clean template (no data)
- **Ready for**: Production deployment

## Tables

### 1. radcheck
Stores user authentication credentials.

**Columns:**
- `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
- `username` (varchar(64)) - User identifier
- `attribute` (varchar(64)) - Attribute name (e.g., 'Cleartext-Password', 'Calling-Station-Id')
- `op` (char(2)) - Operator (e.g., ':=', '==')
- `value` (varchar(253)) - Attribute value

**Indexes:**
- `check_username` ON username
- `idx_radcheck_username` ON username

### 2. radreply
Stores response attributes sent to users upon authentication.

**Columns:**
- `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
- `username` (varchar(64))
- `attribute` (varchar(64)) - Response attribute (e.g., 'Session-Timeout', 'WISPr-Bandwidth-Max-Up')
- `op` (char(2))
- `value` (varchar(253))

**Indexes:**
- `reply_username` ON username
- `idx_radreply_username` ON username

### 3. radpostauth ⭐ (Enhanced for RadTik)
Stores authentication attempts for auditing and MAC address tracking.

**Columns:**
- `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
- `username` (varchar(64))
- `pass` (varchar(64)) - Password attempt
- `reply` (varchar(32)) - 'Access-Accept' or 'Access-Reject'
- `authdate` (timestamp)
- `class` (varchar(64))
- `calling_station_id` (varchar(50)) - **MAC address** ⭐
- `nas_identifier` (varchar(64)) - **NAS/Router identifier ** ⭐
- `processed` (INTEGER DEFAULT 0) - **Sync flag for Laravel** ⭐

**Indexes:**
- `radpostauth_username` ON username
- `radpostauth_class` ON class
- `idx_radpostauth_processed` ON (processed, authdate) - **For sync queries**
- `idx_radpostauth_username` ON username

### 4. radacct
Stores accounting records (session start/stop, data usage).

**Columns:**
- Session tracking (acctuniqueid, acctsessionid, username)
- Network info (nasipaddress, nasportid, nasporttype)
- IP addressing (framedipaddress, framedipv6address, etc.)
- Time tracking (acctstarttime, acctstoptime, acctsessiontime)
- Usage tracking (acctinputoctets, acctoutputoctets)

**Indexes:** Multiple indexes for performance (14 total)

### 5. radgroupcheck
Stores group-level check attributes.

**Indexes:**
- `check_groupname` ON groupname

### 6. radgrouprply
Stores group-level reply attributes.

**Indexes:**
- `reply_groupname` ON groupname

### 7. radusergroup
Maps users to groups.

**Indexes:**
- `usergroup_username` ON username

### 8. nas
Stores Network Access Server (router/AP) information.

**Columns:**
- `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
- `nasname` (varchar(128))
- `shortname` (varchar(32))
- `type` (varchar(30))
- `ports` (integer)
- `secret` (varchar(60))
- `server` (varchar(64))
- `community` (varchar(50))
- `description` (varchar(200))

**Indexes:**
- `nasname` ON nasname

## Performance Optimizations

### WAL Mode (Write-Ahead Logging)
```sql
PRAGMA journal_mode=WAL;
```
- Allows concurrent reads during writes
- Better performance for high-traffic scenarios
- Reduces database locks

### Busy Timeout
```sql
PRAGMA busy_timeout=30000;
```
- 30-second timeout for locked database
- Prevents immediate failures under load

### Other Optimizations
```sql
PRAGMA synchronous=NORMAL;     -- Balanced durability/performance
PRAGMA cache_size=10000;       -- Larger cache for better performance
PRAGMA temp_store=MEMORY;      -- Use RAM for temporary tables
```

## RadTik-Specific Features

### MAC Address Binding
The `radpostauth` table captures MAC addresses (`calling_station_id`) during authentication:

1. User authenticates with WiFi hotspot
2. FreeRADIUS logs MAC address to `radpostauth`
3. Python sync script (`check-activations.py`) reads unprocessed records
4. Laravel API receives MAC address for binding
5. Record marked as `processed = 1`

### Session Tracking Flow

```
User Login → FreeRADIUS Auth → radpostauth (processed=0)
                                      ↓
                              check-activations.py
                                      ↓
                              Laravel API (/api/radius/voucher/activate)
                                      ↓
                              Update voucher + MAC binding
                                      ↓
                              radpostauth (processed=1)
```

## Maintenance

### Vacuum Database
```bash
sqlite3 /etc/freeradius/3.0/sqlite/radius.db "VACUUM;"
```

### Check Database Size
```bash
ls -lh /etc/freeradius/3.0/sqlite/radius.db
```

### Analyze Query Performance
```bash
sqlite3 /etc/freeradius/3.0/sqlite/radius.db "EXPLAIN QUERY PLAN SELECT * FROM radpostauth WHERE processed = 0;"
```

### Archive Old Records
Periodically clean old radpostauth and radacct records to maintain performance:

```sql
-- Archive records older than 90 days
DELETE FROM radpostauth WHERE authdate < datetime('now', '-90 days');
DELETE FROM radacct WHERE acctstarttime < datetime('now', '-90 days');
VACUUM;
```

## Security Notes

1. **File Permissions**: Database should be owned by `freerad:freerad` with 664 permissions
2. **Directory Permissions**: Parent directory should be 775
3. **Password Storage**: Cleartext-Password is used for simplicity (RADIUS protocol limitation)
4. **Network Security**: Ensure RADIUS shared secrets are strong (not 'testing123')

## Installation

The database is automatically copied and configured by `install.sh`:

```bash
sudo bash install.sh
```

The installer:
1. Copies clean template to `/etc/freeradius/3.0/sqlite/radius.db`
2. Sets correct ownership and permissions
3. Verifies WAL mode is enabled
4. Installs sync scripts for Laravel integration

## Testing

### Verify Database Structure
```bash
sqlite3 /etc/freeradius/3.0/sqlite/radius.db ".schema radpostauth"
```

### Check for Clean State
```bash
sqlite3 /etc/freeradius/3.0/sqlite/radius.db "SELECT COUNT(*) FROM radcheck;"
# Should return: 0
```

### Verify Indexes
```bash
sqlite3 /etc/freeradius/3.0/sqlite/radius.db ".indexes radpostauth"
```

## Troubleshooting

### Database Locked Errors
- Check if FreeRADIUS is running: `systemctl status freeradius`
- Verify WAL mode: `sqlite3 radius.db "PRAGMA journal_mode;"`
- Increase busy_timeout if needed

### Permission Errors
```bash
sudo chown -R freerad:freerad /etc/freeradius/3.0/sqlite/
sudo chmod 775 /etc/freeradius/3.0/sqlite/
sudo chmod 664 /etc/freeradius/3.0/sqlite/radius.db
```

### Missing Columns
If the database was created before RadTik enhancements:
```sql
ALTER TABLE radpostauth ADD COLUMN calling_station_id varchar(50) DEFAULT NULL;
ALTER TABLE radpostauth ADD COLUMN nas_identifier varchar(64) DEFAULT NULL;
ALTER TABLE radpostauth ADD COLUMN processed INTEGER DEFAULT 0;
CREATE INDEX idx_radpostauth_processed ON radpostauth(processed, authdate);
```

## Version History

- **v1.0.0** (2026-02-15): Initial production-ready template
  - Added MAC address tracking columns
  - Added processed flag for sync
  - Enabled WAL mode
  - Added performance indexes
  - Clean state (no test data)
