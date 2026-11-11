# Versions and updates

## Versioning

RADTik RADIUS follows [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.

- **PATCH**: bug and security fixes, no action needed beyond updating.
- **MINOR**: new features that keep working with the previous panel and API.
- **MAJOR**: incompatible change; the changelog says what to do.

The version is in [`VERSION`](../VERSION) (`cat /opt/radtik-radius/VERSION` on a server), every release is tagged `vX.Y.Z`
on GitHub, and [CHANGELOG.md](../CHANGELOG.md) lists the changes of each version.

**Order of updates:** update the RADIUS servers first, then the panel. A newer RADIUS server works with an older panel; a newer
panel may use API features that an older server does not have yet (for example the nightly comparison needs `GET /vouchers/usernames`, version 1.1.0).

## Update from the panel (recommended)

Open the server's page -> **Check for Updates**. The panel shows the installed and the latest version (for example `1.1.0 · abc1234`;
an update is offered whenever the latest commit differs from the installed one) -> **Apply Update**. The panel:

1. creates a backup at `/opt/radtik-radius-backup-<time>`,
2. keeps `scripts/config.ini`, `clients.conf` and `sqlite/radius.db`,
3. downloads exactly the commit it checked and copies it to `/opt/radtik-radius`,
4. runs `scripts/post-update.sh`, which deploys the FreeRADIUS configuration and the cron file, updates the Python packages,
   keeps the API certificate permissions right, installs the systemd unit and **checks the FreeRADIUS configuration**,
5. restarts the services and verifies that both are running.

If the configuration check fails nothing is restarted and the old services keep running.

## Update manually

```bash
git clone https://github.com/ahmadfoysal/radtik-radius.git /tmp/radtik-radius-new
sudo bash /tmp/radtik-radius-new/update.sh        # add -y to skip the confirmation
```

To update to a specific release: `git clone --branch v1.1.0 ...`.

## Roll back

Both ways keep a backup. To restore it:

```bash
sudo systemctl stop radtik-radius-api freeradius
sudo mv /opt/radtik-radius /opt/radtik-radius.failed
sudo mv /opt/radtik-radius-backup-<time> /opt/radtik-radius
sudo bash /opt/radtik-radius/scripts/post-update.sh freerad     # puts the old FreeRADIUS files back
sudo systemctl start freeradius radtik-radius-api
```

## For maintainers: releasing

1. Change the code. Add the user-visible changes under `## [Unreleased]` in `CHANGELOG.md`.
2. To release: set the new number in `VERSION`, rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD`, add a fresh empty `[Unreleased]`
   and update the compare links at the bottom.
3. Merge to `main` of the RADTik project. This repository is updated automatically; when `VERSION` is new, the tag and release
   `vX.Y.Z` are created and the commit is titled `Release vX.Y.Z` with the changelog notes in its message.
