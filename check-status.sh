#!/usr/bin/env bash
# Show proxy status, current node and exit IP
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$HOME/.local/bin/accel" ]; then
    "$HOME/.local/bin/accel" status
else
    "$DIR/accel" status
fi
echo
read -r -p "Press Enter to close..." _
