# Changelog

All notable changes to the RADTik RADIUS server are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/): MAJOR = incompatible change, MINOR = new feature, PATCH = fix.
The current version is in the [`VERSION`](VERSION) file; releases are tagged `vX.Y.Z`.

## [Unreleased]

## [1.3.0] - 2026-11-12

### Added
- `POST /vouchers/details` (read only): everything this server knows about one voucher for the panel's voucher page and
  login checker - check/reply attributes (the password only as a SHA-256), groups, the last 20 sessions with data used,
  totals, and the last 30 login attempts (accept/reject, MAC, NAS). Times are sent in UTC.

### Changed
- Messages and docs use the panel's new action names ("Trust this server", "Check connection key", "Send keys to server").
- Docs (README, INSTALL): the installation is manual and pinned to a release tag (`RADTIK_BRANCH=vX.Y.Z`); the panel has no install button.

## [1.2.0] - 2026-11-11

### Added
- `scripts/firewall.sh`, run by `install.sh`: opens 1812/udp, 1813/udp and 5000/tcp. With `--enable-firewall` (or `RADTIK_ENABLE_FIREWALL=1`)
  it also turns ufw on: the SSH port(s) are allowed first and the API port only for the panel (`RADTIK_PANEL_IP`, or looked up from
  `RADTIK_PANEL_URL`). Without the flag nothing is switched on.

### Security
- Removed the stock `localhost_ipv6` client (default secret `testing123`) from `clients.conf`; only the 127.0.0.1 client keeps it
  (used by the panel's local "Test RADIUS Auth").

## [1.1.1] - 2026-11-11

### Fixed
- **Vouchers never became active after a fresh install**: `config.ini` kept the placeholder `api_url`, so first logins were never reported
  to the panel. The panel's "Push Credentials" now writes `api_url`, and the installer accepts `RADTIK_PANEL_URL=https://your-panel`.
- Every `activation-sync.py` log line was written twice (cron output and the log file); it logs to the file only unless run in a terminal.
- A manual install left the panel showing "Unknown" for the installed commit: the installers now write `.installed_commit`.
- `install.sh` set the database path only when `config.ini.example` still had the old default.

### Added
- `activation-sync.py` sends a heartbeat (with the installed version) to the panel every minute, so the panel can warn when
  the server cannot reach it, and logs the likely cause (placeholder `api_url`, wrong token) when it cannot.

## [1.1.0] - 2026-11-11

### Added
- **Expiry is enforced by RADIUS itself.** `activation-sync.py` writes each voucher's expiry into `radcheck` as `Expiration`
  (converted to the server's local time zone). FreeRADIUS rejects the voucher after it, also while the panel is offline,
  and gives every new session a `Session-Timeout` equal to the time left.
- **Rebuild from the database.** `/sync/vouchers` accepts `overwrite`, `mac_address`, `disabled` and `expiration` per voucher;
  new `GET /vouchers/usernames` (paged username list) and `POST /delete/vouchers` (batch delete, up to 1000).
- `scripts/post-update.sh`: one idempotent script that applies an update (FreeRADIUS configuration, scheduled jobs,
  Python packages, API certificate, systemd unit) and refuses a configuration FreeRADIUS rejects.
  `update.sh` and the panel's "Apply update" both use it. `update.sh -y` runs without a prompt.
- `cron/radtik-sync`: the scheduled jobs live in the repository.
- Documentation rewritten: `docs/INSTALL.md`, `docs/API.md`, `docs/ARCHITECTURE.md`, `docs/UPDATING.md`, `SECURITY.md`.

### Changed
- `activation-sync.py` runs every minute and sends only logins the panel has not confirmed yet (state file
  `.activation-sync.state`, 10 minutes overlap) instead of the last 24 hours every time.
- Login times are sent as UTC. Before, the server's local time was sent unlabelled and the panel read it as UTC,
  which shifted every activation and expiry by the server's UTC offset on a non-UTC server.
- `sync-vouchers.py` answers per voucher; an identical voucher sent again is a success (safe retries).
- Python requirements have upper bounds. `config.ini.example` lists only the settings that are used.
- Update keeps `clients.conf`, `config.ini` and the database; `update.sh` also copies hidden files.

### Fixed
- `validate.sh` stopped at the first failed check (`set -e` with `((n++))`).
- The panel's "Apply update" did not deploy FreeRADIUS configuration changes or scheduled-job changes.
- `install.sh` opened only port 5000 in ufw/firewalld; it now also opens the RADIUS ports 1812/1813 (UDP).
- `install.sh` printed a message about a cleanup job that no longer exists.
- `sync-vouchers.py` used a different default database path than the installer.

### Security
- The password a client sends is no longer stored in `radpostauth.pass` (voucher codes in clear text, including wrong guesses).
  The column stays (schema) and is empty.

### Removed
- `cleanup-orphaned.py` and its cron job. The panel compares RADIUS with its database every night and restores or
  removes vouchers itself (`php artisan radius:reconcile`).

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

[Unreleased]: https://github.com/ahmadfoysal/radtik-radius/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/ahmadfoysal/radtik-radius/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/ahmadfoysal/radtik-radius/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/ahmadfoysal/radtik-radius/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/ahmadfoysal/radtik-radius/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ahmadfoysal/radtik-radius/releases/tag/v1.0.0
