# Windrose Dedicated Server on Coolify — Runbook

## What this is

A Docker image that runs the **Windows-only** Windrose dedicated server under **Wine** on a Linux VPS. Deployed on Coolify (Contabo VPS at 154.53.46.109). Invite code comes from `R5/ServerDescription.json` in the `windrose_install` volume.

## Architecture

- **Base**: `debian:bookworm-slim` + winehq-stable (from WineHQ repo)
- **SteamCMD**: pulls Windrose app ID `4129620` on first boot
- **Wine**: runs the real UE5 binary `R5/Binaries/Win64/WindroseServer-Win64-Shipping.exe` directly (the `WindroseServer.exe` bootstrapper at the install root is skipped)
- **Network**: `network_mode: host` because Windrose uses Steam P2P + coturn TURN (`coturn-us.windrose.support:3478`) and dynamically-assigned ports
- **Volumes**: `windrose_install` (entire install, includes saves) and `windrose_wine` (wine prefix)

## Obstacles overcome

Chronological list of things that broke and how we fixed them.

### 1. Wine prefix "not owned by you" (crash loop)

Named Docker volumes come up owned by `root`; Wine refuses to use a prefix it doesn't own. **Fix**: entrypoint starts as root, `chown`s the mounted dirs, re-execs as `steam` via `runuser`.

### 2. `wine64: not found`

Recent `winehq-stable` on Debian bookworm dropped the separate `wine64` binary — only `wine` exists now (handles 64-bit PEs). **Fix**: invoke `wine`, not `wine64`.

### 3. Bogus `ServerDescription.json` seeding

The Steam Community guide hinted at one schema, but the actual file the server writes is at `R5/ServerDescription.json` with a nested schema:

```json
{
  "Version": 1,
  "DeploymentId": "...",
  "ServerDescription_Persistent": {
    "PersistentServerId": "...",
    "InviteCode": "fa7af6ca",
    "IsPasswordProtected": false,
    "Password": "",
    "ServerName": "",
    "WorldIslandId": "...",
    "MaxPlayerCount": 8,
    "P2pProxyAddress": "127.0.0.1"
  }
}
```

**Fix**: don't pre-seed at all. Let the server create its own config on first boot. Entrypoint deletes any leftover flat-schema seed before launch. Edit the file in the volume after first boot if you want custom values — env vars aren't wired through anymore.

### 4. Bootstrapper never spawns real binary under Wine

`WindroseServer.exe` at the install root is a 260 KB launcher that wraps the real UE5 binary. Under Wine + Xvfb it sits idle and never forks the real process. **Fix**: skip it. Invoke `R5/Binaries/Win64/WindroseServer-Win64-Shipping.exe -log` directly.

### 5. WINEDEBUG=-all hid all failures

Had `WINEDEBUG=-all` set globally which suppressed wine's module-load errors, making debugging hell. **Fix**: `WINEDEBUG=err+all,warn+module,fixme-all` — surfaces errors and missing-DLL warnings while keeping fixme noise off.

### 6. OOM kill during terrain generation

Host VPS has 8 GB RAM and no swap. Windrose server's GameThread used 4.5 GB RSS generating terrain and triggered the global Linux OOM killer. **Fix**: add 4 GB swap file on the host:

```bash
fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo "/swapfile none swap sw 0 0" >> /etc/fstab
```

This alone fixed the OOM — terrain gen peaks around 4.5 GB RSS, sometimes spills to swap, but doesn't get killed.

### 7. UE5 default 180s connection timeout vs 5+ min terrain gen

First player connection triggers terrain generation. Gen takes 5+ minutes on this VPS (CPU-bound, multi-threaded). UE5's default `ConnectionTimeout=180.0` drops the client at 3 minutes while the server is still cooking. Client sees "connection error." **Fix**: write `Engine.ini` into the Saved config directory:

```ini
[/Script/OnlineSubsystemUtils.IpNetDriver]
InitialConnectTimeout=900.0
ConnectionTimeout=900.0
PendingConnectionLostTime=30.0

[/Script/Engine.NetDriver]
InitialConnectTimeout=900.0
ConnectionTimeout=900.0
```

Path: write to BOTH `R5/Saved/Config/Windows/Engine.ini` and `R5/Saved/Config/WindowsServer/Engine.ini` — the right one depends on how the UE5 build identifies the platform; covering both is safe.

### 8. coturn TCP drop during long server-side silence

During terrain gen, the server sends no data to the client for 60+ seconds. The `coturn-us.windrose.support:3478` TURN relay drops the TCP channel with "Connection reset by peer" status 10054. **Fix**: no direct fix needed — once the world is built and the server is in `ReadyToPlay`, normal server⇄client chatter keeps the TURN link alive.

## Operational facts

- **First connection ever**: 10+ minutes (SteamCMD validate + UE5 init + terrain gen from scratch)
- **Subsequent connections**: seconds (terrain persists in `windrose_install` volume)
- **Memory ceiling**: ~4.5 GB RSS during gen; steady state much lower
- **Connection chain**: client → Steam P2P lookup → coturn TURN relay → our VPS via host network
- **No UDP port visible** on `ss -uln`: traffic rides Steam's networking fabric, not a raw socket. This is normal.

## Finding the invite code

```bash
docker run --rm -v e1wjha1aqw10pup0xw8wkza4_windrose-install:/d alpine \
  sh -c "cat /d/R5/ServerDescription.json | grep -i InviteCode"
```

Or SSH + `docker exec` on the running container:

```bash
CID=$(docker ps --format '{{.Names}}' | grep windrose | head -1)
docker exec "$CID" cat /home/steam/windrose/R5/ServerDescription.json
```

## Common operations

**Tail server log** (the good one, not Steam noise):
```bash
CID=$(docker ps --format '{{.Names}}' | grep windrose | head -1)
docker exec "$CID" tail -f /home/steam/windrose/R5/Saved/Logs/R5.log
```

**Check who's connected**:
```bash
docker exec "$CID" grep -E "Connected Accounts|Disconnected Accounts|FarewellReason" \
  /home/steam/windrose/R5/Saved/Logs/R5.log | tail -20
```

**Change invite code / password / server name**:
1. Stop container (Coolify → Stop)
2. Edit the volume file:
   ```bash
   docker run --rm -it -v e1wjha1aqw10pup0xw8wkza4_windrose-install:/d alpine vi /d/R5/ServerDescription.json
   ```
3. Restart container

**Nuke the world and start fresh**:
```bash
docker volume rm e1wjha1aqw10pup0xw8wkza4_windrose-install
```
Next deploy re-downloads Windrose and regenerates the world.

**Tail live build logs during a Coolify deploy**:
```bash
docker exec coolify-db psql -U coolify -d coolify -t -A \
  -c "SELECT logs FROM application_deployment_queues ORDER BY id DESC LIMIT 1" \
  | jq -r '.[-30:] | .[] | "[\(.timestamp[:19])] \(.output)"'
```

## Known flaky behavior

- **Memory creeping near 90% of host** during long sessions — swap cushions but the server itself logs *"Memory leak suspected"*. For a few-day throwaway deploy this is acceptable; reboot the container nightly if it gets sticky.
- **TURN relay drops during long silent windows** — only matters during initial terrain gen. Once populated world is loaded, doesn't recur.
