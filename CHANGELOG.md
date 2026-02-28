# Changelog

All notable changes to the RadTik FreeRADIUS installer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Added systemd service override configuration to grant FreeRADIUS write access to SQLite directory
- Installer now automatically creates `/etc/systemd/system/freeradius.service.d/sqlite-write-access.conf`
- Resolves SQLite write permission issues on systems with restricted systemd service configurations
- Ensures `/etc/freeradius/3.0/sqlite/` directory is writable by FreeRADIUS daemon

## [1.0.0] - 2026-02-15

### Added

- Initial release of RadTik FreeRADIUS installer
- One-command installation script for Ubuntu 22.04 LTS
- FreeRADIUS 3.0 with SQLite backend configuration
- Production-ready SQLite database template:
    - Enhanced radpostauth table with MAC tracking columns (calling_station_id, nas_identifier)
    - Sync processing flag (processed) for Laravel integration
    - WAL mode pre-enabled for better performance
    - Performance indexes pre-configured
    - Clean state with no test data
- Python synchronization scripts for Laravel integration
    - Voucher synchronization (every 2 minutes)
    - Activation monitoring with MAC binding (every 1 minute)
    - Deleted users cleanup (every 5 minutes)
- Automated cron job setup
- Validation script (validate.sh) for installation verification
- SQLite optimizations (WAL mode, indexes, busy timeout)
- MikroTik client configuration
- Comprehensive documentation:
    - README.md with badges and structure
    - QUICKSTART.md for quick setup
    - CONTRIBUTING.md for contributors
    - DATABASE.md for database details
- Pre-configured database schema with:
    - radcheck table for authentication
    - radreply table for response attributes
    - radacct table for accounting
    - radpostauth table with RadTik enhancements

### Security

- Added .gitignore to prevent committing secrets
- Configurable API authentication via tokens
- Encrypted communication with Laravel API
- Proper file permissions for freerad user

## [1.1.0] - 2026-02-17

### Added

- **Flask API Server** for real-time voucher synchronization
    - POST /sync/vouchers endpoint for pushing vouchers from Laravel
    - DELETE /delete/voucher endpoint for removing vouchers
    - GET /health endpoint for monitoring
    - GET /stats endpoint for database statistics
    - Bearer token authentication with OpenSSL-generated tokens
    - Gunicorn production WSGI server (4 workers)
    - Systemd service (radtik-radius-api.service) with auto-start
    - Comprehensive error handling and logging
- API_QUICKSTART.md guide for rapid API server setup
- Production-ready deployment on port 5000
- Automatic firewall configuration (ufw allow 5000/tcp)

### Changed

- **Unified installation script**: Consolidated install.sh and install-api.sh into single installer
- **Non-interactive installation**: Removed all user prompts - full stack installs automatically
- Made API server installation mandatory (no optional components)
- Made legacy sync scripts mandatory (comprehensive monitoring)
- Updated QUICKSTART.md with simplified installation flow
- Updated README.md with API server architecture
- Enhanced scripts/README.md with API endpoint documentation

### Improved

- Installation process now requires zero user interaction
- Single command setup: `sudo bash install.sh`
- Automatic service enablement on boot
- Better error messages during installation
- Comprehensive final summary with test commands

### Fixed

- Installation script now validates API server health before completion
- Proper service dependencies and ordering

## [Unreleased]

### Planned

- Support for multiple database backends (MySQL, PostgreSQL)
- Web-based configuration interface
- Enhanced monitoring and alerting
- Rate limiting configuration per profile
- Multi-tenancy support for ISPs
- API rate limiting and throttling
- WebSocket support for real-time updates
