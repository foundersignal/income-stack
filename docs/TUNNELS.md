# SSH Tunnels — Dashboard Access from Mac

Auto-start SSH tunnels on Mac login to access Helsinki dashboards locally.

## What This Does

A macOS launchd service that opens persistent SSH tunnels to the server,
forwarding three dashboard ports to localhost. Tunnels auto-reconnect
if the connection drops.

## Ports

| Port | Service          | Local URL                    |
|------|------------------|------------------------------|
| 3333 | Mission Control  | http://localhost:3333         |
| 3847 | CashClaw         | http://localhost:3847         |
| 4000 | LiteLLM          | http://localhost:4000/ui      |

## Install

```bash
# Copy and edit — replace SERVER_IP with your Hetzner IP
cp configs/tunnels.plist.example ~/Library/LaunchAgents/com.foundersignal.tunnels.plist
sed -i "" "s/SERVER_IP/204.168.198.12/" ~/Library/LaunchAgents/com.foundersignal.tunnels.plist

# Load (starts immediately and on every login)
launchctl load ~/Library/LaunchAgents/com.foundersignal.tunnels.plist
```

## Verify

```bash
# Check service is running
launchctl list | grep foundersignal

# Test dashboards
curl -s http://localhost:3333 | head -3
curl -s http://localhost:3847 | head -3
curl -s http://localhost:4000/health | head -3
```

## Manage

```bash
# Stop tunnels
launchctl unload ~/Library/LaunchAgents/com.foundersignal.tunnels.plist

# Restart tunnels
launchctl unload ~/Library/LaunchAgents/com.foundersignal.tunnels.plist
launchctl load ~/Library/LaunchAgents/com.foundersignal.tunnels.plist

# View logs
cat /tmp/foundersignal-tunnels.err
```

## Requirements

- SSH key access to the server (no password prompt)
- SSH on port 2222
