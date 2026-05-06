# OpenWrt WARP + PBR

**Автоматичне налаштування Cloudflare WARP-тунелю з гнучкою маршрутизацією трафіку для OpenWrt.**

---

## Що це

Скрипт розгортає на роутері під керуванням OpenWrt повноцінний VPN-тунель на базі Cloudflare WARP (WireGuard) з Policy-Based Routing. Весь трафік домашньої мережі йде через зашифрований тунель Cloudflare, при цьому обрані сервіси (наприклад, IPTV або стрімінгові платформи) продовжують працювати напряму через провайдера.

## Коли використовується

- Потрібен безкоштовний VPN для всієї домашньої мережі без налаштування кожного пристрою окремо
- Частина сервісів недоступна через тунель (IPTV, регіональний контент) і повинна йти напряму
- Хочете автоматичне відновлення тунелю без ручного втручання
- Використовуєте безкоштовний тариф Cloudflare WARP і хочете уникнути блокування за зловживання

## Як працює

**Маршрутизація трафіку** — весь LAN-трафік іде через WARP. Домени зі списку `/etc/warp_bypass.conf` (YouTube, ottplayer та інші) йдуть напряму через провайдера. IPv6 вимкнено, щоб трафік не оминав тунель.

**Watchdog** — кожні 10 хвилин перевіряє стан тунелю. При падінні спочатку визначає чи це проблема тунелю чи провайдера, потім послідовно намагається: м'який рестарт інтерфейсу → повна регенерація ключів WARP.

**Ротація ключів** — кожні 5 днів о 04:00 автоматично реєструє новий акаунт у Cloudflare WARP API та замінює ключі. Захищає від блокування безкоштовного тарифу.

## Що залишається на роутері

| Файл | Призначення |
|------|-------------|
| `/etc/warp_bypass.conf` | Список доменів що йдуть напряму на WAN |
| `/root/warp_bypass.sh` | CLI для управління bypass-списком |
| `/root/warp_autoreg.sh` | Реєстрація та ротація ключів WARP |
| `/root/warp_watchdog.sh` | Watchdog тунелю (запускається cron) |

## Використання

**Перше налаштування** — завантажити та запустити скрипт на роутері:

```sh
sh warp_final.sh
```

**Управління bypass-списком** (після налаштування, в будь-який момент):

```sh
warp_bypass.sh list                  # переглянути список
warp_bypass.sh add netflix.com       # додати домен
warp_bypass.sh del youtube.com       # прибрати домен
warp_bypass.sh apply                 # застосувати зміни без reboot
```

**Діагностика:**

```sh
wg show wg0                          # стан WireGuard тунелю
logread | grep WARP                  # логи watchdog та ротації
```

## Вимоги

- OpenWrt із підтримкою WireGuard (`kmod-wireguard`, `wireguard-tools`)
- Встановлені пакети: `pbr`, `jq`, `curl`
- Підключення до інтернету під час першого запуску (реєстрація в Cloudflare WARP API)

---
---

# OpenWrt WARP + PBR

**Automated Cloudflare WARP tunnel setup with flexible traffic routing for OpenWrt.**

---

## What it is

A setup script that deploys a full VPN tunnel based on Cloudflare WARP (WireGuard) with Policy-Based Routing on an OpenWrt router. All home network traffic is routed through Cloudflare's encrypted tunnel, while selected services (such as IPTV or regional streaming platforms) continue to work directly through the ISP.

## When to use it

- You need a free VPN for your entire home network without configuring each device individually
- Some services are unavailable through the tunnel (IPTV, regional content) and must go direct
- You want automatic tunnel recovery without manual intervention
- You're on the Cloudflare WARP free tier and want to avoid getting blocked for key reuse

## How it works

**Traffic routing** — all LAN traffic goes through WARP. Domains listed in `/etc/warp_bypass.conf` (YouTube, ottplayer, etc.) are routed directly through the ISP. IPv6 is disabled to prevent traffic from bypassing the tunnel.

**Watchdog** — checks tunnel health every 10 minutes. On failure, it first determines whether the issue is with the tunnel or the ISP, then attempts recovery in sequence: soft interface restart → full WARP key regeneration.

**Key rotation** — every 5 days at 04:00, automatically registers a new account via the Cloudflare WARP API and replaces the keys. Protects against free-tier throttling or bans.

## Files left on the router

| File | Purpose |
|------|---------|
| `/etc/warp_bypass.conf` | List of domains routed directly to WAN |
| `/root/warp_bypass.sh` | CLI for managing the bypass list |
| `/root/warp_autoreg.sh` | WARP key registration and rotation |
| `/root/warp_watchdog.sh` | Tunnel watchdog (run by cron) |

## Usage

**Initial setup** — download and run the script on the router:

```sh
sh warp_final.sh
```

**Managing the bypass list** (at any time after setup):

```sh
warp_bypass.sh list                  # show current list
warp_bypass.sh add netflix.com       # add a domain
warp_bypass.sh del youtube.com       # remove a domain
warp_bypass.sh apply                 # apply changes without reboot
```

**Diagnostics:**

```sh
wg show wg0                          # WireGuard tunnel status
logread | grep WARP                  # watchdog and rotation logs
```

## Requirements

- OpenWrt with WireGuard support (`kmod-wireguard`, `wireguard-tools`)
- Packages installed: `pbr`, `jq`, `curl`
- Internet connection during first run (registration with Cloudflare WARP API)
