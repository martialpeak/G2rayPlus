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

if [[ "${BASH_SOURCE[0]}" != "/usr/local/bin/g2ray" ]]; then
    echo -e "${CYAN}Installing 'g2ray' globally...${NC}"
    cp "${BASH_SOURCE[0]}" /usr/local/bin/g2ray
    chmod +x /usr/local/bin/g2ray
    echo -e "${GREEN}Installation successful!${NC}"
    echo -e "From now on, just type ${CYAN}g2ray${NC} in the terminal to open this manager."
    sleep 3
    exec g2ray
fi

show_menu() {
    clear
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${GREEN}    g2ray Codespace Manager & Auto-Monitor       ${NC}"
    echo -e "${CYAN}=================================================${NC}"
    echo ""
    echo -e "  ${YELLOW}1)${NC} Add or Update a Monitor"
    echo -e "  ${YELLOW}2)${NC} Remove an active Monitor"
    echo -e "  ${YELLOW}3)${NC} View Live Logs"
    echo -e "  ${YELLOW}4)${NC} Advanced Diagnostics"
    echo -e "  ${YELLOW}5)${NC} Clear Logs"
    echo -e "  ${YELLOW}0)${NC} Exit"
    echo ""
    echo -n "  Select an option [0-5]: "
    read -r OPTION
    echo ""

    case $OPTION in
        1) install_monitor ;;
        2) uninstall_monitor ;;
        3) view_logs ;;
        4) advanced_diagnostics ;;
        5) clear_logs ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid option!${NC}"; sleep 2; show_menu ;;
    esac
}

install_monitor() {
    echo -e "${CYAN}[1/6] Installing dependencies...${NC}"
    apt-get update -qq
    apt-get install -y -qq curl jq iputils-ping
    echo "      Done."

    echo ""
    echo -e "${CYAN}[2/6] GitHub Personal Access Token${NC}"
    while true; do
        echo -n "      Paste your token (hidden): "
        read -sr GH_TOKEN
        GH_TOKEN=$(echo "$GH_TOKEN" | tr -d '[:space:]')
        echo ""
        if [[ -z "$GH_TOKEN" ]]; then echo -e "${RED}      Cannot be empty.${NC}"; continue; fi
        echo "      Verifying..."
        LOGIN=$(curl -s --max-time 10 -H "Authorization: Bearer $GH_TOKEN" https://api.github.com/user | jq -r '.login // empty' || true)
        if [[ -n "$LOGIN" ]]; then
            echo -e "      ${GREEN}OK -- GitHub user: $LOGIN${NC}"
            break
        else
            echo -e "${RED}      Invalid token or no internet. Try again.${NC}"
        fi
    done

    echo ""
    echo -e "${CYAN}[3/6] Fetching your codespaces...${NC}"
    mapfile -t CODESPACES < <(curl -s --max-time 10 -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" https://api.github.com/user/codespaces | jq -r '.codespaces[].name // empty')

    if [[ ${#CODESPACES[@]} -eq 0 ]]; then
        echo -e "${RED}      ERROR: No codespaces found!${NC}"; sleep 3; show_menu; return
    fi

    echo "      Available codespaces:"
    for i in "${!CODESPACES[@]}"; do echo "      $((i+1))) ${CODESPACES[$i]}"; done
    echo ""

    while true; do
        echo -n "      Enter the number of the codespace: "
        read -r SELECTION
        if [[ "$SELECTION" =~ ^[0-9]+$ ]] && (( SELECTION > 0 && SELECTION <= ${#CODESPACES[@]} )); then
            CODESPACE_NAME="${CODESPACES[$((SELECTION-1))]}"
            break
        else
            echo -e "${RED}      Invalid selection.${NC}"
        fi
    done
    echo -e "      ${GREEN}Selected: $CODESPACE_NAME${NC}"

    echo ""
    echo -e "${CYAN}[4/6] Monitoring Interval${NC}"
    echo -n "      Enter check interval in seconds [Default: 60]: "
    read -r USER_INTERVAL
    if [[ -z "$USER_INTERVAL" ]] || ! [[ "$USER_INTERVAL" =~ ^[0-9]+$ ]]; then
        CHECK_INTERVAL=60
        echo -e "      ${YELLOW}Using default: 60 seconds.${NC}"
    else
        CHECK_INTERVAL="$USER_INTERVAL"
    fi

    echo ""
    echo -e "${CYAN}[5/6] Setup Alerts (Telegram / Bale)${NC}"
    TELEGRAM_BOT_TOKEN=""
    TELEGRAM_CHAT_ID=""
    BALE_BOT_TOKEN=""
    BALE_CHAT_ID=""

    echo "      Where do you want to receive alerts?"
    echo "      1) Telegram"
    echo "      2) Bale"
    echo "      3) Both (Telegram + Bale)"
    echo "      0) Skip alerts"
    echo -n "      Your choice [Default: 0]: "
    read -r ALERT_CHOICE
    
    if [[ -z "$ALERT_CHOICE" ]]; then ALERT_CHOICE="0"; fi

    # Telegram Setup
    if [[ "$ALERT_CHOICE" == "1" || "$ALERT_CHOICE" == "3" ]]; then
        echo -e "\n      ${CYAN}--- Telegram Setup ---${NC}"
        echo -n "      Enter Telegram Bot Token: "
        read -r RAW_TG_TOKEN
        TELEGRAM_BOT_TOKEN=$(echo "$RAW_TG_TOKEN" | tr -d '[:space:]')
        
        echo -n "      Enter Telegram Chat ID: "
        read -r RAW_TG_ID
        TELEGRAM_CHAT_ID=$(echo "$RAW_TG_ID" | tr -d '[:space:]')
        
        echo "      Testing Telegram bot..."
        TG_TEST=$(curl -s --max-time 10 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHAT_ID}" \
            -d text="🔔 <b>پیام تست:</b> سیستم مدیریت برای سرور <code>${CODESPACE_NAME}</code> در تلگرام فعال شد!" \
            -d parse_mode="HTML" || true)
            
        if echo "$TG_TEST" | grep -q '"ok":true'; then
            echo -e "      ${GREEN}Telegram test message sent successfully!${NC}"
        else
            echo -e "      ${RED}Failed to send Telegram message. Check Token/Chat ID.${NC}"
            TELEGRAM_BOT_TOKEN=""
            TELEGRAM_CHAT_ID=""
        fi
    fi

    # Bale Setup
    if [[ "$ALERT_CHOICE" == "2" || "$ALERT_CHOICE" == "3" ]]; then
        echo -e "\n      ${CYAN}--- Bale Setup ---${NC}"
        echo -n "      Enter Bale Bot Token: "
        read -r RAW_BALE_TOKEN
        BALE_BOT_TOKEN=$(echo "$RAW_BALE_TOKEN" | tr -d '[:space:]')
        
        echo -n "      Enter Bale Chat ID: "
        read -r RAW_BALE_ID
        BALE_CHAT_ID=$(echo "$RAW_BALE_ID" | tr -d '[:space:]')
        
        echo "      Testing Bale bot..."
        BALE_TEST=$(curl -s --max-time 10 -X POST "https://tapi.bale.ai/bot${BALE_BOT_TOKEN}/sendMessage" \
            -d chat_id="${BALE_CHAT_ID}" \
            -d text="🔔 <b>پیام تست:</b> سیستم مدیریت برای سرور <code>${CODESPACE_NAME}</code> در بله فعال شد!" \
            -d parse_mode="HTML" || true)
            
        if echo "$BALE_TEST" | grep -q '"ok":true'; then
            echo -e "      ${GREEN}Bale test message sent successfully!${NC}"
        else
            echo -e "      ${RED}Failed to send Bale message. Check Token/Chat ID.${NC}"
            BALE_BOT_TOKEN=""
            BALE_CHAT_ID=""
        fi
    fi

    echo ""
    echo -e "${CYAN}[6/6] Configuring System Service...${NC}"
    SERVICE_NAME="g2ray-${CODESPACE_NAME}"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    ENV_FILE="/etc/g2ray-monitor/${CODESPACE_NAME}.env"

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        systemctl stop "$SERVICE_NAME"
    fi

    mkdir -p /etc/g2ray-monitor
    cat > "$ENV_FILE" << ENVEOF
GH_TOKEN=$GH_TOKEN
CODESPACE_NAME=$CODESPACE_NAME
CHECK_INTERVAL=$CHECK_INTERVAL
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID
BALE_BOT_TOKEN=$BALE_BOT_TOKEN
BALE_CHAT_ID=$BALE_CHAT_ID
ENVEOF
    chmod 600 "$ENV_FILE"

    cat > /usr/local/bin/g2ray-monitor.sh << 'MONITOREOF'
#!/bin/bash
set -euo pipefail

GH_TOKEN="${GH_TOKEN:-}"
CODESPACE_NAME="${CODESPACE_NAME:-}"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
BALE_BOT_TOKEN="${BALE_BOT_TOKEN:-}"
BALE_CHAT_ID="${BALE_CHAT_ID:-}"
LOG_FILE="/var/log/g2ray-monitor.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${CODESPACE_NAME}] $*" | tee -a "$LOG_FILE"; }

send_alert() {
    local message="$1"
    
    # Send to Telegram
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
        curl -s --max-time 10 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHAT_ID}" \
            -d text="$message" \
            -d parse_mode="HTML" > /dev/null || true
    fi
    
    # Send to Bale
    if [[ -n "$BALE_BOT_TOKEN" && -n "$BALE_CHAT_ID" ]]; then
        curl -s --max-time 10 -X POST "https://tapi.bale.ai/bot${BALE_BOT_TOKEN}/sendMessage" \
            -d chat_id="${BALE_CHAT_ID}" \
            -d text="$message" \
            -d parse_mode="HTML" > /dev/null || true
    fi
}

get_state() {
    local response
    response=$(curl -s --max-time 10 \
        -H "Authorization: Bearer $GH_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/user/codespaces/${CODESPACE_NAME}" || true)
    if [[ -n "$response" ]]; then
        echo "$response" | jq -r '.state // empty' 2>/dev/null || echo ""
    else
        echo ""
    fi
}

start_codespace() {
    log "Codespace is down -- starting..."
    send_alert "⚠️ <b>هشدار:</b> سرور <code>${CODESPACE_NAME}</code> خاموش شده است! سیستم در حال راه‌اندازی مجدد آن می‌باشد..."
    
    local result
    result=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer $GH_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/user/codespaces/${CODESPACE_NAME}/start" || echo "failed")
        
    if [[ "$result" == "200" || "$result" == "202" ]]; then
        log "Start request sent successfully (HTTP $result)"
        send_alert "✅ <b>وضعیت:</b> دستور روشن شدن با موفقیت ارسال شد. کداسپیس تا چند ثانیه دیگر متصل می‌شود."
    else
        log "ERROR: Start request failed (HTTP $result)"
        send_alert "❌ <b>خطا:</b> راه‌اندازی مجدد سرور با مشکل مواجه شد (ارور سرور گیت‌هاب: $result)."
    fi
}

log "=== g2ray-monitor started ==="
while true; do
    STATE=$(get_state)
    case "$STATE" in
        Available) log "State: $STATE - OK, running" ;;
        Shutdown|Stopped) log "State: $STATE - Waking up"; start_codespace ;;
        Starting|Awaiting*) log "State: $STATE - Waiting for startup" ;;
        "") log "ERROR: Could not get state -- check network/API" ;;
        *) log "Unknown state: $STATE" ;;
    esac
    sleep "$CHECK_INTERVAL"
done
MONITOREOF

    chmod +x /usr/local/bin/g2ray-monitor.sh
    touch /var/log/g2ray-monitor.log

    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=g2ray Monitor - ${CODESPACE_NAME}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
EnvironmentFile=${ENV_FILE}
ExecStart=/usr/local/bin/g2ray-monitor.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$SERVICE_NAME" >/dev/null 2>&1
    sleep 2

    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN}   Done! Service is running for $CODESPACE_NAME${NC}"
    echo -e "${GREEN}=================================================${NC}"
    sleep 3
    show_menu
}

uninstall_monitor() {
    echo -e "${CYAN}=== Uninstall a Monitor ===${NC}"
    mapfile -t SERVICES < <(ls /etc/systemd/system/ | grep -E '^g2ray-.*\.service$' || true)
    
    if [[ ${#SERVICES[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No active monitors found.${NC}"
        sleep 2; show_menu; return
    fi

    for i in "${!SERVICES[@]}"; do echo "  $((i+1))) ${SERVICES[$i]}"; done
    echo "  0) Cancel"
    echo ""
    echo -n "  Select the monitor to remove: "
    read -r DEL_SEL

    if [[ "$DEL_SEL" == "0" ]]; then show_menu; return; fi

    if [[ "$DEL_SEL" =~ ^[0-9]+$ ]] && (( DEL_SEL > 0 && DEL_SEL <= ${#SERVICES[@]} )); then
        TARGET_SERVICE="${SERVICES[$((DEL_SEL-1))]}"
        TARGET_ENV_NAME=$(echo "$TARGET_SERVICE" | sed 's/g2ray-//' | sed 's/\.service//')
        
        echo -e "  ${YELLOW}Stopping and removing $TARGET_SERVICE...${NC}"
        systemctl stop "$TARGET_SERVICE" 2>/dev/null || true
        systemctl disable "$TARGET_SERVICE" 2>/dev/null || true
        rm -f "/etc/systemd/system/$TARGET_SERVICE"
        rm -f "/etc/g2ray-monitor/${TARGET_ENV_NAME}.env"
        systemctl daemon-reload
        echo -e "  ${GREEN}Successfully removed!${NC}"
    else
        echo -e "${RED}Invalid selection.${NC}"
    fi
    sleep 2
    show_menu
}

view_logs() {
    if [[ -f /var/log/g2ray-monitor.log ]]; then
        echo -e "${CYAN}Showing logs... (Press Ctrl+C to return to menu)${NC}"
        trap 'show_menu' INT
        tail -f /var/log/g2ray-monitor.log
        trap - INT
    else
        echo -e "${YELLOW}No logs found yet.${NC}"
        sleep 2
        show_menu
    fi
}

clear_logs() {
    > /var/log/g2ray-monitor.log
    echo -e "${GREEN}Logs cleared successfully!${NC}"
    sleep 2
    show_menu
}

advanced_diagnostics() {
    clear
    echo -e "${CYAN}=== 🛠 Advanced Diagnostics ===${NC}"
    echo ""
    
    echo -e "${YELLOW}1. Server Internet & Ping:${NC}"
    if ping -c 3 8.8.8.8 >/dev/null 2>&1; then echo -e "   ${GREEN}✔ OK (Internet is connected)${NC}"; else echo -e "   ${RED}❌ FAILED (No internet connection)${NC}"; fi
    
    echo -e "\n${YELLOW}2. GitHub API Access:${NC}"
    HTTP_GH=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 https://api.github.com || echo "000")
    if [[ "$HTTP_GH" == "200" || "$HTTP_GH" == "401" ]]; then echo -e "   ${GREEN}✔ OK (HTTP $HTTP_GH)${NC}"; else echo -e "   ${RED}❌ FAILED (HTTP $HTTP_GH)${NC}"; fi

    echo -e "\n${YELLOW}3. Telegram API Access:${NC}"
    HTTP_TG=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 https://api.telegram.org || echo "000")
    if [[ "$HTTP_TG" == "200" ]]; then echo -e "   ${GREEN}✔ OK (Not blocked)${NC}"; else echo -e "   ${RED}❌ FAILED (Blocked or Network error)${NC}"; fi

    echo -e "\n${YELLOW}4. Bale API Access:${NC}"
    HTTP_BALE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 https://tapi.bale.ai || echo "000")
    if [[ "$HTTP_BALE" == "200" || "$HTTP_BALE" == "404" ]]; then echo -e "   ${GREEN}✔ OK (Not blocked)${NC}"; else echo -e "   ${RED}❌ FAILED (Blocked or Network error)${NC}"; fi

    echo -e "\n${YELLOW}5. Active g2ray Services:${NC}"
    systemctl list-units --type=service | grep g2ray || echo -e "   ${YELLOW}No active services found.${NC}"

    echo -e "\n${YELLOW}6. System Resources (RAM & Disk):${NC}"
    free -m | awk 'NR==2{printf "   RAM: %sMB / %sMB (%.2f%% used)\n", $3,$2,$3*100/$2 }'
    df -h / | awk 'NR==2{printf "   Disk: %s / %s (%s used)\n", $3,$2,$5 }'
    
    echo ""
    echo -n "Press Enter to return to menu..."
    read -r
    show_menu
}

show_menu
