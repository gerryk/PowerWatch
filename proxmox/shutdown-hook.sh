#!/usr/bin/env bash
# Native shutdown for a Proxmox VE host: gracefully shut down every running
# QEMU VM (qm) and LXC container (pct) in parallel, falling back to forceStop
# if a guest does not respond within GUEST_SHUTDOWN_TIMEOUT_SEC. Then poweroff.
#
# Invoked by powerwatch.sh when an outage is confirmed.

set -u

LOG=/var/log/powerwatch-shutdown.log
exec >>"$LOG" 2>&1

GUEST_SHUTDOWN_TIMEOUT_SEC="${GUEST_SHUTDOWN_TIMEOUT_SEC:-120}"

log() { printf '[%s] powerwatch/proxmox: %s\n' "$(date -Iseconds)" "$*"; }

log "outage confirmed; beginning proxmox host shutdown"

shutdown_vms() {
  if ! command -v qm >/dev/null 2>&1; then
    log "qm not found; skipping VM shutdown"
    return
  fi
  # qm list columns: VMID NAME STATUS MEM BOOTDISK PID
  local ids
  ids=$(qm list 2>/dev/null | awk 'NR>1 && $3=="running" {print $1}')
  if [[ -z "$ids" ]]; then
    log "no running VMs"
    return
  fi
  for id in $ids; do
    log "qm shutdown $id (timeout=${GUEST_SHUTDOWN_TIMEOUT_SEC}s, forceStop on timeout)"
    qm shutdown "$id" --forceStop 1 --timeout "$GUEST_SHUTDOWN_TIMEOUT_SEC" &
  done
}

shutdown_cts() {
  if ! command -v pct >/dev/null 2>&1; then
    log "pct not found; skipping CT shutdown"
    return
  fi
  # pct list columns: VMID Status Lock Name
  local ids
  ids=$(pct list 2>/dev/null | awk 'NR>1 && $2=="running" {print $1}')
  if [[ -z "$ids" ]]; then
    log "no running CTs"
    return
  fi
  for id in $ids; do
    log "pct shutdown $id (timeout=${GUEST_SHUTDOWN_TIMEOUT_SEC}s, forceStop on timeout)"
    pct shutdown "$id" --forceStop 1 --timeout "$GUEST_SHUTDOWN_TIMEOUT_SEC" &
  done
}

shutdown_vms
shutdown_cts

log "waiting for guests to finish shutting down"
wait
log "all guests stopped; syncing and powering off"
sync
systemctl poweroff
