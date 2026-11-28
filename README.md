# xfree-toolbox

Установщик и пакеты для роутера на OpenWrt 24 и 25+.

## Идея

`xfree-toolbox` — единый инструментарий поверх штатного OpenWrt для гибкого управления сетевыми маршрутами, VPN-интерфейсами, DNS и диагностикой. Вместо ручной стыковки десятков конфигов `dnsmasq`, `nftables`, `ip rule` и `cron` всё настраивается из веб-интерфейса LuCI или консольного меню `xft` через переносимые профили и шаблоны.

## Возможности

- **Маршрутизация по доменам и подсетям:** policy-based routing (`dnsmasq nftset` + `fw4`) с раздельными таблицами для нескольких туннелей и политиками по устройствам LAN.
- **Управление VPN-интерфейсами:** настройка и автовосстановление туннелей, входящий WireGuard/AmneziaWG-сервер с управлением пирами и QR-кодами.
- **DNS и DoH-стек:** несколько инстансов `https-dns-proxy`, привязка резолвинга отдельных доменов к нужному интерфейсу и защита от DNS-утечек (`noresolv`).
- **Мониторинг канала и железа:** периодическая проверка доступности uplink и туннелей (`usb-power-watch`), поддержка USB-модемов, управление LED-индикаторами, аудит `cron`.
- **Диагностика и обслуживание:** интерактивная карта трафика (трассировка пути домена по слоям DNS / VPN / WAN), проверка резолверов, ротируемые бэкапы и автообновление.
- **Два интерфейса управления:** веб-панель в LuCI и консольное меню (`xft`).

## Установка

Самый простой способ — подключиться к роутеру по SSH и выполнить три команды:

```sh
wget -O /tmp/install-from-cloud.sh 'https://raw.githubusercontent.com/XFree/xfree-toolbox-releases/main/install-from-cloud.sh'
chmod +x /tmp/install-from-cloud.sh
sh /tmp/install-from-cloud.sh
```

После установки откройте веб-панель **LuCI → Службы → xfree-toolbox** или введите в SSH команду `xft`.

Основные флаги `install-from-cloud.sh`:
- `--menu` — установить базовые пакеты и сразу открыть консольное меню `menu.sh` (нужен TTY, например `ssh -t`).
- `--apply-template <id>` — установить базовые пакеты и применить шаблон (например, `warp-proton`).
- `--registry-only` — только настроить реестр и ключ `apk` (OpenWrt 25+).
- `--use-tar` — принудительно использовать `tar` вместо `apk` на OpenWrt 25+.
- `--no-luci` — не устанавливать и не обновлять веб-интерфейс `luci-app-xfree-toolbox` (по умолчанию ставится/обновляется, если на роутере есть LuCI).
- `-h` / `--help` — полная справка по всем флагам.

<details>
<summary>Опциональная проверка контрольной суммы установщика (SHA256)</summary>

```sh
wget -O /tmp/SHA256SUMS 'https://raw.githubusercontent.com/XFree/xfree-toolbox-releases/main/SHA256SUMS'
(cd /tmp && grep ' install-from-cloud.sh$' SHA256SUMS | sha256sum -c -)
```

</details>

Уже установлен toolbox:

```sh
sh /root/xfree-toolbox/system/install-from-cloud.sh --menu
```

## Шаблоны

`--apply-template <id>`. В примерах ниже — `warp-proton`.

- `warp` — только Cloudflare WARP (алиас: `default`)
- `warp-proton` — WARP + Proton VPN; AI / Spotify / JetBrains / Notion через Proton (алиасы: `default-with-proton`, `default-with-proton-ai`)

## CLI: обновить и применить, пересоздать

Те же действия, что в меню.

**Обновить и применить** — обновляет toolbox и списки, живой `config/` не затирается. Нужен уже созданный профиль:

```sh
sh /root/xfree-toolbox/system/install-from-cloud.sh --apply-mode sync
```

С явным шаблоном:

```sh
sh /root/xfree-toolbox/system/install-from-cloud.sh --apply-template warp-proton --apply-mode sync
```

**Пересоздать и применить** — профиль из шаблона целиком:

```sh
sh /root/xfree-toolbox/system/install-from-cloud.sh --apply-template warp-proton --force
```

Первое создание профиля (если его ещё нет) — без `--force` и без `--apply-mode`:

```sh
sh /root/xfree-toolbox/system/install-from-cloud.sh --apply-template warp-proton
```

Другое имя профиля: `--apply-profile <name>`. Если toolbox ещё не стоит — те же флаги после wget в `/tmp`. Ход apply всегда на экране, пока фоновая задача не закончится.

## Пакеты (apk)

- индекс: https://raw.githubusercontent.com/XFree/xfree-toolbox-releases/main/packages.adb
- ключ: https://raw.githubusercontent.com/XFree/xfree-toolbox-releases/main/xfree-toolbox.pub
- контрольные суммы: https://raw.githubusercontent.com/XFree/xfree-toolbox-releases/main/SHA256SUMS
- проверки релиза: https://raw.githubusercontent.com/XFree/xfree-toolbox-releases/main/RELEASE_CHECKS.txt (версия: `0.4.17+0`, `verify-all`: `passed`, `e2e`: `passed`)
- баг-репорты и вопросы: https://github.com/XFree/xfree-toolbox-releases/issues
