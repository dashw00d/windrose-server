#!/usr/bin/env bash
set -euo pipefail

# Named volumes mounted on /home/steam/.wine and /home/steam/windrose come up
# owned by root; wine refuses to use a prefix it doesn't own. Fix ownership as
# root on first boot, then re-exec as the `steam` user.
if [ "$(id -u)" = "0" ]; then
  chown -R steam:steam /home/steam/.wine /home/steam/windrose 2>/dev/null || true
  exec runuser -u steam -- /entrypoint.sh
fi

STEAMCMD=/home/steam/steamcmd/steamcmd.sh
INSTALL_DIR=/home/steam/windrose
APP_ID="${STEAM_APP_ID:-4129620}"
SERVER_EXE="WindroseServer.exe"

if [ ! -f "$WINEPREFIX/system.reg" ]; then
  echo "[entrypoint] Initializing wine prefix at $WINEPREFIX"
  wineboot --init
  wineserver -w

  echo "[entrypoint] Installing winetricks components (vcrun2022, d3dcompiler_47)"
  winetricks -q --force vcrun2022 d3dcompiler_47 \
    || echo "[entrypoint] winetricks step failed — continuing; revisit only if server errors on missing DLLs"
fi

echo "[entrypoint] Running SteamCMD app_update for $APP_ID"
"$STEAMCMD" \
  +@sSteamCmdForcePlatformType windows \
  +force_install_dir "$INSTALL_DIR" \
  +login anonymous \
  +app_update "$APP_ID" validate \
  +quit

# The server creates ServerDescription.json itself in R5/ with its own schema
# (Version, DeploymentId, nested ServerDescription_Persistent object) on first
# boot. Don't pre-seed — just delete any bogus flat-schema file from prior runs.
rm -f "$INSTALL_DIR/ServerDescription.json"

cd "$INSTALL_DIR"

echo "[entrypoint] Starting Xvfb on :99"
Xvfb :99 -screen 0 1024x768x16 &
export DISPLAY=:99
sleep 1

echo "[entrypoint] Launching $SERVER_EXE under wine (with -log)"
exec wine "$SERVER_EXE" -log
