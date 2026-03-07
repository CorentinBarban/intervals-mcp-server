#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: community adaptation
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/mvilanova/intervals-mcp-server

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Python 3 & build tools"
$STD apt-get install -y python3 python3-pip python3-venv git build-essential curl
msg_ok "Installed Python 3 & build tools"

msg_info "Installing uv"
$STD curl -LsSf https://astral.sh/uv/install.sh | sh
ln -sf /root/.local/bin/uv /usr/local/bin/uv
msg_ok "Installed uv"

msg_info "Installing ${APP}"
git clone -q --depth 1 https://github.com/mvilanova/intervals-mcp-server.git /opt/intervals-mcp-server
cd /opt/intervals-mcp-server
$STD uv venv --python python3
$STD uv sync --no-dev
msg_ok "Installed ${APP}"

msg_info "Configuring environment"
cat <<EOF >/opt/intervals-mcp-server/.env
# Intervals.icu API Configuration
# Edit this file and set your credentials, then restart the service:
#   systemctl restart intervals-mcp

# Required: Your Intervals.icu API Key (Settings > API)
API_KEY=your_intervals_api_key_here

# Required: Your Intervals.icu Athlete ID (visible in the URL, e.g. i12345)
ATHLETE_ID=your_athlete_id_here

# Optional: API base URL (default shown below)
# INTERVALS_API_BASE_URL=https://intervals.icu/api/v1
EOF
chmod 600 /opt/intervals-mcp-server/.env
msg_ok "Configured environment"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/intervals-mcp.service
[Unit]
Description=Intervals.icu MCP Server (SSE)
Documentation=https://github.com/mvilanova/intervals-mcp-server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/intervals-mcp-server
EnvironmentFile=/opt/intervals-mcp-server/.env
Environment=MCP_TRANSPORT=sse
Environment=FASTMCP_HOST=0.0.0.0
Environment=FASTMCP_PORT=8765
Environment=FASTMCP_LOG_LEVEL=INFO
ExecStart=/opt/intervals-mcp-server/.venv/bin/python src/intervals_mcp_server/server.py
StandardOutput=file:/var/log/intervals-mcp.out
StandardError=file:/var/log/intervals-mcp.err
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now intervals-mcp
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
