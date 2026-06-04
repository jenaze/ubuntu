#!/bin/bash

# 1. Check if a password was provided
if [ -z "$1" ]; then
  echo "Error: No password provided."
  echo "Usage: bash $0 yoursecurepassword"
  exit 1
fi

# 2. Set the root password
echo "root:$1" | chpasswd
echo "✅ Root password updated."

# 3. Update main SSH configuration
SSHD_CONFIG="/etc/ssh/sshd_config"
cp $SSHD_CONFIG ${SSHD_CONFIG}.bak # Backup original

sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' $SSHD_CONFIG
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' $SSHD_CONFIG

# 4. Handle Ubuntu 22.04/24.04 override directories
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
if [ -d "$SSHD_CONFIG_DIR" ]; then
    echo "PermitRootLogin yes" > $SSHD_CONFIG_DIR/01-rootlogin.conf
    echo "PasswordAuthentication yes" >> $SSHD_CONFIG_DIR/01-rootlogin.conf
fi
echo "✅ SSH configuration updated."

# 5. Restart SSH based on the OS version
systemctl daemon-reload

if systemctl list-unit-files | grep -q "ssh.socket"; then
    # Ubuntu 24.04+ (Socket Activation)
    echo "🔄 Detected Ubuntu 24.04+ (socket-based SSH). Restarting..."
    systemctl restart ssh.socket
    systemctl restart ssh.service 2>/dev/null || true
else
    # Older Ubuntu versions
    echo "🔄 Detected older Ubuntu (service-based SSH). Restarting..."
    systemctl restart sshd || systemctl restart ssh
fi

echo "✅ Success! You can now log in as root."
