# Quickstart: LXC Port Proxy

## Prerequisites

- A running Docker-in-LXC container (created via `setup-host.sh`)
- A service running inside the container on a known port

## 1. Expose a Container Port

```bash
# Forward container port 3000 to host port 3000
./dilxc.sh proxy add 3000

# Forward container port 8080 to host port 9090
./dilxc.sh proxy add 8080 9090
```

The service is now reachable from any machine on the LAN at `<host-ip>:<host-port>`.

## 2. Check Active Proxies

```bash
./dilxc.sh proxy list
```

Output:
```
HOST               CONTAINER
0.0.0.0:3000    →  127.0.0.1:3000
0.0.0.0:9090    →  127.0.0.1:8080
```

## 3. Remove Proxies

```bash
# Remove a specific proxy by host port
./dilxc.sh proxy rm 3000

# Remove all proxies
./dilxc.sh proxy rm all
```

## Common Workflow

```bash
# Start a web server in the container
./dilxc.sh exec python3 -m http.server 8000

# In another terminal, expose it to the LAN
./dilxc.sh proxy add 8000

# Access from another machine on the LAN
curl http://gram-server:8000

# Done? Clean up
./dilxc.sh proxy rm 8000
```

## Docker Containers Inside LXC

```bash
# Run a Docker container inside the LXC sandbox
./dilxc.sh docker run -d -p 3000:3000 myapp

# Expose Docker's mapped port to the LAN
./dilxc.sh proxy add 3000

# Now accessible at <host-ip>:3000 from the LAN
```

## Important Notes

- Proxies persist across container restarts — no need to re-add after reboot.
- The proxy listens on all host interfaces (`0.0.0.0`), making it LAN-accessible. Ensure your firewall rules are appropriate.
- Only TCP is supported. For UDP, use `lxc config device add` directly.
- Proxy devices are removed when the container is destroyed.
