#!/usr/bin/env bash
#
# Opens the ports a RADTik RADIUS server needs: 1812/udp and 1813/udp (RADIUS) and 5000/tcp (the panel's API).
# Run as root by install.sh.
#
#   --enable-firewall  (or RADTIK_ENABLE_FIREWALL=1)  also turns ufw ON. The SSH port(s) are allowed FIRST so you are
#                      not locked out, and the API port is opened only for the panel when its address is known:
#                      RADTIK_PANEL_IP=203.0.113.9, or RADTIK_PANEL_URL=https://panel.example.com (looked up).
#
# Without the flag ufw/firewalld only get "allow" rules and are not switched on.
set -uo pipefail

ENABLE="${RADTIK_ENABLE_FIREWALL:-0}"
for arg in "$@"; do
    [ "$arg" = "--enable-firewall" ] && ENABLE=1
done

valid_ipv4() {
    local ip="$1" octet
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -ra parts <<< "$ip"
    for octet in "${parts[@]}"; do
        [ "$octet" -le 255 ] || return 1
    done
}

PANEL_IP="${RADTIK_PANEL_IP:-}"
if [ -z "$PANEL_IP" ] && [ -n "${RADTIK_PANEL_URL:-}" ]; then
    host="${RADTIK_PANEL_URL#*://}"
    host="${host%%[:/]*}"
    PANEL_IP="$(getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1{print $1}')"
fi
if [ -n "$PANEL_IP" ] && ! valid_ipv4 "$PANEL_IP"; then
    echo "  ! The panel address '$PANEL_IP' is not a valid IPv4 address; the API port stays open to everyone." >&2
    PANEL_IP=""
fi

if command -v ufw > /dev/null 2>&1; then
    if [ "$ENABLE" = "1" ]; then
        # SSH first, so enabling the firewall cannot lock the administrator out
        ports="$(sshd -T 2>/dev/null | awk '/^port /{print $2}')"
        [ -n "$ports" ] || ports=22
        for port in $ports; do
            [[ "$port" =~ ^[0-9]{1,5}$ ]] && ufw allow "${port}/tcp" > /dev/null 2>&1
        done
    fi

    ufw allow 1812/udp > /dev/null 2>&1
    ufw allow 1813/udp > /dev/null 2>&1

    if [ "$ENABLE" = "1" ] && [ -n "$PANEL_IP" ]; then
        ufw allow from "$PANEL_IP" to any port 5000 proto tcp > /dev/null 2>&1
        echo "  -> ufw: 1812/udp, 1813/udp open; 5000/tcp only from the panel ($PANEL_IP)"
    else
        ufw allow 5000/tcp > /dev/null 2>&1
        echo "  -> ufw: 1812/udp, 1813/udp and 5000/tcp open"
        [ "$ENABLE" = "1" ] && echo "  ! The panel address is unknown, so port 5000 is open to everyone (set RADTIK_PANEL_IP or RADTIK_PANEL_URL)."
    fi

    if [ "$ENABLE" = "1" ]; then
        ufw --force enable > /dev/null 2>&1
        echo "  -> ufw is now enabled"
    fi
elif command -v firewall-cmd > /dev/null 2>&1; then
    for rule in 1812/udp 1813/udp 5000/tcp; do
        firewall-cmd --permanent --add-port="$rule" > /dev/null 2>&1
    done
    firewall-cmd --reload > /dev/null 2>&1
    echo "  -> firewalld: 1812/udp, 1813/udp and 5000/tcp open (restrict 5000 to the panel with a rich rule if you wish)"
else
    echo "  ! No firewall found. If you use one, open 1812/udp, 1813/udp and 5000/tcp (5000 only for the panel)."
fi

exit 0
