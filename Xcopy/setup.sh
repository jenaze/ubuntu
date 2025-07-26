#!/usr/bin/env bash
# update_sqlite_ssh.sh
set -euo pipefail

###############################################################################
# 1) FUNCTION: install missing tools
###############################################################################
install_if_missing() {
  local pkg="$1"
  local bin="${2:-$1}"
  if ! command -v "$bin" &>/dev/null; then
    echo "[+] Installing $pkg ..."
    if command -v apt-get &>/dev/null; then
      sudo apt-get update -qq && sudo apt-get install -y "$pkg"
    elif command -v yum &>/dev/null; then
      sudo yum install -y "$pkg"
    elif command -v brew &>/dev/null; then
      brew install "$pkg"
    else
      echo "❌  No supported package manager found. Please install $pkg manually."
      exit 1
    fi
  fi
}

install_if_missing sqlite3
install_if_missing openssh-client scp
install_if_missing sshpass

###############################################################################
# 2) ARGUMENT PARSING
###############################################################################
usage() {
  echo "Usage:
  $0  --user <ssh_user> --host <hostname> --pass <ssh_password> \
      --dir  <remote_and_local_directory> --newIp <ip_for_queries> \
      [--update true|false]  [--port <ssh_port>] [--dbname <sqlite_filename>]"
  exit 1
}

# defaults
UPDATE=true
PORT=22
DBNAME="database.sqlite"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)   USER="$2";     shift 2 ;;
    --host)   HOST="$2";     shift 2 ;;
    --pass)   PASSWORD="$2"; shift 2 ;;
    --dir)    DIR="$2";      shift 2 ;;
    --newIp)  NEWIP="$2";    shift 2 ;;
    --update) UPDATE="$2";   shift 2 ;;
    --port)   PORT="$2";     shift 2 ;;
    --dbname) DBNAME="$2";   shift 2 ;;
    *) usage ;;
  esac
done

for var in USER HOST PASSWORD DIR NEWIP; do
  [[ -z "${!var:-}" ]] && { echo "❌  Missing --${var,,}"; usage; }
done

REMOTE_FILE="${HOST}:${DIR}/${DBNAME}"
LOCAL_FILE="${DIR}/${DBNAME}"

###############################################################################
# 3) DOWNLOAD (always)
###############################################################################
echo "[+] Downloading ${REMOTE_FILE} → ${LOCAL_FILE} ..."
mkdir -p "$DIR"
sshpass -p "$PASSWORD" scp -P "$PORT" -o StrictHostKeyChecking=no \
        "$USER@$REMOTE_FILE" "$LOCAL_FILE"

###############################################################################
# 4) UPDATE QUERIES (optional)
###############################################################################
if [[ "$UPDATE" == "true" ]]; then
  echo "[+] Running UPDATE queries with newIp=${NEWIP} ..."
  sqlite3 "$LOCAL_FILE" <<SQL
UPDATE inbounds SET listen = '${NEWIP}' WHERE listen = '${HOST}';
UPDATE inbounds SET tag = replace(tag, '${HOST}', '${NEWIP}');
SQL
  echo "[✓] UPDATE statements executed."
else
  echo "[i] --update=false, skipping UPDATE queries."
fi

echo "[✓] All done."
