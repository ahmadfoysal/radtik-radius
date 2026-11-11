#!/usr/bin/env python3
"""
RadTik RADIUS API Server
Flask-based API server for syncing vouchers from Laravel to FreeRADIUS SQLite database.

Endpoints:
- POST /sync/vouchers - Sync batch of vouchers to RADIUS database
- DELETE /delete/voucher - Delete a voucher from RADIUS database
- GET /health - Health check endpoint

Authentication: Bearer token (configured in config.ini)
"""

import sqlite3
import configparser
import logging
import os
import sys
from datetime import datetime
from functools import wraps
from flask import Flask, request, jsonify

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)

# Load configuration
config = configparser.ConfigParser()
config_path = os.path.join(os.path.dirname(__file__), 'config.ini')

if not os.path.exists(config_path):
    logger.error(f"Configuration file not found: {config_path}")
    sys.exit(1)

config.read(config_path)

# Configuration variables
DB_PATH = config.get('radius', 'db_path', fallback='/var/lib/freeradius/radius.db')
AUTH_TOKEN = config.get('api', 'auth_token')
API_HOST = config.get('api', 'host', fallback='0.0.0.0')
API_PORT = config.getint('api', 'port', fallback=5000)
DEBUG_MODE = config.getboolean('api', 'debug', fallback=False)

# Validate configuration
if not AUTH_TOKEN or AUTH_TOKEN == 'your-secure-token-here':
    logger.error("AUTH_TOKEN not configured in config.ini! Please set a secure token.")
    sys.exit(1)

if not os.path.exists(DB_PATH):
    logger.error(f"RADIUS database not found: {DB_PATH}")
    sys.exit(1)


_MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']


def radius_expiration_value(iso_utc: str) -> str:
    """
    "2026-11-12T10:00:00Z" (UTC, as sent by Laravel) -> "Nov 12 2026 16:00:00" in THIS server's
    local clock. FreeRADIUS reads the Expiration attribute in the server's local time zone (checked
    with FreeRADIUS 3.2: the same text is 6 hours off on a UTC+6 server), so the value must be
    converted. Month names are English whatever the server locale is.
    """
    from datetime import timezone
    text = str(iso_utc).strip()
    if text.endswith('Z'):
        text = text[:-1] + '+00:00'
    moment = datetime.fromisoformat(text)
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    local = moment.astimezone()  # server local time zone
    return f"{_MONTHS[local.month - 1]} {local.day:02d} {local.year} {local:%H:%M:%S}"



def get_db_connection():
    """Get SQLite database connection"""
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        return conn
    except sqlite3.Error as e:
        logger.error(f"Database connection error: {e}")
        raise


def require_auth(f):
    """Decorator to require Bearer token authentication"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        auth_header = request.headers.get('Authorization')
        
        if not auth_header:
            logger.warning(f"Missing Authorization header from {request.remote_addr}")
            return jsonify({'error': 'Missing Authorization header'}), 401
        
        if not auth_header.startswith('Bearer '):
            logger.warning(f"Invalid Authorization format from {request.remote_addr}")
            return jsonify({'error': 'Invalid Authorization format. Use: Bearer <token>'}), 401
        
        token = auth_header.replace('Bearer ', '', 1)
        
        if token != AUTH_TOKEN:
            logger.warning(f"Invalid token from {request.remote_addr}")
            return jsonify({'error': 'Invalid authentication token'}), 401
        
        return f(*args, **kwargs)
    
    return decorated_function


@app.route('/health', methods=['GET'])
@require_auth
def health_check():
    """Health check endpoint"""
    try:
        # Test database connection
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM radcheck")
        count = cursor.fetchone()[0]
        conn.close()
        
        return jsonify({
            'status': 'healthy',
            'timestamp': datetime.now().isoformat(),
            'database': 'connected',
            'radcheck_records': count
        }), 200
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return jsonify({
            'status': 'unhealthy',
            'error': str(e)
        }), 500


@app.route('/sync/vouchers', methods=['POST'])
@require_auth
def sync_vouchers():
    """
    Sync batch of vouchers to RADIUS database
    
    Expected JSON payload:
    {
        "vouchers": [
            {
                "username": "ABC12345",
                "password": "pass123",
                "mikrotik_rate_limit": "512k/512k",
                "nas_identifier": "mikrotik-router-1"
            }
        ]
    }
    
    Returns:
    {
        "success": true,
        "synced": 250,
        "failed": 0,
        "errors": []
    }
    """
    try:
        data = request.get_json()
        
        if not data or 'vouchers' not in data:
            logger.warning(f"Invalid request payload from {request.remote_addr}")
            return jsonify({
                'success': False,
                'error': 'Missing vouchers array in request'
            }), 400
        
        vouchers = data['vouchers']
        
        if not isinstance(vouchers, list):
            return jsonify({
                'success': False,
                'error': 'vouchers must be an array'
            }), 400
        
        if len(vouchers) == 0:
            return jsonify({
                'success': True,
                'synced': 0,
                'failed': 0,
                'errors': []
            }), 200
        
        logger.info(f"Received sync request for {len(vouchers)} vouchers from {request.remote_addr}")
        
        # overwrite=true (a rebuilt server is being refilled from the database): what is in the
        # database wins, so an existing user is replaced instead of reported as a conflict.
        overwrite = bool(data.get('overwrite', False))

        synced = 0
        failed = 0
        errors = []
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        for voucher in vouchers:
            try:
                # Validate required fields
                required_fields = ['username', 'password', 'mikrotik_rate_limit', 'nas_identifier']
                missing_fields = [field for field in required_fields if field not in voucher]
                
                if missing_fields:
                    raise ValueError(f"Missing required fields: {', '.join(missing_fields)}")
                
                username = voucher['username']
                password = voucher['password']
                rate_limit = voucher['mikrotik_rate_limit']
                nas_identifier = voucher['nas_identifier']
                mac_address = voucher.get('mac_address')   # optional: MAC binding to restore
                disabled = bool(voucher.get('disabled'))   # optional: voucher is disabled
                expiration = voucher.get('expiration')     # optional: UTC moment RADIUS must reject after
                expiration_value = radius_expiration_value(expiration) if expiration else None  # ValueError if malformed

                if overwrite:
                    # Replace everything RADTik manages for this user, then write it again below.
                    # A MAC binding that RADIUS has but the database does not know yet (first login
                    # not reported yet) is kept; the database value replaces it only when it has one.
                    managed = ['Cleartext-Password', 'NAS-Identifier', 'Expiration'] + (['Calling-Station-Id'] if mac_address else [])
                    cursor.execute(
                        "DELETE FROM radcheck WHERE username = ? AND (attribute IN (%s) "
                        "OR (attribute = 'Auth-Type' AND value = 'Reject'))" % ','.join('?' * len(managed)),
                        (username, *managed)
                    )
                    cursor.execute("DELETE FROM radreply WHERE username = ? AND attribute = 'Mikrotik-Rate-Limit'", (username,))
                
                # Check if voucher already exists
                cursor.execute(
                    "SELECT COUNT(*) FROM radcheck WHERE username = ? AND attribute = 'Cleartext-Password'",
                    (username,)
                )
                exists = cursor.fetchone()[0] > 0
                
                if exists:
                    # Idempotent: the same voucher sent again (e.g. a retry after a lost
                    # answer) is a success. A different password or NAS is a real conflict.
                    cursor.execute(
                        "SELECT attribute, value FROM radcheck WHERE username = ? "
                        "AND attribute IN ('Cleartext-Password', 'NAS-Identifier')",
                        (username,)
                    )
                    current = {row[0]: row[1] for row in cursor.fetchall()}
                    if current.get('Cleartext-Password') == password and current.get('NAS-Identifier') == nas_identifier:
                        synced += 1
                        logger.info(f"Voucher {username} already exists with the same data, treated as synced")
                    else:
                        logger.warning(f"Voucher {username} already exists with different credentials")
                        errors.append(f"{username}: Already exists with different credentials")
                        failed += 1
                    continue
                
                # Insert into radcheck table (2 rows per voucher)
                # Row 1: Password
                cursor.execute(
                    "INSERT INTO radcheck (username, attribute, op, value) VALUES (?, ?, ?, ?)",
                    (username, 'Cleartext-Password', ':=', password)
                )
                
                # Row 2: NAS Identifier (for router binding)
                cursor.execute(
                    "INSERT INTO radcheck (username, attribute, op, value) VALUES (?, ?, ?, ?)",
                    (username, 'NAS-Identifier', '==', nas_identifier)
                )
                
                # Optional state that lives in RADIUS too (restored after a rebuild)
                if mac_address:
                    cursor.execute(
                        "INSERT INTO radcheck (username, attribute, op, value) VALUES (?, ?, ?, ?)",
                        (username, 'Calling-Station-Id', '==', mac_address)
                    )
                if disabled:
                    cursor.execute(
                        "INSERT INTO radcheck (username, attribute, op, value) VALUES (?, ?, ?, ?)",
                        (username, 'Auth-Type', ':=', 'Reject')
                    )
                if expiration_value:
                    cursor.execute(
                        "INSERT INTO radcheck (username, attribute, op, value) VALUES (?, ?, ?, ?)",
                        (username, 'Expiration', ':=', expiration_value)
                    )

                # Insert into radreply table (1 row per voucher)
                # MikroTik rate limit
                cursor.execute(
                    "INSERT INTO radreply (username, attribute, op, value) VALUES (?, ?, ?, ?)",
                    (username, 'Mikrotik-Rate-Limit', ':=', rate_limit)
                )
                
                synced += 1
                logger.debug(f"Successfully synced voucher: {username}")
                
            except ValueError as e:
                failed += 1
                error_msg = f"{voucher.get('username', 'unknown')}: {str(e)}"
                errors.append(error_msg)
                logger.error(f"Validation error: {error_msg}")
                
            except sqlite3.Error as e:
                failed += 1
                error_msg = f"{username}: Database error - {str(e)}"
                errors.append(error_msg)
                logger.error(f"Database error for {username}: {e}")
                
            except Exception as e:
                failed += 1
                error_msg = f"{voucher.get('username', 'unknown')}: {str(e)}"
                errors.append(error_msg)
                logger.error(f"Unexpected error: {error_msg}")
        
        # Commit all changes
        conn.commit()
        conn.close()
        
        success = failed == 0
        
        logger.info(f"Sync completed: {synced} synced, {failed} failed")
        
        return jsonify({
            'success': success,
            'synced': synced,
            'failed': failed,
            'errors': errors
        }), 200 if success else 207  # 207 Multi-Status for partial success
        
    except Exception as e:
        logger.error(f"Sync endpoint error: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/delete/voucher', methods=['DELETE'])
@require_auth
def delete_voucher():
    """
    Delete a voucher from RADIUS database
    
    Expected JSON payload:
    {
        "username": "ABC12345"
    }
    
    Returns:
    {
        "success": true,
        "message": "Voucher deleted successfully"
    }
    """
    try:
        data = request.get_json()
        
        if not data or 'username' not in data:
            return jsonify({
                'success': False,
                'error': 'Missing username in request'
            }), 400
        
        username = data['username']
        
        logger.info(f"Deleting voucher: {username}")
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Delete from radcheck
        cursor.execute("DELETE FROM radcheck WHERE username = ?", (username,))
        radcheck_deleted = cursor.rowcount
        
        # Delete from radreply
        cursor.execute("DELETE FROM radreply WHERE username = ?", (username,))
        radreply_deleted = cursor.rowcount
        
        # Delete from radpostauth
        cursor.execute("DELETE FROM radpostauth WHERE username = ?", (username,))
        radpostauth_deleted = cursor.rowcount
        
        conn.commit()
        conn.close()
        
        if radcheck_deleted == 0 and radreply_deleted == 0:
            logger.warning(f"Voucher not found: {username}")
            return jsonify({
                'success': False,
                'error': 'Voucher not found'
            }), 404
        
        logger.info(f"Voucher deleted: {username} ({radcheck_deleted} radcheck, {radreply_deleted} radreply, {radpostauth_deleted} radpostauth)")
        
        return jsonify({
            'success': True,
            'message': 'Voucher deleted successfully',
            'deleted': {
                'radcheck': radcheck_deleted,
                'radreply': radreply_deleted,
                'radpostauth': radpostauth_deleted
            }
        }), 200
        
    except Exception as e:
        logger.error(f"Delete endpoint error: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/vouchers/usernames', methods=['GET'])
@require_auth
def list_usernames():
    """
    List the usernames this RADIUS server has, page by page (keyset paging), so Laravel can
    compare them with its database (reconcile, #78).

    Query: ?after=<last username of the previous page>&limit=5000 (max 5000)

    Returns:
    {"success": true, "usernames": ["A", "B"], "next": "B"}     "next" is null on the last page
    """
    after = request.args.get('after', '')
    try:
        limit = max(1, min(int(request.args.get('limit', 5000)), 5000))
    except ValueError:
        return jsonify({'success': False, 'error': 'limit must be a number'}), 400

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT DISTINCT username FROM radcheck WHERE attribute = 'Cleartext-Password' AND username > ? "
            "ORDER BY username LIMIT ?",
            (after, limit + 1)
        )
        rows = [row[0] for row in cursor.fetchall()]
        has_more = len(rows) > limit
        usernames = rows[:limit]

        return jsonify({
            'success': True,
            'usernames': usernames,
            'next': usernames[-1] if has_more else None
        }), 200
    except Exception as e:
        logger.error(f"List usernames error: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500
    finally:
        if conn is not None:
            conn.close()


@app.route('/delete/vouchers', methods=['POST'])
@require_auth
def delete_vouchers():
    """
    Delete many vouchers from the RADIUS database with one request (#77).

    Expected JSON payload:
    {"usernames": ["ABC12345", "DEF67890"]}      (at most 1000)

    Idempotent: a username that does not exist counts as deleted. One transaction, so either
    every username is deleted or (on a database error) none and the failure is reported for all.

    Returns:
    {"success": true, "requested": 2, "deleted": 1, "failed": 0, "errors": []}
    """
    data = request.get_json(silent=True)

    if not data or not isinstance(data.get('usernames'), list):
        return jsonify({'success': False, 'error': 'Missing usernames array in request'}), 400

    usernames = [u for u in data['usernames'] if isinstance(u, str) and u]
    usernames = list(dict.fromkeys(usernames))  # unique, keep order

    if len(usernames) != len(data['usernames']) and len(usernames) == 0:
        return jsonify({'success': False, 'error': 'usernames must be non-empty strings'}), 400

    if len(usernames) > 1000:
        return jsonify({'success': False, 'error': 'At most 1000 usernames per request'}), 400

    if not usernames:
        return jsonify({'success': True, 'requested': 0, 'deleted': 0, 'failed': 0, 'errors': []}), 200

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        deleted = 0
        for username in usernames:
            cursor.execute("DELETE FROM radcheck WHERE username = ?", (username,))
            found = cursor.rowcount
            cursor.execute("DELETE FROM radreply WHERE username = ?", (username,))
            found += cursor.rowcount
            cursor.execute("DELETE FROM radpostauth WHERE username = ?", (username,))
            if found > 0:
                deleted += 1

        conn.commit()
        logger.info(f"Batch delete: {len(usernames)} requested, {deleted} existed and were deleted")

        return jsonify({
            'success': True,
            'requested': len(usernames),
            'deleted': deleted,
            'failed': 0,
            'errors': []
        }), 200

    except Exception as e:
        if conn is not None:
            conn.rollback()
        logger.error(f"Batch delete failed, nothing deleted: {e}")
        return jsonify({
            'success': False,
            'requested': len(usernames),
            'deleted': 0,
            'failed': len(usernames),
            'errors': [f"{u}: {str(e)}" for u in usernames[:50]]
        }), 207
    finally:
        if conn is not None:
            conn.close()


@app.route('/reset/voucher', methods=['POST'])
@require_auth
def reset_voucher():
    """Remove a voucher's Calling-Station-Id binding without deleting it."""
    try:
        data = request.get_json()
        if not data or 'username' not in data:
            return jsonify({
                'success': False,
                'error': 'Missing username in request'
            }), 400

        username = data['username']
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "DELETE FROM radcheck WHERE username = ? AND attribute = 'Calling-Station-Id'",
            (username,)
        )
        deleted = cursor.rowcount
        conn.commit()
        conn.close()

        logger.info(f"Reset MAC binding for {username}: {deleted} row(s) removed")

        return jsonify({
            'success': True,
            'message': 'Voucher MAC binding reset successfully',
            'deleted': deleted,
        }), 200
    except Exception as e:
        logger.error(f"Reset voucher endpoint error: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/toggle/voucher-status', methods=['POST'])
@require_auth
def toggle_voucher_status():
    """
    Enable or disable a voucher in RADIUS database
    
    When disabling: Adds Auth-Type = Reject to block authentication
    When enabling: Removes Auth-Type = Reject to allow authentication
    
    Expected JSON payload:
    {
        "username": "ABC12345",
        "status": "disabled"  // or "active"
    }
    
    Returns:
    {
        "success": true,
        "message": "Voucher status updated successfully",
        "status": "disabled"
    }
    """
    try:
        data = request.get_json()
        
        if not data or 'username' not in data or 'status' not in data:
            return jsonify({
                'success': False,
                'error': 'Missing username or status in request'
            }), 400
        
        username = data['username']
        status = data['status']
        
        if status not in ['active', 'disabled']:
            return jsonify({
                'success': False,
                'error': 'Invalid status. Must be "active" or "disabled"'
            }), 400
        
        logger.info(f"Toggling voucher status: {username} → {status}")
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Check if voucher exists
        cursor.execute(
            "SELECT COUNT(*) FROM radcheck WHERE username = ? AND attribute = 'Cleartext-Password'",
            (username,)
        )
        exists = cursor.fetchone()[0] > 0
        
        if not exists:
            conn.close()
            return jsonify({
                'success': False,
                'error': 'Voucher not found in RADIUS database'
            }), 404
        
        if status == 'disabled':
            # Check if Auth-Type Reject already exists
            cursor.execute(
                "SELECT COUNT(*) FROM radcheck WHERE username = ? AND attribute = 'Auth-Type' AND value = 'Reject'",
                (username,)
            )
            reject_exists = cursor.fetchone()[0] > 0
            
            if not reject_exists:
                # Add Auth-Type = Reject to disable authentication
                cursor.execute(
                    "INSERT INTO radcheck (username, attribute, op, value) VALUES (?, ?, ?, ?)",
                    (username, 'Auth-Type', ':=', 'Reject')
                )
                conn.commit()
                logger.info(f"Voucher disabled: {username} (Auth-Type = Reject added)")
            else:
                logger.info(f"Voucher already disabled: {username}")
        else:
            # status == 'active'
            # Remove Auth-Type = Reject to enable authentication
            cursor.execute(
                "DELETE FROM radcheck WHERE username = ? AND attribute = 'Auth-Type' AND value = 'Reject'",
                (username,)
            )
            deleted_count = cursor.rowcount
            conn.commit()
            
            if deleted_count > 0:
                logger.info(f"Voucher enabled: {username} (Auth-Type = Reject removed)")
            else:
                logger.info(f"Voucher already enabled: {username}")
        
        conn.close()
        
        return jsonify({
            'success': True,
            'message': 'Voucher status updated successfully',
            'status': status
        }), 200
        
    except Exception as e:
        logger.error(f"Toggle status endpoint error: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/sync-mac-bindings', methods=['POST'])
@require_auth
def sync_mac_bindings():
    """
    Sync MAC address bindings from MikroTik to RADIUS database
    
    Expected JSON payload:
    {
        "bindings": [
            {
                "username": "ABC12345",
                "mac_address": "AA:BB:CC:DD:EE:FF",
                "profile": "default"
            }
        ]
    }
    
    Returns:
    {
        "success": true,
        "synced": 10,
        "updated": 5,
        "failed": 0,
        "errors": []
    }
    """
    try:
        data = request.get_json()
        
        if not data or 'bindings' not in data:
            logger.warning(f"Invalid MAC binding request from {request.remote_addr}")
            return jsonify({
                'success': False,
                'error': 'Missing bindings array in request'
            }), 400
        
        bindings = data['bindings']
        
        if not isinstance(bindings, list):
            return jsonify({
                'success': False,
                'error': 'bindings must be an array'
            }), 400
        
        if len(bindings) == 0:
            return jsonify({
                'success': True,
                'synced': 0,
                'updated': 0,
                'failed': 0,
                'errors': []
            }), 200
        
        logger.info(f"Received MAC binding sync request for {len(bindings)} users from {request.remote_addr}")
        
        synced = 0  # New records inserted
        updated = 0  # Existing records updated
        failed = 0
        errors = []
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        for binding in bindings:
            try:
                # Validate required fields
                if 'username' not in binding or 'mac_address' not in binding:
                    raise ValueError("Missing username or mac_address")
                
                username = binding['username']
                mac_address = binding['mac_address']
                
                # Check if MAC binding already exists for this user
                cursor.execute(
                    "SELECT id, value FROM radcheck WHERE username = ? AND attribute = 'Calling-Station-Id'",
                    (username,)
                )
                existing = cursor.fetchone()
                
                if existing:
                    # Update existing MAC binding
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
                        synced += 1  # Count as synced even though no change
                else:
                    # Insert new MAC binding
                    cursor.execute(
                        "INSERT INTO radcheck (username, attribute, op, value) VALUES (?, ?, ?, ?)",
                        (username, 'Calling-Station-Id', '==', mac_address)
                    )
                    synced += 1
                    logger.info(f"Added MAC binding for {username}: {mac_address}")
                
            except ValueError as e:
                failed += 1
                error_msg = f"{binding.get('username', 'unknown')}: {str(e)}"
                errors.append(error_msg)
                logger.error(f"Validation error: {error_msg}")
                
            except sqlite3.Error as e:
                failed += 1
                error_msg = f"{username}: Database error - {str(e)}"
                errors.append(error_msg)
                logger.error(f"Database error for {username}: {e}")
                
            except Exception as e:
                failed += 1
                error_msg = f"{binding.get('username', 'unknown')}: {str(e)}"
                errors.append(error_msg)
                logger.error(f"Unexpected error: {error_msg}")
        
        # Commit all changes
        conn.commit()
        conn.close()
        
        success = failed == 0
        
        logger.info(f"MAC binding sync completed: {synced} new, {updated} updated, {failed} failed")
        
        return jsonify({
            'success': success,
            'synced': synced,
            'updated': updated,
            'failed': failed,
            'errors': errors
        }), 200 if success else 207  # 207 Multi-Status for partial success
        
    except Exception as e:
        logger.error(f"MAC binding sync endpoint error: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/stats', methods=['GET'])
@require_auth
def get_stats():
    """Get RADIUS database statistics"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Count unique users
        cursor.execute("SELECT COUNT(DISTINCT username) FROM radcheck WHERE attribute = 'Cleartext-Password'")
        total_users = cursor.fetchone()[0]
        
        # Count MAC bindings
        cursor.execute("SELECT COUNT(*) FROM radcheck WHERE attribute = 'Calling-Station-Id'")
        mac_bindings_count = cursor.fetchone()[0]
        
        # Count total records
        cursor.execute("SELECT COUNT(*) FROM radcheck")
        radcheck_count = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM radreply")
        radreply_count = cursor.fetchone()[0]
        
        # Get NAS identifiers
        cursor.execute("SELECT DISTINCT value FROM radcheck WHERE attribute = 'NAS-Identifier'")
        nas_identifiers = [row[0] for row in cursor.fetchall()]
        
        conn.close()
        
        return jsonify({
            'total_users': total_users,
            'mac_bindings': mac_bindings_count,
            'radcheck_records': radcheck_count,
            'radreply_records': radreply_count,
            'nas_identifiers': nas_identifiers,
            'timestamp': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        logger.error(f"Stats endpoint error: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.errorhandler(404)
def not_found(e):
    """Handle 404 errors"""
    return jsonify({
        'error': 'Endpoint not found',
        'available_endpoints': [
            'GET /health',
            'POST /sync/vouchers',
            'POST /sync-mac-bindings',
            'DELETE /delete/voucher',
            'GET /stats'
        ]
    }), 404


@app.errorhandler(500)
def internal_error(e):
    """Handle 500 errors"""
    logger.error(f"Internal server error: {e}")
    return jsonify({
        'error': 'Internal server error',
        'message': str(e)
    }), 500


def main():
    """Main entry point"""
    logger.info("=" * 60)
    logger.info("RadTik RADIUS API Server Starting")
    logger.info("=" * 60)
    logger.info(f"Database: {DB_PATH}")
    logger.info(f"Listening on: {API_HOST}:{API_PORT}")
    logger.info(f"Debug mode: {DEBUG_MODE}")
    logger.info("Endpoints:")
    logger.info("  - GET  /health              (Health check)")
    logger.info("  - POST /sync/vouchers       (Sync vouchers)")
    logger.info("  - POST /sync-mac-bindings   (Sync MAC bindings)")
    logger.info("  - DELETE /delete/voucher    (Delete voucher)")
    logger.info("  - GET  /stats               (Database stats)")
    logger.info("=" * 60)
    
    # Run Flask app
    app.run(
        host=API_HOST,
        port=API_PORT,
        debug=DEBUG_MODE,
        threaded=True
    )


if __name__ == '__main__':
    main()
