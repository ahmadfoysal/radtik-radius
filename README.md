# RadTik FreeRADIUS + SQLite Installer

A one-command installer for setting up FreeRADIUS with SQLite backend on Ubuntu 22.04 LTS, pre-configured for RadTik hotspot authentication.

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
git clone https://github.com/yourusername/radtik-radius.git
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

## Support & Documentation

- **FreeRADIUS Documentation**: https://freeradius.org/documentation/
- **FreeRADIUS Wiki**: https://wiki.freeradius.org/
- **RadTik**: https://github.com/yourusername/radtik

## License

This configuration bundle is provided as-is for use with RadTik hotspot systems.
