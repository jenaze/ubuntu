#!/bin/bash

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Function to display usage
usage() {
    echo "Usage: $0 [install|clean]"
    echo "  install - Set up port redirection"
    echo "  clean   - Remove all redirection rules"
    exit 1
}

# Function to get bypass ports from user
get_bypass_ports() {
    read -p "Enter ports to bypass (comma-separated, e.g. 22,80,2052): " ports_input
    IFS=',' read -ra PORTS <<< "$ports_input"
    for port in "${PORTS[@]}"; do
        # Validate port number
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            echo "Invalid port number: $port"
            exit 1
        fi
    done
}

# Function to install rules
install_rules() {
    echo "Installing port redirection rules..."
    
    # Get bypass ports from user
    get_bypass_ports
    
    # Flush existing rules in PREROUTING chain
    iptables -t nat -F PREROUTING
    
    # Add bypass rules
    for port in "${PORTS[@]}"; do
        iptables -t nat -A PREROUTING -p tcp --dport "$port" -j ACCEPT
        echo "Added bypass rule for port $port"
    done
    
    # Add redirect rule for all other traffic
    iptables -t nat -A PREROUTING -p tcp -j REDIRECT --to-ports 443
    echo "Added redirect rule to port 443"
    
    # Ask about permanent save
    read -p "Save rules permanently? [y/N]: " save_choice
    if [[ "$save_choice" =~ ^[Yy]$ ]]; then
        # Install iptables-persistent if not present
        if ! dpkg -l | grep -q iptables-persistent; then
            echo "Installing iptables-persistent..."
            apt-get update
            apt-get install -y iptables-persistent
        fi
        
        # Save rules
        netfilter-persistent save
        echo "Rules saved permanently"
    else
        echo "Rules are temporary and will be lost on reboot"
    fi
}

# Function to clean rules
clean_rules() {
    echo "Removing all port redirection rules..."
    
    # Flush PREROUTING chain
    iptables -t nat -F PREROUTING
    
    # Ask about removing persistent rules
    if [ -f /etc/iptables/rules.v4 ]; then
        read -p "Remove persistent rules? [y/N]: " remove_choice
        if [[ "$remove_choice" =~ ^[Yy]$ ]]; then
            > /etc/iptables/rules.v4
            echo "Persistent rules removed"
        fi
    fi
    
    echo "All redirection rules removed"
}

# Main script logic
case "${1:-install}" in
    install)
        install_rules
        ;;
    clean)
        clean_rules
        ;;
    *)
        usage
        ;;
esac

# Show current rules
echo -e "\nCurrent NAT rules:"
iptables -t nat -L PREROUTING -n -v --line-numbers
