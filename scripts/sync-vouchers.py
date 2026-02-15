#!/usr/bin/env python3
"""
RadTik FreeRADIUS Voucher Synchronization
Syncs vouchers from Laravel to FreeRADIUS radcheck/radreply tables
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


def parse_rate_limit(rate_limit):
    """
    Parse rate limit string (e.g., "10M/10M") to bytes per second
    Supports: K (kilobits), M (megabits), G (gigabits)
    """
    try:
        parts = rate_limit.upper().split('/')
        
        def to_bytes(value):
            if 'G' in value:
                return int(value.replace('G', '')) * 1000000000
            elif 'M' in value:
                return int(value.replace('M', '')) * 1000000
            elif 'K' in value:
                return int(value.replace('K', '')) * 1000
            else:
                return int(value)
        
        upload = to_bytes(parts[0].strip())
        download = to_bytes(parts[1].strip()) if len(parts) > 1 else upload
        
        return upload, download
    except Exception as e:
        print(f"⚠️  Failed to parse rate limit '{rate_limit}': {e}", file=sys.stderr)
        return None, None


def fetch_vouchers_from_laravel():
    """Fetch active vouchers from Laravel API"""
    try:
        response = requests.post(
            f"{LARAVEL_API}/sync/vouchers",
            headers={
                'X-RADIUS-SECRET': API_SECRET,
                'Content-Type': 'application/json'
            },
            timeout=30
        )
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"❌ Failed to fetch vouchers from Laravel: {e}", file=sys.stderr)
        sys.exit(1)


def sync_voucher_to_radius(cursor, voucher):
    """Sync a single voucher to FreeRADIUS database"""
    username = voucher['username']
    password = voucher['password']
    profile = voucher['profile']
    
    try:
        # Delete existing entries
        cursor.execute("DELETE FROM radcheck WHERE username = ?", (username,))
        cursor.execute("DELETE FROM radreply WHERE username = ?", (username,))
        
        # Insert password
        cursor.execute("""
            INSERT INTO radcheck (username, attribute, op, value)
            VALUES (?, 'Cleartext-Password', ':=', ?)
        """, (username, password))
        
        # Add MAC binding if specified in voucher
        if voucher.get('mac_address'):
            cursor.execute("""
                INSERT INTO radcheck (username, attribute, op, value)
                VALUES (?, 'Calling-Station-Id', '==', ?)
            """, (username, voucher['mac_address']))
        
        # Apply profile settings
        if profile:
            # Session timeout (session_timeout in seconds)
            if profile.get('session_timeout'):
                cursor.execute("""
                    INSERT INTO radreply (username, attribute, op, value)
                    VALUES (?, 'Session-Timeout', ':=', ?)
                """, (username, str(profile['session_timeout'])))
            
            # Idle timeout
            if profile.get('idle_timeout'):
                cursor.execute("""
                    INSERT INTO radreply (username, attribute, op, value)
                    VALUES (?, 'Idle-Timeout', ':=', ?)
                """, (username, str(profile['idle_timeout'])))
            
            # Simultaneous use (shared users)
            if profile.get('shared_users'):
                cursor.execute("""
                    INSERT INTO radreply (username, attribute, op, value)
                    VALUES (?, 'Simultaneous-Use', ':=', ?)
                """, (username, str(profile['shared_users'])))
            
            # Bandwidth limit (WISPr-Bandwidth attributes for MikroTik)
            if profile.get('rate_limit'):
                upload, download = parse_rate_limit(profile['rate_limit'])
                if upload and download:
                    # MikroTik uses WISPr-Bandwidth-Max-Up and WISPr-Bandwidth-Max-Down
                    cursor.execute("""
                        INSERT INTO radreply (username, attribute, op, value)
                        VALUES (?, 'WISPr-Bandwidth-Max-Up', ':=', ?)
                    """, (username, str(upload)))
                    
                    cursor.execute("""
                        INSERT INTO radreply (username, attribute, op, value)
                        VALUES (?, 'WISPr-Bandwidth-Max-Down', ':=', ?)
                    """, (username, str(download)))
        
        return True
    except sqlite3.Error as e:
        print(f"⚠️  Failed to sync voucher '{username}': {e}", file=sys.stderr)
        return False


def main():
    """Main synchronization function"""
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Starting voucher synchronization...")
    
    # Fetch vouchers from Laravel
    data = fetch_vouchers_from_laravel()
    vouchers = data.get('vouchers', [])
    
    if not vouchers:
        print("ℹ️  No vouchers to sync")
        return
    
    # Connect to FreeRADIUS database
    try:
        conn = sqlite3.connect(RADIUS_DB, timeout=30.0)
        cursor = conn.cursor()
        
        success_count = 0
        fail_count = 0
        
        for voucher in vouchers:
            if sync_voucher_to_radius(cursor, voucher):
                success_count += 1
            else:
                fail_count += 1
        
        conn.commit()
        conn.close()
        
        print(f"✅ Successfully synced {success_count}/{len(vouchers)} vouchers")
        if fail_count > 0:
            print(f"⚠️  {fail_count} vouchers failed to sync")
    
    except sqlite3.Error as e:
        print(f"❌ Database error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
