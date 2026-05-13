#!/bin/bash

# بررسی دسترسی روت
if [ "$EUID" -ne 0 ]; then
  echo -e "\e[31m[-] Please run this script as root! (sudo su)\e[0m"
  exit 1
fi

echo -e "\e[34m[+]\e[0m Updating system and installing dependencies..."
apt-get update -q -y
apt-get install -q -y python3 python3-pip jq curl
pip3 install pyTelegramBotAPI --break-system-packages 2>/dev/null || pip3 install pyTelegramBotAPI

echo -e "\e[34m[+]\e[0m Setting up directory structure..."
mkdir -p /etc/g2ray-monitor
cd /etc/g2ray-monitor

echo -e "\e[34m[+]\e[0m Downloading g2ray bot..."
wget -qO bot.py "https://raw.githubusercontent.com/martialpeak/G2rayPlus/refs/heads/main/bot.py"

# متوقف کردن سرویس‌های قدیمی (در صورت وجود)
systemctl stop g2ray-panel.service g2ray-telegram.service g2ray-bale.service 2>/dev/null

echo -e "\n\e[36m=========================================\e[0m"
echo -e "\e[33m[?]\e[0m پلتفرم مورد نظر برای اجرای ربات را انتخاب کنید:"
echo -e "  1) تلگرام (Telegram) \e[32m[پیش‌فرض]\e[0m"
echo -e "  2) بله (Bale)"
echo -e "  3) هر دو (تلگرام + بله همزمان)"
read -p "انتخاب شما (1, 2 یا 3): " platform_choice

# تابع نصب سرویس تلگرام
setup_telegram() {
    echo -e "\n\e[36m--- تنظیمات تلگرام ---\e[0m"
    echo -e "\e[33m[?]\e[0m توکن ربات تلگرام خود را وارد کنید: "
    read -r tg_bot_token
    echo -e "\e[33m[?]\e[0m آیدی عددی (Chat ID) تلگرام خود را وارد کنید: "
    read -r tg_chat_id
    
    sed -i "s/YOUR_TG_TOKEN_HERE/$tg_bot_token/" bot.py
    sed -i "s/YOUR_TG_CHAT_ID_HERE/$tg_chat_id/" bot.py

    cat <<EOF > /etc/systemd/system/g2ray-telegram.service
[Unit]
Description=g2ray Bot Panel (Telegram)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/g2ray-monitor
ExecStart=/usr/bin/python3 /etc/g2ray-monitor/bot.py telegram
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable g2ray-telegram.service
    systemctl start g2ray-telegram.service
    echo -e "\e[32m[+] سرویس تلگرام با موفقیت فعال شد.\e[0m"
}

# تابع نصب سرویس بله
setup_bale() {
    echo -e "\n\e[36m--- تنظیمات بله ---\e[0m"
    echo -e "\e[33m[?]\e[0m توکن ربات بله خود را وارد کنید: "
    read -r bale_bot_token
    echo -e "\e[33m[?]\e[0m آیدی عددی (Chat ID) بله خود را وارد کنید: "
    read -r bale_chat_id
    
    sed -i "s/YOUR_BALE_TOKEN_HERE/$bale_bot_token/" bot.py
    sed -i "s/YOUR_BALE_CHAT_ID_HERE/$bale_chat_id/" bot.py

    cat <<EOF > /etc/systemd/system/g2ray-bale.service
[Unit]
Description=g2ray Bot Panel (Bale)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/g2ray-monitor
ExecStart=/usr/bin/python3 /etc/g2ray-monitor/bot.py bale
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable g2ray-bale.service
    systemctl start g2ray-bale.service
    echo -e "\e[32m[+] سرویس بله با موفقیت فعال شد.\e[0m"
}

# بررسی انتخاب کاربر و اجرای توابع
if [ "$platform_choice" == "2" ]; then
    setup_bale
elif [ "$platform_choice" == "3" ]; then
    setup_telegram
    setup_bale
else
    # اگر 1 زد یا اینتر خالی زد (پیش‌فرض)
    setup_telegram
fi

echo -e "\n\e[32m[✔] Installation Successful!\e[0m"
echo -e "ربات شما با موفقیت راه‌اندازی شد. اکنون می‌توانید به ربات پیام /start ارسال کنید."
