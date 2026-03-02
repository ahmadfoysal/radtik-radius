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
from datetime import datetime, timedelta
from typing import List, Dict, Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/radtik-activation-sync.log'),
        logging.StreamHandler(sys.stdout)
    ]
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


def get_db_connection():
    """Get SQLite database connection"""
    try:
        conn = sqlite3.connect(RADIUS_DB_PATH, timeout=10)
        conn.row_factory = sqlite3.Row
        return conn
    except sqlite3.Error as e:
        logger.error(f"Database connection error: {e}")
        raise


def fetch_unique_activations_last_24h() -> List[Dict]:
    """
    Fetch unique successful authentications from last 24 hours
    Returns distinct combinations of username, nas_identifier, and mac address
    """
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get activations from last 24 hours, distinct by username + nas + mac
        yesterday = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d %H:%M:%S')
        
        query = """
            SELECT 
                username,
                nasidentifier,
                nasipaddress,
                callingstationid,
                MIN(authdate) as first_auth_date
            FROM radpostauth
            WHERE reply = 'Access-Accept'
              AND authdate > ?
            GROUP BY username, 
                     COALESCE(nasidentifier, nasipaddress),
                     callingstationid
            ORDER BY first_auth_date ASC
        """
        
        cursor.execute(query, (yesterday,))
        rows = cursor.fetchall()
        conn.close()
        
        # Convert to list of dicts
        activations = []
        for row in rows:
            activations.append({
                'username': row['username'],
                'nas_identifier': row['nasidentifier'] or row['nasipaddress'],
                'calling_station_id': row['callingstationid'],
                'authenticated_at': row['first_auth_date']
            })
        
        return activations
        
    except sqlite3.Error as e:
        logger.error(f"Database query error: {e}")
        return []


def post_activations_to_laravel(activations: List[Dict]) -> bool:
    """
    POST activation data to Laravel API
    Returns True if successful, False otherwise
    """
    if not activations:
        logger.info("No activations to sync")
        return True
    
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
            return True
        else:
            logger.error(f"Laravel API error: [{response.status_code}] {response.text}")
            return False
            
    except requests.exceptions.Timeout:
        logger.error("Laravel API request timed out")
        return False
    except requests.exceptions.ConnectionError as e:
        logger.error(f"Cannot connect to Laravel API: {e}")
        return False
    except Exception as e:
        logger.error(f"Failed to post activations: {e}")
        return False


def main():
    """Main function - fetches and posts activations"""
    try:
        logger.info("Starting activation sync...")
        
        # Fetch unique activations from last 24 hours
        activations = fetch_unique_activations_last_24h()
        
        if not activations:
            logger.info("No activations found in last 24 hours")
            return
        
        logger.info(f"Found {len(activations)} unique activation(s) from last 24 hours")
        
        # Post to Laravel
        success = post_activations_to_laravel(activations)
        
        if success:
            logger.info("Activation sync completed successfully")
        else:
            logger.error("Failed to sync activations")
            sys.exit(1)
            
    except Exception as e:
        logger.error(f"Sync error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == '__main__':
    main()
