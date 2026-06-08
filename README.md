# PowerWatch

Autonomous shutdown for Linux boxes on a "dumb" UPS (no USB / network
comms). Each box detects a power outage by pinging one or more devices
that are **not** on the UPS. When pings have failed for long enough, it
runs a per-host shutdown hook that drains workloads gracefully before
calling `systemctl poweroff`.

Three flavours of hook are provided, according to the various sysytems I currently have:

| Subdir              | Box           | What the hook does                                                                              |
| ------------------- | ------------- | ----------------------------------------------------------------------------------------------- |
| `docker-host/`      | Docker host   | `docker stop -t 30` every running container, then `systemctl poweroff`                          |
| `proxmox/`          | Proxmox VE    | `qm shutdown` all running VMs and `pct shutdown` all running CTs in parallel, then `poweroff`   |
| `truenas-scale/`    | TrueNAS SCALE | `midclt call system.shutdown` (middleware-managed shutdown), falling back to `poweroff`         |

The watcher daemon (`common/powerwatch.sh`) and systemd unit
(`common/powerwatch.service`) are shared.

## Architecture

```
  ┌────────────────────┐         ┌──────────────────────┐
  │ mains-powered host │ ◀─ping─ │  PowerWatch box      │
  │ (router / Pi / …)  │         │  (on UPS)            │
  └────────────────────┘         │                      │
                                 │  powerwatch.sh       │
                                 │   └─ pings fail N s  │
                                 │      └─ exec hook    │
                                 │         ├─ drain     │
                                 │         └─ poweroff  │
                                 └──────────────────────┘
```

When grid power dies, the router/AP/Pi you ping loses power too. Once
they have been unreachable for `OUTAGE_THRESHOLD_SEC`, PowerWatch
declares an outage and runs the native shutdown hook. A single
successful ping at any time resets the timer — brief blips (router
reboots, switch storms) don't trigger.

## Picking ping targets

Pick **two or more** devices that are:

- **On mains**, not on this UPS (or any UPS).
- Always-on (no sleep / WoL).
- Reachable over your LAN with predictable, low ping times.

Good candidates: the household router, a wall-powered Pi, a smart plug
with a known IP, the ISP gateway. **Don't** include cloud hosts — they'll
look down whenever your ISP is.

Why ≥ 2: if a single target dies (battery in the Pi, someone unplugs
the router for an upgrade), you don't want every server in the house to
shut itself off.

## Picking thresholds

```
total worst-case shutdown time ≈
    OUTAGE_THRESHOLD_SEC          # how long we wait to be sure
  + hook duration                 # container/VM drain + poweroff
```

Keep that **comfortably below the UPS runtime under load**. Measure the
runtime once with a battery test. If your UPS keeps the load up for ~10
minutes, a 60-second threshold plus a 2-minute drain still leaves you
~7 minutes of headroom.

Defaults in each `powerwatch.conf`:

| Setting                    | Default | Notes                                                             |
| -------------------------- | ------- | ----------------------------------------------------------------- |
| `CHECK_INTERVAL_SEC`       | 5       | How often to ping.                                                |
| `OUTAGE_THRESHOLD_SEC`     | 60      | Confirmed-outage window.                                          |
| `PING_TIMEOUT_SEC`         | 2       | Per-ping `-W`.                                                    |
| `STOP_TIMEOUT_SEC`         | 30      | (docker)  SIGTERM grace per container.                            |
| `GUEST_SHUTDOWN_TIMEOUT_SEC` | 120   | (proxmox) ACPI grace per VM/CT before forceStop.                  |
| `MIDCLT_TIMEOUT_SEC`       | 300     | (truenas) max wait for middleware shutdown before poweroff fallback. |

## Install

On the target box (as root):

```sh
# Copy this repo to the box first (scp / rsync / git clone) then:
cd PowerWatch/<docker-host|proxmox|truenas-scale>
sudo ./install.sh
sudo vim /etc/powerwatch/powerwatch.conf   # set PING_TARGETS
sudo systemctl enable --now powerwatch.service
journalctl -u powerwatch -f
```

## Testing safely

Don't validate this with a real outage on a production box. Two safer
options:

**1. Decouple the hook.** Edit `/etc/powerwatch/powerwatch.conf` and set
`SHUTDOWN_HOOK=/bin/true` (or a script that just logs). Then unplug or
block one ping target. After `OUTAGE_THRESHOLD_SEC` you should see the
"outage confirmed; invoking shutdown hook" line in `journalctl -u
powerwatch`. No real shutdown happens.

**2. Run a guest test.** On the Proxmox or Docker host, spin up a
disposable container/VM and run the real hook manually — it'll stop the
workloads and then poweroff the box. Schedule it.

The first option is the right one for routine verification.

## TrueNAS SCALE caveat

SCALE upgrades may replace files under `/usr` and parts of `/etc`. After
any major version upgrade, re-run `truenas-scale/install.sh`. A more
durable option: keep this repo on a pool dataset (e.g.
`/mnt/tank/scripts/PowerWatch`) and register a **Post-Init script** in
the TrueNAS UI (System Settings → Advanced → Init/Shutdown Scripts) that
runs `install.sh` at boot — that way the unit is recreated on every
startup even after an upgrade.

## Layout

```
PowerWatch/
├── README.md
├── common/
│   ├── powerwatch.sh           # the watcher daemon (shared)
│   └── powerwatch.service      # systemd unit (shared)
├── docker-host/
│   ├── shutdown-hook.sh        # docker stop → poweroff
│   ├── powerwatch.conf         # config template
│   └── install.sh
├── proxmox/
│   ├── shutdown-hook.sh        # qm/pct shutdown → poweroff
│   ├── powerwatch.conf
│   └── install.sh
└── truenas-scale/
    ├── shutdown-hook.sh        # midclt system.shutdown → poweroff
    ├── powerwatch.conf
    └── install.sh
```
