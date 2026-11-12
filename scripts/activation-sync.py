#!/usr/bin/env python3
"""
RadTik Activation Sync Script
Polls FreeRADIUS radpostauth table for new authentications and syncs to Laravel.

This script runs via cron and:
1. Checks radpostauth table for unique Access-Accept entries from last 24 hours
2. POSTs activation data to Laravel API
3. Tracks last sync attempt to avoid duplicates
4. Verifies auth token with Laravel's radius_servers table
"""

import sqlite3
import requests
import configparser
import logging
import sys
import os
import json
from datetime import datetime, timedelta, timezone
from typing import List, Dict, Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    # cron appends stdout to the same log file, so log to the screen only when a person runs it in a terminal
    # (otherwise every line was written twice)
    handlers=[logging.FileHandler('/var/log/radtik-activation-sync.log')]
    + ([logging.StreamHandler(sys.stdout)] if sys.stdout.isatty() else [])
)
logger = logging.getLogger('activation-sync')

# Load configuration
config = configparser.ConfigParser()
config_path = os.path.join(os.path.dirname(__file__), 'config.ini')

if not os.path.exists(config_path):
    logger.error(f"Configuration file not found: {config_path}")
    sys.exit(1)

config.read(config_path)

# Configuration variables
RADIUS_DB_PATH = config.get('radius', 'db_path', fallback='/etc/freeradius/3.0/sqlite/radius.db')
LARAVEL_API_URL = config.get('laravel', 'api_url', fallback='')
AUTH_TOKEN = config.get('api', 'auth_token', fallback='')

# Validate configuration
if not LARAVEL_API_URL:
    logger.error("LARAVEL_API_URL not configured in config.ini [laravel] section!")
    sys.exit(1)

if not AUTH_TOKEN:
    logger.error("AUTH_TOKEN not configured in config.ini [api] section!")
    sys.exit(1)

if not os.path.exists(RADIUS_DB_PATH):
    logger.error(f"RADIUS database not found: {RADIUS_DB_PATH}")
    sys.exit(1)


_MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

STATE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.activation-sync.state')
OVERLAP_MINUTES = 10  # always look this far back, so a missed run or a clock jump loses nothing


def radius_expiration_value(iso_utc: str) -> str:
    """
    "2026-11-12T10:00:00Z" (UTC, as sent by Laravel) -> "Nov 12 2026 16:00:00" in THIS server's
    local clock. FreeRADIUS reads the Expiration attribute in the server's local time zone (checked
    with FreeRADIUS 3.2: the same text is 6 hours off on a UTC+6 server), so the value must be
    converted. Month names are English whatever the server locale is.
    """
    text = str(iso_utc).strip()
    if text.endswith('Z'):
        text = text[:-1] + '+00:00'
    moment = datetime.fromisoformat(text)
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    local = moment.astimezone()  # server local time zone
    return f"{_MONTHS[local.month - 1]} {local.day:02d} {local.year} {local:%H:%M:%S}"


def authdate_to_utc_iso(authdate: str) -> str:
    """
    radpostauth.authdate is written by FreeRADIUS in the server's LOCAL time ("%S.%M" =
    "YYYY-MM-DD HH:MM:SS.ffffff"). Laravel needs an unambiguous moment: send UTC with a Z.
    """
    text = str(authdate).strip().replace(' ', 'T', 1)
    if '.' in text:
        text = text.split('.', 1)[0]
    moment = datetime.fromisoformat(text)  # naive = server local time
    return moment.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def load_last_id() -> int:
    """Highest radpostauth id that Laravel has confirmed (0 = unknown: look back 24 hours)."""
    try:
        with open(STATE_PATH) as handle:
            return int(json.load(handle).get('last_id', 0))
    except (OSError, ValueError, TypeError):
        return 0


def save_last_id(last_id: int) -> None:
    try:
        with open(STATE_PATH, 'w') as handle:
            json.dump({'last_id': int(last_id)}, handle)
    except OSError as e:
        logger.warning(f"Could not save sync state: {e}")



def get_db_connection():
    """Get SQLite database connection"""
    try:
        conn = sqlite3.connect(RADIUS_DB_PATH, timeout=10)
        conn.row_factory = sqlite3.Row
        return conn
    except sqlite3.Error as e:
        logger.error(f"Database connection error: {e}")
        raise


def fetch_unique_activations_last_24h(last_id: int = 0) -> tuple:
    """
    Fetch unique successful authentications from the last 24 hours that Laravel has not
    confirmed yet: rows newer than `last_id`, plus everything from the last few minutes
    (overlap). Without a saved state (`last_id` 0) it is the whole 24 hours, as before.
    Returns (distinct combinations of username, nas_identifier and mac address, highest id seen).
    """
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # authdate is in the server's local time, so compare with local time
        yesterday = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d %H:%M:%S')
        recent = (datetime.now() - timedelta(minutes=OVERLAP_MINUTES)).strftime('%Y-%m-%d %H:%M:%S')
        
        query = """
            SELECT 
                username,
                nas_identifier,
                calling_station_id,
                MIN(authdate) as first_auth_date,
                MAX(id) as max_id
            FROM radpostauth
            WHERE reply = 'Access-Accept'
              AND authdate > ?
              AND (? = 0 OR id > ? OR authdate > ?)
            GROUP BY username, 
                     nas_identifier,
                     calling_station_id
            ORDER BY first_auth_date ASC
        """
        
        cursor.execute(query, (yesterday, last_id, last_id, recent))
        rows = cursor.fetchall()
        conn.close()
        
        # Convert to list of dicts
        activations = []
        for row in rows:
            activations.append({
                'username': row['username'],
                'nas_identifier': row['nas_identifier'],
                'calling_station_id': row['calling_station_id'],
                'authenticated_at': authdate_to_utc_iso(row['first_auth_date'])
            })
        
        highest = max([row['max_id'] for row in rows], default=last_id)
        return activations, highest
        
    except sqlite3.Error as e:
        logger.error(f"Database query error: {e}")
        return [], last_id


def post_activations_to_laravel(activations: List[Dict]) -> Dict:
    """
    POST activation data to Laravel API
    Returns response data with MAC bindings if any
    """
    if not activations:
        logger.info("No activations to sync")
        return {'success': True, 'mac_bindings': []}
    
    try:
        url = f"{LARAVEL_API_URL}/api/radius/activations"
        headers = {
            'Authorization': f'Bearer {AUTH_TOKEN}',
            'Content-Type': 'application/json'
        }
        
        payload = {
            'activations': activations
        }
        
        logger.info(f"Posting {len(activations)} unique activations to Laravel...")
        
        response = requests.post(
            url,
            headers=headers,
            json=payload,
            timeout=30
        )
        
        if response.status_code == 200:
            result = response.json()
            logger.info(f"✓ Successfully synced {len(activations)} activations")
            return result
        else:
            logger.error(f"Laravel API error: [{response.status_code}] {response.text}")
            return {'success': False, 'mac_bindings': []}
            
    except requests.exceptions.Timeout:
        logger.error("Laravel API request timed out")
        return {'success': False, 'mac_bindings': []}
    except requests.exceptions.ConnectionError as e:
        logger.error(f"Cannot connect to Laravel API: {e}")
        return {'success': False, 'mac_bindings': []}
    except Exception as e:
        logger.error(f"Failed to post activations: {e}")
        return {'success': False, 'mac_bindings': []}


def sync_mac_bindings_to_radius(mac_bindings: List[Dict]) -> bool:
    """
    Sync MAC bindings directly to RADIUS database
    Adds Calling-Station-Id check to radcheck table to lock voucher to MAC
    Returns True if successful
    """
    if not mac_bindings:
        return True
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        synced = 0
        updated = 0
        
        logger.info(f"Syncing {len(mac_bindings)} MAC bindings to RADIUS database...")
        
        for binding in mac_bindings:
            try:
                username = binding['username']
                mac_address = binding['mac_address']
                
                # Check if MAC binding already exists for this user
                cursor.execute(
                    "SELECT id, value FROM radcheck WHERE username = ? AND attribute = 'Calling-Station-Id'",
                    (username,)
                )
                existing = cursor.fetchone()
                
                if existing:
                    # Update existing MAC binding (in case MAC changed)
                    existing_mac = existing['value']
                    
                    if existing_mac != mac_address:
                        cursor.execute(
                            "UPDATE radcheck SET value = ? WHERE username = ? AND attribute = 'Calling-Station-Id'",
                            (mac_address, username)
                        )
                        updated += 1
                        logger.info(f"Updated MAC for {username}: {existing_mac} → {mac_address}")
                    else:
                        logger.debug(f"MAC binding unchanged for {username}: {mac_address}")
                        synced += 1
                else:
                    # Insert new MAC binding
                    cursor.execute(
                        "INSERT INTO radcheck (username, attribute, op, value) VALUES (?, ?, ?, ?)",
                        (username, 'Calling-Station-Id', '==', mac_address)
                    )
                    synced += 1
                    logger.info(f"Added MAC binding for {username}: {mac_address}")
                
            except sqlite3.Error as e:
                logger.error(f"Database error for {username}: {e}")
                continue
        
        # Commit all changes
        conn.commit()
        conn.close()
        
        logger.info(f"✓ MAC bindings synced: {synced} added, {updated} updated")
        return True
        
    except sqlite3.Error as e:
        logger.error(f"Failed to sync MAC bindings: {e}")
        return False
    except Exception as e:
        logger.error(f"Unexpected error syncing MAC bindings: {e}")
        return False


def sync_expirations_to_radius(expirations: List[Dict]) -> bool:
    """
    Write the expiry Laravel computed into radcheck as `Expiration`, in this server's local time.
    FreeRADIUS then rejects the voucher after that moment on its own (also while Laravel is
    offline) and gives every new session a Session-Timeout of the time that is left, so the router
    cuts the session at expiry. Idempotent: an unchanged value is left alone. Users that are not
    in RADIUS (deleted) are skipped, so no stray rows appear.
    Returns True if every entry was handled.
    """
    if not expirations:
        return True

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        added = updated = skipped = 0

        for entry in expirations:
            try:
                username = entry['username']
                value = radius_expiration_value(entry['expires_at'])
            except (KeyError, ValueError) as e:
                logger.error(f"Bad expiration entry {entry}: {e}")
                continue

            cursor.execute(
                "SELECT COUNT(*) FROM radcheck WHERE username = ? AND attribute = 'Cleartext-Password'",
                (username,)
            )
            if cursor.fetchone()[0] == 0:
                skipped += 1
                continue

            cursor.execute("SELECT id, value FROM radcheck WHERE username = ? AND attribute = 'Expiration'", (username,))
            existing = cursor.fetchone()

            if existing is None:
                cursor.execute(
                    "INSERT INTO radcheck (username, attribute, op, value) VALUES (?, 'Expiration', ':=', ?)",
                    (username, value)
                )
                added += 1
            elif existing['value'] != value:
                cursor.execute("UPDATE radcheck SET value = ?, op = ':=' WHERE id = ?", (value, existing['id']))
                updated += 1

        conn.commit()
        conn.close()
        logger.info(f"Expirations synced: {added} added, {updated} updated, {skipped} skipped (user not in RADIUS)")
        return True

    except sqlite3.Error as e:
        logger.error(f"Failed to sync expirations: {e}")
        return False


def read_version() -> str:
    """The installed RADTik RADIUS version (VERSION file next to scripts/), or '' when unreadable."""
    try:
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'VERSION')) as handle:
            return handle.read().strip()
    except OSError:
        return ''


def send_heartbeat() -> bool:
    """
    Tell the panel "I am alive and can reach you" (every run = every minute). The panel warns its owner when this stops,
    which is how a wrong api_url is noticed. Failing is logged with the likely cause; the run goes on.
    """
    url = f"{LARAVEL_API_URL.rstrip('/')}/api/radius/heartbeat"

    if 'example.com' in LARAVEL_API_URL:
        logger.error(f"api_url in config.ini is still the placeholder ({LARAVEL_API_URL}). "
                     "Press 'Send keys to server' in the panel or edit [laravel] api_url.")

    try:
        response = requests.post(
            url,
            headers={'Authorization': f'Bearer {AUTH_TOKEN}', 'Content-Type': 'application/json'},
            json={'version': read_version()},
            timeout=15
        )
        if response.status_code == 200:
            return True
        logger.error(f"The panel answered {response.status_code} to the heartbeat at {url}. "
                     "Check auth_token in config.ini (panel: Check connection key).")
    except requests.exceptions.RequestException as e:
        logger.error(f"Cannot reach the panel at {LARAVEL_API_URL}: {e}. Check [laravel] api_url in config.ini.")

    return False


def main():
    """Main function - fetches and posts activations"""
    try:
        logger.info("Starting activation sync...")

        send_heartbeat()
        
        # Fetch the activations Laravel has not confirmed yet (24 hours when there is no state)
        last_id = load_last_id()
        activations, highest_id = fetch_unique_activations_last_24h(last_id)
        
        if not activations:
            logger.info("No activations found in last 24 hours")
            return
        
        logger.info(f"Found {len(activations)} unique activation(s) from last 24 hours")
        
        # Post to Laravel
        result = post_activations_to_laravel(activations)
        
        if not result.get('success'):
            logger.error("Failed to sync activations")
            sys.exit(1)
        
        logger.info("Activation sync completed successfully")

        # Expiry: RADIUS enforces it itself from now on (#32)
        expirations_ok = sync_expirations_to_radius(result.get('expirations', []))
        
        # Check if Laravel returned MAC bindings to sync
        mac_bindings = result.get('mac_bindings', [])
        
        if mac_bindings:
            logger.info(f"Received {len(mac_bindings)} MAC binding(s) to sync to RADIUS")
            
            # Sync MAC bindings to RADIUS database
            binding_success = sync_mac_bindings_to_radius(mac_bindings)
            
            if binding_success:
                logger.info("MAC binding sync completed successfully")
            else:
                logger.warning("MAC binding sync failed, but activations were processed")
        else:
            logger.info("No MAC bindings required")

        # Only move the state forward when everything Laravel told us was applied
        if expirations_ok:
            save_last_id(highest_id)
        else:
            logger.warning("Expirations were not applied; the same activations are sent again next time")
            
    except Exception as e:
        logger.error(f"Sync error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == '__main__':
    main()
