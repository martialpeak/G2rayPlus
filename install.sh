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

# GitHub Project URL
REPO_URL="https://github.com/martialpeak/G2rayPlus"

CONF_DIR="/etc/g2ray-monitor"
CONF_FILE="$CONF_DIR/global.conf"
mkdir -p "$CONF_DIR"
touch "$CONF_FILE"

# ==========================================
# 0. CLEANUP OLD CODES (ربات‌ها دیگر حذف نمی‌شوند)
# ==========================================
systemctl stop g2ray-panel.service 2>/dev/null || true
rm -f /etc/systemd/system/g2ray-panel.service 2>/dev/null || true
systemctl daemon-reload

# ==========================================
# 1. AUTO-INSTALL GLOBAL COMMAND & PYTHON DEPS
# ==========================================
if [[ "${BASH_SOURCE[0]}" != "/usr/local/bin/g2ray" ]]; then
    echo -e "${CYAN}[+] Installing 'g2ray' core to system...${NC}"
    apt-get update -qq && apt-get install -y -qq curl jq iputils-ping python3 python3-pip
    
    # نصب کتابخانه تلگرام
    pip3 install pyTelegramBotAPI --break-system-packages 2>/dev/null || pip3 install pyTelegramBotAPI
    
    cp "${BASH_SOURCE[0]}" /usr/local/bin/g2ray
    chmod +x /usr/local/bin/g2ray
    
    # دانلود مستقیم فایل ربات از گیت‌هاب و قرار دادن در مسیر سیستم
    echo -e "${CYAN}[+] Downloading bot.py from GitHub...${NC}"
    curl -Ls https://raw.githubusercontent.com/martialpeak/G2rayPlus/refs/heads/main/bot.py -o /etc/g2ray-monitor/bot.py
    
    # بررسی اینکه فایل با موفقیت دانلود شده باشد
    if [[ ! -f /etc/g2ray-monitor/bot.py ]]; then
        echo -e "${RED}[!] Error: Failed to download bot.py!${NC}"
        exit 1
    fi
    echo -e "${GREEN}[✔] Update successful!${NC}"
    echo -e "From now on, just type ${YELLOW}g2ray${NC} anywhere in your terminal."
    sleep 2
    exec g2ray
fi
# ==========================================
# 2. GLOBAL SETTINGS (Only Telegram/Bale)
# ==========================================
load_config() {
    TG_BOT=""; TG_ID=""; BALE_BOT=""; BALE_ID=""
    if [[ -f "$CONF_FILE" ]]; then source "$CONF_FILE"; fi
}

save_config() {
    cat > "$CONF_FILE" <<EOF
TG_BOT="$TG_BOT"
TG_ID="$TG_ID"
BALE_BOT="$BALE_BOT"
BALE_ID="$BALE_ID"
EOF
    chmod 600 "$CONF_FILE"
}
load_config

# ==========================================
# 3. MENUS (Header with Project Link)
# ==========================================
draw_header() {
    clear
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${GREEN}    g2ray Central Manager (Codespaces)           ${NC}"
    echo -e "${YELLOW}    URL: ${REPO_URL}${NC}"
    echo -e "${CYAN}=================================================${NC}"
}

show_main_menu() {
    draw_header
    echo ""
    echo -e "  ${YELLOW}1)${NC} 🖥️  Monitors Management"
    echo -e "  ${YELLOW}2)${NC} ⚙️  Global Alerts & Cleanup"
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
    draw_header
    echo -e "  --- 🖥️ Monitors Management ---"
    echo ""
    echo -e "  ${YELLOW}1)${NC} ➕ Add New Monitor (Requires GitHub Token)"
    echo -e "  ${YELLOW}2)${NC} 🗑️ Remove a Monitor"
    echo -e "  ${YELLOW}3)${NC} 📋 List Active Monitors"
    echo -e "  ${YELLOW}4)${NC} 🔌 Power Control (Start/Stop Server)"
    echo -e "  ${YELLOW}0)${NC} 🔙 Back to Main Menu"
    echo ""
    echo -n "  Select option: "
    read -r OPT
    case $OPT in
        1) add_monitor ;;
        2) remove_monitor ;;
        3) list_monitors ;;
        4) power_control ;;
        0) show_main_menu ;;
        *) menu_monitors ;;
    esac
}

# ... (بقیه توابع add_monitor, remove_monitor, power_control ثابت می‌مانند) ...

# تابع Diagnostics اصلاح شده با آدرس گیت‌هاب
run_tests() {
    echo -e "\n${CYAN}Running Diagnostics...${NC}"
    echo -e "Project URL  : ${YELLOW}${REPO_URL}${NC}"
    ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo -e "Internet     : ${GREEN}OK${NC}" || echo -e "Internet     : ${RED}Fail${NC}"
    curl -s -m 3 https://api.telegram.org >/dev/null && echo -e "Telegram API : ${GREEN}Reachable${NC}" || echo -e "Telegram API : ${RED}Blocked${NC}"
    curl -s -m 3 https://tapi.bale.ai >/dev/null && echo -e "Bale API     : ${GREEN}Reachable${NC}" || echo -e "Bale API     : ${RED}Blocked${NC}"
}

setup_bot_service() {
    local platform=$1
    local svc_name="g2ray-${platform}-bot.service"
    
    cat > "/etc/systemd/system/${svc_name}" <<EOF
[Unit]
Description=g2ray ${platform} interactive bot
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /etc/g2ray-monitor/bot.py ${platform}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl restart "${svc_name}"
    systemctl enable "${svc_name}" >/dev/null 2>&1
}
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
    echo -e "  ${YELLOW}2)${NC} ⚙️  Global Alerts & Cleanup"
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
    echo -e "  ${YELLOW}1)${NC} ➕ Add New Monitor (Requires GitHub Token)"
    echo -e "  ${YELLOW}2)${NC} 🗑️ Remove a Monitor"
    echo -e "  ${YELLOW}3)${NC} 📋 List Active Monitors"
    echo -e "  ${YELLOW}4)${NC} 🔌 Power Control (Start/Stop Server)"
    echo -e "  ${YELLOW}0)${NC} 🔙 Back to Main Menu"
    echo ""
    echo -n "  Select option: "
    read -r OPT
    case $OPT in
        1) add_monitor ;;
        2) remove_monitor ;;
        3) list_monitors ;;
        4) power_control ;;
        0) show_main_menu ;;
        *) menu_monitors ;;
    esac
}

menu_settings() {
    clear
    echo -e "${CYAN}--- ⚙️ Global Alerts & Cleanup ---${NC}"
    echo -e "Current Telegram   : $(if [[ -n "$TG_BOT" ]]; then echo -e "${GREEN}Set${NC}"; else echo -e "${RED}Not Set${NC}"; fi)"
    echo -e "Current Bale       : $(if [[ -n "$BALE_BOT" ]]; then echo -e "${GREEN}Set${NC}"; else echo -e "${RED}Not Set${NC}"; fi)"
    echo ""
    echo -e "  ${YELLOW}1)${NC} Set/Update Telegram Alerts"
    echo -e "  ${YELLOW}2)${NC} Set/Update Bale Alerts"
    echo -e "  ${YELLOW}3)${NC} 🧹 Deep Cleanup (Purge ALL monitors & codes)"
    echo -e "  ${YELLOW}0)${NC} 🔙 Back to Main Menu"
    echo ""
    echo -n "  Select option: "
    read -r OPT
    case $OPT in
        1) 
            echo -n "Enter Telegram Bot Token: "; read -r TG_BOT; 
            echo -n "Enter Telegram Chat ID: "; read -r TG_ID; 
            save_config; 
            setup_bot_service "telegram"
            echo -e "${GREEN}Saved & Telegram Bot Started!${NC}"; sleep 1; menu_settings ;;
        2) 
            echo -n "Enter Bale Bot Token: "; read -r BALE_BOT; 
            echo -n "Enter Bale Chat ID: "; read -r BALE_ID; 
            save_config; 
            setup_bot_service "bale"
            echo -e "${GREEN}Saved & Bale Bot Started!${NC}"; sleep 1; menu_settings ;;
        3)  purge_all ;;
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
    echo -e "\n${CYAN}--- GitHub Verification ---${NC}"
    echo -n "  Paste GitHub Token for this codespace (hidden): "
    read -sr GH_TOKEN
    echo ""
    GH_TOKEN=$(echo "$GH_TOKEN" | tr -d '[:space:]')
    
    if [[ -z "$GH_TOKEN" ]]; then echo -e "${RED}Token cannot be empty!${NC}"; sleep 2; menu_monitors; return; fi
    
    echo "  Verifying token..."
    LOGIN=$(curl -s --max-time 10 -H "Authorization: Bearer $GH_TOKEN" https://api.github.com/user | jq -r '.login // empty' || true)
    if [[ -z "$LOGIN" ]]; then
        echo -e "${RED}  Invalid token or network error!${NC}"; sleep 2; menu_monitors; return
    fi
    echo -e "  ${GREEN}Authorized as: $LOGIN${NC}"

    echo -e "\n${CYAN}Fetching codespaces...${NC}"
    mapfile -t CODESPACES < <(curl -s --max-time 10 -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" https://api.github.com/user/codespaces | jq -r '.codespaces[].name // empty')

    if [[ ${#CODESPACES[@]} -eq 0 ]]; then
        echo -e "${RED}No codespaces found for this token!${NC}"; sleep 2; menu_monitors; return
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

    cat > "$CONF_DIR/${CS_NAME}.env" <<EOF
GH_TOKEN="$GH_TOKEN"
INTERVAL="$INTERVAL"
EOF
    chmod 600 "$CONF_DIR/${CS_NAME}.env"

    WORKER="/usr/local/bin/g2ray-worker.sh"
    cat > "$WORKER" << 'WORKEREOF'
#!/bin/bash
set -euo pipefail

CS_NAME="$1"
LOG="/var/log/g2ray-monitor.log"

source /etc/g2ray-monitor/global.conf
source "/etc/g2ray-monitor/${CS_NAME}.env"

TG_BOT="${TG_BOT:-}"
TG_ID="${TG_ID:-}"
BALE_BOT="${BALE_BOT:-}"
BALE_ID="${BALE_ID:-}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${CS_NAME}] $*" >> "$LOG"; }

send_alert() {
    local msg="$1"
    [[ -n "$TG_BOT" && -n "$TG_ID" ]] && curl -s --max-time 10 -X POST "https://api.telegram.org/bot${TG_BOT}/sendMessage" -d chat_id="${TG_ID}" -d text="$msg" -d parse_mode="HTML" > /dev/null || true
    [[ -n "$BALE_BOT" && -n "$BALE_ID" ]] && curl -s --max-time 10 -X POST "https://tapi.bale.ai/bot${BALE_BOT}/sendMessage" -d chat_id="${BALE_ID}" -d text="$msg" -d parse_mode="HTML" > /dev/null || true
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
    state=$(curl -s --max-time 10 -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/user/codespaces/${CS_NAME}" | jq -r '.state // empty' || true)
    case "$state" in
        Available) log "OK" ;;
        Shutdown|Stopped) start_cs ;;
    esac
    sleep "$INTERVAL"
done
WORKEREOF
    chmod +x "$WORKER"

    SVC="/etc/systemd/system/g2ray-${CS_NAME}.service"
    cat > "$SVC" << EOF
[Unit]
Description=g2ray Monitor (${CS_NAME})
After=network.target

[Service]
Type=simple
User=root
ExecStart=$WORKER ${CS_NAME}
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
        TARGET_ENV=$(echo "$SVC" | sed 's/g2ray-//' | sed 's/\.service//')
        
        systemctl disable --now "$SVC" 2>/dev/null || true
        rm -f "/etc/systemd/system/$SVC"
        rm -f "$CONF_DIR/${TARGET_ENV}.env"
        systemctl daemon-reload
        echo -e "${GREEN}Removed successfully!${NC}"
    fi
    sleep 1; menu_monitors
}

power_control() {
    clear
    echo -e "${CYAN}--- 🔌 Power Control ---${NC}"
    mapfile -t ENV_FILES < <(ls /etc/g2ray-monitor/*.env 2>/dev/null | grep -v 'global.conf' || true)
    
    if [[ ${#ENV_FILES[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No servers configured yet. Add a monitor first!${NC}"
        sleep 2; menu_monitors; return
    fi

    echo ""
    for i in "${!ENV_FILES[@]}"; do
        NAME=$(basename "${ENV_FILES[$i]}" .env)
        if systemctl is-active --quiet "g2ray-${NAME}.service"; then
            STATUS="${GREEN}Monitor: ON${NC}"
        else
            STATUS="${RED}Monitor: OFF${NC}"
        fi
        echo -e "  $((i+1))) ${NAME} [${STATUS}]"
    done
    echo "  0) Cancel"
    echo ""
    echo -n "  Select server to control: "
    read -r SEL

    if [[ "$SEL" == "0" ]]; then menu_monitors; return; fi
    if ! [[ "$SEL" =~ ^[0-9]+$ ]] || (( SEL < 1 || SEL > ${#ENV_FILES[@]} )); then
        echo -e "${RED}Invalid selection.${NC}"; sleep 1; power_control; return
    fi

    TARGET_ENV="${ENV_FILES[$((SEL-1))]}"
    CS_NAME=$(basename "$TARGET_ENV" .env)
    
    # Load the GH_TOKEN for this specific server
    source "$TARGET_ENV"

    echo -e "\n  ${CYAN}Action for $CS_NAME:${NC}"
    echo -e "  ${YELLOW}1)${NC} ▶️ Start Server & Monitor"
    echo -e "  ${YELLOW}2)${NC} 🛑 Stop Server & Monitor"
    echo -e "  ${YELLOW}0)${NC} 🔙 Back"
    echo -n "  Select action: "
    read -r ACT

    if [[ "$ACT" == "1" ]]; then
        echo -e "  ${YELLOW}Starting server and monitor...${NC}"
        curl -s -o /dev/null -X POST -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/user/codespaces/${CS_NAME}/start" || true
        systemctl start "g2ray-${CS_NAME}.service" 2>/dev/null || true
        echo -e "  ${GREEN}Server started!${NC}"
    elif [[ "$ACT" == "2" ]]; then
        echo -e "  ${YELLOW}Stopping monitor and server...${NC}"
        systemctl stop "g2ray-${CS_NAME}.service" 2>/dev/null || true
        curl -s -o /dev/null -X POST -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/user/codespaces/${CS_NAME}/stop" || true
        echo -e "  ${GREEN}Server stopped!${NC}"
    fi
    sleep 2; power_control
}

purge_all() {
    echo -e "\n${RED}⚠️ WARNING: This will STOP and DELETE all monitors, tokens, and settings!${NC}"
    echo -n "Are you absolutely sure? (type 'yes' to confirm): "
    read -r CONFIRM
    if [[ "$CONFIRM" == "yes" ]]; then
        echo -e "${YELLOW}Purging system...${NC}"
        mapfile -t SERVICES < <(ls /etc/systemd/system/ | grep -E '^g2ray-.*\.service$' || true)
        for SVC in "${SERVICES[@]:-}"; do
            systemctl disable --now "$SVC" 2>/dev/null || true
            rm -f "/etc/systemd/system/$SVC"
        done
        rm -rf /etc/g2ray-monitor/*
        systemctl daemon-reload
        echo -e "${GREEN}System completely purged!${NC}"
        sleep 2
        show_main_menu
    else
        echo -e "${GREEN}Aborted.${NC}"
        sleep 1; menu_settings
    fi
}

run_tests() {
    echo -e "\n${CYAN}Running Diagnostics...${NC}"
    ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo -e "Internet: ${GREEN}OK${NC}" || echo -e "Internet: ${RED}Fail${NC}"
    curl -s -m 3 https://api.telegram.org >/dev/null && echo -e "Telegram API: ${GREEN}Reachable${NC}" || echo -e "Telegram API: ${RED}Blocked${NC}"
    curl -s -m 3 https://tapi.bale.ai >/dev/null && echo -e "Bale API: ${GREEN}Reachable${NC}" || echo -e "Bale API: ${RED}Blocked${NC}"
}

# START APP
show_main_menu
