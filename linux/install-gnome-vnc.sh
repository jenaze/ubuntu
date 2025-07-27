#!/bin/bash
# -------------------------------------------------------------
# ask-resolution.sh  –  run once as root after install-gnome-vnc.sh
# -------------------------------------------------------------
set -e

# Ask for resolution (default 1280x800)
read -p "Enter VNC resolution [1280x800]: " RES
RES=${RES:-1280x800}

# Persist the chosen resolution
echo "$RES" >/root/.vnc/vnc_resolution

# Re-create service file with the chosen resolution
cat >/etc/systemd/system/vncserver@.service <<EOF
[Unit]
Description=Start TigerVNC server at startup
After=syslog.target network.target

[Service]
Type=forking
User=root
PAMName=login
PIDFile=/root/.vnc/%H:%i.pid
ExecStartPre=-/usr/bin/vncserver -kill :%i > /dev/null 2>&1
ExecStart=/usr/bin/vncserver :%i -geometry $(cat /root/.vnc/vnc_resolution) -depth 24 -localhost no
ExecStop=/usr/bin/vncserver -kill :%i

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl restart vncserver@1.service

echo "Resolution set to: $RES"
echo "Reboot or run 'systemctl restart vncserver@1' to apply immediately."
