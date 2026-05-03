# 🚀 EDUP EP-RT2983 Custom OpenWrt Release

[🇺🇸 English](#english) | [🇺🇦 Українська](#українська)

---

<a id="english"></a>
## 🇺🇸 English

Custom OpenWrt firmware build for the **EDUP EP-RT2983** router, designed to work perfectly out of the box without the need for initial console configuration. 

Compiled using the official OpenWrt Image Builder with injected `uci-defaults` scripts for automated setup on the very first boot.

### ✨ Key Features & Default Settings
*   **Default IP Address:** `192.168.2.1`
*   **Wi-Fi Enabled out of the box:**
    *   **SSID (2.4GHz):** `EDUP_2.4G_XXXX` *(where XXXX are the last 4 characters of the MAC address)*
    *   **SSID (5GHz):** `EDUP_5G_XXXX`
    *   **Password:** `12345678`
*   **Web Interface (LuCI):** Pre-installed with HTTPS (`luci-ssl`) support.
*   **DNS:** Pre-configured WAN DNS to `1.1.1.1` and `8.8.8.8`.
*   **SSH/SFTP:** Root login with password authentication is enabled by default.
*   **System Stability:** Includes a custom `iptables` dummy script to prevent system crashes specific to some EDUP hardware revisions.

### 📦 Included Files
*   `*-sysupgrade.bin` - The main firmware file for flashing via Web UI or console.
*   `*-imagebuilder-*.tar.zst` - The custom Image Builder archive (optional) if you want to compile your own variation based on this setup.

---

<a id="українська"></a>
## 🇺🇦 Українська

Кастомна збірка прошивки OpenWrt для роутера **EDUP EP-RT2983**, створена для повноцінної роботи "з коробки" без необхідності початкового налаштування через консоль.

Зібрана за допомогою офіційного OpenWrt Image Builder з інтеграцією скриптів `uci-defaults` для автоматичного застосування налаштувань під час першого завантаження.

### ✨ Головні особливості та налаштування
*   **IP-адреса за замовчуванням:** `192.168.2.1`
*   **Wi-Fi увімкнено одразу:**
    *   **SSID (2.4GHz):** `EDUP_2.4G_XXXX` *(де XXXX — останні 4 символи MAC-адреси)*
    *   **SSID (5GHz):** `EDUP_5G_XXXX`
    *   **Пароль:** `12345678`
*   **Веб-інтерфейс (LuCI):** Встановлено за замовчуванням із підтримкою HTTPS (`luci-ssl`).
*   **DNS:** Налаштовано WAN DNS на `1.1.1.1` та `8.8.8.8`.
*   **SSH/SFTP:** Дозволено вхід для користувача root за паролем.
*   **Стабільність системи:** Додано спеціальну "заглушку" `iptables` для запобігання падінню системи, яке зустрічається на деяких ревізіях EDUP.

### 📦 Файли в релізі
*   `*-sysupgrade.bin` — Головний файл прошивки для оновлення через веб-інтерфейс або консоль.
*   `*-imagebuilder-*.tar.zst` — Архів Image Builder (опціонально), якщо ви захочете зібрати власну модифікацію на цій базі.
