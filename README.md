
# 🚀 EDUP EP-RT2983 Custom OpenWrt Release (Mesh, VPN & Smart Wi-Fi Edition) Based on stable sources OpenWrt 25.12.2

[🇺🇸 English](#english) | [🇺🇦 Українська](#українська)

---
<p align="center">
  <a href="https://www.paypal.com/paypalme/kostyamat">
    <img src="https://thumbs.dreamstime.com/b/cute-kawaii-coffee-mug-character-smiling-steam-isolated-white-adorable-cartoon-happy-face-decorative-lace-pattern-401912575.jpg" alt="Buy me a coffee" width="200"/>
    <br>
    <strong>If you found my work helpful, buy me a coffee! It keeps me motivated ☕</strong>
  </a>
</p>

<a id="english"></a>
## 🇺🇸 English

Custom OpenWrt firmware build for the **EDUP EP-RT2983** router, designed to work perfectly out of the box with advanced Wi-Fi features, Mesh, and Anti-DPI VPN protocols enabled by default. 

Compiled using the official OpenWrt Image Builder with injected `uci-defaults` scripts for automated setup on the very first boot. This release replaces standard restricted drivers with full `wpad-mesh-openssl` and integrates core VPN/PBR modules.

### ⚠️ CRITICAL INSTALLATION INSTRUCTIONS ⚠️
*   **Flash Over Chinese Snapshot:** You must flash this image forcibly over the original factory/Chinese snapshot build.
*   **DO NOT Keep Settings:** When flashing via LuCI, you **MUST UNCHECK** the "Keep settings" box.
*   **DO NOT Restore Backups:** Never attempt to restore configuration backups from the Chinese build on this firmware version. Doing so will **brick the device**! Start fresh.

### ✨ Key Features & Default Settings

#### 📡 Smart Wi-Fi & Mesh
*   **Default IP Address:** `192.168.2.1`
*   **Smart Wi-Fi Enabled out of the box:**
    *   **Single SSID (Unified 2.4GHz & 5GHz):** `EDUP_XXXX` *(where XXXX are the last 4 characters of the MAC address)*
    *   **Password:** `12345678`
*   **Mesh Restored:** A hidden 802.11s backhaul interface (`EDUP_MESH_BACKHAUL`) is pre-configured on the 5GHz band. Connecting multiple routers will automatically build a mesh network.
*   **WPS Restored:** Full WPS (Wi-Fi Protected Setup) support is enabled and functioning properly.
*   **Band Steering & Fast Roaming:** `usteer` demon and 802.11r/k/v standards are enabled by default. Your devices will seamlessly switch between access points and frequency bands.

#### 🛡️ VPN & Smart Routing (Anti-DPI)
*   **AmneziaWG (AWG):** Built-in support for the modern WireGuard fork with Deep Packet Inspection (DPI) protection to bypass strict ISP censorship.
*   **Advanced WARP + PBR Script:** The firmware includes a built-in, automated Smart Routing script. It routes all LAN traffic through a Cloudflare WARP tunnel while keeping a customizable "bypass list" of domains (like streaming services) that go directly through your ISP. 
    *   *Note: Use the built-in `warp_bypass.sh` CLI tool to easily add or remove domains from the bypass list (`/etc/warp_bypass.conf`). It features automatic key rotation and a 3-stage tunnel watchdog.*
*   **System Tools:** `jq`, `curl`, and `ca-bundle` are included out of the box for advanced VPN automation and API interaction.

#### ⚙️ System Defaults
*   **Web Interface (LuCI):** Pre-installed with HTTPS (`luci-ssl`) and `luci-app-usteer` for visual band steering management.
*   **DNS:** Pre-configured WAN DNS to `1.1.1.1` and `8.8.8.8`.
*   **SSH/SFTP:** Root login with password authentication is enabled by default.

---

<a id="українська"></a>
## 🇺🇦 Українська

Кастомна збірка прошивки OpenWrt для роутера **EDUP EP-RT2983**, створена для повноцінної роботи "з коробки" з активованими технологіями розумного Wi-Fi, Mesh та вбудованими Anti-DPI VPN-протоколами.

Зібрана за допомогою офіційного OpenWrt Image Builder з інтеграцією скриптів `uci-defaults` для автоматичного застосування налаштувань під час першого завантаження. Стандартні урізані драйвери замінено на повноцінний `wpad-mesh-openssl`, а також інтегровано ключові VPN/PBR-модулі.

### ⚠️ КРИТИЧНІ ІНСТРУКЦІЇ ЗІ ВСТАНОВЛЕННЯ ⚠️
*   **Прошивка поверх Snapshot:** Цей образ потрібно прошивати примусово (forcibly) поверх заводського "китайського" снапшоту.
*   **БЕЗ збереження налаштувань:** Під час оновлення через веб-інтерфейс **ОБОВ'ЯЗКОВО ЗНІМІТЬ ГАЛОЧКУ "Keep settings"**.
*   **НІЯКИХ бекапів:** Категорично заборонено відновлювати налаштування (backup) від китайської збірки на цю версію прошивки. Це гарантовано **перетворить роутер на "цеглину" (труп)**! Налаштовуйте з нуля.

### ✨ Головні особливості та налаштування

#### 📡 Розумний Wi-Fi та Mesh
*   **IP-адреса за замовчуванням:** `192.168.2.1`
*   **Розумний Wi-Fi увімкнено одразу:**
    *   **Єдина мережа (Single SSID для 2.4GHz та 5GHz):** `EDUP_XXXX` *(де XXXX — останні 4 символи MAC-адреси)*
    *   **Пароль:** `12345678`
*   **Відновлено Mesh:** Прихований інтерфейс 802.11s (`EDUP_MESH_BACKHAUL`) вже налаштований на діапазоні 5GHz. Кілька таких роутерів автоматично об'єднаються в єдину безшовну Mesh-мережу.
*   **Відновлено WPS:** Повноцінна підтримка WPS (Wi-Fi Protected Setup) активована і працює коректно.
*   **Band Steering та Безшовний роумінг:** Демон `usteer` та стандарти 802.11r/k/v активовані. Ваші пристрої будуть миттєво перемикатися між діапазонами та точками доступу без розривів.

#### 🛡️ VPN та Розумна Маршрутизація (Anti-DPI)
*   **AmneziaWG (AWG):** Вбудована підтримка сучасного форку WireGuard із захистом від глибокого аналізу трафіку (DPI) для обходу жорстких блокувань інтернет-провайдерів.
*   **Просунутий скрипт WARP + PBR:** У прошивку інтегровано автоматизований скрипт розумної маршрутизації. Він автоматично загортає весь локальний трафік у тунель Cloudflare WARP, але дозволяє пускати обрані домени (наприклад, стрімінгові сервіси) напряму через вашого провайдера.
    *   *Примітка: Використовуйте вбудовану CLI-утиліту `warp_bypass.sh` для швидкого додавання або видалення доменів зі списку виключень (`/etc/warp_bypass.conf`). Скрипт має 3-стадійний watchdog тунелю та автоматичну ротацію ключів.*
*   **Системні утиліти:** `jq`, `curl` та `ca-bundle` додані для зручної автоматизації VPN та роботи з API.

#### ⚙️ Системні налаштування
*   **Веб-інтерфейс (LuCI):** Встановлено із підтримкою HTTPS (`luci-ssl`) та модулем `luci-app-usteer` для керування клієнтами Wi-Fi.
*   **DNS:** Налаштовано WAN DNS на `1.1.1.1` та `8.8.8.8`.
*   **SSH/SFTP:** Дозволено вхід для користувача root за паролем.
