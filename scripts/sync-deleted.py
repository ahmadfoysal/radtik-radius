#!/usr/bin/env python3
"""
RadTik FreeRADIUS Deleted Users Sync
Removes deleted vouchers from FreeRADIUS database
"""

import requests
import sqlite3
import configparser
import sys
import os
from datetime import datetime, timedelta

# Load configuration
config = configparser.ConfigParser()
config_path = os.path.join(os.path.dirname(__file__), 'config.ini')

if not os.path.exists(config_path):
    print(f"❌ Configuration file not found: {config_path}", file=sys.stderr)
    sys.exit(1)

config.read(config_path)

LARAVEL_API = config['laravel']['api_url']
API_SECRET = config['laravel']['api_secret']
RADIUS_DB = config['radius']['db_path']


def sync_deleted_users():
    """Remove deleted users from FreeRADIUS database"""
    try:
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Syncing deleted users...")
        
        # Get deleted users from last 10 minutes
        since = (datetime.now() - timedelta(minutes=10)).isoformat()
        
        # Call Laravel API
        response = requests.get(
            f"{LARAVEL_API}/sync/deleted-vouchers",
            headers={"X-RADIUS-SECRET": API_SECRET},
            params={"since": since},
            timeout=30
        )
        response.raise_for_status()
        
        data = response.json()
        deleted_users = data.get('deleted_users', [])
        
        if not deleted_users:
            print("ℹ️  No deleted users to sync")
            return
        
        # Connect to FreeRADIUS database
        conn = sqlite3.connect(RADIUS_DB)
        cursor = conn.cursor()
        
        removed_count = 0
        
        for username in deleted_users:
            try:
                # Remove from radcheck
                cursor.execute("DELETE FROM radcheck WHERE username = ?", (username,))
                check_deleted = cursor.rowcount
                
                # Remove from radreply
                cursor.execute("DELETE FROM radreply WHERE username = ?", (username,))
                reply_deleted = cursor.rowcount
                
                if check_deleted > 0 or reply_deleted > 0:
                    removed_count += 1
                    print(f"  → Removed user '{username}' (radcheck: {check_deleted}, radreply: {reply_deleted})")
                
                # Note: We keep radacct and radpostauth for audit/historical purposes
                
            except Exception as e:
                print(f"⚠️  Failed to remove user '{username}': {e}", file=sys.stderr)
        
        # Commit all changes
        conn.commit()
        conn.close()
        
        print(f"✅ Removed {removed_count}/{len(deleted_users)} users from FreeRADIUS")
        
    except requests.exceptions.RequestException as e:
        print(f"❌ API request failed: {e}", file=sys.stderr)
        sys.exit(1)
    except sqlite3.Error as e:
        print(f"❌ Database error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"❌ Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    sync_deleted_users()
