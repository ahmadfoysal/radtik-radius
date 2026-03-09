#!/usr/bin/env python3
"""
RadTik Orphaned Voucher Cleanup Script
Removes vouchers from RADIUS database that don't exist in RADTik Laravel database.

This script runs via cron and:
1. Queries all usernames from RADIUS radcheck table
2. Sends usernames to Laravel API for verification
3. Deletes orphaned vouchers (those not in RADTik) from RADIUS database
4. Prevents RADIUS database from becoming cluttered with stale data

RADTik database is the source of truth.
"""

import sqlite3
import requests
import configparser
import logging
import sys
import os
from typing import List, Dict, Set
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/radtik-cleanup-orphaned.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('cleanup-orphaned')

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
BATCH_SIZE = config.getint('cleanup', 'batch_size', fallback=1000)
DRY_RUN = config.getboolean('cleanup', 'dry_run', fallback=False)

# Validate configuration
if not LARAVEL_API_URL:
    logger.error("LARAVEL_API_URL not configured in config.ini [laravel] section!")
    logger.error("Please set: api_url = https://your-domain.com")
    sys.exit(1)

if not AUTH_TOKEN:
    logger.error("AUTH_TOKEN not configured in config.ini [api] section!")
    logger.error("This should match the RADIUS server auth_token in Laravel")
    sys.exit(1)

def get_radius_usernames() -> List[str]:
    """
    Get all usernames from RADIUS radcheck table
    
    Returns:
        List of usernames currently in RADIUS database
    """
    try:
        conn = sqlite3.connect(RADIUS_DB_PATH)
        cursor = conn.cursor()
        
        cursor.execute("SELECT DISTINCT username FROM radcheck WHERE attribute = 'Cleartext-Password'")
        usernames = [row[0] for row in cursor.fetchall()]
        
        conn.close()
        
        logger.info(f"Found {len(usernames)} unique usernames in RADIUS database")
        return usernames
        
    except sqlite3.Error as e:
        logger.error(f"Database error while reading usernames: {e}")
        return []
    except Exception as e:
        logger.error(f"Unexpected error reading usernames: {e}")
        return []

def verify_with_laravel(usernames: List[str]) -> Dict[str, List[str]]:
    """
    Send usernames to Laravel API for verification
    
    Args:
        usernames: List of usernames to verify
        
    Returns:
        Dictionary with 'valid' and 'orphaned' lists
    """
    if not usernames:
        return {'valid': [], 'orphaned': []}
    
    api_endpoint = f"{LARAVEL_API_URL.rstrip('/')}/api/radius/verify-vouchers"
    
    try:
        response = requests.post(
            api_endpoint,
            json={'usernames': usernames},
            headers={
                'Authorization': f'Bearer {AUTH_TOKEN}',
                'Content-Type': 'application/json',
                'Accept': 'application/json'
            },
            timeout=60
        )
        
        if response.status_code == 200:
            data = response.json()
            return {
                'valid': data.get('valid_usernames', []),
                'orphaned': data.get('orphaned_usernames', [])
            }
        else:
            logger.error(f"Laravel API returned error: {response.status_code} - {response.text}")
            return {'valid': [], 'orphaned': []}
            
    except requests.exceptions.Timeout:
        logger.error("Request to Laravel API timed out")
        return {'valid': [], 'orphaned': []}
    except requests.exceptions.ConnectionError:
        logger.error(f"Could not connect to Laravel API: {api_endpoint}")
        return {'valid': [], 'orphaned': []}
    except Exception as e:
        logger.error(f"Error communicating with Laravel API: {e}")
        return {'valid': [], 'orphaned': []}

def delete_orphaned_vouchers(usernames: List[str]) -> int:
    """
    Delete vouchers from RADIUS database
    
    Args:
        usernames: List of usernames to delete
        
    Returns:
        Number of vouchers successfully deleted
    """
    if not usernames:
        return 0
    
    if DRY_RUN:
        logger.info(f"DRY RUN: Would delete {len(usernames)} orphaned vouchers")
        for username in usernames[:10]:  # Show first 10
            logger.info(f"  - {username}")
        if len(usernames) > 10:
            logger.info(f"  ... and {len(usernames) - 10} more")
        return len(usernames)
    
    deleted_count = 0
    
    try:
        conn = sqlite3.connect(RADIUS_DB_PATH)
        cursor = conn.cursor()
        
        # Delete from radcheck and radreply tables
        for username in usernames:
            try:
                cursor.execute("DELETE FROM radcheck WHERE username = ?", (username,))
                cursor.execute("DELETE FROM radreply WHERE username = ?", (username,))
                deleted_count += 1
                
                if deleted_count % 100 == 0:
                    logger.info(f"Deleted {deleted_count}/{len(usernames)} orphaned vouchers...")
                    
            except sqlite3.Error as e:
                logger.error(f"Failed to delete voucher {username}: {e}")
                continue
        
        conn.commit()
        conn.close()
        
        logger.info(f"Successfully deleted {deleted_count} orphaned vouchers from RADIUS")
        
        return deleted_count
        
    except sqlite3.Error as e:
        logger.error(f"Database error during deletion: {e}")
        return deleted_count
    except Exception as e:
        logger.error(f"Unexpected error during deletion: {e}")
        return deleted_count

def main():
    """Main execution function"""
    logger.info("=" * 60)
    logger.info("Starting orphaned voucher cleanup")
    logger.info("=" * 60)
    
    if DRY_RUN:
        logger.info("** DRY RUN MODE - No changes will be made **")
    
    # Step 1: Get all usernames from RADIUS
    radius_usernames = get_radius_usernames()
    
    if not radius_usernames:
        logger.info("No vouchers found in RADIUS database. Nothing to clean.")
        return
    
    # Step 2: Process in batches
    total_deleted = 0
    total_valid = 0
    
    for i in range(0, len(radius_usernames), BATCH_SIZE):
        batch = radius_usernames[i:i + BATCH_SIZE]
        batch_num = (i // BATCH_SIZE) + 1
        total_batches = (len(radius_usernames) + BATCH_SIZE - 1) // BATCH_SIZE
        
        logger.info(f"Processing batch {batch_num}/{total_batches} ({len(batch)} usernames)...")
        
        # Verify with Laravel
        result = verify_with_laravel(batch)
        
        valid_count = len(result['valid'])
        orphaned_count = len(result['orphaned'])
        
        total_valid += valid_count
        
        logger.info(f"Batch {batch_num}: {valid_count} valid, {orphaned_count} orphaned")
        
        # Delete orphaned vouchers
        if result['orphaned']:
            deleted = delete_orphaned_vouchers(result['orphaned'])
            total_deleted += deleted
    
    # Summary
    logger.info("=" * 60)
    logger.info("Cleanup Summary:")
    logger.info(f"  Total vouchers in RADIUS: {len(radius_usernames)}")
    logger.info(f"  Valid vouchers (kept): {total_valid}")
    logger.info(f"  Orphaned vouchers (deleted): {total_deleted}")
    logger.info("=" * 60)
    
    if DRY_RUN:
        logger.info("** DRY RUN completed - No actual changes made **")
    else:
        logger.info("Cleanup completed successfully")

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        logger.info("Cleanup interrupted by user")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        import traceback
        logger.error(traceback.format_exc())
        sys.exit(1)
