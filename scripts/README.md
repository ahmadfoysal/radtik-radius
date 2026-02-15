# RadTik FreeRADIUS Python Scripts

This folder contains Python synchronization scripts for integrating FreeRADIUS with Laravel RadTik application.

## Scripts

- **sync-vouchers.py**: Syncs vouchers from Laravel to FreeRADIUS (radcheck/radreply tables)
- **check-activations.py**: Monitors radpostauth for new activations and updates Laravel with MAC addresses
- **sync-deleted.py**: Removes deleted vouchers from FreeRADIUS database

## Configuration

Copy `config.ini.example` to `config.ini` and configure:

```ini
[laravel]
api_url = https://your-radtik-domain.com/api/radius
api_secret = your-radius-server-token-from-laravel

[radius]
db_path = /etc/freeradius/3.0/sqlite/radius.db
```

## Requirements

- Python 3.6+
- requests library (`pip3 install requests`)

## Manual Execution

```bash
# Sync vouchers
python3 sync-vouchers.py

# Check activations
python3 check-activations.py

# Clean deleted users
python3 sync-deleted.py
```

## Automated Execution

These scripts are automatically scheduled via cron jobs during installation:

- Voucher sync: Every 2 minutes
- Activation check: Every 1 minute
- Deleted users: Every 5 minutes

See `/etc/cron.d/radtik-sync` on the RADIUS server.
