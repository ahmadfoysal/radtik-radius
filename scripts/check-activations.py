#!/usr/bin/env python3
"""
RadTik FreeRADIUS Activation Monitor
Monitors radpostauth for first logins and updates Laravel with MAC address
"""

import requests
import sqlite3
import configparser
import sys
import os
from datetime import datetime

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


def bind_mac_to_user(cursor, username, mac_address):
    """Add MAC address check to radcheck table"""
    try:
        # Check if MAC binding already exists
        cursor.execute("""
            SELECT COUNT(*) FROM radcheck
            WHERE username = ? AND attribute = 'Calling-Station-Id'
        """, (username,))
        
        if cursor.fetchone()[0] == 0:
            cursor.execute("""
                INSERT INTO radcheck (username, attribute, op, value)
                VALUES (?, 'Calling-Station-Id', '==', ?)
            """, (username, mac_address))
            return True
        return False
    except Exception as e:
        print(f"⚠️  Failed to bind MAC for '{username}': {e}", file=sys.stderr)
        return False


def check_new_activations():
    """Check radpostauth for new activations and notify Laravel"""
    try:
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Checking for new activations...")
        
        # Connect to FreeRADIUS database
        conn = sqlite3.connect(RADIUS_DB)
        cursor = conn.cursor()
        
        # Get unprocessed successful authentications
        cursor.execute("""
            SELECT username, calling_station_id, nas_identifier, authdate
            FROM radpostauth
            WHERE reply = 'Access-Accept'
            AND (processed IS NULL OR processed = 0)
            ORDER BY authdate ASC
            LIMIT 100
        """)
        
        rows = cursor.fetchall()
        
        if not rows:
            print("ℹ️  No new activations")
            conn.close()
            return
        
        processed_count = 0
        bound_count = 0
        
        for username, mac, nas, authdate in rows:
            try:
                # Call Laravel API to activate voucher
                response = requests.post(
                    f"{LARAVEL_API}/voucher/activate",
                    headers={"X-RADIUS-SECRET": API_SECRET},
                    json={
                        "username": username,
                        "mac_address": mac,
                        "nas_identifier": nas,
                        "activated_at": authdate
                    },
                    timeout=30
                )
                
                if response.status_code == 200:
                    result = response.json()
                    
                    # If MAC binding required, update radcheck
                    if result.get('should_bind_mac'):
                        if bind_mac_to_user(cursor, username, mac):
                            bound_count += 1
                            print(f"  → Bound MAC {mac} to user '{username}'")
                    
                    # Mark as processed
                    cursor.execute("""
                        UPDATE radpostauth SET processed = 1
                        WHERE username = ? AND authdate = ?
                    """, (username, authdate))
                    
                    processed_count += 1
                else:
                    print(f"⚠️  API returned status {response.status_code} for '{username}'", file=sys.stderr)
                    
            except requests.exceptions.RequestException as e:
                print(f"⚠️  API request failed for '{username}': {e}", file=sys.stderr)
            except Exception as e:
                print(f"⚠️  Error processing '{username}': {e}", file=sys.stderr)
        
        # Commit all changes
        conn.commit()
        conn.close()
        
        print(f"✅ Processed {processed_count} activations ({bound_count} MAC bindings)")
        
    except sqlite3.Error as e:
        print(f"❌ Database error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"❌ Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    check_new_activations()
