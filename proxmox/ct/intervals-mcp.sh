#!/usr/bin/env bash
# =============================================================================
# Intervals.icu MCP Server — Proxmox LXC Installer
# Usage (depuis le nœud Proxmox) :
#   bash <(curl -fsSL https://raw.githubusercontent.com/CorentinBarban/intervals-mcp-server/main/proxmox/ct/intervals-mcp.sh)
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Couleurs
# -----------------------------------------------------------------------------
YW="\033[33m"; GN="\033[1;92m"; RD="\033[01;31m"; CL="\033[m"; BFR="\r\033[K"
INFO="ℹ️ "; OK="✔"; ERR="✘"; GEAR="⚙"

msg_info()  { echo -e " ${GEAR} ${YW}${1}${CL}"; }
msg_ok()    { echo -e "${BFR} ${OK} ${GN}${1}${CL}"; }
msg_error() { echo -e " ${ERR} ${RD}${1}${CL}" >&2; }

REPO_URL="https://github.com/CorentinBarban/intervals-mcp-server.git"

# -----------------------------------------------------------------------------
# Valeurs par défaut
# -----------------------------------------------------------------------------
APP="Intervals-MCP"
CTID=$(pvesh get /cluster/nextid)
HOSTNAME="intervals-mcp"
TEMPLATE=""   # résolu dynamiquement dans check_prerequisites
STORAGE="local-lvm"
DISK_SIZE=4
MEMORY=512
SWAP=512
CORES=1
BRIDGE="vmbr0"
MCP_PORT=8765

# -----------------------------------------------------------------------------
# Pré-requis
# -----------------------------------------------------------------------------
check_prerequisites() {
  [[ $EUID -eq 0 ]] || { msg_error "Ce script doit être exécuté en tant que root."; exit 1; }
  command -v pct   &>/dev/null || { msg_error "pct introuvable — exécuter sur un nœud Proxmox VE."; exit 1; }
  command -v pvesh &>/dev/null || { msg_error "pvesh introuvable."; exit 1; }

  local tpl_cache="/var/lib/vz/template/cache"

  # Détermine le nom exact depuis pveam (source de vérité)
  msg_info "Vérification du catalogue de templates..."
  pveam update &>/dev/null
  local tpl_name
  tpl_name=$(pveam available --section system 2>/dev/null \
    | awk '{print $2}' | grep "debian-12-standard" | sort -V | tail -1)
  [[ -n "$tpl_name" ]] || { msg_error "Aucun template Debian 12 trouvé dans pveam."; exit 1; }

  # Vérifie que le fichier existe physiquement sur disque
  if [[ ! -f "${tpl_cache}/${tpl_name}" ]]; then
    msg_info "Téléchargement du template $tpl_name"
    pveam download local "$tpl_name"
    msg_ok "Template téléchargé"
  fi

  TEMPLATE="local:vztmpl/${tpl_name}"
  msg_ok "Template : ${tpl_name}"
}

# -----------------------------------------------------------------------------
# Prompts interactifs
# -----------------------------------------------------------------------------
prompt_credentials() {
  echo ""
  echo -e " ${INFO}${YW}Credentials Intervals.icu${CL}"
  while true; do
    read -r -p "   API Key (Settings > API) : " INTERVALS_API_KEY
    [[ -n "$INTERVALS_API_KEY" ]] && break
    msg_error "L'API Key ne peut pas être vide."
  done
  while true; do
    read -r -p "   Athlete ID (ex: i12345)  : " INTERVALS_ATHLETE_ID
    [[ -n "$INTERVALS_ATHLETE_ID" ]] && break
    msg_error "L'Athlete ID ne peut pas être vide."
  done
  echo ""
}

prompt_container_settings() {
  if command -v whiptail &>/dev/null; then
    CTID=$(whiptail --inputbox "Container ID" 8 40 "$CTID" --title "$APP" 3>&1 1>&2 2>&3) || true
    HOSTNAME=$(whiptail --inputbox "Hostname" 8 40 "$HOSTNAME" --title "$APP" 3>&1 1>&2 2>&3) || true
    MEMORY=$(whiptail --inputbox "RAM (Mo)" 8 40 "$MEMORY" --title "$APP" 3>&1 1>&2 2>&3) || true
    DISK_SIZE=$(whiptail --inputbox "Disque (Go)" 8 40 "$DISK_SIZE" --title "$APP" 3>&1 1>&2 2>&3) || true
    CORES=$(whiptail --inputbox "vCPU" 8 40 "$CORES" --title "$APP" 3>&1 1>&2 2>&3) || true
  else
    echo -e " ${INFO}${YW}Configuration du container (Entrée = valeur par défaut)${CL}"
    read -r -p "   Container ID  [$CTID]     : " v; CTID="${v:-$CTID}"
    read -r -p "   Hostname      [$HOSTNAME] : " v; HOSTNAME="${v:-$HOSTNAME}"
    read -r -p "   RAM Mo        [$MEMORY]   : " v; MEMORY="${v:-$MEMORY}"
    read -r -p "   Disque Go     [$DISK_SIZE]: " v; DISK_SIZE="${v:-$DISK_SIZE}"
    read -r -p "   vCPU          [$CORES]    : " v; CORES="${v:-$CORES}"
    echo ""
  fi
}

# -----------------------------------------------------------------------------
# Création du container
# -----------------------------------------------------------------------------
create_container() {
  msg_info "Création du container LXC $CTID ($HOSTNAME)"
  pct create "$CTID" "$TEMPLATE" \
    --hostname    "$HOSTNAME"    \
    --storage     "$STORAGE"     \
    --rootfs      "${STORAGE}:${DISK_SIZE}" \
    --memory      "$MEMORY"      \
    --swap        "$SWAP"        \
    --cores       "$CORES"       \
    --net0        "name=eth0,bridge=${BRIDGE},ip=dhcp" \
    --nameserver  "8.8.8.8 8.8.4.4" \
    --unprivileged 1             \
    --features    nesting=1      \
    --onboot      1              \
    --start       0
  msg_ok "Container créé"

  msg_info "Démarrage du container"
  pct start "$CTID"
  # Attente résolution DNS (pas uniquement connectivité IP)
  local retries=30
  until pct exec "$CTID" -- bash -c "curl -fsSo /dev/null https://deb.debian.org 2>/dev/null" || (( retries-- == 0 )); do
    sleep 2
  done
  msg_ok "Container démarré"
}

# -----------------------------------------------------------------------------
# Installation de l'application (commandes exécutées directement via pct exec)
# -----------------------------------------------------------------------------
run_install_script() {
  msg_info "Mise à jour du système"
  pct exec "$CTID" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get install -y --no-install-recommends \
      python3 python3-pip python3-venv git curl ca-certificates build-essential
    apt-get clean
    rm -rf /var/lib/apt/lists/*
  "
  msg_ok "Système mis à jour"

  msg_info "Installation de uv"
  pct exec "$CTID" -- bash -c "
    curl -LsSf https://astral.sh/uv/install.sh | sh
    ln -sf /root/.local/bin/uv /usr/local/bin/uv
  "
  msg_ok "uv installé"

  msg_info "Clonage et installation de ${APP}"
  pct exec "$CTID" -- bash -c "
    git clone -q --depth 1 ${REPO_URL} /opt/intervals-mcp-server
    cd /opt/intervals-mcp-server
    /root/.local/bin/uv venv --python python3 -q
    /root/.local/bin/uv sync --no-dev -q
  "
  msg_ok "${APP} installé"

  msg_info "Création du fichier d'environnement"
  pct exec "$CTID" -- bash -c "
    cat > /opt/intervals-mcp-server/.env << 'ENVEOF'
API_KEY=PLACEHOLDER_API_KEY
ATHLETE_ID=PLACEHOLDER_ATHLETE_ID
ENVEOF
    chmod 600 /opt/intervals-mcp-server/.env
  "
  msg_ok "Fichier .env créé"

  msg_info "Création du service systemd"
  pct exec "$CTID" -- bash -c "
    cat > /etc/systemd/system/intervals-mcp.service << 'SVCEOF'
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
SVCEOF
    systemctl daemon-reload
    systemctl enable -q intervals-mcp
  "
  msg_ok "Service systemd créé"
}

# -----------------------------------------------------------------------------
# Injection des credentials
# -----------------------------------------------------------------------------
inject_credentials() {
  msg_info "Injection des credentials"
  pct exec "$CTID" -- bash -c "
    sed -i 's|API_KEY=.*|API_KEY=${INTERVALS_API_KEY}|' /opt/intervals-mcp-server/.env
    sed -i 's|ATHLETE_ID=.*|ATHLETE_ID=${INTERVALS_ATHLETE_ID}|' /opt/intervals-mcp-server/.env
    systemctl restart intervals-mcp
  "
  msg_ok "Credentials configurés"
}

# -----------------------------------------------------------------------------
# Vérification
# -----------------------------------------------------------------------------
verify() {
  local status
  status=$(pct exec "$CTID" -- systemctl is-active intervals-mcp 2>/dev/null || echo "inactive")
  if [[ "$status" == "active" ]]; then
    local ip
    ip=$(pct exec "$CTID" -- bash -c "hostname -I | awk '{print \$1}'" 2>/dev/null || echo "?")
    echo ""
    msg_ok "${APP} déployé avec succès !"
    echo ""
    echo -e "   Container ID : ${GN}${CTID}${CL}"
    echo -e "   Endpoint SSE : ${GN}http://${ip}:${MCP_PORT}/sse${CL}"
    echo ""
    echo -e " ${INFO}${YW}Modifier les credentials :${CL}"
    echo    "   pct exec ${CTID} -- nano /opt/intervals-mcp-server/.env"
    echo -e " ${INFO}${YW}Voir les logs :${CL}"
    echo    "   pct exec ${CTID} -- journalctl -u intervals-mcp -f"
    echo ""
  else
    msg_error "Le service ne s'est pas démarré (status: ${status})"
    echo "   pct exec ${CTID} -- journalctl -u intervals-mcp -n 50"
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# Point d'entrée
# -----------------------------------------------------------------------------
echo -e "\n ${GN}=== ${APP} — Proxmox LXC Installer ===${CL}\n"
check_prerequisites
prompt_credentials
prompt_container_settings
create_container
run_install_script
inject_credentials
verify
