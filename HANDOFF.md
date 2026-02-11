# Handoff Notes (Historical)

This was the original handoff document used to diagnose and fix the sandbox setup.
The work described here is **complete**. Keeping it for reference.

## What Was Done (2026-02-11)

### Problem
The `claude-sandbox` LXD container had no IPv4 connectivity. It got an IPv6 address
from lxdbr0 but couldn't get a DHCP lease or reach the internet. The container was
partially provisioned (no software installed).

### Root Cause
Two firewall issues on the host, both caused by running Docker alongside LXD:

1. **UFW blocked DHCP/DNS from lxdbr0** — The default `before.rules` only allows
   DHCP replies (sport 67 → dport 68), not DHCP requests from containers to
   dnsmasq on the bridge (dport 67). DNS queries (udp+tcp/53) were also dropped.

2. **DOCKER-USER chain blocked forwarding** — Docker's `DOCKER-USER` chain
   (managed in `/etc/ufw/after.rules`) has an allow-list of subnets followed by
   a blanket DROP. The lxdbr0 subnet (10.200.12.0/24) wasn't in the list.

### Fix Applied
Added persistent rules via UFW (survives reboots and Docker restarts):

- `/etc/ufw/before.rules` — DHCP, DNS, and forwarding rules for lxdbr0
- `/etc/ufw/after.rules` — added 10.200.12.0/24 to DOCKER-USER allow-list

Then deleted the broken container and recreated it with `setup-host.sh`.
Full details in the README's [Host Firewall Setup](README.md#host-firewall-setup) section.

### Verification (all passed)
- Container gets IPv4 address (10.200.12.x)
- Internet connectivity works (ping 8.8.8.8)
- DNS resolution works (ping google.com)
- Docker runs inside container (hello-world)
- Claude Code v2.1.39 installed
- clean-baseline snapshot created
- Project mount working at /home/ubuntu/project-src

## Original Handoff Context

The sections below are the original notes from before the fix was applied.
They're preserved for context on the host environment and design decisions.

### Host Environment

- **Server**: Ubuntu (hostname: gram-server, user: john, LG Gram homelab)
- **LXD bridge**: lxdbr0 at 10.200.12.1/24 with IPv4 NAT
- **Storage**: btrfs pool on dedicated 45GB LVM volume at /var/lib/lxd-storage
- **Docker**: heavily used on this host with many compose stacks, dedicated LVM volume
- **Pi-hole**: runs in Docker with macvlan networking (host can't reach it directly)
- **LAN**: 10.10.10.0/24, **VPN**: 10.8.0.0/24

### Design Decisions

- **LXD over Docker/bubblewrap**: Claude Code's bubblewrap sandbox can't run Docker.
  Docker-in-Docker is fragile. LXD gives a full system container where Docker runs
  natively — Claude doesn't know it's sandboxed.
- **Read-only source mount**: Protects host files. Claude works on a writable copy.
- **btrfs snapshots**: Instant rollback. Take one before every session.
- **fish shell**: Configured as default for the ubuntu user inside the container,
  with equivalent aliases and functions in both bash and fish configs.
