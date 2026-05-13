#!/bin/bash
set -euo pipefail

[[ $EUID -ne 0 ]] && echo "Run with sudo" && exit 1
exec < /dev/tty

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

CONF_DIR="/etc/g2ray-monitor"
CONF_FILE="$CONF_DIR/global.conf"
mkdir -p "$CONF_DIR"

# ==========================================
# 1. AUTO-INSTALL GLOBAL COMMAND
# ==========================================
if [[ "${BASH_SOURCE[0]}" != "/usr/local/bin/g2ray" ]]; then
    echo -e "${CYAN}[+] Installing 'g2ray' core to system...${NC}"
    apt-get update -qq && apt-get install -y -qq curl jq iputils-ping
    cp "${BASH_SOURCE[0]}" /usr/local/bin/g2ray
    chmod +x /usr/local/bin/g2ray
    echo -e "${GREEN}[✔] Installation successful!${NC}"
    echo -e "From now on, just type ${YELLOW}g2ray${NC} anywhere in your terminal."
    sleep 3
    exec g2ray
fi

# ==========================================
# 2. CONFIGURATION MANAGER
# ==========================================
load_config() {
    GH_TOKEN=""; TG_BOT=""; TG_ID=""; BALE_BOT=""; BALE_ID=""
    if [[ -f "$CONF_FILE" ]]; then source "$CONF_FILE"; fi
}

save_config() {
    cat > "$CONF_FILE" <<EOF
GH_TOKEN="$GH_TOKEN"
TG_BOT="$TG_BOT"
TG_ID="$TG_ID"
BALE_BOT="$BALE_BOT"
BALE_ID="$BALE_ID"
EOF
    chmod 600 "$CONF_FILE"
}
load_config

# ==========================================
# 3. MENUS
# ==========================================
show_main_menu() {
    clear
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${GREEN}    g2ray Central Manager (Codespaces)           ${NC}"
    echo -e "${CYAN}=================================================${NC}"
    echo ""
    echo -e "  ${YELLOW}1)${NC} 🖥️  Monitors Management"
    echo -e "  ${YELLOW}2)${NC} ⚙️  Global Settings (Tokens & Alerts)"
    echo -e "  ${YELLOW}3)${NC} 🛠️  Logs & Diagnostics"
    echo -e "  ${YELLOW}0)${NC} ❌ Exit"
    echo ""
    echo -n "  Select option: "
    read -r OPT
    case $OPT in
        1) menu_monitors ;;
        2) menu_settings ;;
        3) menu_diagnostics ;;
        0) clear; exit 0 ;;
        *) show_main_menu ;;
    esac
}

menu_monitors() {
    clear
    echo -e "${CYAN}--- 🖥️ Monitors Management ---${NC}"
    echo -e "  ${YELLOW}1)${NC} ➕ Add New Monitor"
    echo -e "  ${YELLOW}2)${NC} 🗑️ Remove Monitor"
    echo -e "  ${YELLOW}3)${NC} 📋 List Active Monitors"
    echo -e "  ${YELLOW}0)${NC} 🔙 Back to Main Menu"
    echo ""
    echo -n "  Select option: "
    read -r OPT
    case $OPT in
        1) add_monitor ;;
        2) remove_monitor ;;
        3) list_monitors ;;
        0) show_main_menu ;;
        *) menu_monitors ;;
    esac
}

menu_settings() {
    clear
    echo -e "${CYAN}--- ⚙️ Global Settings ---${NC}"
    echo -e "Current GitHub Token : $(if [[ -n "$GH_TOKEN" ]]; then echo -e "${GREEN}Set${NC}"; else echo -e "${RED}Not Set${NC}"; fi)"
    echo -e "Current Telegram   : $(if [[ -n "$TG_BOT" ]]; then echo -e "${GREEN}Set${NC}"; else echo -e "${RED}Not Set${NC}"; fi)"
    echo -e "Current Bale       : $(if [[ -n "$BALE_BOT" ]]; then echo -e "${GREEN}Set${NC}"; else echo -e "${RED}Not Set${NC}"; fi)"
    echo ""
    echo -e "  ${YELLOW}1)${NC} Set/Update GitHub Token"
    echo -e "  ${YELLOW}2)${NC} Set/Update Telegram Alerts"
    echo -e "  ${YELLOW}3)${NC} Set/Update Bale Alerts"
    echo -e "  ${YELLOW}0)${NC} 🔙 Back to Main Menu"
    echo ""
    echo -n "  Select option: "
    read -r OPT
    case $OPT in
        1) 
            echo -n "Enter GitHub Token: "; read -r GH_TOKEN; 
            save_config; echo -e "${GREEN}Saved!${NC}"; sleep 1; menu_settings ;;
        2) 
            echo -n "Enter Telegram Bot Token: "; read -r TG_BOT; 
            echo -n "Enter Telegram Chat ID: "; read -r TG_ID; 
            save_config; echo -e "${GREEN}Saved!${NC}"; sleep 1; menu_settings ;;
        3) 
            echo -n "Enter Bale Bot Token: "; read -r BALE_BOT; 
            echo -n "Enter Bale Chat ID: "; read -r BALE_ID; 
            save_config; echo -e "${GREEN}Saved!${NC}"; sleep 1; menu_settings ;;
        0) show_main_menu ;;
        *) menu_settings ;;
    esac
}

menu_diagnostics() {
    clear
    echo -e "${CYAN}--- 🛠️ Logs & Diagnostics ---${NC}"
    echo -e "  ${YELLOW}1)${NC} 📜 View Live Logs"
    echo -e "  ${YELLOW}2)${NC} 🧹 Clear Logs"
    echo -e "  ${YELLOW}3)${NC} 🩺 Run System Test"
    echo -e "  ${YELLOW}0)${NC} 🔙 Back to Main Menu"
    echo ""
    echo -n "  Select option: "
    read -r OPT
    case $OPT in
        1) tail -f /var/log/g2ray-monitor.log 2>/dev/null || echo "No logs."; echo "Press Ctrl+C to exit"; sleep 2; menu_diagnostics ;;
        2) > /var/log/g2ray-monitor.log; echo -e "${GREEN}Logs Cleared!${NC}"; sleep 1; menu_diagnostics ;;
        3) run_tests; echo -n "Press Enter..."; read -r; menu_diagnostics ;;
        0) show_main_menu ;;
        *) menu_diagnostics ;;
    esac
}

# ==========================================
# 4. CORE FUNCTIONS
# ==========================================
add_monitor() {
    if [[ -z "$GH_TOKEN" ]]; then
        echo -e "\n${RED}[!] GitHub Token is not set! Please go to Global Settings first.${NC}"
        sleep 2; menu_monitors; return
    fi

    echo -e "\n${CYAN}Fetching your codespaces...${NC}"
    mapfile -t CODESPACES < <(curl -s --max-time 10 -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" https://api.github.com/user/codespaces | jq -r '.codespaces[].name // empty')

    if [[ ${#CODESPACES[@]} -eq 0 ]]; then
        echo -e "${RED}No codespaces found or invalid token!${NC}"; sleep 2; menu_monitors; return
    fi

    echo ""
    for i in "${!CODESPACES[@]}"; do echo "  $((i+1))) ${CODESPACES[$i]}"; done
    echo "  0) Cancel"
    echo -n "  Select codespace to monitor: "
    read -r SEL
    
    if [[ "$SEL" == "0" ]]; then menu_monitors; return; fi
    if ! [[ "$SEL" =~ ^[0-9]+$ ]] || (( SEL < 1 || SEL > ${#CODESPACES[@]} )); then
        echo -e "${RED}Invalid selection.${NC}"; sleep 1; menu_monitors; return
    fi
    
    CS_NAME="${CODESPACES[$((SEL-1))]}"
    
    echo -n "  Check interval in seconds [Default: 60]: "
    read -r INTERVAL
    [[ -z "$INTERVAL" ]] && INTERVAL=60

    # Build the background worker script ONCE
    WORKER="/usr/local/bin/g2ray-worker.sh"
    cat > "$WORKER" << 'WORKEREOF'
#!/bin/bash
set -euo pipefail
source /etc/g2ray-monitor/global.conf

CS_NAME="$1"
INTERVAL="$2"
LOG="/var/log/g2ray-monitor.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${CS_NAME}] $*" >> "$LOG"; }

send_alert() {
    local msg="$1"
    [[ -n "$TG_BOT" && -n "$TG_ID" ]] && curl -s -X POST "https://api.telegram.org/bot${TG_BOT}/sendMessage" -d chat_id="${TG_ID}" -d text="$msg" -d parse_mode="HTML" > /dev/null
    [[ -n "$BALE_BOT" && -n "$BALE_ID" ]] && curl -s -X POST "https://tapi.bale.ai/bot${BALE_BOT}/sendMessage" -d chat_id="${BALE_ID}" -d text="$msg" -d parse_mode="HTML" > /dev/null
}

start_cs() {
    log "Down! Attempting to revive..."
    send_alert "⚠️ سرور <code>${CS_NAME}</code> خاموش شد. در حال استارت مجدد..."
    res=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/user/codespaces/${CS_NAME}/start" || true)
    if [[ "$res" == "200" || "$res" == "202" ]]; then
        log "Revive successful."
        send_alert "✅ سرور با موفقیت روشن شد."
    else
        log "Revive failed HTTP $res"
        send_alert "❌ خطا در روشن کردن سرور: $res"
    fi
}

log "Started monitoring ($INTERVAL s)"
while true; do
    state=$(curl -s -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/user/codespaces/${CS_NAME}" | jq -r '.state // empty' || true)
    case "$state" in
        Available) log "OK" ;;
        Shutdown|Stopped) start_cs ;;
    esac
    sleep "$INTERVAL"
done
WORKEREOF
    chmod +x "$WORKER"

    # Create Service
    SVC="/etc/systemd/system/g2ray-${CS_NAME}.service"
    cat > "$SVC" << EOF
[Unit]
Description=g2ray Monitor (${CS_NAME})
After=network.target

[Service]
Type=simple
User=root
ExecStart=$WORKER ${CS_NAME} ${INTERVAL}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "g2ray-${CS_NAME}.service" >/dev/null 2>&1
    echo -e "${GREEN}\n[✔] Monitor added and started successfully!${NC}"
    sleep 2
    menu_monitors
}

list_monitors() {
    echo -e "\n${CYAN}--- Active Monitors ---${NC}"
    systemctl list-units --type=service | grep g2ray- || echo -e "${YELLOW}No monitors running.${NC}"
    echo -n "Press Enter..."; read -r; menu_monitors
}

remove_monitor() {
    mapfile -t SERVICES < <(ls /etc/systemd/system/ | grep -E '^g2ray-.*\.service$' || true)
    if [[ ${#SERVICES[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No active monitors.${NC}"; sleep 1; menu_monitors; return
    fi
    echo ""
    for i in "${!SERVICES[@]}"; do echo "  $((i+1))) ${SERVICES[$i]}"; done
    echo "  0) Cancel"
    echo -n "  Select to remove: "
    read -r SEL
    if [[ "$SEL" == "0" ]]; then menu_monitors; return; fi
    if [[ "$SEL" =~ ^[0-9]+$ ]] && (( SEL > 0 && SEL <= ${#SERVICES[@]} )); then
        SVC="${SERVICES[$((SEL-1))]}"
        systemctl disable --now "$SVC" 2>/dev/null || true
        rm -f "/etc/systemd/system/$SVC"
        systemctl daemon-reload
        echo -e "${GREEN}Removed successfully!${NC}"
    fi
    sleep 1; menu_monitors
}

run_tests() {
    echo -e "\n${CYAN}Running Diagnostics...${NC}"
    ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo -e "Internet: ${GREEN}OK${NC}" || echo -e "Internet: ${RED}Fail${NC}"
    [[ -n "$GH_TOKEN" ]] && echo -e "GitHub Auth: ${GREEN}Ready${NC}" || echo -e "GitHub Auth: ${RED}Missing${NC}"
    curl -s -m 3 https://api.telegram.org >/dev/null && echo -e "Telegram API: ${GREEN}Reachable${NC}" || echo -e "Telegram API: ${RED}Blocked${NC}"
}

# START APP
show_main_menu
