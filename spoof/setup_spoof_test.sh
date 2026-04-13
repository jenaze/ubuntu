#!/bin/bash

# بررسی دسترسی روت (Root)
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run this script as root (use sudo)."
  exit 1
fi

# بررسی پارامترهای ورودی
if [ "$#" -eq 2 ]; then
    TARGET_IP=$1
    SPOOFED_IP=$2
    echo "✅ Using provided parameters:"
    echo "   🌐 Target IP: $TARGET_IP"
    echo "   🎭 Spoofed IP: $SPOOFED_IP"
    echo "------------------------------------------------------"
else
    echo "ℹ️ Tip: You can also run this script with parameters:"
    echo "   Usage: sudo ./setup_spoof_test.sh <TARGET_IP> <SPOOFED_IP>"
    echo "⏳ Falling back to interactive mode..."
    echo "------------------------------------------------------"
    read -p "🌐 Enter Target IP (Server 2 IP - e.g., 91.108.18.17): " TARGET_IP
    read -p "🎭 Enter Spoofed Source IP (e.g., 1.2.3.4): " SPOOFED_IP
fi

# اگر ورودی‌ها خالی بود خارج شود
if [ -z "$TARGET_IP" ] || [ -z "$SPOOFED_IP" ]; then
    echo "⚠️ IP addresses cannot be empty. Exiting..."
    exit 1
fi

echo "🔄 Updating package lists..."
apt-get update -y

echo "📦 Installing prerequisites (iptables, tcpdump, iproute2)..."
apt-get install -y iptables tcpdump iproute2

echo "⚙️ Enabling IP Forwarding in sysctl..."
# فعال‌سازی فورواردینگ آی‌پی
sysctl -w net.ipv4.ip_forward=1
if grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf; then
  sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
else
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p

echo "✅ Prerequisites configured successfully!"
echo "------------------------------------------------------"

echo "🧹 Clearing existing POSTROUTING rules for this target (if any)..."
iptables -t nat -D POSTROUTING -d "$TARGET_IP" -j SNAT --to-source "$SPOOFED_IP" 2>/dev/null

echo "🔗 Adding SNAT rule..."
iptables -t nat -A POSTROUTING -d "$TARGET_IP" -j SNAT --to-source "$SPOOFED_IP"

echo "------------------------------------------------------"
echo "🚀 All Done!"
echo "Now, leave this terminal open and start pinging the target:"
echo "👉 ping $TARGET_IP"
echo ""
echo "On your SECOND server ($TARGET_IP), run this command to monitor the traffic:"
echo "👉 tcpdump -i any icmp"
echo "------------------------------------------------------"
