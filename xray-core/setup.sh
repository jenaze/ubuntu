#!/bin/bash

# ==============================================================================
# Xray Auto-Installer & Updater Script (Robust & Debuggable)
#
# Description:
#   This script automates the installation, update, and management of Xray-core.
#   It automatically installs required dependencies if they are missing.
#
#   USAGE:
#     ./install_xray.sh                  -> Installs the latest version.
#     ./install_xray.sh install [vX.Y.Z] -> Installs a specific version (or latest if omitted).
#     ./install_xray.sh update [vX.Y.Z]  -> Updates to a specific version (or latest if omitted).
#     ./install_xray.sh uninstall        -> Completely removes Xray and its configuration.
#     ./install_xray.sh --version        -> Checks the currently installed Xray version.
#     ./install_xray.sh --help           -> Shows this help message.
#
# ==============================================================================

# --- Configuration ---
INSTALL_DIR="$HOME/xray"
CONFIG_FILE="$INSTALL_DIR/xray_config.json"
SERVICE_NAME="xray.service"
PATH_UNIT_NAME="xray.path"
RESTART_SERVICE_NAME="xray-restarter.service"
XRAY_BINARY="$INSTALL_DIR/xray"
DEBUG_FILE="/tmp/xray_api_response.json"
SERVICE_DROPIN_DIR="/etc/systemd/system/$SERVICE_NAME.d"

# --- Use absolute paths for reliability ---
CURL_CMD="/usr/bin/curl"
JQ_CMD="/usr/bin/jq"
UNZIP_CMD="/usr/bin/unzip"
SYSTEMCTL_CMD="/usr/bin/systemctl"
FILE_CMD="/usr/bin/file"

# --- Color Codes for Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Functions ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

show_help() {
    echo "Xray Auto-Installer & Updater Script"
    echo ""
    echo "Usage: $0 [COMMAND] [VERSION]"
    echo ""
    echo "COMMANDS:"
    echo "  (no args)      Install the latest version of Xray."
    echo "  install [ver]  Install a specific version (e.g., v1.8.4) or latest if omitted."
    echo "  update [ver]   Update to a specific version or latest if omitted."
    echo "  uninstall      Completely remove Xray and its configuration."
    echo "  --version      Check the currently installed Xray version."
    echo "  --help         Show this help message."
    echo ""
    echo "EXAMPLES:"
    echo "  $0                      # Install latest"
    echo "  $0 install v1.8.4       # Install version v1.8.4"
    echo "  $0 update               # Update to latest"
    echo "  $0 update v1.8.6        # Update to version v1.8.6"
    echo "  $0 uninstall            # Remove Xray"
}

ensure_dependencies_are_installed() {
    local deps=("curl" "unzip" "jq" "file")
    local missing_deps=()

    if ! command -v sudo &> /dev/null; then
        log_error "This script requires 'sudo' to install system packages and services."
        exit 1
    fi

    if [[ ! -x "$SYSTEMCTL_CMD" ]]; then
        log_error "This script requires a systemd-based Linux distribution."
        log_error "'systemctl' command not found at $SYSTEMCTL_CMD. Cannot manage services."
        exit 1
    fi

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -eq 0 ]; then
        log_success "All required dependencies are installed."
        return
    fi

    log_warning "The following dependencies are missing: ${missing_deps[*]}"
    log_info "Attempting to install them automatically..."

    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt-get"
        INSTALL_CMD="sudo apt-get update && sudo apt-get install -y"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="sudo dnf install -y"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        INSTALL_CMD="sudo yum install -y"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
        INSTALL_CMD="sudo pacman -Syu --noconfirm"
    else
        log_error "Could not detect a supported package manager (apt-get, dnf, yum, pacman)."
        log_error "Please install the missing dependencies manually: ${missing_deps[*]}"
        exit 1
    fi

    log_info "Using '$PKG_MANAGER' to install: ${missing_deps[*]}"
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Dependency installation aborted by user."
        exit 1
    fi

    if ! eval "$INSTALL_CMD ${missing_deps[*]}"; then
        log_error "Failed to install dependencies. Please check the output above."
        exit 1
    fi

    log_success "Dependencies installed and verified successfully."
}

get_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64) echo "linux-64" ;;
        aarch64|arm64) echo "linux-arm64-v8a" ;;
        armv7l) echo "linux-arm32-v7a" ;;
        s390x) echo "linux-s390x" ;;
        *) log_error "Unsupported architecture: $arch"; exit 1 ;;
    esac
}

get_latest_xray_version() {
    log_info "Fetching latest Xray release version..."
    local api_response
    api_response=$("$CURL_CMD" -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest")
    
    local latest_version
    latest_version=$(echo "$api_response" | "$JQ_CMD" -r '.tag_name')
    
    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        log_error "Could not parse the latest version from GitHub API."
        log_error "The raw API response has been saved to $DEBUG_FILE for inspection."
        echo "$api_response" > "$DEBUG_FILE"
        exit 1
    fi
    echo "$latest_version"
}

install_xray_binary() {
    local version=$1
    local arch=$(get_arch)
    local download_url="https://github.com/XTLS/Xray-core/releases/download/${version}/Xray-${arch}.zip"
    local zip_file="/tmp/xray-${version}.zip"

    log_info "Downloading Xray ${version} for ${arch} from ${download_url}..."
    if ! "$CURL_CMD" -L -o "$zip_file" "$download_url"; then
        log_error "Failed to download Xray. The version might not exist for your architecture."
        rm -f "$zip_file"
        exit 1
    fi

    if ! "$FILE_CMD" "$zip_file" | grep -q "Zip archive"; then
        log_error "Downloaded file is not a valid zip archive. It might be an error page."
        log_error "File details: $("$FILE_CMD" "$zip_file")"
        log_error "Please check the URL manually or your network connection."
        rm -f "$zip_file"
        exit 1
    fi

    log_info "Extracting Xray to $INSTALL_DIR..."
    if ! mkdir -p "$INSTALL_DIR"; then
        log_error "Failed to create installation directory: $INSTALL_DIR"
        rm -f "$zip_file"
        exit 1
    fi

    if ! "$UNZIP_CMD" -o "$zip_file" -d "$INSTALL_DIR"; then
        log_error "Failed to extract the Xray archive."
        rm -f "$zip_file"
        exit 1
    fi

    chmod +x "$XRAY_BINARY"
    rm -f "$zip_file"
    log_success "Xray binary ${version} installed successfully."
}

setup_xray_service() {
    if ! mkdir -p "$INSTALL_DIR"; then
        log_error "Failed to create installation directory: $INSTALL_DIR"
        exit 1
    fi

    log_info "Creating a basic SOCKS5 proxy configuration at $CONFIG_FILE..."
    cat > "$CONFIG_FILE" <<'EOF'
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": 1080,
      "protocol": "socks",
      "sniffing": { "enabled": true, "destOverride": ["http", "tls"] },
      "settings": { "auth": "noauth" }
    }
  ],
  "outbounds": [{ "protocol": "freedom", "settings": {} }]
}
EOF
    log_success "Configuration file created. You can modify it at $CONFIG_FILE."

    log_info "Creating systemd service files..."
    sudo tee "/etc/systemd/system/$SERVICE_NAME" > /dev/null <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
Type=simple
User=$USER
Group=$USER
LimitNPROC=65535
LimitNOFILE=65535
ExecStart=$XRAY_BINARY run -config $CONFIG_FILE
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

    log_info "Configuring log rotation for the service..."
    sudo mkdir -p "$SERVICE_DROPIN_DIR"
    sudo tee "$SERVICE_DROPIN_DIR/10-log-limit.conf" > /dev/null <<'EOF'
[Service]
# Limit the journal size for this service to prevent it from growing too large.
# This value is the maximum disk space the journal for this service can use.
# Adjust as needed (e.g., 10M, 100M). Default is 50M.
LogMaxUse=50M
EOF
    log_success "Service log limit set to 50M."

    sudo tee "/etc/systemd/system/$RESTART_SERVICE_NAME" > /dev/null <<EOF
[Unit]
Description=Restarter for Xray Service
[Service]
Type=oneshot
ExecStart=$SYSTEMCTL_CMD restart $SERVICE_NAME
EOF

    sudo tee "/etc/systemd/system/$PATH_UNIT_NAME" > /dev/null <<EOF
[Unit]
Description=Watch Xray config for changes
[Path]
PathModified=$CONFIG_FILE
Unit=$RESTART_SERVICE_NAME
[Install]
WantedBy=multi-user.target
EOF

    log_success "Systemd files created."
    
    log_info "Reloading systemd and enabling services..."
    sudo "$SYSTEMCTL_CMD" daemon-reload
    sudo "$SYSTEMCTL_CMD" enable --now "$SERVICE_NAME"
    sudo "$SYSTEMCTL_CMD" enable --now "$PATH_UNIT_NAME"
    log_success "Xray service is running and enabled to start on boot."
}

# --- Action Functions ---

install_action() {
    local target_version=$1
    if [[ -z "$target_version" ]]; then
        target_version=$(get_latest_xray_version)
    fi
    if [[ -f "$XRAY_BINARY" ]]; then
        log_warning "Xray is already installed. Use the 'update' command to change its version."
        exit 1
    fi
    ensure_dependencies_are_installed
    install_xray_binary "$target_version"
    setup_xray_service
}

update_action() {
    local target_version=$1
    if [[ ! -f "$XRAY_BINARY" ]]; then
        log_warning "Xray is not installed. Proceeding with a fresh installation."
        install_action "$target_version"
        return
    fi
    
    ensure_dependencies_are_installed
    local current_version=$("$XRAY_BINARY" version 2>/dev/null | awk '{print $2}')
    
    if [[ -z "$target_version" ]]; then
        target_version=$(get_latest_xray_version)
    fi

    if [[ "$current_version" == "$target_version" ]]; then
        log_success "Xray is already up-to-date at version $target_version."
        exit 0
    fi

    log_info "Current version: $current_version"
    log_info "Target version:  $target_version"
    
    read -p "Do you want to proceed with the update? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Update aborted by user."
        exit 0
    fi

    install_xray_binary "$target_version"
    log_info "Restarting Xray service to apply the new version..."
    sudo "$SYSTEMCTL_CMD" restart "$SERVICE_NAME"
    log_success "Xray has been successfully updated to $target_version."
}

uninstall_action() {
    if [[ ! -f "$XRAY_BINARY" ]]; then
        log_warning "Xray is not installed in $INSTALL_DIR. Nothing to uninstall."
        exit 0
    fi

    log_warning "This will completely remove Xray and its configuration."
    log_warning "The following will be deleted:"
    log_warning "  - Service files: $SERVICE_NAME, $PATH_UNIT_NAME, $RESTART_SERVICE_NAME"
    log_warning "  - Installation directory: $INSTALL_DIR"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Uninstallation aborted by user."
        exit 0
    fi

    log_info "Stopping and disabling Xray services..."
    sudo "$SYSTEMCTL_CMD" stop "$SERVICE_NAME" 2>/dev/null || true
    sudo "$SYSTEMCTL_CMD" stop "$PATH_UNIT_NAME" 2>/dev/null || true
    sudo "$SYSTEMCTL_CMD" disable "$SERVICE_NAME" 2>/dev/null || true
    sudo "$SYSTEMCTL_CMD" disable "$PATH_UNIT_NAME" 2>/dev/null || true

    log_info "Removing systemd service files..."
    sudo rm -f "/etc/systemd/system/$SERVICE_NAME"
    sudo rm -f "/etc/systemd/system/$RESTART_SERVICE_NAME"
    sudo rm -f "/etc/systemd/system/$PATH_UNIT_NAME"
    sudo rm -rf "$SERVICE_DROPIN_DIR"

    log_info "Reloading systemd daemon..."
    sudo "$SYSTEMCTL_CMD" daemon-reload

    log_info "Removing Xray installation directory: $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"

    log_success "Xray has been successfully uninstalled."
}

# --- Main Execution ---
main() {
    case "$1" in
        "install")
            install_action "$2"
            ;;
        "update")
            update_action "$2"
            ;;
        "uninstall")
            uninstall_action
            ;;
        "--version")
            if [[ -f "$XRAY_BINARY" ]]; then
                current_version=$("$XRAY_BINARY" version | awk '{print $2}')
                log_success "Installed Xray version: $current_version"
            else
                log_warning "Xray is not installed in $INSTALL_DIR."
            fi
            ;;
        "--help"|"-h")
            show_help
            ;;
        "")
            install_action
            ;;
        *)
            log_error "Invalid command: $1"
            show_help
            exit 1
            ;;
    esac
    
    # Only show the final success message for install/update operations
    if [[ "$1" == "install" || "$1" == "update" || "$1" == "" ]]; then
        echo
        log_success "Operation complete!"
        echo "------------------------------------------------"
        echo "Xray is running as a SOCKS5 proxy on port 1080."
        echo "Configuration file: $CONFIG_FILE"
        echo "Service log limit: 50M (configured in $SERVICE_DROPIN_DIR/10-log-limit.conf)"
        echo ""
        echo "Useful commands:"
        echo "  Check status:     $SYSTEMCTL_CMD status $SERVICE_NAME"
        echo "  View logs:        journalctl -u $SERVICE_NAME -f"
        echo "  Stop service:     sudo $SYSTEMCTL_CMD stop $SERVICE_NAME"
        echo "------------------------------------------------"
    fi
}

main "$@"
