import telebot
from telebot import apihelper
from telebot.types import InlineKeyboardMarkup, InlineKeyboardButton
import subprocess
import json
import os
import sys
import time

# ==========================================
# خواندن اتوماتیک توکن‌ها از فایل کانفیگ ترمینال
# ==========================================
def load_config():
    conf_path = "/etc/g2ray-monitor/global.conf"
    config = {'TG_BOT': '', 'TG_ID': '', 'BALE_BOT': '', 'BALE_ID': ''}
    if os.path.exists(conf_path):
        with open(conf_path, 'r') as f:
            for line in f:
                if '=' in line:
                    key, val = line.strip().split('=', 1)
                    config[key] = val.strip('"').strip("'")
    return config

cfg = load_config()

TG_BOT_TOKEN = cfg.get('TG_BOT', '')
TG_CHAT_ID = cfg.get('TG_ID', '')
BALE_BOT_TOKEN = cfg.get('BALE_BOT', '')
BALE_CHAT_ID = cfg.get('BALE_ID', '')

# تشخیص اینکه اسکریپت برای کدام پیام‌رسان اجرا شده است
platform = sys.argv[1] if len(sys.argv) > 1 else 'telegram'

if platform == 'bale':
    if not BALE_BOT_TOKEN:
        print("Bale token not set in global.conf. Exiting.")
        sys.exit(0)
    apihelper.API_URL = "https://tapi.bale.ai/bot{0}/{1}"
    BOT_TOKEN = BALE_BOT_TOKEN
    ADMIN_ID = BALE_CHAT_ID
    APP_NAME = "بله 🔵"
else:
    if not TG_BOT_TOKEN:
        print("Telegram token not set in global.conf. Exiting.")
        sys.exit(0)
    BOT_TOKEN = TG_BOT_TOKEN
    ADMIN_ID = TG_CHAT_ID
    APP_NAME = "تلگرام ✈️"

bot = telebot.TeleBot(BOT_TOKEN)
user_states = {}
# ─────────────────────────────────────────
# توابع کمکی
# ─────────────────────────────────────────

def check_auth(user_id):
    return str(user_id) == str(ADMIN_ID)

def get_services():
    """لیست تمام سرویس‌های g2ray نصب‌شده"""
    try:
        return [
            f for f in os.listdir('/etc/systemd/system')
            if f.startswith('g2ray-') and f.endswith('.service') and 'bot' not in f
        ]
    except Exception:
        return []

def get_service_status(cs_name):
    """وضعیت یک سرویس systemd را برمی‌گرداند"""
    try:
        result = subprocess.run(
            f"systemctl is-active g2ray-{cs_name}.service",
            shell=True, capture_output=True, text=True
        )
        return result.stdout.strip()
    except Exception:
        return "unknown"

def get_codespace_state(token, cs_name):
    """وضعیت یک Codespace را از GitHub API می‌گیرد"""
    try:
        cmd = (
            f'curl -s --max-time 10 '
            f'-H "Authorization: Bearer {token}" '
            f'-H "Accept: application/vnd.github+json" '
            f'"https://api.github.com/user/codespaces/{cs_name}"'
        )
        res = subprocess.check_output(cmd, shell=True, text=True)
        data = json.loads(res)
        return data.get('state', 'Unknown'), data.get('machine', {}).get('display_name', '')
    except Exception:
        return 'Unknown', ''

def get_env_token(cs_name):
    """توکن GH را از فایل env می‌خواند"""
    env_file = f"/etc/g2ray-monitor/{cs_name}.env"
    if not os.path.exists(env_file):
        return ""
    with open(env_file, 'r') as f:
        for line in f:
            if line.startswith("GH_TOKEN="):
                return line.strip().split('=', 1)[1]
    return ""

def format_uptime():
    """آپتایم سیستم را فرمت می‌کند"""
    try:
        res = subprocess.check_output("uptime -p", shell=True, text=True).strip()
        return res
    except Exception:
        return "نامشخص"

def get_log_file_size():
    """سایز فایل لاگ را برمی‌گرداند"""
    log_path = "/var/log/g2ray-monitor.log"
    if os.path.exists(log_path):
        size = os.path.getsize(log_path)
        if size < 1024:
            return f"{size} B"
        elif size < 1024 * 1024:
            return f"{size // 1024} KB"
        else:
            return f"{size // (1024 * 1024)} MB"
    return "0 B"

# ─────────────────────────────────────────
# منوها
# ─────────────────────────────────────────

def show_main_menu(chat_id, edit_message_id=None):
    markup = InlineKeyboardMarkup(row_width=2)
    markup.add(
        InlineKeyboardButton("➕ افزودن مانیتور", callback_data="add_monitor"),
        InlineKeyboardButton("🗑 حذف مانیتور",    callback_data="remove_monitor"),
    )
    markup.add(
        InlineKeyboardButton("▶️ روشن کردن سرور", callback_data="power_on"),
        InlineKeyboardButton("🛑 خاموش کردن سرور", callback_data="power_off"),
    )
    markup.add(
        InlineKeyboardButton("📊 وضعیت سرویس‌ها", callback_data="status"),
        InlineKeyboardButton("📜 لاگ‌های زنده",   callback_data="logs"),
    )
    markup.add(
        InlineKeyboardButton("🔄 وضعیت GitHub",   callback_data="gh_status"),
        InlineKeyboardButton("🗂 لیست مانیتورها", callback_data="list_monitors"),
    )
    markup.add(
        InlineKeyboardButton("🧹 پاک‌سازی لاگ",   callback_data="clear_log"),
        InlineKeyboardButton("ℹ️ اطلاعات سیستم",  callback_data="system_info"),
    )

    services = get_services()
    count = len(services)
    status_line = f"🟢 {count} مانیتور فعال" if count > 0 else "⚫️ هیچ مانیتوری تنظیم نشده"

    text = (
        f"🤖 **پنل کنترل مرکزی g2ray** ({APP_NAME})\n"
        f"━━━━━━━━━━━━━━━━━━━━\n"
        f"{status_line}\n"
        f"🕐 آپتایم: {format_uptime()}\n"
        f"━━━━━━━━━━━━━━━━━━━━\n"
        f"یکی از گزینه‌ها را انتخاب کنید:"
    )

    if edit_message_id:
        try:
            bot.edit_message_text(text, chat_id, edit_message_id, reply_markup=markup, parse_mode="Markdown")
        except Exception:
            bot.send_message(chat_id, text, reply_markup=markup, parse_mode="Markdown")
    else:
        bot.send_message(chat_id, text, reply_markup=markup, parse_mode="Markdown")

def back_button(target="main"):
    markup = InlineKeyboardMarkup()
    markup.add(InlineKeyboardButton("🔙 بازگشت به منو", callback_data=f"back_{target}"))
    return markup

# ─────────────────────────────────────────
# هندلرهای دستورات
# ─────────────────────────────────────────

@bot.message_handler(commands=['start', 'menu'])
def send_welcome(message):
    if not check_auth(message.from_user.id):
        bot.send_message(message.chat.id, "⛔️ شما دسترسی ندارید.")
        return
    show_main_menu(message.chat.id)

@bot.message_handler(commands=['status'])
def cmd_status(message):
    if not check_auth(message.from_user.id): return
    handle_status(message.chat.id)

@bot.message_handler(commands=['logs'])
def cmd_logs(message):
    if not check_auth(message.from_user.id): return
    handle_logs(message.chat.id)

@bot.message_handler(commands=['help'])
def cmd_help(message):
    if not check_auth(message.from_user.id): return
    text = (
        "📋 **راهنمای دستورات:**\n\n"
        "/start یا /menu — نمایش منوی اصلی\n"
        "/status — وضعیت سرویس‌ها\n"
        "/logs — آخرین لاگ‌ها\n"
        "/help — این راهنما\n"
    )
    bot.send_message(message.chat.id, text, parse_mode="Markdown")

# ─────────────────────────────────────────
# توابع نمایش اطلاعات
# ─────────────────────────────────────────

def handle_status(chat_id):
    services = get_services()
    if not services:
        bot.send_message(chat_id, "⚠️ هیچ سرویسی تنظیم نشده است.", reply_markup=back_button())
        return

    lines = ["📊 **وضعیت سرویس‌های g2ray:**\n━━━━━━━━━━━━━━━━━━━━"]
    for s in services:
        cs_name = s.replace('g2ray-', '').replace('.service', '')
        st = get_service_status(cs_name)
        icon = "🟢" if st == "active" else "🔴"
        lines.append(f"{icon} `{cs_name}` — {st}")

    lines.append(f"\n🕐 آخرین بروزرسانی: {time.strftime('%H:%M:%S')}")
    bot.send_message(chat_id, "\n".join(lines), parse_mode="Markdown", reply_markup=back_button())

def handle_logs(chat_id, lines_count=20):
    cmd = f"tail -n {lines_count} /var/log/g2ray-monitor.log 2>/dev/null || echo 'لاگی یافت نشد'"
    res = subprocess.check_output(cmd, shell=True, text=True)
    markup = InlineKeyboardMarkup(row_width=3)
    markup.add(
        InlineKeyboardButton("10 خط",  callback_data="logs_10"),
        InlineKeyboardButton("20 خط",  callback_data="logs_20"),
        InlineKeyboardButton("50 خط",  callback_data="logs_50"),
    )
    markup.add(InlineKeyboardButton("🔙 بازگشت به منو", callback_data="back_main"))
    bot.send_message(
        chat_id,
        f"📜 **آخرین {lines_count} خط لاگ** (سایز: {get_log_file_size()}):\n\n```\n{res.strip()}\n```",
        parse_mode="Markdown",
        reply_markup=markup
    )

def handle_gh_status(chat_id):
    services = get_services()
    if not services:
        bot.send_message(chat_id, "⚠️ هیچ مانیتوری تنظیم نشده است.", reply_markup=back_button())
        return

    msg = bot.send_message(chat_id, "⏳ در حال دریافت وضعیت از GitHub...")
    lines = ["🔄 **وضعیت Codespace‌ها در GitHub:**\n━━━━━━━━━━━━━━━━━━━━"]
    for s in services:
        cs_name = s.replace('g2ray-', '').replace('.service', '')
        token = get_env_token(cs_name)
        if token:
            state, machine = get_codespace_state(token, cs_name)
            state_icons = {
                'Available': '🟢', 'Starting': '🟡', 'Shutdown': '🔴',
                'Stopped': '🔴', 'Awaiting': '🟡', 'Unknown': '⚫️',
            }
            icon = state_icons.get(state, '⚫️')
            machine_str = f" | {machine}" if machine else ""
            lines.append(f"{icon} `{cs_name}` — {state}{machine_str}")
        else:
            lines.append(f"⚫️ `{cs_name}` — توکن یافت نشد")

    lines.append(f"\n🕐 {time.strftime('%H:%M:%S')}")
    bot.edit_message_text("\n".join(lines), chat_id, msg.message_id,
                          parse_mode="Markdown", reply_markup=back_button())

def handle_list_monitors(chat_id):
    services = get_services()
    if not services:
        bot.send_message(chat_id, "⚠️ هیچ مانیتوری تنظیم نشده است.", reply_markup=back_button())
        return

    lines = ["🗂 **لیست مانیتورهای فعال:**\n━━━━━━━━━━━━━━━━━━━━"]
    for i, s in enumerate(services, 1):
        cs_name = s.replace('g2ray-', '').replace('.service', '')
        st = get_service_status(cs_name)
        icon = "🟢" if st == "active" else "🔴"
        # خواندن فاصله زمانی از env
        env_file = f"/etc/g2ray-monitor/{cs_name}.env"
        interval = "؟"
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    if line.startswith("CHECK_INTERVAL="):
                        interval = line.strip().split('=', 1)[1] + "s"
        lines.append(f"{i}. {icon} `{cs_name}`\n   ├ سرویس: {st}\n   └ فاصله: {interval}")

    bot.send_message(chat_id, "\n".join(lines), parse_mode="Markdown", reply_markup=back_button())

def handle_system_info(chat_id):
    try:
        uptime    = subprocess.check_output("uptime -p", shell=True, text=True).strip()
        mem       = subprocess.check_output("free -h | awk 'NR==2{print $3\"/\"$2}'", shell=True, text=True).strip()
        disk      = subprocess.check_output("df -h / | awk 'NR==2{print $3\"/\"$2\" (\"$5\")\"}'", shell=True, text=True).strip()
        cpu       = subprocess.check_output("top -bn1 | grep 'Cpu(s)' | awk '{print $2}'", shell=True, text=True).strip()
        services  = get_services()
        log_size  = get_log_file_size()
        text = (
            f"ℹ️ **اطلاعات سیستم:**\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"⏱ آپتایم: {uptime}\n"
            f"💾 رم: {mem}\n"
            f"💿 دیسک: {disk}\n"
            f"🖥 CPU: {cpu}%\n"
            f"📡 مانیتورهای فعال: {len(services)}\n"
            f"📄 سایز لاگ: {log_size}\n"
            f"🤖 پلتفرم: {APP_NAME}\n"
            f"━━━━━━━━━━━━━━━━━━━━\n"
            f"🕐 {time.strftime('%Y-%m-%d %H:%M:%S')}"
        )
    except Exception as e:
        text = f"❌ خطا در دریافت اطلاعات: {e}"
    bot.send_message(chat_id, text, parse_mode="Markdown", reply_markup=back_button())

# ─────────────────────────────────────────
# هندلر اصلی callback
# ─────────────────────────────────────────

@bot.message_handler(func=lambda message: True)
def handle_text_input(message):
    if not check_auth(message.from_user.id):
        return
    chat_id = message.chat.id
    text = message.text or ""

    # اگر دستور بود، state را پاک کن
    if text.startswith('/'):
        user_states.pop(chat_id, None)
        return

    state = user_states.get(chat_id, {})
    step = state.get('step')

    if step == 'waiting_token':
        process_token_state(message)
    elif step == 'waiting_interval':
        process_interval_state(message)

@bot.callback_query_handler(func=lambda call: True)
def callback_query(call):
    if not check_auth(call.from_user.id):
        bot.answer_callback_query(call.id, "⛔️ دسترسی ندارید")
        return

    chat_id = call.message.chat.id
    msg_id  = call.message.message_id
    data    = call.data

    # ── بازگشت ──
    if data.startswith("back_"):
        show_main_menu(chat_id, edit_message_id=msg_id)
        return

    # ── وضعیت سرویس‌ها ──
    if data == "status":
        bot.answer_callback_query(call.id)
        handle_status(chat_id)

    # ── لاگ‌ها ──
    elif data == "logs":
        bot.answer_callback_query(call.id)
        handle_logs(chat_id, 20)

    elif data.startswith("logs_"):
        count = int(data.split("_")[1])
        bot.answer_callback_query(call.id)
        handle_logs(chat_id, count)

    # ── وضعیت GitHub ──
    elif data == "gh_status":
        bot.answer_callback_query(call.id, "در حال دریافت...")
        handle_gh_status(chat_id)

    # ── لیست مانیتورها ──
    elif data == "list_monitors":
        bot.answer_callback_query(call.id)
        handle_list_monitors(chat_id)

    # ── اطلاعات سیستم ──
    elif data == "system_info":
        bot.answer_callback_query(call.id)
        handle_system_info(chat_id)

    # ── پاک‌سازی لاگ ──
    elif data == "clear_log":
        markup = InlineKeyboardMarkup()
        markup.add(
            InlineKeyboardButton("✅ بله، پاک شود", callback_data="confirm_clear_log"),
            InlineKeyboardButton("❌ خیر",          callback_data="back_main"),
        )
        bot.answer_callback_query(call.id)
        bot.send_message(chat_id, "⚠️ آیا مطمئنید که می‌خواهید فایل لاگ پاک شود؟", reply_markup=markup)

    elif data == "confirm_clear_log":
        subprocess.run("truncate -s 0 /var/log/g2ray-monitor.log 2>/dev/null || true", shell=True)
        bot.answer_callback_query(call.id, "✅ لاگ پاک شد")
        bot.send_message(chat_id, "🧹 فایل لاگ با موفقیت پاک شد.", reply_markup=back_button())

    # ── روشن/خاموش سرور ──
    elif data in ["power_on", "power_off"]:
        services = get_services()
        if not services:
            bot.answer_callback_query(call.id)
            bot.send_message(chat_id, "⚠️ هیچ سروری تنظیم نشده است.", reply_markup=back_button())
            return
        markup   = InlineKeyboardMarkup()
        is_on    = data == "power_on"
        prefix   = "startcs_" if is_on else "stopcs_"
        icon     = "▶️" if is_on else "🛑"
        action   = "روشن" if is_on else "خاموش"
        for s in services:
            cs_name = s.replace('g2ray-', '').replace('.service', '')
            st      = get_service_status(cs_name)
            st_icon = "🟢" if st == "active" else "🔴"
            markup.add(InlineKeyboardButton(f"{icon} {cs_name} {st_icon}", callback_data=f"{prefix}{cs_name}"))
        markup.add(InlineKeyboardButton("🔙 بازگشت", callback_data="back_main"))
        bot.answer_callback_query(call.id)
        bot.send_message(chat_id, f"❓ **کدام سرور {action} شود؟**", reply_markup=markup, parse_mode="Markdown")

    elif data.startswith("stopcs_"):
        cs_name = data.split("stopcs_", 1)[1]
        bot.answer_callback_query(call.id, "در حال متوقف کردن...")
        subprocess.run(f"systemctl stop g2ray-{cs_name}.service 2>/dev/null; pkill -9 -f 'g2ray-monitor.sh' 2>/dev/null || true", shell=True)
        token = get_env_token(cs_name)
        if token:
            cmd = (
                f'curl -s -o /dev/null -w "%{{http_code}}" '
                f'-X POST -H "Authorization: Bearer {token}" '
                f'https://api.github.com/user/codespaces/{cs_name}/stop'
            )
            code = subprocess.check_output(cmd, shell=True, text=True)
            if code in ("200", "202"):
                bot.send_message(chat_id,
                    f"🛑 مانیتورینگ متوقف شد و دستور خاموشی به GitHub ارسال گردید.\n"
                    f"سرور `{cs_name}` تا لحظاتی دیگر خاموش می‌شود.",
                    parse_mode="Markdown", reply_markup=back_button())
            else:
                bot.send_message(chat_id,
                    f"⚠️ سرویس متوقف شد ولی ارسال دستور به GitHub با خطا مواجه شد (کد: {code}).",
                    parse_mode="Markdown", reply_markup=back_button())
        else:
            bot.send_message(chat_id,
                f"🛑 سرویس مانیتورینگ `{cs_name}` متوقف شد.\n(توکن یافت نشد — دستور GitHub ارسال نشد)",
                parse_mode="Markdown", reply_markup=back_button())

    elif data.startswith("startcs_"):
        cs_name = data.split("startcs_", 1)[1]
        bot.answer_callback_query(call.id, "در حال روشن کردن...")
        subprocess.run(f"systemctl start g2ray-{cs_name}.service", shell=True)
        bot.send_message(chat_id,
            f"▶️ سیستم مانیتورینگ برای `{cs_name}` فعال شد.\nسرور به زودی روشن می‌شود.",
            parse_mode="Markdown", reply_markup=back_button())

    # ── افزودن مانیتور ──
    elif data == "add_monitor":
        bot.answer_callback_query(call.id)
        user_states[chat_id] = {'step': 'waiting_token'}
        bot.send_message(chat_id,
            "🔑 لطفاً **توکن GitHub** (GH_TOKEN) خود را ارسال کنید:\n\n"
            "_(برای لغو /menu را بفرستید)_",
            parse_mode="Markdown")

    # ── حذف مانیتور ──
    elif data == "remove_monitor":
        services = get_services()
        if not services:
            bot.answer_callback_query(call.id)
            bot.send_message(chat_id, "⚠️ هیچ مانیتوری برای حذف یافت نشد.", reply_markup=back_button())
            return
        markup = InlineKeyboardMarkup()
        for s in services:
            cs_name = s.replace('g2ray-', '').replace('.service', '')
            markup.add(InlineKeyboardButton(f"❌ {cs_name}", callback_data=f"del_confirm_{cs_name}"))
        markup.add(InlineKeyboardButton("🔙 بازگشت", callback_data="back_main"))
        bot.answer_callback_query(call.id)
        bot.send_message(chat_id, "🗑 **کدام مانیتور حذف شود؟**", reply_markup=markup, parse_mode="Markdown")

    # ── تأیید حذف (دو مرحله‌ای) ──
    elif data.startswith("del_confirm_"):
        cs_name = data.split("del_confirm_", 1)[1]
        markup  = InlineKeyboardMarkup()
        markup.add(
            InlineKeyboardButton(f"✅ بله، حذف شود", callback_data=f"del_{cs_name}"),
            InlineKeyboardButton("❌ خیر",           callback_data="back_main"),
        )
        bot.answer_callback_query(call.id)
        bot.send_message(chat_id,
            f"⚠️ آیا مطمئنید که مانیتور `{cs_name}` برای همیشه حذف شود؟",
            reply_markup=markup, parse_mode="Markdown")

    elif data.startswith("del_"):
        cs_name = data.split("del_", 1)[1]
        bot.answer_callback_query(call.id, "در حال حذف...")
        
        # --- بخش اصلاح شده: اضافه شدن دستور pkill برای نابودی پروسه در حال اجرا ---
        cmd = (
            f"systemctl stop g2ray-{cs_name}.service 2>/dev/null; "
            f"systemctl disable g2ray-{cs_name}.service 2>/dev/null; "
            f"pkill -9 -f {cs_name} 2>/dev/null; "
            f"rm -f /etc/systemd/system/g2ray-{cs_name}.service; "
            f"rm -f /etc/g2ray-monitor/{cs_name}.env; "
            f"systemctl daemon-reload"
        )
        subprocess.run(cmd, shell=True)
        bot.send_message(chat_id,
            f"✅ مانیتور `{cs_name}` با موفقیت حذف شد.",
            parse_mode="Markdown", reply_markup=back_button())

    # ── انتخاب Codespace ──
    elif data.startswith("cs_"):
        cs_name = data.split("cs_", 1)[1]
        if chat_id not in user_states:
            user_states[chat_id] = {}
        user_states[chat_id]['codespace'] = cs_name
        user_states[chat_id]['step'] = 'waiting_interval'
        bot.answer_callback_query(call.id)
        bot.send_message(chat_id,
            f"✅ سرور `{cs_name}` انتخاب شد.\n\n"
            f"⏱ فاصله زمانی بررسی (ثانیه) را وارد کنید:\n"
            f"پیشنهاد: 60 یا 120",
            parse_mode="Markdown")

# ─────────────────────────────────────────
# فرایند افزودن مانیتور (State Machine)
# ─────────────────────────────────────────

def process_token_state(message):
    chat_id = message.chat.id
    token   = message.text.strip()
    user_states[chat_id]['token'] = token
    user_states[chat_id]['step']  = 'waiting_codespace'
    wait_msg = bot.send_message(chat_id, "⏳ در حال اتصال به GitHub...")
    cmd = (
        f'curl -s --max-time 10 '
        f'-H "Authorization: Bearer {token}" '
        f'-H "Accept: application/vnd.github+json" '
        f'https://api.github.com/user/codespaces'
    )
    try:
        res  = subprocess.check_output(cmd, shell=True, text=True)
        data = json.loads(res)
        if 'codespaces' not in data or not data['codespaces']:
            bot.edit_message_text("❌ توکن نامعتبر است یا Codespace‌ای یافت نشد.", chat_id, wait_msg.message_id)
            user_states.pop(chat_id, None)
            return
        markup = InlineKeyboardMarkup()
        for cs in data['codespaces']:
            name   = cs['name']
            state  = cs.get('state', '?')
            icon   = "🟢" if state == "Available" else "🔴"
            markup.add(InlineKeyboardButton(f"{icon} {name} ({state})", callback_data=f"cs_{name}"))
        bot.edit_message_text(
            "🖥 لطفاً Codespace مورد نظر را انتخاب کنید:",
            chat_id, wait_msg.message_id, reply_markup=markup
        )
    except Exception as e:
        bot.edit_message_text(f"❌ خطا در اتصال: {e}", chat_id, wait_msg.message_id)
        user_states.pop(chat_id, None)

def process_interval_state(message):
    chat_id  = message.chat.id
    interval = message.text.strip()
    if not interval.isdigit() or int(interval) < 10:
        interval = "60"

    data    = user_states.get(chat_id, {})
    token   = data.get('token')
    cs_name = data.get('codespace')

    if not token or not cs_name:
        bot.send_message(chat_id, "❌ خطا: اطلاعات ناقص است. دوباره از /menu شروع کنید.")
        user_states.pop(chat_id, None)
        return

    _install_monitor(chat_id, token, cs_name, interval)

def _install_monitor(chat_id, token, cs_name, interval):
    os.makedirs('/etc/g2ray-monitor', exist_ok=True)
    env_file     = f"/etc/g2ray-monitor/{cs_name}.env"
    service_file = f"/etc/systemd/system/g2ray-{cs_name}.service"

    env_content = (
        f"GH_TOKEN={token}\n"
        f"CODESPACE_NAME={cs_name}\n"
        f"CHECK_INTERVAL={interval}\n"
        f"TG_BOT_TOKEN={TG_BOT_TOKEN}\n"
        f"TG_CHAT_ID={TG_CHAT_ID}\n"
        f"BALE_BOT_TOKEN={BALE_BOT_TOKEN}\n"
        f"BALE_CHAT_ID={BALE_CHAT_ID}\n"
    )
    with open(env_file, 'w') as f:
        f.write(env_content)
    os.chmod(env_file, 0o600)

    monitor_script = r"""#!/bin/bash
set -euo pipefail
GH_TOKEN="${GH_TOKEN:-}"
CODESPACE_NAME="${CODESPACE_NAME:-}"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
LOG_FILE="/var/log/g2ray-monitor.log"
MAX_LOG_SIZE=5242880  # 5MB

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${CODESPACE_NAME}] $*" | tee -a "$LOG_FILE"
    # چرخش لاگ اگر از ۵ مگابایت بیشتر شد
    if [[ -f "$LOG_FILE" && $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt $MAX_LOG_SIZE ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        touch "$LOG_FILE"
        log "=== Log rotated ==="
    fi
}

send_alert() {
    local message="$1"
    if [[ -n "${TG_BOT_TOKEN:-}" && "${TG_BOT_TOKEN}" != "YOUR_TG_TOKEN_HERE" ]]; then
        curl -s --max-time 10 -X POST \
            "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
            -d chat_id="${TG_CHAT_ID}" \
            -d text="$message" \
            -d parse_mode="HTML" > /dev/null || true
    fi
    if [[ -n "${BALE_BOT_TOKEN:-}" && "${BALE_BOT_TOKEN}" != "YOUR_BALE_TOKEN_HERE" ]]; then
        curl -s --max-time 10 -X POST \
            "https://tapi.bale.ai/bot${BALE_BOT_TOKEN}/sendMessage" \
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
    log "Codespace is down -- attempting restart..."
    send_alert "⚠️ <b>هشدار:</b> سرور <code>${CODESPACE_NAME}</code> خاموش شده! در حال راه‌اندازی مجدد..."
    local result
    result=$(curl -s --max-time 30 -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Authorization: Bearer $GH_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/user/codespaces/${CODESPACE_NAME}/start" || echo "failed")
    if [[ "$result" == "200" || "$result" == "202" ]]; then
        log "Start request sent successfully (HTTP $result)"
        send_alert "✅ <b>موفقیت:</b> دستور روشن شدن با موفقیت ارسال شد."
    else
        log "ERROR: Start request failed (HTTP $result)"
        send_alert "❌ <b>خطا:</b> راه‌اندازی مجدد با مشکل مواجه شد (کد: $result)."
    fi
}

consecutive_errors=0
log "=== g2ray-monitor started (interval: ${CHECK_INTERVAL}s) ==="

while true; do
    STATE=$(get_state)
    case "$STATE" in
        Available)
            log "State: $STATE - OK"
            consecutive_errors=0
            ;;
        Shutdown|Stopped)
            log "State: $STATE - Starting up"
            start_codespace
            consecutive_errors=0
            ;;
        Starting|"Awaiting"*)
            log "State: $STATE - Waiting..."
            ;;
        "")
            consecutive_errors=$((consecutive_errors + 1))
            log "ERROR: Could not get state (attempt $consecutive_errors)"
            if [[ $consecutive_errors -ge 5 ]]; then
                send_alert "⚠️ <b>هشدار:</b> ${consecutive_errors} بار متوالی نتوانستم وضعیت <code>${CODESPACE_NAME}</code> را بگیرم."
                consecutive_errors=0
            fi
            ;;
        *)
            log "Unknown state: $STATE"
            ;;
    esac
    sleep "$CHECK_INTERVAL"
done
"""
    with open('/usr/local/bin/g2ray-monitor.sh', 'w') as f:
        f.write(monitor_script)
    os.chmod('/usr/local/bin/g2ray-monitor.sh', 0o755)

    service_content = (
        f"[Unit]\n"
        f"Description=g2ray Monitor - {cs_name}\n"
        f"After=network-online.target\n"
        f"Wants=network-online.target\n\n"
        f"[Service]\n"
        f"Type=simple\n"
        f"User=root\n"
        f"EnvironmentFile={env_file}\n"
        f"ExecStart=/usr/local/bin/g2ray-monitor.sh\n"
        f"Restart=always\n"
        f"RestartSec=15\n"
        f"TimeoutStopSec=3\n"
        f"KillSignal=SIGKILL\n"
        f"SendSIGKILL=yes\n"
        f"StandardOutput=journal\n"
        f"StandardError=journal\n\n"
        f"[Install]\n"
        f"WantedBy=multi-user.target\n"
    )
    with open(service_file, 'w') as f:
        f.write(service_content)

    subprocess.run(
        f"systemctl daemon-reload; systemctl enable --now g2ray-{cs_name}.service",
        shell=True
    )
    bot.send_message(
        chat_id,
        f"🎉 مانیتورینگ برای `{cs_name}` با موفقیت راه‌اندازی شد!\n"
        f"⏱ فاصله بررسی: {interval} ثانیه\n\n"
        f"برای مشاهده وضعیت از منوی اصلی استفاده کنید.",
        parse_mode="Markdown",
        reply_markup=back_button()
    )
    user_states.pop(chat_id, None)



# ─────────────────────────────────────────
# اجرا
# ─────────────────────────────────────────
if __name__ == "__main__":
    print(f"[g2ray] Bot started on {APP_NAME}")
    bot.infinity_polling(timeout=10, long_polling_timeout=5)
