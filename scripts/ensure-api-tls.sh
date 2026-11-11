#!/bin/bash
#
# Create the self-signed TLS certificate for the RadTik RADIUS API (#33),
# if it does not exist yet. The Laravel panel does not trust it through a
# certificate authority: it pins the certificate's public key, which it
# reads over the (host-key-pinned) SSH connection ("Fetch API certificate").
#
# Safe to run more than once. Run as root.
set -euo pipefail

TLS_DIR="/opt/radtik-radius/tls"
CERT="$TLS_DIR/api.crt"
KEY="$TLS_DIR/api.key"
SERVICE_USER="${1:-freerad}"

mkdir -p "$TLS_DIR"

if [ ! -s "$CERT" ] || [ ! -s "$KEY" ]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$KEY" -out "$CERT" \
        -subj "/CN=radtik-radius-api" >/dev/null 2>&1
    echo "  → Created self-signed API certificate: $CERT"
else
    echo "  → API certificate already exists: $CERT"
fi

chown root:"$SERVICE_USER" "$TLS_DIR" "$KEY" "$CERT"
chmod 750 "$TLS_DIR"
chmod 640 "$KEY"
chmod 644 "$CERT"
