# Changelog

All notable changes to the RadTik FreeRADIUS installer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-15

### Added
- Initial release of RadTik FreeRADIUS installer
- One-command installation script for Ubuntu 22.04 LTS
- FreeRADIUS 3.0 with SQLite backend configuration
- Python synchronization scripts for Laravel integration
  - Voucher synchronization (every 2 minutes)
  - Activation monitoring with MAC binding (every 1 minute)
  - Deleted users cleanup (every 5 minutes)
- Automated cron job setup
- SQLite optimizations (WAL mode, indexes, busy timeout)
- MikroTik client configuration
- Comprehensive documentation (README, QUICKSTART)
- Pre-configured database schema with:
  - radcheck table for authentication
  - radreply table for response attributes
  - radacct table for accounting
  - radpostauth table for authentication logs

### Security
- Added .gitignore to prevent committing secrets
- Configurable API authentication via tokens
- Encrypted communication with Laravel API
- Proper file permissions for freerad user

## [Unreleased]

### Planned
- Support for multiple database backends (MySQL, PostgreSQL)
- Web-based configuration interface
- Enhanced monitoring and alerting
- Rate limiting configuration per profile
- Multi-tenancy support for ISPs
