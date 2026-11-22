#!/usr/bin/env bash
# Install clash / accel into the user's home directory
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "Do not run install.sh with sudo"
    exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
CONF="$HOME/.config/mihomo"
UNIT_DIR="$HOME/.config/systemd/user"

echo "Installing to $BIN"
mkdir -p "$BIN" "$CONF" "$UNIT_DIR"
install -m 755 "$ROOT/clash" "$BIN/clash"
install -m 755 "$ROOT/accel" "$BIN/accel"
install -m 755 "$ROOT/start-menu.sh" "$BIN/clash-menu"
install -m 755 "$ROOT/check-status.sh" "$BIN/clash-status"
install -m 755 "$ROOT/install-tun.sh" "$CONF/install-tun.sh"
if [ ! -f "$CONF/README.md" ]; then
    install -m 644 "$ROOT/README.md" "$CONF/README.md"
fi

# Ensure ~/.local/bin is in PATH
if ! grep -qs '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    {
        echo
        echo '# added by clash-server-accel'
        echo 'export PATH="$HOME/.local/bin:$PATH"'
    } >> "$HOME/.bashrc"
fi

# Shell helpers: proxy_on / proxy_off / proxy_status
if ! grep -qs 'proxy_on()' "$HOME/.bashrc" 2>/dev/null; then
    cat >> "$HOME/.bashrc" <<'BASHRC'

# >>> clash-server-accel >>>
proxy_on() {
    export http_proxy='http://127.0.0.1:7899'
    export https_proxy="$http_proxy"
    export all_proxy='socks5h://127.0.0.1:7899'
    export HTTP_PROXY="$http_proxy"
    export HTTPS_PROXY="$https_proxy"
    export ALL_PROXY="$all_proxy"
    export no_proxy='localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16'
    export NO_PROXY="$no_proxy"
    echo "Proxy enabled -> $http_proxy"
}
proxy_off() {
    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY
    echo "Proxy disabled"
}
proxy_status() {
    if [ -n "$http_proxy" ]; then echo "Environment: $http_proxy"; else echo "Environment: not set"; fi
    if systemctl is-active --quiet mihomo-tun 2>/dev/null; then
        echo "Service: TUN global mode (running)"
    elif systemctl --user is-active --quiet mihomo 2>/dev/null; then
        echo "Service: HTTP proxy mode (running)"
    else
        echo "Service: not running"
    fi
    curl -sS -m 8 -x http://127.0.0.1:7899 -o /dev/null -w 'Connectivity: HTTP %{http_code}, %{time_total}s\n' https://www.gstatic.com/generate_204 2>&1 || true
}
# <<< clash-server-accel <<<
BASHRC
fi

# systemd user service
install -m 644 "$ROOT/mihomo.service" "$UNIT_DIR/mihomo.service"
if [ "${CLASH_SKIP_SYSTEMD:-0}" != "1" ]; then
    systemctl --user daemon-reload 2>/dev/null || true
fi

# Desktop launcher (respect the XDG desktop directory)
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
if [ -z "$DESKTOP_DIR" ] || [ "$DESKTOP_DIR" = "$HOME" ]; then
    DESKTOP_DIR="$HOME/Desktop"
fi
if [ -d "$DESKTOP_DIR" ]; then
    sed -e "s|@HOME@|$HOME|g" \
        "$ROOT/clash-accelerator.desktop.in" > "$DESKTOP_DIR/clash-accelerator.desktop"
    chmod 755 "$DESKTOP_DIR/clash-accelerator.desktop"
    if command -v gio >/dev/null 2>&1; then
        gio set "$DESKTOP_DIR/clash-accelerator.desktop" metadata::trusted true 2>/dev/null || true
    fi
fi

# Dependency checks
if ! command -v mihomo >/dev/null 2>&1 && [ ! -x /usr/local/bin/mihomo ]; then
    echo "Warning: mihomo not found; install it to /usr/local/bin/mihomo"
fi
if ! /usr/bin/python3 -c 'import yaml' 2>/dev/null; then
    echo "Warning: PyYAML is missing; install python3-yaml"
fi

echo
echo "Installation complete. Next steps:"
echo "  source ~/.bashrc"
echo "  clash add \"your subscription URL\""
echo "  accel status"
