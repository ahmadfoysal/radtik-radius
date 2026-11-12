# Security

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use GitHub's private reporting
("Security" tab -> "Report a vulnerability") on this repository, or contact the maintainer
through the profile linked from this repository. Include the version (`cat /opt/radtik-radius/VERSION`)
and steps to reproduce.

## How a RADTik RADIUS server is protected

- **API**: HTTPS on port 5000 with a self-signed certificate and a Bearer token. The RADTik panel does not
  trust a certificate authority; it pins the certificate's public key ("Trust this server").
  Allow port 5000 only from the panel's IP address in your firewall (`install.sh --enable-firewall` does this, see docs/INSTALL.md).
- **RADIUS**: UDP 1812/1813 accept requests from any address that knows the shared secret
  (`clients.conf`, generated per installation). If your routers have fixed addresses, restrict these ports to them.
- **Voucher codes are never logged**: `radpostauth.pass` is always empty and `auth_log` is off.
  Do not run FreeRADIUS with `-X` (debug output prints requests including passwords) on a live server.
- **Secrets stay out of the repository**: `scripts/config.ini` is git-ignored; `clients.conf` ships with a placeholder
  that the installer replaces.
- Updates keep `config.ini`, `clients.conf` and the database; FreeRADIUS is not restarted into a configuration it rejects.

## Supported versions

Only the latest release receives fixes. See [CHANGELOG.md](CHANGELOG.md).
