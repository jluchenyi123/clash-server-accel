#!/usr/bin/env bash
# Enable the mihomo TUN system-wide proxy (requires sudo)
# Requirements: Linux with systemd + systemd-resolved + NetworkManager
# Keeps LAN/Tailscale traffic direct; DNS through mihomo; 5-minute auto-rollback
set -uo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Run with sudo: sudo bash $0"
    exit 1
fi

SVC_USER="${CLASH_USER:-${SUDO_USER:-}}"
if [[ -z "$SVC_USER" || "$SVC_USER" == "root" ]]; then
    echo "Cannot determine the non-root user for mihomo."
    echo "Run from your account: sudo bash $0"
    exit 1
fi

SVC_HOME="$(getent passwd "$SVC_USER" | cut -d: -f6)"
SVC_GROUP="$(id -gn "$SVC_USER")"
SVC_UID="$(id -u "$SVC_USER")"
SVC_RUNTIME="/run/user/$SVC_UID"
DIR="$SVC_HOME/.config/mihomo"
UNIT="/etc/systemd/system/mihomo-tun.service"
STATE="$DIR/tun-state.env"
ROLLBACK="$DIR/rollback-tun.sh"
TIMER="mihomo-tun-rollback"

MIHOMO_BIN="${MIHOMO_BIN:-$(command -v mihomo 2>/dev/null || true)}"
MIHOMO_BIN="${MIHOMO_BIN:-/usr/local/bin/mihomo}"

log() { echo; echo "[$(date '+%F %T')] $*"; }
die() { log "Error: $*"; exit 1; }

# ---------- Preflight ----------
[[ -x "$MIHOMO_BIN" ]] || die "mihomo not found (set MIHOMO_BIN=/path/to/mihomo)"
[[ -f "$DIR/config-tun.yaml" ]] || die "$DIR/config-tun.yaml not found (generate it with: clash tun on)"
[[ -c /dev/net/tun ]] || die "/dev/net/tun not found (check that the kernel supports TUN)"
command -v nmcli >/dev/null || die "nmcli not found (TUN mode uses NetworkManager for DNS)"
command -v resolvectl >/dev/null || die "resolvectl not found (systemd-resolved is required)"

log "Validating TUN config..."
if ! "$MIHOMO_BIN" -t -d "$DIR" -f "$DIR/config-tun.yaml" >/tmp/mihomo-tun-check.log 2>&1; then
    tail -20 /tmp/mihomo-tun-check.log
    die "Config validation failed"
fi

DEV="$(ip route show default | awk '/^default/{print $5; exit}')"
[[ -n "$DEV" ]] || die "No default network interface found"
CONN="$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v d="$DEV" '$2==d{print $1; exit}')"
[[ -n "$CONN" ]] || die "No NetworkManager connection found for interface $DEV"
GW="$(ip route show default | awk '/^default/{print $3; exit}')"

OLD_DNS="$(nmcli -g ipv4.dns connection show "$CONN")"
OLD_IGNORE="$(nmcli -g ipv4.ignore-auto-dns connection show "$CONN")"
OLD_SEARCH="$(nmcli -g ipv4.dns-search connection show "$CONN")"

log "User: $SVC_USER    Interface: $DEV    Connection: $CONN"
log "Original DNS: '${OLD_DNS}'    ignore-auto-dns: ${OLD_IGNORE:-no}    search: '${OLD_SEARCH}'"

cat > "$STATE" <<EOF
DEV="$DEV"
CONN="$CONN"
OLD_DNS="$OLD_DNS"
OLD_IGNORE="${OLD_IGNORE:-no}"
OLD_SEARCH="$OLD_SEARCH"
EOF
chmod 600 "$STATE"

# ---------- Generate rollback script ----------
cat > "$ROLLBACK" <<EOF
#!/usr/bin/env bash
set -u
STATE="$STATE"
[ -f "\$STATE" ] && . "\$STATE"
DEV="\${DEV:-$DEV}"
CONN="\${CONN:-$CONN}"
OLD_DNS="\${OLD_DNS:-}"
OLD_IGNORE="\${OLD_IGNORE:-no}"
OLD_SEARCH="\${OLD_SEARCH:-}"
GW="\$(ip route show default | awk '/^default/{print \$3; exit}')"

systemctl disable --now mihomo-tun.service 2>/dev/null || true

if command -v nmcli >/dev/null 2>&1 && [ -n "\$CONN" ]; then
    nmcli connection modify "\$CONN" ipv4.dns "\$OLD_DNS" ipv4.ignore-auto-dns "\$OLD_IGNORE" ipv4.dns-search "\$OLD_SEARCH" 2>/dev/null || true
    nmcli device reapply "\$DEV" >/dev/null 2>&1 || true
fi

resolvectl revert "\$DEV" >/dev/null 2>&1 || true
if ! resolvectl status "\$DEV" 2>/dev/null | grep -qE 'DNS Servers:.*(192\\.168\\.|10\\.|172\\.)'; then
    if [ -n "\${OLD_DNS:-}" ]; then
        resolvectl dns "\$DEV" \$OLD_DNS >/dev/null 2>&1 || true
    elif [ -n "\${GW:-}" ]; then
        resolvectl dns "\$DEV" "\$GW" >/dev/null 2>&1 || true
    fi
fi
resolvectl flush-caches >/dev/null 2>&1 || true
systemctl restart systemd-resolved 2>/dev/null || true

runuser -u $SVC_USER -- env XDG_RUNTIME_DIR=$SVC_RUNTIME systemctl --user enable --now mihomo.service 2>/dev/null || true
logger -t mihomo-tun-rollback "Restored HTTP proxy mode (DNS/routes reverted)"
echo "[rollback] Restored the original HTTP proxy mode"
EOF
chmod 750 "$ROLLBACK"
chown root:root "$ROLLBACK"

# ---------- 5-minute auto-rollback guard ----------
systemctl stop "$TIMER.timer" 2>/dev/null || true
systemctl reset-failed "$TIMER.timer" "$TIMER.service" 2>/dev/null || true
systemd-run --unit="$TIMER" --on-active=300 --timer-property=AccuracySec=1s "$ROLLBACK" >/dev/null 2>&1 \
    || die "Cannot create the auto-rollback timer"
log "5-minute auto-rollback enabled (if SSH/Tailscale drops, HTTP proxy mode is restored after 5 minutes)"

DONE=0
cleanup() {
    rc=$?
    trap - EXIT INT TERM
    if [[ $DONE -ne 1 ]]; then
        log "Installation did not complete (exit $rc); rolling back..."
        systemctl stop "$TIMER.timer" 2>/dev/null || true
        bash "$ROLLBACK" || true
    fi
    exit "$rc"
}
trap cleanup EXIT INT TERM

# ---------- Stop the user HTTP proxy ----------
log "Stopping the user HTTP proxy service..."
runuser -u "$SVC_USER" -- env XDG_RUNTIME_DIR="$SVC_RUNTIME" systemctl --user disable --now mihomo.service 2>/dev/null || true

# ---------- Install and start the TUN service ----------
log "Installing and starting mihomo-tun.service..."
cat > "$UNIT" <<UNIT_EOF
[Unit]
Description=Mihomo TUN system-wide proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SVC_USER
Group=$SVC_GROUP
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
ExecStart=$MIHOMO_BIN -d "$DIR" -f "$DIR/config-tun.yaml"
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT_EOF

systemctl daemon-reload
systemctl enable --now mihomo-tun.service

TUN_OK=0
for _ in $(seq 1 20); do
    sleep 1
    if systemctl is-active --quiet mihomo-tun.service && ip -o link show type tun 2>/dev/null | grep -q .; then
        TUN_OK=1
        break
    fi
    if ! systemctl is-active --quiet mihomo-tun.service; then
        break
    fi
done

if [[ $TUN_OK -ne 1 ]]; then
    log "TUN service failed to start; logs:"
    journalctl -u mihomo-tun -n 40 --no-pager || true
    die "TUN service did not start"
fi
log "TUN interface created: $(ip -o link show type tun | awk -F': ' '{print $2}' | head -1)"

# ---------- Point DNS at mihomo ----------
log "Pointing DNS for $DEV at mihomo (127.0.0.1:53)..."
if ! nmcli connection modify "$CONN" ipv4.dns "127.0.0.1" ipv4.ignore-auto-dns yes ipv4.dns-search "~."; then
    die "Failed to update NetworkManager DNS"
fi
nmcli device reapply "$DEV" >/dev/null 2>&1 || true
resolvectl dns "$DEV" 127.0.0.1 >/dev/null 2>&1 || true
resolvectl domain "$DEV" "~." >/dev/null 2>&1 || true
resolvectl flush-caches >/dev/null 2>&1 || true
sleep 3

# ---------- Functional tests ----------
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY

DNS_IP=""
for _ in $(seq 1 10); do
    resolvectl flush-caches >/dev/null 2>&1 || true
    DNS_IP="$(getent ahostsv4 github.com 2>/dev/null | awk '{print $1; exit}')"
    [[ "$DNS_IP" == 198.18.* ]] && break
    sleep 1
done
log "DNS test: github.com -> ${DNS_IP:-resolution failed} (expected 198.18.x.x)"

OK=0
for url in https://www.gstatic.com/generate_204 https://github.com; do
    for _ in 1 2 3; do
        CODE="$(curl -sS -m 20 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)"
        if [[ "$CODE" == "204" || "$CODE" == "200" ]]; then
            log "Network test OK: $url ($CODE)"
            OK=1
            break
        fi
        sleep 2
    done
done

LAN_OK=0
if [ -n "$GW" ] && ping -c1 -W2 "$GW" >/dev/null 2>&1; then LAN_OK=1; fi
TS_OK=0
if command -v tailscale >/dev/null 2>&1; then
    timeout 10 tailscale status >/dev/null 2>&1 && TS_OK=1
fi
log "LAN: $([[ $LAN_OK -eq 1 ]] && echo ok || echo not tested/failed)    Tailscale: $([[ $TS_OK -eq 1 ]] && echo ok || echo not installed/failed)"

if [[ "$DNS_IP" != 198.18.* ]]; then
    die "DNS did not go through mihomo (no fake-ip)"
fi
if [[ $OK -ne 1 ]]; then
    die "Global proxy connectivity test failed"
fi

# ---------- Success ----------
systemctl stop "$TIMER.timer" 2>/dev/null || true
systemctl reset-failed "$TIMER.timer" "$TIMER.service" 2>/dev/null || true
DONE=1

log "TUN global proxy enabled; auto-rollback cancelled"
echo
echo "=== Route check ==="
ip route get 1.1.1.1 2>/dev/null || true
echo
echo "=== DNS check ==="
resolvectl status "$DEV" 2>/dev/null | sed -n '1,10p'
echo
echo "=== Service status ==="
systemctl status mihomo-tun.service --no-pager -l | head -12
echo
echo "Programs that do not set http_proxy now use the proxy automatically."
echo "Manage: systemctl {status|restart|stop} mihomo-tun"
echo "Restore HTTP proxy mode: sudo bash $ROLLBACK"
