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

INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/CorentinBarban/intervals-mcp-server/main/proxmox/install/intervals-mcp-install.sh"

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
    --unprivileged 1             \
    --features    nesting=1      \
    --onboot      1              \
    --start       0
  msg_ok "Container créé"

  msg_info "Démarrage du container"
  pct start "$CTID"
  # Attente connectivité réseau
  local retries=30
  until pct exec "$CTID" -- bash -c "ping -c1 8.8.8.8 &>/dev/null" 2>/dev/null || (( retries-- == 0 )); do
    sleep 2
  done
  msg_ok "Container démarré"
}

# -----------------------------------------------------------------------------
# Installation de l'application
# -----------------------------------------------------------------------------
run_install_script() {
  msg_info "Installation de ${APP} dans le container"
  # Télécharge le script sur l'hôte (curl disponible ici), puis le pousse dans le container
  local tmp_script
  tmp_script=$(mktemp /tmp/intervals-mcp-install-XXXXXX.sh)
  curl -fsSL "$INSTALL_SCRIPT_URL" -o "$tmp_script"
  pct push "$CTID" "$tmp_script" /tmp/intervals-mcp-install.sh
  rm -f "$tmp_script"
  pct exec "$CTID" -- bash /tmp/intervals-mcp-install.sh
  msg_ok "Application installée"
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
