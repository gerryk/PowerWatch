#!/usr/bin/env bash
# Install PowerWatch on a Docker host. Run as root on the target box.
#
# Lays down:
#   /usr/local/sbin/powerwatch.sh                  (the watcher)
#   /usr/local/sbin/powerwatch-shutdown-hook.sh    (docker-native shutdown)
#   /etc/powerwatch/powerwatch.conf                (config — EDIT before enable)
#   /etc/systemd/system/powerwatch.service         (systemd unit)

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
echo "  1. Edit /etc/powerwatch/powerwatch.conf and set PING_TARGETS to mains-powered IPs."
echo "  2. Dry-run: sudo /usr/local/sbin/powerwatch.sh /etc/powerwatch/powerwatch.conf"
echo "     (Ctrl-C to stop; or temporarily point SHUTDOWN_HOOK at /bin/true to verify detection.)"
echo "  3. Enable + start: sudo systemctl enable --now powerwatch.service"
echo "  4. Watch logs:     journalctl -u powerwatch -f"
