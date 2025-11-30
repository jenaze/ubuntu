#!/bin/bash

# ---------------- COLORS ----------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---------------- CONFIG PATHS ----------------
CONFIG_DIR="/etc/lena-vxlan"
CONF_FILES="$CONFIG_DIR/confs"
BRIDGE_SCRIPT="/usr/local/bin/vxlan_loader.sh"
HAPROXY_CFG="/etc/haproxy/haproxy.cfg"

# ---------------- CHECK ROOT ----------------
if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}[!] This script must be run as root.${NC}"
    exit 1
fi

# ---------------- INITIAL SETUP ----------------
mkdir -p "$CONF_FILES"

# ---------------- DEPENDENCIES ----------------
check_dependencies() {
    local DEPS_MARKER="/etc/.lena_deps_v2"
    if [[ ! -f "$DEPS_MARKER" ]]; then
        echo -e "${YELLOW}[*] Installing dependencies...${NC}"
        apt-get update -y -qq
        for pkg in iproute2 net-tools grep awk iputils-ping jq curl iptables haproxy; do
            if ! command -v $pkg &> /dev/null; then
                apt-get install -y -qq $pkg
            fi
        done
        touch "$DEPS_MARKER"
    fi
}

# ---------------- HELPER FUNCTIONS ----------------

get_next_vni() {
    # Finds the highest VNI used and adds 1. Starts at 100.
    local max_vni=100
    if ls $CONF_FILES/*.conf 1> /dev/null 2>&1; then
        for f in $CONF_FILES/*.conf; do
            local vni=$(grep "VNI=" "$f" | cut -d'=' -f2)
            if [[ "$vni" -ge "$max_vni" ]]; then
                max_vni=$vni
            fi
        done
    fi
    echo $((max_vni + 1))
}

regenerate_systemd_script() {
    # This creates the loader script that runs on boot to bring up ALL tunnels
    cat <<EOF > "$BRIDGE_SCRIPT"
#!/bin/bash
# Load all VXLAN configurations
for cfg in $CONF_FILES/*.conf; do
    [ -e "\$cfg" ] || continue
    source "\$cfg"
    
    # Delete if exists to avoid errors
    ip link del "\$IFACE" 2>/dev/null
    
    # Get Main Interface
    MAIN_IF=\$(ip route get 1.1.1.1 | awk '{print \$5}' | head -n1)
    
    # Create Link
    ip link add "\$IFACE" type vxlan id "\$VNI" local "\$LOCAL_BIND_IP" remote "\$REMOTE_IP" dev "\$MAIN_IF" dstport "\$DSTPORT" nolearning
    ip addr add "\$INTERNAL_IP" dev "\$IFACE"
    ip link set "\$IFACE" up
    
    # Keepalive (Background)
    ( while true; do ping -c 1 "\$TARGET_PING_IP" >/dev/null 2>&1; sleep 30; done ) &
done
EOF
    chmod +x "$BRIDGE_SCRIPT"

    # Create/Update Systemd Service
    cat <<EOF > /etc/systemd/system/vxlan-manager.service
[Unit]
Description=Lena VXLAN Tunnel Manager
After=network.target

[Service]
ExecStart=$BRIDGE_SCRIPT
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable vxlan-manager.service >/dev/null 2>&1
}

regenerate_haproxy() {
    # Rebuilds HAProxy config based on all active tunnels that have forwarding enabled
    cat <<EOL > "$HAPROXY_CFG"
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 4096

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

EOL

    # Loop through configs to find forwarding rules
    if ls $CONF_FILES/*.conf 1> /dev/null 2>&1; then
        for f in $CONF_FILES/*.conf; do
            source "$f"
            # If this tunnel has forwarding enabled (Only defined on Master side)
            if [[ -n "$FORWARD_PORTS" ]]; then
                IFS=',' read -ra ports <<< "$FORWARD_PORTS"
                for port in "${ports[@]}"; do
                    # Check if backend already defined to avoid dupes (basic check)
                    echo "frontend ft_${VNI}_${port}" >> "$HAPROXY_CFG"
                    echo "    bind *:${port}" >> "$HAPROXY_CFG"
                    echo "    default_backend bk_${VNI}_${port}" >> "$HAPROXY_CFG"
                    echo "" >> "$HAPROXY_CFG"
                    echo "backend bk_${VNI}_${port}" >> "$HAPROXY_CFG"
                    echo "    server remote_${VNI} ${TARGET_PING_IP}:${port} check" >> "$HAPROXY_CFG"
                    echo "" >> "$HAPROXY_CFG"
                done
            fi
        done
    fi
    
    systemctl restart haproxy
}

# ---------------- ACTIONS ----------------

add_tunnel() {
    echo -e "${CYAN}=== Add New Connection ===${NC}"
    echo "1) I am the CENTRAL Server (IRAN)"
    echo "2) I am the REMOTE Server (KHAREJ)"
    read -p "Select Role: " role

    MAIN_IP=$(hostname -I | awk '{print $1}')
    
    if [[ "$role" == "1" ]]; then
        # MASTER SETUP
        read -p "Enter Remote Server (Kharej) IP: " R_IP
        
        VNI=$(get_next_vni)
        echo -e "${GREEN}[*] Generated Tunnel ID (VNI): ${VNI}${NC}"
        
        # Determine Port for VXLAN (Randomized or Fixed per VNI to avoid collision)
        VXLAN_PORT=$((4000 + VNI)) 
        
        # Internal IP Logic: 10.VNI.0.1/24
        # Example VNI 101 -> IP 10.101.0.1
        LOCAL_INT_IP="10.${VNI}.0.1/24"
        REMOTE_INT_IP="10.${VNI}.0.2" # For Pinging
        
        read -p "Do you want to forward ports via HAProxy? (y/n): " hap_opt
        FWD_PORTS=""
        if [[ "$hap_opt" == "y" || "$hap_opt" == "Y" ]]; then
            read -p "Enter ports to forward (comma separated, e.g. 443,8443): " FWD_PORTS
        fi
        
        # Write Config
        cat <<EOF > "$CONF_FILES/vxlan_${VNI}.conf"
VNI=${VNI}
ROLE="master"
REMOTE_IP=${R_IP}
LOCAL_BIND_IP=${MAIN_IP}
DSTPORT=${VXLAN_PORT}
IFACE="vxlan${VNI}"
INTERNAL_IP="${LOCAL_INT_IP}"
TARGET_PING_IP="${REMOTE_INT_IP}"
FORWARD_PORTS="${FWD_PORTS}"
EOF
        
        echo -e "${GREEN}[✓] Configuration Saved.${NC}"
        echo -e "${YELLOW}!!! IMPORTANT !!!${NC}"
        echo -e "Go to your REMOTE server and select option 1 -> 2 (Remote Role)."
        echo -e "Enter these details:"
        echo -e "  - Master IP: ${GREEN}${MAIN_IP}${NC}"
        echo -e "  - Tunnel ID: ${GREEN}${VNI}${NC}"
        
    elif [[ "$role" == "2" ]]; then
        # SLAVE SETUP
        read -p "Enter Master Server (Iran) IP: " M_IP
        read -p "Enter Tunnel ID (VNI) provided by Master: " VNI
        
        if [[ -z "$VNI" ]]; then echo "Error: ID required."; return; fi
        
        VXLAN_PORT=$((4000 + VNI))
        LOCAL_INT_IP="10.${VNI}.0.2/24"
        REMOTE_INT_IP="10.${VNI}.0.1" # For Pinging
        
        # Write Config
        cat <<EOF > "$CONF_FILES/vxlan_${VNI}.conf"
VNI=${VNI}
ROLE="slave"
REMOTE_IP=${M_IP}
LOCAL_BIND_IP=${MAIN_IP}
DSTPORT=${VXLAN_PORT}
IFACE="vxlan${VNI}"
INTERNAL_IP="${LOCAL_INT_IP}"
TARGET_PING_IP="${REMOTE_INT_IP}"
FORWARD_PORTS=""
EOF
        echo -e "${GREEN}[✓] Configuration Saved.${NC}"
    else
        echo "Invalid selection."
        return
    fi
    
    # Apply Changes
    regenerate_systemd_script
    systemctl start vxlan-manager.service
    
    if [[ "$role" == "1" && -n "$FWD_PORTS" ]]; then
        regenerate_haproxy
        echo -e "${GREEN}[✓] HAProxy updated with new ports.${NC}"
    fi
    
    echo -e "${GREEN}[✓] Tunnel interface vxlan${VNI} created.${NC}"
}

list_tunnels() {
    echo -e "${CYAN}=== Active Tunnels ===${NC}"
    printf "%-8s %-15s %-15s %-15s\n" "ID" "Role" "Remote IP" "Interface"
    echo "--------------------------------------------------------"
    for f in $CONF_FILES/*.conf; do
        [ -e "$f" ] || continue
        source "$f"
        printf "%-8s %-15s %-15s %-15s\n" "$VNI" "$ROLE" "$REMOTE_IP" "$IFACE"
    done
    echo ""
    read -p "Press Enter..."
}

delete_tunnel() {
    list_tunnels
    read -p "Enter ID (VNI) to delete: " del_vni
    if [[ -f "$CONF_FILES/vxlan_${del_vni}.conf" ]]; then
        source "$CONF_FILES/vxlan_${del_vni}.conf"
        ip link del "$IFACE" 2>/dev/null
        rm "$CONF_FILES/vxlan_${del_vni}.conf"
        
        regenerate_systemd_script
        regenerate_haproxy
        echo -e "${GREEN}[✓] Tunnel $del_vni deleted.${NC}"
    else
        echo -e "${RED}[x] Tunnel config not found.${NC}"
    fi
    read -p "Press Enter..."
}

install_bbr() {
    echo "Running BBR script..."
    curl -fsSLk https://raw.githubusercontent.com/MrAminiDev/NetOptix/main/scripts/bbr.sh | bash
}

# ---------------- MENU ----------------

Lena_menu() {
    check_dependencies
    clear
    echo "+-------------------------------------------------------------------------+"
    echo -e "| ${GREEN}LENA MULTI-VXLAN MANAGER${NC} | Version : ${GREEN} 3.0.0 (1-to-Many)${NC}"
    echo "+-------------------------------------------------------------------------+"
    echo -e "1- Add New Tunnel (Connect a server)"
    echo -e "2- List Active Tunnels"
    echo -e "3- Delete a Tunnel"
    echo -e "4- Install BBR"
    echo -e "5- Force Restart Services"
    echo -e "0- Exit"
    echo "+-------------------------------------------------------------------------+"
}

while true; do
    Lena_menu
    read -p "Select option: " opt
    case $opt in
        1) add_tunnel ;;
        2) list_tunnels ;;
        3) delete_tunnel ;;
        4) install_bbr; read -p "Done..." ;;
        5) 
           regenerate_systemd_script
           regenerate_haproxy
           systemctl restart vxlan-manager
           echo "Services restarted."
           sleep 1
           ;;
        0) exit 0 ;;
        *) echo "Invalid" ; sleep 1 ;;
    esac
done
