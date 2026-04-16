#!/usr/bin/env bash
set -euo pipefail

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

CONFIG_FILE="$INSTALL_DIR/ServerDescription.json"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[entrypoint] Seeding $CONFIG_FILE from env vars"
  if [ -n "${SERVER_PASSWORD:-}" ]; then
    PW_PROTECTED=true
  else
    PW_PROTECTED=false
  fi
  cat > "$CONFIG_FILE" <<JSON
{
  "ServerName": "${SERVER_NAME:-Windrose Server}",
  "InviteCode": "${INVITE_CODE:-}",
  "IsPasswordProtected": $PW_PROTECTED,
  "Password": "${SERVER_PASSWORD:-}",
  "MaxPlayerCount": ${MAX_PLAYERS:-8},
  "WorldIslandId": "${WORLD_ISLAND_ID:-Default}",
  "P2pProxyAddress": "${P2P_PROXY_ADDRESS:-}"
}
JSON
else
  echo "[entrypoint] $CONFIG_FILE exists — leaving as-is (edit via volume to change)"
fi

cd "$INSTALL_DIR"

echo "[entrypoint] Starting Xvfb on :99"
Xvfb :99 -screen 0 1024x768x16 &
export DISPLAY=:99
sleep 1

echo "[entrypoint] Launching $SERVER_EXE under wine"
exec wine64 "$SERVER_EXE"
