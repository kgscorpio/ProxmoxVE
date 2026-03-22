#!/usr/bin/env bash
#set -x  # Uncomment this line to see EVERY command executed for deep debugging

# 1. Check if the source file is actually reachable
INSTALL_FUNC_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/install.func"
if ! curl -sSf "$INSTALL_FUNC_URL" > /dev/null; then
  echo "Error: Cannot reach install.func at $INSTALL_FUNC_URL"
  exit 1
fi
source <(curl -s "$INSTALL_FUNC_URL")

msg_info "Installing Dependencies"
$STD apt-get update
$STD apt-get install -y curl sudo ffmpeg
msg_ok "Dependencies Installed"

msg_info "Setting up Stash"
mkdir -p /opt/stash /var/lib/stash

# 2. Robust URL extraction with debug message
msg_info "Fetching latest Stash release URL..."
STASH_URL=$(curl -s https://api.github.com/repos/stashapp/stash/releases/latest \
  | grep "browser_download_url" \
  | grep "/stash-linux\"" \
  | cut -d '"' -f 4 \
  | head -n 1)

if [[ -z "$STASH_URL" ]]; then
  msg_error "Failed to find download URL. GitHub API might be rate-limiting."
  exit 1
fi

# Print the URL so you can see it in the Proxmox console
echo -e "${INFO}${YW} Download URL: ${STASH_URL}${CL}"

msg_info "Downloading Stash binary..."
# Removed -q from wget so you can see the download progress/errors
wget -qLO /opt/stash/stash "$STASH_URL"
chmod +x /opt/stash/stash
msg_ok "Stash Binary Downloaded"

msg_info "Creating Systemd Service"
cat <<EOF >/etc/systemd/system/stash.service
[Unit]
Description=Stash Daemon
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/var/lib/stash
ExecStart=/opt/stash/stash --config /var/lib/stash/config.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now stash.service
msg_ok "Stash Service Started"

motd_ssh
customize
