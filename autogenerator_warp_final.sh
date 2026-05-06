#!/bin/sh
# =============================================================================
# WARP + PBR для OpenWrt — фінальна версія з керуванням bypass-списком
# WARP + PBR for OpenWrt — final version with bypass list management
# -----------------------------------------------------------------------------
# Логіка / Logic:
#   - Весь LAN-трафік → WARP-тунель (wg0)
#     All LAN traffic → WARP tunnel (wg0)
#   - Домени з /etc/warp_bypass.conf → прямо на WAN (без тунелю)
#     Domains from /etc/warp_bypass.conf → directly to WAN (no tunnel)
#   - IPv6 вимкнено (wan6 + AAAA-фільтр) → трафік лише по IPv4 через WARP
#     IPv6 disabled (wan6 + AAAA filter) → traffic uses IPv4 only, through WARP
#   - Watchdog кожні 10 хв: 3-стадійне відновлення тунелю
#     Watchdog every 10 min: 3-stage tunnel recovery
#   - Ротація ключів кожні 5 днів о 04:00 (безкоштовний тариф CF)
#     Key rotation every 5 days at 04:00 (Cloudflare free tier)
# -----------------------------------------------------------------------------
# Постійні файли на роутері після налаштування:
# Files left on the router after setup:
#   /etc/warp_bypass.conf   — список bypass-доменів / bypass domain list
#   /root/warp_bypass.sh    — CLI для управління списком / bypass list CLI
#   /root/warp_autoreg.sh   — реєстрація/ротація ключів / key registration & rotation
#   /root/warp_watchdog.sh  — watchdog тунелю / tunnel watchdog (run by cron)
# =============================================================================
set -e

log() { echo ">>> $*"; }
die() { echo "ПОМИЛКА / ERROR: $*" >&2; exit 1; }

# --- Перевірка залежностей / Dependency check ---
for bin in wg jq curl uci ip; do
    command -v "$bin" >/dev/null 2>&1 \
        || die "'$bin' не знайдено. Встановіть пакет і повторіть. / not found. Install the package and retry."
done

# =============================================================================
# 1. АВТОВИЗНАЧЕННЯ МЕРЕЖІ / AUTO-DETECT LAN NETWORK
# =============================================================================
LAN_IP=$(uci -q get network.lan.ipaddr || echo "192.168.1.1")
LAN_SUBNET="$(echo "$LAN_IP" | cut -d'.' -f1-3).0/24"
log "LAN: $LAN_SUBNET"

# =============================================================================
# 2. WIREGUARD ІНТЕРФЕЙС wg0 / WIREGUARD INTERFACE wg0
# Ключі порожні — їх заповнить warp_autoreg.sh при першому запуску
# Keys are empty — warp_autoreg.sh will fill them on first run
# =============================================================================
uci -q delete network.wg0      || true
uci -q delete network.wg0_peer || true

uci set network.wg0="interface"
uci set network.wg0.proto="wireguard"
uci set network.wg0.mtu='1280'         # WARP вимагає ≤ 1280 / WARP requires ≤ 1280

uci set network.wg0_peer="wireguard_wg0"
uci set network.wg0_peer.endpoint_host="162.159.192.1"
uci set network.wg0_peer.endpoint_port="2408"
uci set network.wg0_peer.route_allowed_ips='0'  # маршрутами керує PBR / routes managed by PBR
uci add_list network.wg0_peer.allowed_ips="0.0.0.0/0"
uci set network.wg0_peer.persistent_keepalive='25'

uci commit network
log "WireGuard налаштовано / configured"

# =============================================================================
# 3. FIREWALL
# Без зони 'vpn' firewall мовчки дропає весь трафік через wg0
# Without the 'vpn' zone firewall silently drops all traffic through wg0
# =============================================================================

# Видаляємо стару зону vpn щоб не дублювати
# Remove existing vpn zone to avoid duplicates
old_vpn=$(uci show firewall 2>/dev/null \
    | grep "firewall\.@zone\[.*\]\.name='vpn'" \
    | sed "s/firewall\.@zone\[\([0-9]*\)\].*/\1/" \
    | head -n1)
[ -n "$old_vpn" ] && { uci delete "firewall.@zone[$old_vpn]" || true; }

# Видаляємо старий forwarding lan→vpn щоб не дублювати
# Remove existing lan→vpn forwarding rule to avoid duplicates
for i in $(uci show firewall 2>/dev/null \
    | grep "firewall\.@forwarding\[" \
    | sed "s/firewall\.@forwarding\[\([0-9]*\)\].*/\1/" \
    | sort -rn); do
    src=$(uci -q get "firewall.@forwarding[$i].src"  || true)
    dst=$(uci -q get "firewall.@forwarding[$i].dest" || true)
    [ "$src" = "lan" ] && [ "$dst" = "vpn" ] \
        && { uci delete "firewall.@forwarding[$i]" || true; }
done

# Нова зона vpn / New vpn zone
uci add firewall zone
uci set firewall.@zone[-1].name='vpn'
uci set firewall.@zone[-1].network='wg0'
uci set firewall.@zone[-1].input='REJECT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='REJECT'
uci set firewall.@zone[-1].masq='1'     # NAT для зворотних пакетів / NAT for return packets
uci set firewall.@zone[-1].mtu_fix='1'  # MSS clamp під MTU тунелю / MSS clamp for tunnel MTU

# Дозволяємо LAN → VPN / Allow LAN → VPN forwarding
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='vpn'

# Глобальний MSS clamp — захист від чорних дір MTU
# Global MSS clamp — protection against MTU black holes
uci set firewall.@defaults[0].mss_clamping='1'
uci commit firewall
log "Firewall: зона vpn + LAN→VPN forwarding налаштовано / vpn zone + LAN→VPN forwarding configured"

# =============================================================================
# 4. ВИМКНЕННЯ IPv6 / DISABLE IPv6
# Якщо провайдер роздає IPv6, клієнти оминають PBR і йдуть через ISP напряму.
# If the ISP provides IPv6, clients bypass PBR and go directly through the ISP.
# filter_aaaa=1 — dnsmasq не повертає AAAA → клієнти не знають IPv6-адрес
# filter_aaaa=1 — dnsmasq drops AAAA replies → clients have no IPv6 addresses
# → автоматично використовують IPv4 → весь трафік через WARP
# → automatically fall back to IPv4 → all traffic goes through WARP
# =============================================================================
uci -q delete network.wan6 || true   # прибираємо DHCPv6/SLAAC від провайдера / remove ISP DHCPv6
uci set network.lan.ipv6='0'         # вимикаємо IPv6 на LAN / disable IPv6 on LAN
uci set network.globals.ula_prefix='' # прибираємо внутрішній ULA-префікс / remove internal ULA prefix
uci commit network

uci set dhcp.@dnsmasq[0].filter_aaaa='1'       # фільтр AAAA-записів / filter AAAA DNS records
uci set dhcp.@dnsmasq[0].rebind_protection='0'  # потрібно для dnsmasq nftset / required for dnsmasq nftset
uci commit dhcp
log "IPv6 вимкнено / disabled"

# =============================================================================
# 5. BYPASS КОНФІГ-ФАЙЛ / BYPASS CONFIG FILE (/etc/warp_bypass.conf)
# Домени що йдуть напряму на WAN (без тунелю).
# Domains routed directly to WAN (bypassing the tunnel).
# Формат: один домен на рядок, # — коментар, порожні рядки ігноруються.
# Format: one domain per line, # — comment, empty lines are ignored.
# Керування / Management: warp_bypass.sh add|del|list|apply
# =============================================================================

# Створюємо тільки якщо файл ще не існує — щоб не затерти користувацькі зміни
# Create only if the file does not exist — to preserve user edits
if [ ! -f /etc/warp_bypass.conf ]; then
cat << 'CONF_EOF' > /etc/warp_bypass.conf
# =============================================================================
# WARP Bypass список / WARP Bypass list
# Домени що йдуть напряму на WAN (без тунелю)
# Domains routed directly to WAN (bypassing the tunnel)
# =============================================================================
# Управління / Management:
#   warp_bypass.sh list              — показати список / show list
#   warp_bypass.sh add example.com  — додати домен / add domain
#   warp_bypass.sh del example.com  — видалити домен / remove domain
#   warp_bypass.sh apply            — застосувати зміни / apply changes (no reboot)
# =============================================================================

# --- ottplayer ---
# Базовий домен + відомі піддомени
# Base domain + known subdomains
# widget.* — Smart TV SDK | api.* — provider API | m.* — mobile
ottplayer.tv
widget.ottplayer.tv
api.ottplayer.tv
m.ottplayer.tv
ottplayer.es
widget.ottplayer.es
api.ottplayer.es

# --- YouTube ---
# googlevideo.com — основна доставка відеопотоку / main video stream delivery (required to avoid buffering)
# ytimg.com       — thumbnails та статика / thumbnails and static assets
# yt3.ggpht.com   — аватарки каналів / channel avatars
# youtubei.*      — внутрішній API / internal autoplay API
youtube.com
googlevideo.com
ytimg.com
yt3.ggpht.com
youtu.be
youtube-nocookie.com
youtubei.googleapis.com
yt.be
CONF_EOF
log "Bypass конфіг створено / config created: /etc/warp_bypass.conf"
else
log "Bypass конфіг вже існує, не перезаписуємо / config already exists, skipping: /etc/warp_bypass.conf"
fi

# =============================================================================
# 6. CLI УПРАВЛІННЯ BYPASS-СПИСКОМ / BYPASS LIST CLI (/root/warp_bypass.sh)
# Залишається на роутері постійно / Persists on the router permanently
# =============================================================================
cat << 'BYPASS_EOF' > /root/warp_bypass.sh
#!/bin/sh
# =============================================================================
# warp_bypass.sh — керування списком bypass-доменів для WARP
#                  bypass domain list manager for WARP
# Використання / Usage:
#   warp_bypass.sh list              — показати список / show list
#   warp_bypass.sh add <domain>      — додати домен / add domain
#   warp_bypass.sh del <domain>      — видалити домен / remove domain
#   warp_bypass.sh apply             — застосувати зміни до PBR / apply changes to PBR (no reboot)
# =============================================================================
CONF="/etc/warp_bypass.conf"

# Зчитуємо активні домени (без коментарів і порожніх рядків)
# Read active domains (stripping comments and blank lines)
active_domains() {
    grep -v '^[[:space:]]*#' "$CONF" 2>/dev/null \
        | grep -v '^[[:space:]]*$' \
        | sed 's/[[:space:]]*#.*//' \
        | tr -d ' \t'
}

cmd_list() {
    echo "============================================"
    echo " Bypass список / Bypass list (WAN, no WARP)"
    echo "============================================"
    section=""
    while IFS= read -r line; do
        # Заголовки секцій виду: # --- назва --- / Section headers: # --- name ---
        if echo "$line" | grep -qE '^# ---'; then
            section=$(echo "$line" | sed 's/# --- //;s/ ---//')
            echo ""
            echo "[ $section ]"
        # Коментарі-пояснення — пропускаємо / Inline comments — skip
        elif echo "$line" | grep -q '^#'; then
            :
        # Порожні рядки — пропускаємо / Empty lines — skip
        elif [ -z "$(echo "$line" | tr -d ' \t')" ]; then
            :
        else
            domain=$(echo "$line" | sed 's/[[:space:]]*#.*//' | tr -d ' \t')
            [ -n "$domain" ] && echo "  $domain"
        fi
    done < "$CONF"
    echo ""
    count=$(active_domains | grep -c . || true)
    echo "Всього / Total: $count"
    echo "============================================"
}

cmd_add() {
    domain="$1"
    [ -z "$domain" ] && { echo "Вкажіть домен / Provide a domain: warp_bypass.sh add <domain>"; exit 1; }

    # Базова перевірка формату / Basic format validation
    echo "$domain" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?$' \
        || { echo "Невірний формат / Invalid domain format: $domain"; exit 1; }

    if active_domains | grep -qxF "$domain"; then
        echo "Домен вже є в списку / Domain already in list: '$domain'"
        exit 0
    fi

    echo "$domain" >> "$CONF"
    echo "Додано / Added: $domain"
    echo "Запустіть / Run 'warp_bypass.sh apply' щоб застосувати / to apply changes."
}

cmd_del() {
    domain="$1"
    [ -z "$domain" ] && { echo "Вкажіть домен / Provide a domain: warp_bypass.sh del <domain>"; exit 1; }

    if ! active_domains | grep -qxF "$domain"; then
        echo "Домен не знайдено / Domain not found: '$domain'"
        exit 1
    fi

    tmp=$(mktemp)
    # Видаляємо рядок з точним збігом / Remove line with exact match
    grep -vE "^[[:space:]]*${domain}([[:space:]]|$)" "$CONF" > "$tmp"
    mv "$tmp" "$CONF"
    echo "Видалено / Removed: $domain"
    echo "Запустіть / Run 'warp_bypass.sh apply' щоб застосувати / to apply changes."
}

cmd_apply() {
    # Знаходимо індекс правила Bypass-Tunnel в PBR
    # Find the Bypass-Tunnel policy index in PBR
    idx=$(uci show pbr 2>/dev/null \
        | grep "pbr\.@policy\[.*\]\.name='Bypass-Tunnel'" \
        | sed "s/pbr\.@policy\[\([0-9]*\)\].*/\1/" \
        | head -n1)

    if [ -z "$idx" ]; then
        echo "ПОМИЛКА / ERROR: правило 'Bypass-Tunnel' не знайдено в PBR / not found in PBR."
        echo "Запустіть основний скрипт налаштування / Run the main setup script first."
        exit 1
    fi

    # Очищуємо поточний dest_addr і заповнюємо з файлу
    # Clear current dest_addr list and repopulate from config file
    uci -q delete "pbr.@policy[$idx].dest_addr" || true

    count=0
    while IFS= read -r domain; do
        [ -z "$domain" ] && continue
        uci add_list "pbr.@policy[$idx].dest_addr=$domain"
        count=$((count + 1))
    done << DOMAINS
$(active_domains)
DOMAINS

    uci commit pbr
    /etc/init.d/pbr restart

    echo "Застосовано / Applied: $count domains → WAN (bypass WARP)"
}

cmd_help() {
    echo "Використання / Usage: warp_bypass.sh <команда/command> [аргумент/argument]"
    echo ""
    echo "Команди / Commands:"
    echo "  list              — показати список / show bypass list"
    echo "  add <domain>      — додати домен / add domain"
    echo "  del <domain>      — видалити домен / remove domain"
    echo "  apply             — застосувати зміни / apply changes to PBR (no reboot)"
    echo ""
    echo "Приклади / Examples:"
    echo "  warp_bypass.sh add netflix.com"
    echo "  warp_bypass.sh del youtube.com"
    echo "  warp_bypass.sh list"
    echo "  warp_bypass.sh apply"
    echo ""
    echo "Конфіг / Config: /etc/warp_bypass.conf"
}

case "$1" in
    list)           cmd_list ;;
    add)            cmd_add  "$2" ;;
    del)            cmd_del  "$2" ;;
    apply)          cmd_apply ;;
    help|--help|-h) cmd_help ;;
    *)              cmd_help; exit 1 ;;
esac
BYPASS_EOF

chmod +x /root/warp_bypass.sh
log "CLI менеджер bypass створено / bypass CLI created: /root/warp_bypass.sh"

# =============================================================================
# 7. PBR — Policy-Based Routing
# Правило Bypass-Tunnel заповнюється з /etc/warp_bypass.conf
# Bypass-Tunnel rule is populated from /etc/warp_bypass.conf
# =============================================================================
while uci -q delete pbr.@policy[0] 2>/dev/null; do :; done

uci set pbr.config=pbr
uci set pbr.config.enabled='1'
uci set pbr.config.ipv6_enabled='0'
uci set pbr.config.resolver_set='dnsmasq.nftset'

# --- ПРАВИЛО 1 / RULE 1: Bypass → WAN ---
# Читаємо домени з конфіг-файлу / Read domains from config file
uci add pbr policy
uci set pbr.@policy[-1].name='Bypass-Tunnel'
uci set pbr.@policy[-1].interface='wan'

count=0
while IFS= read -r line; do
    domain=$(echo "$line" | sed 's/[[:space:]]*#.*//' | tr -d ' \t')
    [ -z "$domain" ] && continue
    uci add_list pbr.@policy[-1].dest_addr="$domain"
    count=$((count + 1))
done < /etc/warp_bypass.conf
log "PBR Bypass-Tunnel: $count доменів завантажено / domains loaded from config"

# --- ПРАВИЛО 2 / RULE 2: Весь інший LAN-трафік → WARP / All other LAN traffic → WARP ---
uci add pbr policy
uci set pbr.@policy[-1].name='All-via-WARP'
uci set pbr.@policy[-1].src_addr="$LAN_SUBNET"
uci set pbr.@policy[-1].interface='wg0'

uci commit pbr
log "PBR налаштовано / configured"

# =============================================================================
# 8. СКРИПТ РЕЄСТРАЦІЇ КЛЮЧІВ / KEY REGISTRATION SCRIPT (/root/warp_autoreg.sh)
# Реєструє новий акаунт у Cloudflare WARP API та застосовує ключі
# Registers a new account via Cloudflare WARP API and applies the keys
# Lock-файл (mkdir — атомарна операція в busybox) запобігає race condition
# Lock file (mkdir — atomic in busybox) prevents race condition with watchdog/cron
# =============================================================================
cat << 'AUTOREG_EOF' > /root/warp_autoreg.sh
#!/bin/sh
LOCK="/var/run/warp_autoreg.lock"
TAG="WARP-reg"

# Атомарний lock — запобігає одночасному запуску з watchdog або cron
# Atomic lock — prevents concurrent execution with watchdog or cron
if ! mkdir "$LOCK" 2>/dev/null; then
    logger -t "$TAG" "Вже виконується / Already running — пропускаємо / skipping."
    exit 0
fi
trap 'rm -rf "$LOCK"' EXIT INT TERM

for bin in wg jq curl uci ip; do
    command -v "$bin" >/dev/null 2>&1 \
        || { logger -t "$TAG" "Немає / Missing: '$bin', виходимо / exiting."; exit 1; }
done

PRIV_KEY=$(wg genkey)
PUB_KEY=$(echo "$PRIV_KEY" | wg pubkey)
INSTALL_ID=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 22)
TIMESTAMP=$(date -u +%FT%T.000Z)

DATA=$(printf \
    '{"key":"%s","install_id":"%s","fcm_token":"%s:APA91b","tos":"%s","model":"OpenWrt","locale":"en_US"}' \
    "$PUB_KEY" "$INSTALL_ID" "$INSTALL_ID" "$TIMESTAMP")

logger -t "$TAG" "Реєстрація нового акаунту WARP / Registering new WARP account..."

RESPONSE=$(curl -s --max-time 20 \
    -X POST "https://api.cloudflareclient.com/v0a884/reg" \
    -H "Content-Type: application/json" \
    -d "$DATA") || true

if [ -z "$RESPONSE" ]; then
    logger -t "$TAG" "curl повернув порожню відповідь / returned empty response (no internet?)."
    exit 1
fi

IPV4=$(echo "$RESPONSE"     | jq -r '.config.interface.addresses.v4 // empty')
PEER_PUB=$(echo "$RESPONSE" | jq -r '.config.peers[0].public_key    // empty')

if [ -z "$IPV4" ]     || [ "$IPV4"     = "null" ] \
|| [ -z "$PEER_PUB" ] || [ "$PEER_PUB" = "null" ]; then
    snippet=$(echo "$RESPONSE" | head -c 300)
    logger -t "$TAG" "Помилка реєстрації CF / CF registration error: $snippet"
    exit 1
fi

# Гасимо інтерфейс перед зміною ключів / Bring down interface before changing keys
ifdown wg0 2>/dev/null || true
sleep 2

uci set  network.wg0.private_key="${PRIV_KEY}"
uci -q delete network.wg0.addresses || true
uci add_list network.wg0.addresses="${IPV4}/32"
uci set  network.wg0_peer.public_key="${PEER_PUB}"
uci commit network

ifup wg0

# Чекаємо підйому інтерфейсу (до 20 сек) / Wait for interface to come up (up to 20 sec)
i=0
while [ $i -lt 20 ]; do
    ip link show wg0 2>/dev/null | grep -q "UP" && break
    sleep 1
    i=$((i + 1))
done

if ! ip link show wg0 2>/dev/null | grep -q "UP"; then
    logger -t "$TAG" "ПОПЕРЕДЖЕННЯ / WARNING: wg0 не піднявся / did not come up in ${i}s."
else
    logger -t "$TAG" "OK. IP: ${IPV4} | peer: ${PEER_PUB}"
fi

/etc/init.d/pbr restart
AUTOREG_EOF

chmod +x /root/warp_autoreg.sh

# =============================================================================
# 9. WATCHDOG (/root/warp_watchdog.sh) — 3-стадійне відновлення / 3-stage recovery
# -----------------------------------------------------------------------------
# Стадія 0 / Stage 0: ping через wg0
#   OK → виходимо / exit. Тунель живий / Tunnel is alive.
# Стадія 1 / Stage 1: ping без прив'язки до iface / ping without interface binding
#   Немає інтернету / No internet → чекаємо провайдера / wait for ISP. Нічого не чіпаємо / do nothing.
# Стадія 2 / Stage 2: м'який рестарт / soft restart (ifdown/ifup)
#   OK → виходимо / exit. Тунель відновлено / Tunnel recovered.
# Стадія 3 / Stage 3: warp_autoreg.sh — повна регенерація ключів / full key regeneration
# =============================================================================
cat << 'WATCHDOG_EOF' > /root/warp_watchdog.sh
#!/bin/sh
TAG="WARP-watch"
LOCK="/var/run/warp_autoreg.lock"
HOST="1.1.1.1"
CNT=3   # кількість ping-пакетів / number of ping packets
TMO=3   # таймаут кожного ping (сек) / timeout per ping (sec)

tunnel_ok()   { ping -c "$CNT" -W "$TMO" -I wg0 "$HOST" >/dev/null 2>&1; }
internet_ok() { ping -c "$CNT" -W "$TMO"        "$HOST" >/dev/null 2>&1; }

# Стадія 0 / Stage 0 — тунель живий? / Is the tunnel alive?
if tunnel_ok; then
    logger -t "$TAG" "wg0 OK."
    exit 0
fi

logger -t "$TAG" "wg0 не відповідає / not responding. Діагностика / Diagnosing..."

# Стадія 1 / Stage 1 — інтернет взагалі є? / Is there internet at all?
if ! internet_ok; then
    logger -t "$TAG" "Інтернет недоступний / Internet unavailable — чекаємо провайдера / waiting for ISP."
    exit 0
fi

# Не конкуруємо з autoreg якщо він вже виконується
# Skip if autoreg is already running (e.g. scheduled key rotation at 04:00)
if [ -d "$LOCK" ]; then
    logger -t "$TAG" "autoreg вже виконується / already running — пропускаємо / skipping."
    exit 0
fi

# Стадія 2 / Stage 2 — м'який рестарт / soft restart
logger -t "$TAG" "Інтернет є, тунель впав / Internet OK, tunnel down. М'який рестарт / Soft restart wg0..."
ifdown wg0 2>/dev/null || true
sleep 3
ifup wg0
sleep 15   # чекаємо WireGuard handshake / wait for WireGuard handshake

if tunnel_ok; then
    logger -t "$TAG" "Тунель відновлено м'яким рестартом / Tunnel recovered via soft restart."
    exit 0
fi

# Стадія 3 / Stage 3 — регенерація ключів / key regeneration
logger -t "$TAG" "М'який рестарт не допоміг / Soft restart failed. Регенерація ключів / Regenerating WARP keys..."
/root/warp_autoreg.sh
WATCHDOG_EOF

chmod +x /root/warp_watchdog.sh
log "Скрипти створено / Scripts created: warp_autoreg.sh, warp_watchdog.sh"

# =============================================================================
# 10. CRON
# =============================================================================
touch /etc/crontabs/root   # створюємо якщо не існує / create if missing

# Прибираємо старі записи / Remove old entries
sed -i '/warp_watchdog\.sh/d' /etc/crontabs/root 2>/dev/null || true
sed -i '/warp_autoreg\.sh/d'  /etc/crontabs/root 2>/dev/null || true

# Watchdog кожні 10 хвилин / every 10 minutes
echo "*/10 * * * * /root/warp_watchdog.sh" >> /etc/crontabs/root
# Ротація ключів кожні 5 днів о 04:00 / Key rotation every 5 days at 04:00
echo "0 4 */5 * * /root/warp_autoreg.sh"   >> /etc/crontabs/root
log "Cron: watchdog кожні 10 хв / every 10 min | ротація / rotation кожні 5 днів / every 5 days at 04:00"

# =============================================================================
# 11. ЗАПУСК / START
# =============================================================================
log "Перезапуск сервісів / Restarting services..."
/etc/init.d/cron     restart
/etc/init.d/firewall restart
/etc/init.d/dnsmasq  restart

log "Перша реєстрація WARP / First WARP registration (10-20 сек / sec)..."
/root/warp_autoreg.sh

echo ""
echo "======================================================="
echo " Готово / Done."
echo "-------------------------------------------------------"
echo " Тунель / Tunnel : wg0 (Cloudflare WARP, MTU 1280)"
echo " IPv6            : вимкнено / disabled"
echo " Bypass          : /etc/warp_bypass.conf"
echo " Watchdog        : кожні 10 хв / every 10 min, 3-stage recovery"
echo " Ротація / Rotation : кожні 5 днів о / every 5 days at 04:00"
echo "-------------------------------------------------------"
echo " Статус тунелю / Tunnel status : wg show wg0"
echo " Логи / Logs                   : logread | grep WARP"
echo " Bypass-список / Bypass list   : warp_bypass.sh list"
echo " Додати / Add domain           : warp_bypass.sh add <domain>"
echo " Видалити / Remove domain      : warp_bypass.sh del <domain>"
echo " Застосувати / Apply changes   : warp_bypass.sh apply"
echo "======================================================="
