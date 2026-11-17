# xfree-toolbox

Установщик и пакеты для роутера на OpenWrt 24 и 25+.

## Установка

В консоли роутера:

```sh
wget -O /tmp/install-from-cloud.sh 'https://raw.githubusercontent.com/XFree/xfree-toolbox-releases/main/install-from-cloud.sh'
chmod +x /tmp/install-from-cloud.sh
sh /tmp/install-from-cloud.sh --menu
```

Без меню — тот же скрипт, без `--menu`.

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
