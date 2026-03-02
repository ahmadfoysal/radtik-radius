# RadTik-RADIUS Update Management

## Overview

The RADTik-RADIUS package now includes an integrated update management system that allows administrators to check for and apply updates directly from the RADTik panel without SSH access.

## Features

### 1. Version Checking
- Automatically checks GitHub for new releases
- Compares installed version with latest available version
- Displays update availability status in real-time

### 2. One-Click Updates
- Apply updates with a single button click
- Automatic backup creation before each update
- Configuration files are preserved
- Services automatically restarted after update

### 3. Safety Features
- **Automatic Backups**: Every update creates a timestamped backup
- **Configuration Preservation**: Your config.ini and clients.conf are kept
- **Service Verification**: Services are checked after update completion
- **Rollback Instructions**: Clear rollback steps provided if needed

## How It Works

### Architecture

```
RADTik Panel (Livewire)
    ↓ (Check for Updates)
RadiusServerSshService
    ↓ (SSH Command: curl GitHub API)
GitHub Releases API
    ↓ (Version Comparison)
Update Available/Not Available
```

```
RADTik Panel (Apply Update)
    ↓
RadiusServerSshService
    ↓ (SSH Commands)
RADIUS Server:
    1. Create backup
    2. Download from GitHub
    3. Extract and copy files
    4. Preserve config.ini
    5. Restart services
    6. Verify status
```

### Update Process

1. **Backup Creation**
   ```bash
   /opt/radtik-radius → /opt/radtik-radius-backup-{timestamp}
   ```

2. **Download Latest Release**
   ```bash
   curl -L https://github.com/ahmadfoysal/radtik-radius/archive/refs/tags/v{version}.tar.gz
   ```

3. **Extract and Deploy**
   - Files extracted to temporary directory
   - Copied to /opt/radtik-radius
   - Configuration files preserved from backup

4. **Service Restart**
   ```bash
   systemctl restart radtik-radius-api
   systemctl restart freeradius
   ```

5. **Verification**
   - Check service status
   - Confirm version update
   - Display results to administrator

## Usage

### From RADTik Panel

1. Navigate to: **RADIUS → Servers → [Select Server] → Show**
2. Look for the "Software Version & Updates" card
3. Click **"Check for Updates"** button
4. If update is available, click **"Apply Update"** button
5. Confirm the update action
6. Wait for the update to complete (usually 1-2 minutes)

### Manual Update (SSH)

If you have SSH access, you can also update manually:

```bash
# Using the update script
cd /opt/radtik-radius
sudo bash update.sh

# Or manually
sudo systemctl stop radtik-radius-api freeradius
cd /tmp
curl -L -o radtik-radius.tar.gz \
  https://github.com/ahmadfoysal/radtik-radius/archive/refs/tags/v1.0.1.tar.gz
tar -xzf radtik-radius.tar.gz
sudo cp -r radtik-radius-1.0.1/* /opt/radtik-radius/
# Preserve your config.ini!
sudo systemctl start radtik-radius-api freeradius
```

## Rollback Procedure

If an update causes issues:

```bash
# Find your backup (use the timestamp from update message)
ls -la /opt/radtik-radius-backup-*

# Restore from backup
sudo rm -rf /opt/radtik-radius
sudo mv /opt/radtik-radius-backup-{timestamp} /opt/radtik-radius

# Restart services
sudo systemctl restart radtik-radius-api freeradius

# Verify services are running
sudo systemctl status radtik-radius-api freeradius
```

## Version File

Each installation includes a VERSION file:

```bash
cat /opt/radtik-radius/VERSION
# Output: 1.0.0
```

This file is used by the update system to determine the currently installed version.

## Security Considerations

- Updates are fetched from official GitHub repository only
- SSH authentication required (same as server management)
- Automatic backups prevent data loss
- Configuration secrets are preserved
- Update actions are logged in Laravel logs

## Troubleshooting

### "Failed to check for updates"

**Cause**: Server cannot reach GitHub API

**Solution**:
```bash
# Test connectivity from server
ssh user@radius-server
curl -I https://api.github.com/repos/ahmadfoysal/radtik-radius/releases/latest

# Check firewall
sudo ufw status
```

### "Services failed to start after update"

**Cause**: Configuration conflict or permission issue

**Solution**:
```bash
# Check service logs
sudo journalctl -u radtik-radius-api -n 50
sudo journalctl -u freeradius -n 50

# Rollback to backup (see Rollback Procedure above)
```

### "VERSION file not found"

**Cause**: Old installation without VERSION file

**Solution**:
```bash
# Create VERSION file manually
echo "1.0.0" | sudo tee /opt/radtik-radius/VERSION
```

## API Methods

### RadiusServerSshService

#### `getInstalledVersion()`
Returns currently installed version.

```php
$result = $sshService->getInstalledVersion();
// Returns: ['success' => true, 'version' => '1.0.0']
```

#### `checkForUpdates()`
Checks GitHub for latest release and compares with installed version.

```php
$result = $sshService->checkForUpdates();
// Returns: [
//   'success' => true,
//   'installed_version' => '1.0.0',
//   'latest_version' => '1.0.1',
//   'update_available' => true,
//   'message' => 'Update available: v1.0.0 → v1.0.1'
// ]
```

#### `applyUpdate(string $targetVersion = 'latest')`
Downloads and applies update from GitHub.

```php
$result = $sshService->applyUpdate();
// Returns: [
//   'success' => true,
//   'old_version' => '1.0.0',
//   'new_version' => '1.0.1',
//   'backup_location' => '/opt/radtik-radius-backup-2026-03-01_10-30-45',
//   'api_status' => 'active',
//   'radius_status' => 'active'
// ]
```

## Future Enhancements

- [ ] Automatic update notifications
- [ ] Scheduled update checks
- [ ] Update staging/testing mode
- [ ] Differential updates (download only changed files)
- [ ] Update history tracking
- [ ] Automatic rollback on service failure

## Release Versioning

This project follows [Semantic Versioning](https://semver.org/):

- **MAJOR** version: Incompatible API changes
- **MINOR** version: New functionality (backwards compatible)
- **PATCH** version: Bug fixes (backwards compatible)

Example:
- `1.0.0` → `1.0.1`: Bug fix (safe to update)
- `1.0.0` → `1.1.0`: New features (safe to update)
- `1.0.0` → `2.0.0`: Breaking changes (review before updating)
