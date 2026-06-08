#!/usr/bin/env bash
# Native shutdown for TrueNAS SCALE (Debian/systemd, middleware-managed).
#
# Best path is to hand control to the middleware via `midclt call
# system.shutdown` — that lets TrueNAS stop services in the correct order,
# flush iSCSI/NFS sessions, and export ZFS pools cleanly before halting.
#
# Falls back to plain `systemctl poweroff` (which also unmounts ZFS via the
# zfs-mount service) if midclt is unavailable or errors out.

set -u

LOG=/var/log/powerwatch-shutdown.log
exec >>"$LOG" 2>&1

MIDCLT_TIMEOUT_SEC="${MIDCLT_TIMEOUT_SEC:-300}"

log() { printf '[%s] powerwatch/truenas: %s\n' "$(date -Iseconds)" "$*"; }

log "outage confirmed; beginning TrueNAS SCALE shutdown"

if command -v midclt >/dev/null 2>&1; then
  log "invoking midclt call system.shutdown (timeout ${MIDCLT_TIMEOUT_SEC}s)"
  if timeout "$MIDCLT_TIMEOUT_SEC" midclt call system.shutdown; then
    log "midclt accepted shutdown; system will halt"
    exit 0
  fi
  log "midclt shutdown failed or timed out; falling back to systemctl poweroff"
else
  log "midclt not found; using systemctl poweroff directly"
fi

sync
systemctl poweroff
