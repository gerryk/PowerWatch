#!/usr/bin/env bash
# Install PowerWatch on a TrueNAS SCALE host. Run as root on the target box.
#
# CAVEAT: TrueNAS SCALE may replace files under /usr and parts of /etc on
# major version upgrades. After any SCALE upgrade, re-run this installer.
# A more durable option is to store the scripts on a pool dataset and add a
# Post-Init shell script via the TrueNAS UI to copy them into place at boot —
# see README.md.

set -euo pipefail

if (( EUID != 0 )); then
  echo "must be run as root" >&2
  exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON="$HERE/../common"

install -m 0755 "$COMMON/powerwatch.sh"        /usr/local/sbin/powerwatch.sh
install -m 0755 "$HERE/shutdown-hook.sh"       /usr/local/sbin/powerwatch-shutdown-hook.sh

install -d -m 0755 /etc/powerwatch
if [[ ! -e /etc/powerwatch/powerwatch.conf ]]; then
  install -m 0644 "$HERE/powerwatch.conf"      /etc/powerwatch/powerwatch.conf
  echo "wrote /etc/powerwatch/powerwatch.conf — EDIT this to set PING_TARGETS for your network"
else
  echo "/etc/powerwatch/powerwatch.conf already exists; leaving it untouched"
fi

install -m 0644 "$COMMON/powerwatch.service"   /etc/systemd/system/powerwatch.service

systemctl daemon-reload
echo
echo "Installed. Next steps:"
echo "  1. Edit /etc/powerwatch/powerwatch.conf and set PING_TARGETS."
echo "  2. Safe end-to-end test: temporarily set SHUTDOWN_HOOK=/bin/true in the conf,"
echo "     then sudo systemctl start powerwatch and disconnect a ping target."
echo "  3. Enable + start for real: sudo systemctl enable --now powerwatch.service"
echo "  4. Watch logs:               journalctl -u powerwatch -f"
echo
echo "Reminder: re-run this installer after any TrueNAS SCALE version upgrade."
