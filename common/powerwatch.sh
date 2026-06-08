#!/usr/bin/env bash
# powerwatch — monitor mains-powered host(s) via ICMP. When all ping targets
# have been unreachable for OUTAGE_THRESHOLD_SEC, exec the configured
# SHUTDOWN_HOOK (which is responsible for gracefully stopping workloads and
# powering the box off).
#
# A single successful ping at any time resets the outage timer, so brief
# network blips do not trigger shutdown.

set -u

CONFIG="${1:-/etc/powerwatch/powerwatch.conf}"

if [[ ! -r "$CONFIG" ]]; then
  echo "powerwatch: config not readable: $CONFIG" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG"

: "${PING_TARGETS:?must set PING_TARGETS (space-separated list of IPs/hostnames on mains, not on the UPS)}"
: "${SHUTDOWN_HOOK:?must set SHUTDOWN_HOOK (absolute path to per-host shutdown script)}"
: "${CHECK_INTERVAL_SEC:=5}"
: "${OUTAGE_THRESHOLD_SEC:=60}"
: "${PING_TIMEOUT_SEC:=2}"

if [[ ! -x "$SHUTDOWN_HOOK" ]]; then
  echo "powerwatch: SHUTDOWN_HOOK not executable: $SHUTDOWN_HOOK" >&2
  exit 1
fi

log() { printf '[%s] powerwatch: %s\n' "$(date -Iseconds)" "$*"; }

ping_one() {
  ping -c 1 -W "$PING_TIMEOUT_SEC" -q "$1" >/dev/null 2>&1
}

any_target_up() {
  local t
  for t in $PING_TARGETS; do
    if ping_one "$t"; then return 0; fi
  done
  return 1
}

log "starting: targets=[$PING_TARGETS] interval=${CHECK_INTERVAL_SEC}s threshold=${OUTAGE_THRESHOLD_SEC}s hook=$SHUTDOWN_HOOK"

state="up"
down_since=0

while :; do
  if any_target_up; then
    if [[ "$state" == "down" ]]; then
      log "ping target recovered; resetting outage timer"
      state="up"
      down_since=0
    fi
  else
    now=$(date +%s)
    if [[ "$state" == "up" ]]; then
      state="down"
      down_since=$now
      log "all ping targets unreachable; starting outage timer"
    else
      elapsed=$(( now - down_since ))
      if (( elapsed >= OUTAGE_THRESHOLD_SEC )); then
        log "outage confirmed after ${elapsed}s; invoking shutdown hook"
        exec "$SHUTDOWN_HOOK"
      fi
    fi
  fi
  sleep "$CHECK_INTERVAL_SEC"
done
