#!/bin/bash

# Generate a random password if none provided, or use the first argument
PASSWORD="${1:-$(openssl rand -base64 12)}"

# Configure SSH to allow root login (with key authentication only is safer)
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin without-password/' /etc/ssh/sshd_config

# If you really need password authentication, use this instead:
# sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Set the root password
echo "root:${PASSWORD}" | chpasswd

# Restart SSH service
systemctl restart sshd

# Output the password if it was generated
if [ -z "$1" ]; then
    echo "Generated root password: ${PASSWORD}"
    echo "Please change it immediately after login"
fi
