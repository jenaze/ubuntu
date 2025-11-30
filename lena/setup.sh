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
    cat <<EOF > "$BRIDGE_SCRIPT"
#!/bin/bash
for cfg in $CONF_FILES/*.conf; do
    [ -e "\$cfg" ] || continue
    source "\$cfg"
    ip link del "\$IFACE" 2>/dev/null
    MAIN_IF=\$(ip route get 1.1.1.1 | awk '{print \$5}' | head -n1)
    ip link add "\$IFACE" type vxlan id "\$VNI" local "\$LOCAL_BIND_IP" remote "\$REMOTE_IP" dev "\$MAIN_IF" dstport "\$DSTPORT" nolearning
    ip addr add "\$INTERNAL_IP" dev "\$IFACE"
    ip link set "\$IFACE" up
    ( while true; do ping -c 1 "\$TARGET_PING_IP" >/dev/null 2>&1; sleep 30; done ) &
done
EOF
    chmod +x "$BRIDGE_SCRIPT"

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
    cat <<EOL > "$HAPROXY_CFG"
global
    log /dev/log local0
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

    if ls $CONF_FILES/*.conf 1> /dev/null 2>&1; then
        for f in $CONF_FILES/*.conf; do
            source "$f"
            if [[ -n "$FORWARD_PORTS" ]]; then
                IFS=',' read -ra ports <<< "$FORWARD_PORTS"
                for port in "${ports[@]}"; do
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
        SUGGESTED_PORT=$((4790 + VNI))
        
        echo -e "${GREEN}[*] Generated Tunnel ID (VNI): ${VNI}${NC}"
        
        # 1. Ask for Port
        read -p "Enter Tunnel UDP Port [Default: $SUGGESTED_PORT]: " USER_PORT
        VXLAN_PORT=${USER_PORT:-$SUGGESTED_PORT}

        LOCAL_INT_IP="10.${VNI}.0.1/24"
        REMOTE_INT_IP="10.${VNI}.0.2"
        
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
        echo -e "${CYAN}------------------------------------------------${NC}"
        echo -e "   YOUR LOCAL VXLAN IP: ${GREEN}${LOCAL_INT_IP}${NC}"
        echo -e "${CYAN}------------------------------------------------${NC}"
        echo -e "${YELLOW}!!! INSTRUCTIONS FOR REMOTE SERVER !!!${NC}"
        echo -e "Go to your REMOTE server -> Select Option 1 -> Option 2."
        echo -e "Enter these details:"
        echo -e "  - Master IP:   ${GREEN}${MAIN_IP}${NC}"
        echo -e "  - Tunnel ID:   ${GREEN}${VNI}${NC}"
        echo -e "  - Tunnel Port: ${GREEN}${VXLAN_PORT}${NC}"
        echo -e "${CYAN}------------------------------------------------${NC}"
        
    elif [[ "$role" == "2" ]]; then
        # SLAVE SETUP
        read -p "Enter Master Server (Iran) IP: " M_IP
        read -p "Enter Tunnel ID (VNI): " VNI
        read -p "Enter Tunnel UDP Port: " VXLAN_PORT
        
        if [[ -z "$VNI" || -z "$VXLAN_PORT" ]]; then echo "Error: ID and Port required."; return; fi
        
        LOCAL_INT_IP="10.${VNI}.0.2/24"
        REMOTE_INT_IP="10.${VNI}.0.1" 
        
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
        echo -e "${CYAN}------------------------------------------------${NC}"
        echo -e "   YOUR LOCAL VXLAN IP: ${GREEN}${LOCAL_INT_IP}${NC}"
        echo -e "${CYAN}------------------------------------------------${NC}"
    else
        echo "Invalid selection."
        return
    fi
    
    # Apply Changes
    regenerate_systemd_script
    systemctl start vxlan-manager.service
    
    if [[ "$role" == "1" && -n "$FWD_PORTS" ]]; then
        regenerate_haproxy
        echo -e "${GREEN}[✓] HAProxy updated.${NC}"
    fi
}

list_tunnels() {
    echo -e "${CYAN}=== Active Tunnels ===${NC}"
    # Header
    printf "${YELLOW}%-5s %-8s %-15s %-12s %-6s %-18s${NC}\n" "ID" "Role" "Remote IP" "Interface" "Port" "Internal IP"
    echo "----------------------------------------------------------------------"
    
    for f in $CONF_FILES/*.conf; do
        [ -e "$f" ] || continue
        source "$f"
        # Print Row
        printf "%-5s %-8s %-15s %-12s %-6s %-18s\n" "$VNI" "$ROLE" "$REMOTE_IP" "$IFACE" "$DSTPORT" "$INTERNAL_IP"
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
    echo -e "| ${GREEN}LENA MULTI-VXLAN MANAGER${NC} | Version : ${GREEN} 2.1.0${NC}"
    echo "+-------------------------------------------------------------------------+"
    echo -e "1- Add New Tunnel"
    echo -e "2- List Active Tunnels (Show IP & Ports)"
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
