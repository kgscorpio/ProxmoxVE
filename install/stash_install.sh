#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/kgscorpio/ProxmoxVE/main/misc/install.func)

msg_info "Installing Dependencies"
$STD apt-get update
$STD apt-get install -y curl sudo ffmpeg
msg_ok "Dependencies Installed"

msg_info "Setting up Stash"
mkdir -p /opt/stash /var/lib/stash
# Fetch latest release binary URL
STASH_URL=$(curl -s https://api.github.com/repos/stashapp/stash/releases/latest | grep "browser_download_url.*linux_amd64" | cut -d : -f 2,3 | tr -d \" | xargs)
wget -qO /opt/stash/stash "$STASH_URL"
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
