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
# حتما لینک زیر را با لینک RAW فایل bot.py در گیت‌هاب خودتان عوض کنید:
wget -qO bot.py "https://raw.githubusercontent.com/martialpeak/G2rayPlus/refs/heads/main/bot.py"

echo -e "\e[33m[?]\e[0m Enter your Telegram Bot Token (from @BotFather): "
read -r user_bot_token
echo -e "\e[33m[?]\e[0m Enter your Telegram Admin Chat ID: "
read -r user_chat_id

echo -e "\e[34m[+]\e[0m Applying your configuration..."
sed -i "s/YOUR_TG_TOKEN_HERE/$user_bot_token/" bot.py
sed -i "s/YOUR_TG_CHAT_ID_HERE/$user_chat_id/" bot.py

echo -e "\e[34m[+]\e[0m Creating Systemd background service..."
cat <<EOF > /etc/systemd/system/g2ray-panel.service
[Unit]
Description=g2ray Telegram Bot Panel
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

echo -e "\e[34m[+]\e[0m Starting the bot service..."
systemctl daemon-reload
systemctl enable g2ray-panel.service
systemctl start g2ray-panel.service

echo -e "\e[32m[✔] Installation Successful!\e[0m"
echo -e "You can now go to your Telegram bot and send /start"
