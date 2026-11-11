# Architecture

```
                 HTTPS :5000 (Bearer token, pinned certificate)
  RADTik panel  ─────────────────────────────────────────────►  API (gunicorn, sync-vouchers.py)
  (Laravel)     ◄─────────────────────────────────────────────   │ writes radcheck / radreply
       ▲          HTTPS: POST /api/radius/activations            ▼
       │                                                    SQLite (radius.db) ◄──── FreeRADIUS (UDP 1812/1813)
       │ RouterOS API (disconnect sessions)                                                ▲
       ▼                                                                                   │ Access-Request
   MikroTik router(s) ─────────────────────────────────────────────────────────────────────┘
```

The panel owns the data. This server holds a copy that FreeRADIUS can read, and can always be refilled from the panel.

## Components

| Part | What it does |
|---|---|
| FreeRADIUS 3 | Answers `Access-Request` from the routers using the SQL module and SQLite (`radcheck`, `radreply`, `radpostauth`). The `expiration` module enforces `Expiration`. |
| `sync-vouchers.py` | The HTTPS API the panel calls. See [API.md](API.md). |
| `activation-sync.py` | Cron job, every minute. Reports new logins to the panel and writes the expiry the panel answers with into RADIUS. |
| `post-update.sh` | Applies an update to the running system ([UPDATING.md](UPDATING.md)). |

## What a voucher looks like in the database

| Table | Attribute | Meaning |
|---|---|---|
| `radcheck` | `Cleartext-Password := <code>` | the voucher code is the password |
| `radcheck` | `NAS-Identifier == <router>` | a voucher works only on its router |
| `radcheck` | `Calling-Station-Id == <MAC>` | MAC binding (profiles with binding, set after the first login) |
| `radcheck` | `Auth-Type := Reject` | the voucher is disabled |
| `radcheck` | `Expiration := Nov 12 2026 16:00:00` | expiry, **in this server's local time** |
| `radreply` | `Mikrotik-Rate-Limit := 5M/5M` | speed limit |

## Flows

**Creating vouchers.** The panel stores them (status *inactive*) and sends them in batches to `POST /sync/vouchers`.
The API answers per voucher (HTTP 207 when some failed); sending the same voucher again is harmless.

**First login.** FreeRADIUS accepts and logs the login in `radpostauth` (username, NAS, MAC, time; never the password).
Within a minute `activation-sync.py` posts new logins (times in UTC) to the panel. The panel starts the voucher's validity
from that first login and answers with the expiry; the script writes it as `Expiration`.

**Expiry.** From the moment of `Expiration` FreeRADIUS rejects the voucher, with or without the panel. While it is still valid,
every new session gets `Session-Timeout` = time left, so the router cuts the session on time. The panel additionally removes
the user's session and login cookie on the router and then deletes the voucher.
Limit: if the panel is offline at the very first login, RADIUS learns the expiry only once the panel has confirmed that login.

**Deleting.** The panel deletes in its own database first and then removes users here in batches (`POST /delete/vouchers`),
retrying until it succeeds.

**Rebuilding.** The panel compares the username list (`GET /vouchers/usernames`) with its database every night, restores
what is missing and reports users that exist only here. *Resync from database* sends everything again. See [INSTALL.md](INSTALL.md#rebuilding-or-reinstalling-a-server).

## Time zones

The panel and the API use UTC. FreeRADIUS reads `Expiration` and writes `radpostauth.authdate` in the **server's local time**,
so `activation-sync.py` converts both ways. The server's time zone can be anything; its clock must be correct (`timedatectl`).
