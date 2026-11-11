# HTTPS API

Served by gunicorn on port **5000** over HTTPS (self-signed certificate, pinned by the RADTik panel) and used only by the panel.
Every request needs `Authorization: Bearer <token>` (the `auth_token` in `scripts/config.ini`); otherwise the answer is `401`.
Bodies and answers are JSON.

```bash
TOKEN=$(sudo awk -F' = ' '/^auth_token/{print $2}' /opt/radtik-radius/scripts/config.ini)
curl -sk -H "Authorization: Bearer $TOKEN" https://localhost:5000/health
```

| Method and path | Purpose |
|---|---|
| `GET /health` | Service and database check |
| `POST /sync/vouchers` | Create vouchers (batch), optionally overwriting |
| `GET /vouchers/usernames` | All usernames, paged |
| `POST /delete/vouchers` | Delete vouchers (batch) |
| `DELETE /delete/voucher` | Delete one voucher |
| `POST /reset/voucher` | Remove a voucher's MAC binding |
| `POST /toggle/voucher-status` | Disable or enable a voucher |
| `POST /sync-mac-bindings` | Set MAC bindings (batch) |
| `GET /stats` | Counters |

## `POST /sync/vouchers`

```json
{
  "overwrite": false,
  "vouchers": [
    {
      "username": "ABC12345",
      "password": "ABC12345",
      "mikrotik_rate_limit": "5M/5M",
      "nas_identifier": "router-1",
      "mac_address": "AA:BB:CC:DD:EE:01",
      "disabled": false,
      "expiration": "2026-11-12T10:00:00Z"
    }
  ]
}
```

`username`, `password`, `mikrotik_rate_limit` and `nas_identifier` are required. `mac_address` (MAC binding), `disabled` and
`expiration` (a UTC moment; the server stores it in its local time as `Expiration`) are optional.

Answer: `{"success": true, "synced": 1, "failed": 0, "errors": []}`. If some vouchers fail the status is **207** and `errors`
lists them as `"username: reason"`.

- A voucher that already exists **with the same password and NAS** counts as synced (safe to send again).
- A different password or NAS is a conflict (`"username: Already exists with different credentials"`) unless `overwrite` is `true`.
- With `overwrite: true` the given values replace the stored ones (password, NAS, rate limit, expiry; a MAC binding that
  is stored but not sent is kept). This is what *Resync from database* uses.
- A malformed `expiration` fails only that voucher.

## `GET /vouchers/usernames?after=<username>&limit=5000`

Keyset paging, `limit` at most 5000. Answer: `{"success": true, "usernames": ["A", "B"], "next": "B"}`; `next` is `null` on the last page.

## `POST /delete/vouchers`

`{"usernames": ["ABC12345", "DEF67890"]}` (at most 1000). Answer:
`{"success": true, "requested": 2, "deleted": 1, "failed": 0, "errors": []}`. A username that does not exist counts as deleted.
All users are removed in one transaction; on a database error nothing is deleted and `errors` lists the users (status 207).

## `DELETE /delete/voucher`

`{"username": "ABC12345"}` -> `200` or `404` when the voucher does not exist.

## `POST /reset/voucher`

`{"username": "ABC12345"}` removes the MAC binding and keeps the voucher. Answer: `{"success": true, "deleted": 1}`.

## `POST /toggle/voucher-status`

`{"username": "ABC12345", "status": "disabled"}` (`"active"` enables again). `404` if the voucher does not exist.

## `POST /sync-mac-bindings`

`{"bindings": [{"username": "ABC12345", "mac_address": "AA:BB:CC:DD:EE:01"}]}` ->
`{"success": true, "synced": 1, "updated": 0, "failed": 0, "errors": []}`.

## `GET /stats`

`{"total_users": 120, "mac_bindings": 40, "radcheck_records": 380, "radreply_records": 120, "nas_identifiers": ["router-1"], "timestamp": "..."}`

## Errors

`400` invalid request, `401` missing or wrong token, `404` unknown path or voucher, `500` unexpected error (`{"success": false, "error": "..."}`).
The panel treats anything that is not the formats above as a failure and retries.
