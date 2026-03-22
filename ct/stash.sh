#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/kgscorpio/ProxmoxVE/main/misc/build.func)

# --- Metadata ---
APP="Stash"
var_tags="${var_tags:-media;video}"
var_cpu="${var_cpu:-2}"           # Stash uses CPU for generating "scrub" previews
var_ram="${var_ram:-2048}"        # 2GB is the sweet spot for scanning large libraries
var_disk="${var_disk:-20}"        # Stash metadata (blobs/thumbnails) grows fast
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/stash ]]; then msg_error "No ${APP} Installation Found!"; exit; fi
  msg_info "Updating ${APP} Binary"
  systemctl stop stash
  wget -qO /opt/stash/stash https://github.com/stashapp/stash/releases/latest/download/stash-linux-amd64
  chmod +x /opt/stash/stash
  systemctl start stash
  msg_ok "Updated ${APP}"
  exit
}

start
build_container

# --- Post-Build Identity Mapping & Security ---
msg_info "Starting Advanced Identity Mapping"

# 1. Get User Input & Resolve IDs
read -p "Enter Host Username to map to CT Root (e.g., your login): " MAPPED_USER
MAP_UID=$(id -u "$MAPPED_USER" 2>/dev/null)
MAP_GID=$(id -g "$MAPPED_USER" 2>/dev/null)

# 2. Security Guardrail
if [[ -z "$MAP_UID" || "$MAP_UID" -eq 0 ]]; then
  msg_error "Invalid UID ($MAP_UID). Mapping to Root (0) is blocked for security."
  exit 1
fi

# 3. Configure Host Authorization (subuid/subgid)
if ! grep -q "root:$MAP_UID:1" /etc/subuid; then
  echo "root:$MAP_UID:1" >> /etc/subuid
  echo "root:$MAP_GID:1" >> /etc/subgid
fi

# 4. Apply Universal ID Mapping to Config
pct stop $CTID
cat <<EOF >> /etc/pve/lxc/${CTID}.conf
# Custom Mapping: Internal Root (0) -> Host User ($MAP_UID)
lxc.idmap: u 0 $MAP_UID 1
lxc.idmap: g 0 $MAP_GID 1
# Map remaining 65534 IDs to standard Proxmox range
lxc.idmap: u 1 100001 65534
lxc.idmap: g 1 100001 65534
EOF

# 5. Surgical Permission Fix from Host
msg_info "Surgically re-mapping file ownership on Host..."
MOUNT_PATH=$(pct mount $CTID)
# Only change files owned by the temporary 'root' (100000)
find "$MOUNT_PATH" -uid 100000 -exec chown $MAP_UID {} +
find "$MOUNT_PATH" -gid 100000 -exec chgrp $MAP_GID {} +
pct unmount $CTID

pct start $CTID
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup initialized with Host User ${MAPPED_USER}!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9999${CL}"
