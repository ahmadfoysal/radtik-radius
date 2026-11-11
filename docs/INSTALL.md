# Installation

## Requirements

- A server (VPS) with a public IP address, **Ubuntu 22.04 LTS**, root or sudo access, 1 vCPU / 1 GB RAM is enough for a few thousand vouchers.
- A RADTik panel account (the panel creates the API token and the shared secret).
- Open ports: see the table in the [README](../README.md#install).

## Firewall

The installer opens 1812/udp, 1813/udp and 5000/tcp in ufw or firewalld but does **not** switch the firewall on. To switch ufw on, with the API
reachable only from the panel (SSH is allowed first, so you are not locked out):

```bash
sudo RADTIK_PANEL_URL=https://your-panel.example.com bash /opt/radtik-radius/install.sh --enable-firewall
# or, when you know the panel server's IP:  RADTIK_PANEL_IP=203.0.113.9 ... --enable-firewall
```

## 1. Install the server

The installation is **manual**: the panel connects to the server afterwards and manages it, it does not install it. As root, install a release tag
(replace `X.Y.Z`; the panel's *Setup Guide* shows the exact command for its version):

```bash
curl -fsSL https://raw.githubusercontent.com/ahmadfoysal/radtik-radius/vX.Y.Z/bootstrap-install.sh \
  | sudo RADTIK_BRANCH=vX.Y.Z RADTIK_PANEL_URL=https://your-panel.example.com bash
```

The installer: installs FreeRADIUS, SQLite and Python packages; deploys the configuration; generates a **unique RADIUS shared secret**
and a **random API token**; creates the API's self-signed certificate; installs the systemd service `radtik-radius-api`;
opens ports 1812/1813/5000 in ufw or firewalld if one is present; installs the cron job (`/etc/cron.d/radtik-sync`).

At the end it prints the API token and the shared secret. Keep them; they are also stored in `/opt/radtik-radius/scripts/config.ini`
and `/etc/freeradius/3.0/clients.conf`.

## 2. Connect it to the panel

On the server's page in the panel:

1. **Test SSH Connection**.
2. **Fetch API certificate**. The panel pins the API's public key; nothing is sent to the API before this is done.
3. **Verify Token Sync**. If the token differs, press **Push Credentials** (it writes the panel's token and secret to the server and restarts the services).
4. **Panel address.** `activation-sync.py` reports first logins to `[laravel] api_url` in `/opt/radtik-radius/scripts/config.ini`. **Push Credentials** (step 3)
   writes the panel's address (its `APP_URL`) there. Alternatively install with `RADTIK_PANEL_URL=https://your-panel.example.com` set,
   or edit the file by hand. Without it vouchers never become active. Once a minute the server also tells the panel it is alive;
   if the panel has not heard from it for 10 minutes the server's page shows a warning.
5. **Test RADIUS Auth** to check FreeRADIUS answers.

## 3. Connect a router

In the panel, open the router, choose this RADIUS server and press **Apply RADIUS Config**, then **Check Status**. The router needs
hotspot authentication through RADIUS and must be reachable from the panel through its API port (8728, or 8729 with SSL), because
the panel disconnects users of expired vouchers through it.

By hand on a MikroTik (the `secret` is the shared secret from `clients.conf`):

```
/radius add service=hotspot address=<radius-server-ip> secret=<shared-secret> timeout=3s
/ip hotspot profile set [find] use-radius=yes
```

## 4. Check the installation

On the server:

```bash
sudo bash /opt/radtik-radius/validate.sh          # all checks, with a summary
sudo systemctl status freeradius radtik-radius-api
TOKEN=$(sudo awk -F' = ' '/^auth_token/{print $2}' /opt/radtik-radius/scripts/config.ini)
curl -sk -H "Authorization: Bearer $TOKEN" https://localhost:5000/health
```

Logs: `/var/log/freeradius/radius.log`, `/var/log/radtik-radius-error.log` (API), `/var/log/radtik-activation-sync.log` (shows "Cannot reach the panel ..." or "api_url ... placeholder" when the address is wrong).

## Rebuilding or reinstalling a server

The panel's database is the source of truth, so a lost server can be refilled:

1. Install the new server. Use the **same API token and shared secret** as before (press **Push Credentials** in the panel).
2. **Fetch API certificate** again (the new server has a new certificate) and, if the panel complains, reset the SSH host key on the server's Edit page.
3. Press **Resync from database**. Every live voucher is sent again, including passwords, rate limits, MAC bindings, disabled state and expiry.
4. **Compare now** should report nothing missing.

What cannot be restored: the accounting history (`radacct`) and login logs of the old server.

## Troubleshooting

| Symptom | Check |
|---|---|
| Panel says the API is unreachable | port 5000 open from the panel's IP; `systemctl status radtik-radius-api`; the certificate was fetched |
| Panel and server disagree on the token | **Verify Token Sync**, then **Push Credentials** |
| Users cannot log in | `freeradius -CX` (configuration), router's RADIUS secret equals `clients.conf`, router's NAS identifier equals the one in the panel |
| Vouchers do not become *active* after the first login | `tail /var/log/radtik-activation-sync.log`; `api_url` and `auth_token` in `config.ini` |
| Expiry is off by hours | the server's time zone is handled; check the server clock (`timedatectl`) |
