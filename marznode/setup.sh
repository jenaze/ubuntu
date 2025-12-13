#!/bin/bash

# MarzNode Installation & Management Script
# Usage: 
#   bash <(curl -s https://raw.githubusercontent.com/khodedawsh/marznode/main/install.sh)
#   or ./marznode_manager.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MARZNODE_DIR="/root/marznode"
DATA_DIR="/var/lib/marznode"
XRAY_CONFIG="/var/lib/marznode/xray_config.json"

# Default values
SERVICE_PORT="53042"
INSECURE="False"
SERVICE_ADDRESS=""

# Function to get latest Xray release version
get_latest_xray_version() {
    echo -e "${BLUE}Fetching latest Xray release version...${NC}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    echo -e "${GREEN}Latest Xray version: $LATEST_VERSION${NC}"
}

# Function to check if a specific Xray version exists
check_xray_version_exists() {
    local version=$1
    echo -e "${BLUE}Checking if Xray version $version exists...${NC}"
    
    # Check if the version exists by attempting to fetch the release info
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://api.github.com/repos/XTLS/Xray-core/releases/tags/$version)
    
    if [ "$HTTP_STATUS" = "200" ]; then
        echo -e "${GREEN}Version $version exists!${NC}"
        return 0
    else
        echo -e "${RED}Version $version does not exist!${NC}"
        return 1
    fi
}

# Function to get user configuration
get_configuration() {
    echo -e "${BLUE}=== Configuration Setup ===${NC}"
    
    # Service Port
    echo -n -e "${YELLOW}Enter SERVICE_PORT [default: 53042]: ${NC}"
    read custom_port
    if [ ! -z "$custom_port" ]; then
        SERVICE_PORT="$custom_port"
    fi
    echo -e "${GREEN}Using SERVICE_PORT: $SERVICE_PORT${NC}"
    
    # Insecure mode
    while true; do
        echo -n -e "${YELLOW}Enable INSECURE mode? (y/n) [default: n]: ${NC}"
        read insecure_input
        case $insecure_input in
            [Yy]* ) INSECURE="True"; break;;
            [Nn]* ) INSECURE="False"; break;;
            "" ) INSECURE="False"; break;;
            * ) echo -e "${RED}Please answer y or n.${NC}";;
        esac
    done
    echo -e "${GREEN}INSECURE mode: $INSECURE${NC}"
    
    # Service Address
    echo -n -e "${YELLOW}Enter SERVICE_ADDRESS [leave empty to disable]: ${NC}"
    read service_address
    if [ ! -z "$service_address" ]; then
        SERVICE_ADDRESS="$service_address"
        echo -e "${GREEN}Using SERVICE_ADDRESS: $SERVICE_ADDRESS${NC}"
    else
        echo -e "${GREEN}SERVICE_ADDRESS will be disabled${NC}"
    fi
}

# Function to edit client.pem
edit_client_pem() {
    echo -e "${BLUE}Editing client.pem certificate...${NC}"
    echo -e "${YELLOW}Please edit your certificate content (Ctrl+X, Y, Enter when finished)${NC}"
    nano $DATA_DIR/client.pem
    echo -e "${GREEN}Certificate updated successfully!${NC}"
    
    # Restart service to apply changes
    echo -e "${YELLOW}Restarting service to apply certificate changes...${NC}"
    cd $MARZNODE_DIR
    docker compose restart
    echo -e "${GREEN}Service restarted!${NC}"
}

# Function to install/update Xray
install_xray() {
    local version=$1
    echo -e "${BLUE}Installing/Updating Xray-core...${NC}"
    
    if [ -z "$version" ]; then
        get_latest_xray_version
        VERSION_TO_INSTALL=$LATEST_VERSION
    else
        VERSION_TO_INSTALL=$version
    fi
    
    mkdir -p $DATA_DIR/data
    cd $DATA_DIR/data
    
    # Remove existing Xray files
    rm -f xray Xray-*
    
    # Download specified Xray release
    echo -e "${YELLOW}Downloading Xray version $VERSION_TO_INSTALL...${NC}"
    wget -q --show-progress https://github.com/XTLS/Xray-core/releases/download/${VERSION_TO_INSTALL}/Xray-linux-64.zip
    
    # Install unzip if not exists
    if ! command -v unzip &> /dev/null; then
        apt install unzip -y
    fi
    
    # Extract and cleanup
    unzip -o Xray-linux-64.zip
    rm Xray-linux-64.zip
    
    # Copy xray executable
    cp xray $DATA_DIR/xray
    chmod +x $DATA_DIR/xray $DATA_DIR/data/xray
    
    echo -e "${GREEN}Xray $VERSION_TO_INSTALL installed successfully!${NC}"
}

# Function to create docker compose file
create_docker_compose() {
    echo -e "${YELLOW}Creating Docker compose configuration...${NC}"
    
    # Build environment variables section
    ENV_VARS="      SERVICE_PORT: \"$SERVICE_PORT\"
       AUTH_GENERATION_ALGORITHM: \"plain\"
       INSECURE: \"$INSECURE\"
       XRAY_EXECUTABLE_PATH: \"/var/lib/marznode/xray\"
       XRAY_ASSETS_PATH: \"/var/lib/marznode/data\"
       XRAY_CONFIG_PATH: \"/var/lib/marznode/xray_config.json\"
       XRAY_RESTART_ON_FAILURE: \"True\"
       XRAY_RESTART_ON_FAILURE_INTERVAL: \"0\"
      
       SING_BOX_EXECUTABLE_PATH: \"/usr/local/bin/sing-box\"
       HYSTERIA_EXECUTABLE_PATH: \"/usr/local/bin/hysteria\"
       SSL_CLIENT_CERT_FILE: \"/var/lib/marznode/client.pem\"
       SSL_KEY_FILE: \"./server.key\"
       SSL_CERT_FILE: \"./server.cert\""
    
    # Add SERVICE_ADDRESS only if provided
    if [ ! -z "$SERVICE_ADDRESS" ]; then
        ENV_VARS="$ENV_VARS
       SERVICE_ADDRESS: \"$SERVICE_ADDRESS\""
    fi

    cat > $MARZNODE_DIR/compose.yml << EOF
services:
  marznode:
    image: dawsh/marznode:latest
    restart: always
    network_mode: host
    command: [ "sh", "-c", "sleep 10 && python3 marznode.py" ]

    environment:
 $ENV_VARS

    volumes:
      - /var/lib/marznode:/var/lib/marznode
EOF
}

# Function to install MarzNode
install_marznode() {
    echo -e "${BLUE}Installing MarzNode...${NC}"
    
    # Get configuration from user
    get_configuration
    
    # Update system
    echo -e "${YELLOW}Updating system packages...${NC}"
    apt-get update -y && apt-get upgrade -y
    
    # Check and install Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker not found. Installing Docker...${NC}"
        curl -fsSL https://get.docker.com | sh
    else
        echo -e "${GREEN}Docker is already installed. Skipping...${NC}"
    fi
    
    # Clone MarzNode
    echo -e "${YELLOW}Cloning MarzNode repository...${NC}"
    git clone https://github.com/khodedawsh/marznode $MARZNODE_DIR
    cd $MARZNODE_DIR
    
    # Create client.pem
    echo -e "${YELLOW}Please paste your panel certificate content below (Ctrl+D when finished):${NC}"
    mkdir -p $DATA_DIR
    cat > $DATA_DIR/client.pem
    
    # Install Xray
    install_xray
    
    # Copy config files
    echo -e "${YELLOW}Copying configuration files...${NC}"
    cp $MARZNODE_DIR/xray_config.json $XRAY_CONFIG
    
    # Create Docker compose file
    create_docker_compose
    
    # Start services
    echo -e "${YELLOW}Starting MarzNode services...${NC}"
    cd $MARZNODE_DIR
    docker compose down 2>/dev/null || true
    docker compose up -d
    
    echo -e "${GREEN}MarzNode installation completed successfully!${NC}"
    echo -e "${GREEN}Configuration:${NC}"
    echo -e "  PORT: $SERVICE_PORT"
    echo -e "  INSECURE: $INSECURE"
    if [ ! -z "$SERVICE_ADDRESS" ]; then
        echo -e "  ADDRESS: $SERVICE_ADDRESS"
    fi
}

# Function to update Xray only
# UPDATED: Now stops the service first to avoid "Text file busy" error
update_xray() {
    echo -e "${BLUE}Updating Xray-core...${NC}"
    
    echo -e "${YELLOW}Stopping MarzNode service to release file lock...${NC}"
    cd $MARZNODE_DIR
    docker compose down || true
    
    # Now it is safe to copy the file
    install_xray
    
    # Restart MarzNode to apply changes
    echo -e "${YELLOW}Starting MarzNode service...${NC}"
    cd $MARZNODE_DIR
    docker compose up -d
    
    echo -e "${GREEN}Xray update completed!${NC}"
}

# Function to update Xray to a specific version
update_xray_custom() {
    echo -e "${BLUE}Update Xray to Custom Version${NC}"
    echo -n -e "${YELLOW}Enter Xray version (e.g., v1.8.6): ${NC}"
    read custom_version
    
    if [ -z "$custom_version" ]; then
        echo -e "${RED}No version specified!${NC}"
        return 1
    fi
    
    # Check if the version exists
    if check_xray_version_exists "$custom_version"; then
        echo -e "${YELLOW}Stopping MarzNode service...${NC}"
        cd $MARZNODE_DIR
        docker compose down || true
        
        install_xray "$custom_version"
        
        echo -e "${YELLOW}Starting MarzNode service...${NC}"
        docker compose up -d
        
        echo -e "${GREEN}Xray updated to version $custom_version successfully!${NC}"
    else
        echo -e "${RED}Failed to update Xray. Version $custom_version does not exist.${NC}"
        echo -e "${YELLOW}You can check available versions at: https://github.com/XTLS/Xray-core/releases${NC}"
    fi
}

# Function to show status
show_status() {
    echo -e "${BLUE}=== MarzNode Status ===${NC}"
    cd $MARZNODE_DIR
    docker compose ps
    
    echo -e "\n${BLUE}=== Xray Version ===${NC}"
    $DATA_DIR/xray --version | head -1 || echo "Xray not found"
    
    echo -e "\n${BLUE}=== Current Configuration ===${NC}"
    echo "SERVICE_PORT: $SERVICE_PORT"
    echo "INSECURE: $INSECURE"
    if [ ! -z "$SERVICE_ADDRESS" ]; then
        echo "SERVICE_ADDRESS: $SERVICE_ADDRESS"
    else
        echo "SERVICE_ADDRESS: (disabled)"
    fi
    
    echo -e "\n${BLUE}=== Service Logs (last 10 lines) ===${NC}"
    docker compose logs --tail=10
}

# Function to show menu
show_menu() {
    echo -e "\n${BLUE}=== MarzNode Management Menu ===${NC}"
    echo -e "1) Install MarzNode (Full installation)"
    echo -e "2) Update Xray-core to latest version"
    echo -e "3) Update Xray-core to custom version"
    echo -e "4) Show status"
    echo -e "5) Restart services"
    echo -e "6) View logs"
    echo -e "7) Check for Xray updates"
    echo -e "8) Edit client.pem certificate"
    echo -e "9) Exit"
    echo -n -e "${YELLOW}Select an option [1-9]: ${NC}"
}

# Main script
while true; do
    show_menu
    read choice
    
    case $choice in
        1)
            install_marznode
            ;;
        2)
            update_xray
            ;;
        3)
            update_xray_custom
            ;;
        4)
            show_status
            ;;
        5)
            echo -e "${YELLOW}Restarting services...${NC}"
            cd $MARZNODE_DIR
            docker compose restart
            echo -e "${GREEN}Services restarted!${NC}"
            ;;
        6)
            echo -e "${YELLOW}Showing logs (Ctrl+C to exit)...${NC}"
            cd $MARZNODE_DIR
            docker compose logs -f
            ;;
        7)
            get_latest_xray_version
            ;;
        8)
            edit_client_pem
            ;;
        9)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option! Please choose 1-9.${NC}"
            ;;
    esac
    
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read
done
