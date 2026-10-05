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

`--apply-template <id>`. В примерах ниже — `default-with-proton`.

- `default` — только Cloudflare WARP
- `default-with-proton` — WARP + Proton VPN; Telegram, Netflix и часть AI (Claude, Cursor, Lovable) через Proton, остальное через WARP
- `default-with-proton-ai` — как `default-with-proton`, но все AI-сервисы через Proton

## CLI: обновить и применить, пересоздать

Те же действия, что в меню.

**Обновить и применить** — обновляет toolbox и списки, живой `config/` не затирается. Нужен уже созданный профиль:

```sh
sh /root/xfree-toolbox/system/install-from-cloud.sh --apply-mode sync
```

С явным шаблоном:

```sh
sh /root/xfree-toolbox/system/install-from-cloud.sh --apply-template default-with-proton --apply-mode sync
```

**Пересоздать и применить** — профиль из шаблона целиком:

```sh
sh /root/xfree-toolbox/system/install-from-cloud.sh --apply-template default-with-proton --force
```

Первое создание профиля (если его ещё нет) — без `--force` и без `--apply-mode`:

```sh
sh /root/xfree-toolbox/system/install-from-cloud.sh --apply-template default-with-proton
```

Другое имя профиля: `--apply-profile <name>`. Если toolbox ещё не стоит — те же флаги после wget в `/tmp`. Ход apply всегда на экране, пока фоновая задача не закончится.

## Пакеты (apk)

- индекс: https://raw.githubusercontent.com/XFree/xfree-toolbox-releases/main/packages.adb
- ключ: https://raw.githubusercontent.com/XFree/xfree-toolbox-releases/main/xfree-toolbox.pub
