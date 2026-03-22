#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/kgscorpio/ProxmoxVE/main/misc/build.func)

# --- Metadata ---
APP="Stash"
var_tags="${var_tags:-stash}"
var_cpu="${var_cpu:-2}"           # Stash uses CPU for generating "scrub" previews
var_ram="${var_ram:-2048}"        # 2GB is the sweet spot for scanning large libraries
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"
# Robust URL extraction: Grabs the 4th field between double quotes
STASH_URL=$(curl -s https://api.github.com/repos/stashapp/stash/releases/latest \
  | grep "browser_download_url" \
  | grep "/stash-linux\"" \
  | cut -d '"' -f 4)

if [[ -z "$STASH_URL" ]]; then
  msg_error "Failed to find download URL. GitHub API might be rate-limiting."
  exit 1
fi
msg_info "Using Download url $STASH_URL"


header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  
  if [[ ! -f /opt/stash/stash ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # 1. Version Check
  local_version=$(/opt/stash/stash -v | awk '{print $1}')
  latest_version=$(curl -s https://api.github.com/repos/stashapp/stash/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

  if [ "$local_version" == "$latest_version" ]; then
    msg_ok "Stash is already up to date (${local_version})."
    exit
  fi

  # 2. Pre-Update Backup
  msg_info "Backing up Stash Data (Database & Config)"
  BACKUP_DIR="/var/lib/stash_backups"
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  mkdir -p "$BACKUP_DIR"
  # We use 'cp -r' to copy the current database and config
  cp -r /var/lib/stash "$BACKUP_DIR/stash_backup_$TIMESTAMP"
  # Keep only the last 5 backups to save disk space
  (cd "$BACKUP_DIR" && ls -t | tail -n +6 | xargs rm -rf)
  msg_ok "Backup created: $BACKUP_DIR/stash_backup_$TIMESTAMP"

  # 3. Perform Update
  msg_info "Updating Stash from ${local_version} to ${latest_version}"
  systemctl stop stash
  
  STASH_URL=$(curl -s https://api.github.com/repos/stashapp/stash/releases/latest | grep "browser_download_url.*linux_amd64" | cut -d : -f 2,3 | tr -d \" | xargs)
  wget -qO /opt/stash/stash "$STASH_URL"
  chmod +x /opt/stash/stash
  
  systemctl start stash
  msg_ok "Updated ${APP} to ${latest_version}"
  exit
}

start
build_container

# ... (after build_container) ...

# 1. Get Input
echo -e "${INFO}${YW} Configuring Identity Mapping...${CL}"
read -r -p "Enter Host Username to map to CT Root [root]: " MAPPED_USER
MAPPED_USER=${MAPPED_USER:-root}
MAP_UID=$(id -u "$MAPPED_USER" 2>/dev/null)
MAP_GID=$(id -g "$MAPPED_USER" 2>/dev/null)

# 2. Security Check
[[ "$MAP_UID" -eq 0 ]] && { msg_error "Mapping to Root is not allowed."; exit 1; }
[[ -z "$MAP_UID" ]] && { msg_error "User not found."; exit 1; }

# 3. Host Authorization
if ! grep -q "root:$MAP_UID:1" /etc/subuid; then
  msg_info "Authorizing UID mapping in /etc/subuid..."
  echo "root:$MAP_UID:1" >> /etc/subuid
  echo "root:$MAP_GID:1" >> /etc/subgid
fi

# 4. Config Injection
pct stop $CTID &>/dev/null
cat <<EOF >> /etc/pve/lxc/${CTID}.conf
lxc.idmap: u 0 $MAP_UID 1
lxc.idmap: g 0 $MAP_GID 1
lxc.idmap: u 1 100001 65534
lxc.idmap: g 1 100001 65534
EOF

# --- Corrected Surgical Permission Fix ---
msg_info "Surgically re-mapping file ownership..."
MOUNT_OUTPUT=$(pct mount $CTID)
MOUNT_PATH=$(echo "$MOUNT_OUTPUT" | cut -d"'" -f2)

if [[ -d "$MOUNT_PATH" ]]; then
  # Use -h to handle broken symlinks without crashing
  find "$MOUNT_PATH" -uid 100000 -exec chown -h $MAP_UID {} +
  find "$MOUNT_PATH" -gid 100000 -exec chgrp -h $MAP_GID {} +
  pct unmount $CTID &>/dev/null
fi

pct start $CTID &>/dev/null
msg_ok "Identity mapping completed for ${GN}${MAPPED_USER}${CL}"
