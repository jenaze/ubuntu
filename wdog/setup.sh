#!/bin/bash

# ==========================================
#       تنظیمات و مسیر فایل‌ها
# ==========================================
WATCHDOG_SCRIPT="/root/http_watchdog.sh"
SERVICE_FILE="/etc/systemd/system/bkh-watchdog.service"

# رنگ‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ==========================================
#          توابع سیستمی
# ==========================================

function show_header() {
    clear
    echo -e "${CYAN}==========================================================${NC}"
    echo -e "${YELLOW}       Auto-Restart Watchdog Manager (Final Version)${NC}"
    echo -e "${CYAN}==========================================================${NC}"
    echo -e "${GREEN}Watchdog Script Path :${NC} $WATCHDOG_SCRIPT"
    echo -e "${GREEN}Systemd Service Path :${NC} $SERVICE_FILE"
    echo -e "${CYAN}==========================================================${NC}"
    
    if systemctl is-active --quiet bkh-watchdog; then
        echo -e "Service Status: ${GREEN}Active (Running)${NC}"
    else
        echo -e "Service Status: ${RED}Inactive / Not Installed${NC}"
    fi
    echo ""
}

function install_watchdog() {
    echo -e "${YELLOW}Installing Watchdog Script...${NC}"

cat > "$WATCHDOG_SCRIPT" << 'EOF'
#!/bin/bash

# لیست سرویس‌ها و پورت‌ها
SERVICES=(
    # FORMAT: "service_name|url"
    # -- END LIST --
)

while true; do
    for ENTRY in "${SERVICES[@]}"; do
        [[ "$ENTRY" == \#* ]] && continue

        IFS='|' read -r SERVICE_NAME CHECK_URL <<< "$ENTRY"

        # استفاده از -I برای کمترین مصرف دیتا (Head Only)
        if ! curl -s -I --max-time 2 "$CHECK_URL" > /dev/null; then
            
            echo "$(date): [WARNING] Connection lost for $SERVICE_NAME. Starting retries..."
            RECOVERY_SUCCESS=false

            for i in {1..3}; do
                sleep 5
                if curl -s -I --max-time 2 "$CHECK_URL" > /dev/null; then
                    echo "$(date): [$SERVICE_NAME] Connection recovered at attempt $i."
                    RECOVERY_SUCCESS=true
                    break
                fi
            done

            if [ "$RECOVERY_SUCCESS" = false ]; then
                echo "$(date): [CRITICAL] Restarting $SERVICE_NAME..."
                systemctl restart "$SERVICE_NAME"
            fi
        fi
    done
    sleep 10
done
EOF

    chmod +x "$WATCHDOG_SCRIPT"

    echo -e "${YELLOW}Creating Systemd Service...${NC}"
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Backhaul HTTP Watchdog
After=network.target

[Service]
ExecStart=$WATCHDOG_SCRIPT
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable bkh-watchdog
    systemctl start bkh-watchdog
    
    echo -e "${GREEN}Installation Complete!${NC}"
    read -p "Press Enter to continue..."
}

function add_service() {
    echo -e "${YELLOW}--- Add New Service ---${NC}"
    
    # 1. دریافت نام سرویس (هوشمند)
    echo -e "Enter Config Name (e.g., ${CYAN}iran52103${NC} or ${CYAN}iran52103.toml${NC})"
    read -p "> " RAW_NAME
    
    # 2. دریافت آدرس (هوشمند)
    echo -e "Enter IP:Port (e.g., ${CYAN}127.0.0.1:8080${NC} or ${CYAN}http://...${NC})"
    read -p "> " RAW_URL

    if [[ -z "$RAW_NAME" || -z "$RAW_URL" ]]; then
        echo -e "${RED}Error: Inputs cannot be empty.${NC}"
    else
        # --- پردازش نام سرویس ---
        CLEAN_NAME=${RAW_NAME%.toml}          # حذف .toml
        S_NAME="backhaul-${CLEAN_NAME}.service" # ساخت نام استاندارد

        # --- پردازش آدرس URL ---
        # بررسی میکند که آیا اولش http دارد یا خیر
        if [[ "$RAW_URL" != http* ]]; then
            S_URL="http://$RAW_URL"
        else
            S_URL="$RAW_URL"
        fi

        echo -e "Service: ${CYAN}$S_NAME${NC}"
        echo -e "URL:     ${CYAN}$S_URL${NC}"

        # اضافه کردن به فایل
        sed -i "/# -- END LIST --/i \    \"$S_NAME|$S_URL\"" "$WATCHDOG_SCRIPT"
        
        echo -e "${GREEN}Service Added Successfully!${NC}"
        systemctl restart bkh-watchdog
    fi
    read -p "Press Enter to continue..."
}

function remove_service() {
    echo -e "${YELLOW}--- Remove Service ---${NC}"
    echo "Current List:"
    grep "|" "$WATCHDOG_SCRIPT" | cat -n
    
    echo ""
    read -p "Enter the line number to delete (or 0 to cancel): " LINE_NUM

    if [[ "$LINE_NUM" != "0" && -n "$LINE_NUM" ]]; then
        TARGET_LINE=$(grep "|" "$WATCHDOG_SCRIPT" | sed -n "${LINE_NUM}p")
        
        if [[ -n "$TARGET_LINE" ]]; then
            ESCAPED_LINE=$(echo "$TARGET_LINE" | sed 's/[\/&]/\\&/g')
            sed -i "/$ESCAPED_LINE/d" "$WATCHDOG_SCRIPT"
            
            echo -e "${GREEN}Service Removed!${NC}"
            systemctl restart bkh-watchdog
        else
            echo -e "${RED}Invalid number selected.${NC}"
        fi
    fi
    read -p "Press Enter to continue..."
}

function view_logs() {
    echo -e "${YELLOW}--- Recent Logs ---${NC}"
    journalctl -u bkh-watchdog -n 20 --no-pager
    read -p "Press Enter to continue..."
}

function clear_logs() {
    echo -e "${YELLOW}Cleaning up logs...${NC}"
    
    # چرخاندن فایل لاگ و حذف لاگ‌های قدیمی‌تر از 1 ثانیه
    journalctl --rotate
    journalctl --vacuum-time=1s
    
    echo -e "${GREEN}Logs Cleared Successfully!${NC}"
    read -p "Press Enter to continue..."
}

# ==========================================
#            منوی اصلی
# ==========================================

while true; do
    show_header
    echo "1) Install / Re-install Watchdog"
    echo "2) Add a Service to Monitor"
    echo "3) Remove a Service"
    echo "4) Edit Script Manually (nano)"
    echo "5) View Logs"
    echo "6) Clear Logs"  # گزینه جدید
    echo "0) Exit"
    echo ""
    read -p "Select an option: " OPTION

    case $OPTION in
        1) install_watchdog ;;
        2) add_service ;;
        3) remove_service ;;
        4) nano "$WATCHDOG_SCRIPT"; systemctl restart bkh-watchdog ;;
        5) view_logs ;;
        6) clear_logs ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid Option${NC}"; sleep 1 ;;
    esac
done
