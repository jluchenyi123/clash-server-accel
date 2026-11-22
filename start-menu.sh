#!/usr/bin/env bash
# Open the Clash subscription management menu
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$HOME/.local/bin/clash" ]; then
    exec "$HOME/.local/bin/clash" menu
fi
exec "$DIR/clash" menu
