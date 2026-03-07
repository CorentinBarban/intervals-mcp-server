#!/usr/bin/env bash
# =============================================================================
# Intervals.icu MCP Server — Install script (runs inside the LXC container)
# Appelé par proxmox/ct/intervals-mcp.sh via pct exec
# =============================================================================
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

YW="\033[33m"; GN="\033[1;92m"; CL="\033[m"; BFR="\r\033[K"
msg_info() { echo -e "  ⚙ ${YW}${1}${CL}"; }
msg_ok()   { echo -e "${BFR}  ✔ ${GN}${1}${CL}"; }

# -----------------------------------------------------------------------------
msg_info "Mise à jour du système"
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y --no-install-recommends \
  python3 python3-pip python3-venv \
  git curl ca-certificates build-essential
apt-get clean
rm -rf /var/lib/apt/lists/*
msg_ok "Système mis à jour"

# -----------------------------------------------------------------------------
msg_info "Installation de uv"
curl -LsSf https://astral.sh/uv/install.sh | sh
ln -sf /root/.local/bin/uv /usr/local/bin/uv
msg_ok "uv installé"

# -----------------------------------------------------------------------------
msg_info "Clonage du dépôt"
git clone -q --depth 1 https://github.com/CorentinBarban/intervals-mcp-server.git /opt/intervals-mcp-server
cd /opt/intervals-mcp-server
uv venv --python python3 -q
uv sync --no-dev -q
msg_ok "Application installée"

# -----------------------------------------------------------------------------
msg_info "Création du fichier d'environnement"
cat <<'EOF' > /opt/intervals-mcp-server/.env
# Intervals.icu API Configuration
API_KEY=PLACEHOLDER_API_KEY
ATHLETE_ID=PLACEHOLDER_ATHLETE_ID
# INTERVALS_API_BASE_URL=https://intervals.icu/api/v1
EOF
chmod 600 /opt/intervals-mcp-server/.env
msg_ok "Fichier .env créé"

# -----------------------------------------------------------------------------
msg_info "Création du service systemd"
cat <<EOF > /etc/systemd/system/intervals-mcp.service
[Unit]
Description=Intervals.icu MCP Server (SSE)
Documentation=https://github.com/CorentinBarban/intervals-mcp-server
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
systemctl daemon-reload
systemctl enable -q intervals-mcp
msg_ok "Service systemd créé"
