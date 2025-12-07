#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
NC='\033[0m'

LOGFILE="/var/log/network_optimizer.log"

# Helper Functions
log() { echo -e "${GREEN}[INFO]${NC} $1"; echo "[INFO] $1" >> "$LOGFILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; echo "[WARN] $1" >> "$LOGFILE"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; echo "[ERROR] $1" >> "$LOGFILE"; exit 1; }

print_banner() {
  clear
  echo -e "${CYAN}"
  echo "╭──────────────────────────────────────────────────╮"
  echo "│         NetworkOptimizer v3.0 (Ultimate)         │"
  echo "│   BBRv3 + Advanced Buffer Tuning + Latency Mode  │"
  echo "╰──────────────────────────────────────────────────╯"
  echo -e "${NC}"
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
     error "Please run this script as root (sudo)."
  fi
}

check_os_compatibility() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
  fi
  if [[ "$ID" != "ubuntu" && "$ID" != "debian" && "$ID_LIKE" != *"ubuntu"* && "$ID_LIKE" != *"debian"* ]]; then
    warn "Kernel installation is optimized for Ubuntu/Debian."
    return 1
  fi
  return 0
}

# --- 1. Kernel Installation ---
install_xanmod_kernel() {
  echo -e "\n${BLUE}>>> Installing XanMod Kernel (BBRv3)...${NC}"
  
  if ! check_os_compatibility; then
    echo -e "${RED}⛔ Cancelled: OS not fully supported for auto-kernel install.${NC}"
    read -p "Press Enter..."
    return
  fi

  warn "This will update your kernel. A reboot will be required."
  apt-get update -y && apt-get install -y wget gpg

  echo -e "${YELLOW}⏳ Adding XanMod Repository...${NC}"
  wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes
  echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-release.list

  echo -e "${YELLOW}⏳ Installing Linux XanMod v3...${NC}"
  apt-get update -y
  apt-get install -y linux-xanmod-x64v3

  log "Kernel installed successfully."
  
  read -p "Do you want to reboot now? (y/n): " reboot_choice
  if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then reboot; fi
}

# --- 2. Network Optimization (Sysctl + Modules) ---
apply_optimizations() {
  echo -e "\n${BLUE}>>> Applying Network Optimizations...${NC}"

  # 1. Load Modules
  modprobe tcp_bbr 2>/dev/null && log "Module tcp_bbr loaded."
  echo "tcp_bbr" > /etc/modules-load.d/bbr.conf

  # 2. Sysctl Configuration (Merged & Optimized)
  cat <<EOF > /etc/sysctl.d/99-network-optimizer.conf
# --- Queueing & Congestion ---
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# --- TCP Fast Open & Probing ---
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1

# --- Memory Buffers (High Performance) ---
net.core.rmem_default=262144
net.core.rmem_max=134217728
net.core.wmem_default=262144
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864

# --- Connection Handling ---
net.core.somaxconn=2048
net.ipv4.tcp_max_syn_backlog=2048
net.core.netdev_max_backlog=500000
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_tw_recycle=0

# --- Keepalive (Stability) ---
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5

# --- Security & Features ---
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_sack=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_no_metrics_save=1
net.ipv4.ip_local_port_range=10240 65535
EOF

  sysctl --system > /dev/null 2>&1
  log "Sysctl parameters applied."
  
  # 3. NIC Latency Tuning (Optional)
  echo -e "\n${YELLOW}--- Low Latency Mode (Gaming/VoIP) ---${NC}"
  echo "Disabling NIC offloads reduces latency but increases CPU usage."
  read -p "Enable Low Latency Mode (Disable Offloads/Coalescing)? (y/n): " latency_choice

  if [[ "$latency_choice" =~ ^[Yy]$ ]]; then
    # Detect default interface
    IFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
    log "Detected Interface: $IFACE"
    
    # Disable Offloads (GRO, GSO, TSO)
    ethtool -K "$IFACE" gro off gso off tso off lro off 2>/dev/null \
      && log "NIC Offloads disabled (Low Latency)." \
      || warn "Could not disable some offloads (Hardware dependent)."
      
    # Disable Coalescing (Immediate Interrupts)
    ethtool -C "$IFACE" rx-usecs 0 rx-frames 1 tx-usecs 0 tx-frames 1 2>/dev/null \
      && log "Interrupt Coalescing disabled." \
      || warn "Could not change coalescing settings."
  else
    log "Skipping Low Latency Mode (Standard BBR Mode)."
  fi

  echo -e "${GREEN}✔ Optimization Complete.${NC}"
  read -p "Press Enter to continue..."
}

# --- 3. Status Check ---
check_status() {
  clear
  print_banner
  
  kernel_ver=$(uname -r)
  cc_algo=$(sysctl -n net.ipv4.tcp_congestion_control)
  qdisc=$(sysctl -n net.core.default_qdisc)
  
  echo -e "${BLUE}--- System Status ---${NC}"
  echo -e "Kernel:     ${GREEN}$kernel_ver${NC}"
  
  if [[ "$kernel_ver" == *"xanmod"* ]]; then
    echo -e "BBR Type:   ${GREEN}BBRv3 (Detected)${NC}"
  else
    echo -e "BBR Type:   ${YELLOW}BBRv1 (Standard)${NC}"
  fi
  
  echo -e "Congestion: ${GREEN}$cc_algo${NC}"
  echo -e "Qdisc:      ${GREEN}$qdisc${NC}"
  echo -e "FastOpen:   $(sysctl -n net.ipv4.tcp_fastopen)"
  
  echo -e "\n${BLUE}--- Interface Settings ---${NC}"
  IFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
  echo "Interface: $IFACE"
  ethtool -k "$IFACE" 2>/dev/null | grep -E "tcp-segmentation-offload|generic-segmentation-offload" | head -n 2
  
  echo -e "\n--------------------------------------------------"
  read -p "Press Enter..."
}

# --- Main Menu ---
main_menu() {
  while true; do
    print_banner
    echo -e "1) Install XanMod Kernel (For BBRv3) ${YELLOW}[Reboot Required]${NC}"
    echo -e "2) Apply Network Optimizations (Sysctl + Latency Tuning)"
    echo -e "3) Check Status"
    echo -e "4) Exit"
    echo -e "--------------------------------------------------"
    read -p "Select option [1-4]: " choice

    case $choice in
      1) install_xanmod_kernel ;;
      2) apply_optimizations ;;
      3) check_status ;;
      4) exit 0 ;;
      *) echo "Invalid option." ; sleep 1 ;;
    esac
  done
}

check_root
main_menu
