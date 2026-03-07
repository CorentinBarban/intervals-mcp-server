#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 tteck
# Author: community adaptation
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/mvilanova/intervals-mcp-server

APP="Intervals-MCP"
var_tags="${var_tags:-mcp,intervals}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function read_credentials() {
  echo -e "\n${INFO}${YW} Intervals.icu credentials${CL}"
  while true; do
    read -r -p "  API Key (Settings > API): " INTERVALS_API_KEY
    [[ -n "$INTERVALS_API_KEY" ]] && break
    msg_error "API Key cannot be empty."
  done
  while true; do
    read -r -p "  Athlete ID (e.g. i12345): " INTERVALS_ATHLETE_ID
    [[ -n "$INTERVALS_ATHLETE_ID" ]] && break
    msg_error "Athlete ID cannot be empty."
  done
  echo ""
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/intervals-mcp-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP}"
  cd /opt/intervals-mcp-server
  git pull --ff-only
  /opt/intervals-mcp-server/.venv/bin/pip install -q --upgrade .
  systemctl restart intervals-mcp
  msg_ok "Updated ${APP}"
  exit
}

read_credentials
start
build_container

msg_info "Injecting credentials"
pct exec "$CTID" -- bash -c "
  sed -i 's|API_KEY=.*|API_KEY=${INTERVALS_API_KEY}|' /opt/intervals-mcp-server/.env
  sed -i 's|ATHLETE_ID=.*|ATHLETE_ID=${INTERVALS_ATHLETE_ID}|' /opt/intervals-mcp-server/.env
  systemctl restart intervals-mcp
"
msg_ok "Credentials configured"

description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} SSE endpoint available at:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8765/sse${CL}"
echo -e "${INFO}${YW} Update credentials anytime:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}pct exec $CTID -- nano /opt/intervals-mcp-server/.env${CL}"
