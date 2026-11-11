# RADTik RADIUS Server

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![FreeRADIUS](https://img.shields.io/badge/FreeRADIUS-3.x-blue.svg)](https://freeradius.org/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20LTS-orange.svg)](https://ubuntu.com/)

The RADIUS side of **RADTik**, a WiFi voucher platform for hotspot operators. It installs and runs
[FreeRADIUS](https://freeradius.org/) with a SQLite backend plus a small HTTPS API that the RADTik panel uses to
create, remove and check voucher users. MikroTik routers authenticate hotspot users against it.

> This repository is published automatically from the main RADTik project. Please report problems as issues here;
> changes are made upstream, so pull requests cannot be merged directly.

## What you get

- FreeRADIUS 3 configured for hotspot vouchers (`Cleartext-Password`, `NAS-Identifier` binding, MAC binding, rate limits).
- An HTTPS API (gunicorn + Flask) for the panel: batch sync, batch delete, enable/disable, MAC reset, username list, statistics.
- **Expiry enforced by RADIUS itself**: after a voucher's expiry FreeRADIUS rejects it even if the panel is offline, and
  sessions get a `Session-Timeout` so the router disconnects the user on time.
- A login reporter (`activation-sync.py`, every minute) that tells the panel when a voucher is first used.
- A rebuildable server: the panel's database is the source of truth, so a lost or reinstalled server can be refilled with one click.
- Safe updates (backup, protected configuration, config check before restart) and semantic versioning.

## Install

**From the RADTik panel (recommended):** add the server (IP, SSH user) under *RADIUS servers* and press *Install*.

**Manually, on a fresh Ubuntu 22.04 server, as root:**

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadfoysal/radtik-radius/main/bootstrap-install.sh | sudo bash
```

Then connect it to the panel; see [docs/INSTALL.md](docs/INSTALL.md) (about 10 minutes).

| Port | Protocol | Used by | Who should reach it |
|---|---|---|---|
| 1812, 1813 | UDP | RADIUS authentication / accounting | your MikroTik routers |
| 5000 | TCP (HTTPS) | RADTik API | the RADTik panel only |
| 22 | TCP | SSH (install, updates) | the RADTik panel / you |

## Documentation

| | |
|---|---|
| [docs/INSTALL.md](docs/INSTALL.md) | Requirements, installation, connecting to the panel and a router, rebuilding a server |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How vouchers, logins, expiry and deletion flow between panel and RADIUS |
| [docs/API.md](docs/API.md) | The HTTPS API |
| [docs/UPDATING.md](docs/UPDATING.md) | Versions, updating, rolling back |
| [sqlite/DATABASE.md](sqlite/DATABASE.md) | The database schema |
| [SECURITY.md](SECURITY.md) | Reporting problems, hardening |
| [CHANGELOG.md](CHANGELOG.md) | What changed in each version |

## Versioning

[Semantic Versioning](https://semver.org/). The version is in [`VERSION`](VERSION), changes are in the
[changelog](CHANGELOG.md), and every version is tagged `vX.Y.Z`. The panel shows the installed version
(for example `1.1.0 · abc1234`) and offers updates.

## Repository layout

```
bootstrap-install.sh      one-line installer (clones this repository, runs install.sh)
install.sh                full installation: FreeRADIUS, API, cron, firewall
update.sh                 manual update with backup (the panel uses the same steps)
validate.sh               checks a finished installation
clients.conf              RADIUS clients (the shared secret is generated at install time)
mods-available/ mods-config/ sites-enabled/   FreeRADIUS configuration deployed by install/update
sqlite/                   database template and schema notes
cron/radtik-sync          scheduled jobs (installed to /etc/cron.d)
radtik-radius-api.service systemd unit of the API
requirements.txt          Python packages
scripts/
  sync-vouchers.py        the HTTPS API
  activation-sync.py      reports first logins to the panel, writes expiry into RADIUS
  post-update.sh          applies an update to the running system (idempotent)
  ensure-api-tls.sh       creates the API's self-signed certificate
  config.ini.example      configuration template (config.ini is created by the installer and never committed)
docs/                     documentation
```

## License

[MIT](LICENSE)
