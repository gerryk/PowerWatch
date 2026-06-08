#!/usr/bin/env bash
# Native shutdown for a Docker host: gracefully stop every running container
# (giving each STOP_TIMEOUT_SEC for SIGTERM before SIGKILL), then poweroff.
#
# Invoked by powerwatch.sh when an outage is confirmed.

set -u

LOG=/var/log/powerwatch-shutdown.log
exec >>"$LOG" 2>&1

STOP_TIMEOUT_SEC="${STOP_TIMEOUT_SEC:-30}"

log() { printf '[%s] powerwatch/docker: %s\n' "$(date -Iseconds)" "$*"; }

log "outage confirmed; beginning docker host shutdown"

if ! command -v docker >/dev/null 2>&1; then
  log "docker not found in PATH; skipping container shutdown"
else
  mapfile -t running < <(docker ps -q)
  if (( ${#running[@]} == 0 )); then
    log "no running containers"
  else
    log "stopping ${#running[@]} container(s) with ${STOP_TIMEOUT_SEC}s grace: ${running[*]}"
    docker stop -t "$STOP_TIMEOUT_SEC" "${running[@]}" || log "docker stop returned non-zero (continuing)"
  fi
fi

log "syncing filesystems and powering off"
sync
systemctl poweroff
