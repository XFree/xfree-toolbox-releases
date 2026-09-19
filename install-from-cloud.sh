#!/bin/sh
# GitHub apk-feed installer (raw.githubusercontent.com; apk/uclient-fetch does not follow 30x).
# First install writes XFREE_APK_FEED_SOURCE=github to /etc/xfree-toolbox/apk-feed.env.
XFREE_APK_FEED_SOURCE="${XFREE_APK_FEED_SOURCE:-github}"
# Установка/обновление xfree-toolbox с Nextcloud.
# OpenWrt 25+: реестр apk (ключ + feed) + установка пакета apk (или tar с --use-tar).
# OpenWrt 24.x: tar → install-bootstrap (с нуля) или self-update (обновление с сохранением profiles).
# Factory wget (/tmp): свой артефакт, при публикации собирается из общего lib/ (embed).
# Только прописать apk feed и обновить пакет (apk/tar). Не source lib со старого toolbox.
# После установки — всегда exec /root/xfree-toolbox/system/install-from-cloud.sh (меню, apply, хуки).
# Запуск: wget скрипт с share или sh /root/xfree-toolbox/system/install-from-cloud.sh
# shellcheck shell=sh
set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
TARGET_DIR="${TARGET_DIR:-/root/xfree-toolbox}"

# Исходный argv: factory /tmp после apk/tar делает exec установленной копии.
xfree_handoff_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}
XFREE_HANDOFF_ARGS=""
for _xfree_handoff_a in "$@"; do
  XFREE_HANDOFF_ARGS="$XFREE_HANDOFF_ARGS $(xfree_handoff_quote "$_xfree_handoff_a")"
done

# Скрипт из /tmp (wget): самодостаточный (embed). Не брать lib со старого toolbox —
# иначе обновление ломается на устаревшем apk-registry.sh / common.sh.
# Lib с диска — только если этот файл лежит в дереве (git / установленный пакет).
xfree_find_toolbox_lib_root() {
  if [ -f "$SCRIPT_DIR/../lib/owrt-release.sh" ]; then
    CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P
    return 0
  fi
  return 1
}

ROOT_DIR="$(xfree_find_toolbox_lib_root 2>/dev/null || true)"
COMMON_SH=""
OWRT_LIB=""
INSTALL_CHANNEL_SH=""
APK_REGISTRY_SH=""
if [ -n "$ROOT_DIR" ]; then
  COMMON_SH="$ROOT_DIR/lib/common.sh"
  OWRT_LIB="$ROOT_DIR/lib/owrt-release.sh"
  INSTALL_CHANNEL_SH="$ROOT_DIR/lib/install-channel.sh"
  APK_REGISTRY_SH="$ROOT_DIR/lib/apk-registry.sh"
fi

die() {
  printf '[-] %s\n' "$*" >&2
  exit 1
}

info() {
  printf '[*] %s\n' "$*"
}

warn() {
  printf '[!] %s\n' "$*" >&2
}

success() {
  printf '[✓] %s\n' "$*"
}

# --- defaults (bootstrap; config.sh when installed in tree) ---
FACTORY_PUBLIC_BASE="${XFREE_FACTORY_PUBLIC_BASE:-https://xfree-cloud.duckdns.org/public.php/dav/files/L982AaEEYAHYtTj}"
INSTALL_SCRIPT_NAME="${XFREE_INSTALL_SCRIPT_NAME:-install-from-cloud.sh}"
UPDATE_URL="${XFREE_UPDATE_URL:-https://xfree-cloud.duckdns.org/public.php/dav/files/xkwFs6doydiM4Pw}"
FEED_BASE="${XFREE_APK_FEED_PUBLIC_BASE:-https://xfree-cloud.duckdns.org/public.php/dav/files/GFqGBrf6giHzpZQ}"
STATE_ROOT="${XFREE_STATE_ROOT:-/etc/xfree-toolbox}"
ARCHIVE_NAME="${ARCHIVE_NAME:-xfree-toolbox.tar.gz}"
APK_KEYS_DIR="${ROUTER_APK_KEYS_DIR:-/etc/apk/keys}"
APK_REPOS_DIR="${ROUTER_APK_REPOS_DIR:-/etc/apk/repositories.d}"
APK_REPO_FILE="${ROUTER_APK_REPO_FILE:-xfree-toolbox.list}"
PUBKEY_BASENAME="${XFREE_APK_PUBKEY_NAME:-xfree-toolbox.pub}"
APK_PKG_NAME="${XFREE_APK_PACKAGE_NAME:-xfree-toolbox}"

if [ -n "$COMMON_SH" ] && [ -f "$COMMON_SH" ]; then
  # shellcheck disable=SC1090
  . "$COMMON_SH"
  UPDATE_ETAG_SH="$ROOT_DIR/lib/update-etag.sh"
  if [ -f "$UPDATE_ETAG_SH" ]; then
    # shellcheck disable=SC1090
    . "$UPDATE_ETAG_SH"
  fi
  load_base_config "$ROOT_DIR" 2>/dev/null || true
  UPDATE_URL="${UPDATE_URL:-${XFREE_UPDATE_URL:-}}"
  FEED_BASE="${FEED_BASE:-${XFREE_APK_FEED_PUBLIC_BASE:-}}"
  TARGET_DIR="${TARGET_DIR:-${XFREE_ROOT_DIR:-/root/xfree-toolbox}}"
  FACTORY_PUBLIC_BASE="${FACTORY_PUBLIC_BASE:-${XFREE_FACTORY_PUBLIC_BASE:-}}"
  INSTALL_SCRIPT_NAME="${INSTALL_SCRIPT_NAME:-${XFREE_INSTALL_SCRIPT_NAME:-install-from-cloud.sh}}"
fi

if [ -n "$OWRT_LIB" ] && [ -f "$OWRT_LIB" ]; then
  # shellcheck disable=SC1090
  . "$OWRT_LIB"
fi

if [ -n "$INSTALL_CHANNEL_SH" ] && [ -f "$INSTALL_CHANNEL_SH" ]; then
  # shellcheck disable=SC1090
  . "$INSTALL_CHANNEL_SH"
fi
if [ -n "$APK_REGISTRY_SH" ] && [ -f "$APK_REGISTRY_SH" ]; then
  # shellcheck disable=SC1090
  . "$APK_REGISTRY_SH"
fi

# Старый toolbox на роутере может иметь apk-registry.sh без seed_source/active_url.
# Factory wget тогда не должен считать lib «уже загруженной» и пропускать embed.
xfree_cloud_embedded_libs_ready() {
  command -v xfree_resolve_update_channel >/dev/null 2>&1 \
    && command -v xfree_apk_registry_feed_url >/dev/null 2>&1 \
    && command -v xfree_apk_feed_seed_source >/dev/null 2>&1 \
    && command -v xfree_apk_feed_active_url >/dev/null 2>&1
}

xfree_load_cloud_embedded_libs() {
  if xfree_cloud_embedded_libs_ready; then
    return 0
  fi
  if [ -n "$OWRT_LIB" ] && [ -f "$OWRT_LIB" ]; then
    # shellcheck disable=SC1090
    . "$OWRT_LIB"
  fi
  if [ -n "$INSTALL_CHANNEL_SH" ] && [ -f "$INSTALL_CHANNEL_SH" ]; then
    # shellcheck disable=SC1090
    . "$INSTALL_CHANNEL_SH"
  fi
  if [ -n "$APK_REGISTRY_SH" ] && [ -f "$APK_REGISTRY_SH" ]; then
    # shellcheck disable=SC1090
    . "$APK_REGISTRY_SH"
    if xfree_cloud_embedded_libs_ready; then
      return 0
    fi
  fi
  # --- embed lib/owrt-release.sh (build-time; do not edit) ---
  # OpenWrt release helpers (distribution channel: tar vs apk).
  # shellcheck shell=sh
  
  owrt_release_load() {
    OWRT_DISTRIB_RELEASE=""
    OWRT_DISTRIB_ID=""
    OWRT_RELEASE_MAJOR=""
  
    if [ -f /etc/openwrt_release ]; then
      # shellcheck disable=SC1091
      . /etc/openwrt_release 2>/dev/null || true
      OWRT_DISTRIB_RELEASE="${DISTRIB_RELEASE:-}"
      OWRT_DISTRIB_ID="${DISTRIB_ID:-}"
    fi
  
    if [ -z "$OWRT_DISTRIB_RELEASE" ] && [ -f /etc/os-release ]; then
      # shellcheck disable=SC1091
      . /etc/os-release 2>/dev/null || true
      OWRT_DISTRIB_RELEASE="${OPENWRT_VERSION:-${VERSION_ID:-}}"
      [ -n "$OWRT_DISTRIB_ID" ] || OWRT_DISTRIB_ID="${NAME:-OpenWrt}"
    fi
  
    [ -n "$OWRT_DISTRIB_RELEASE" ] || return 1
  
    OWRT_RELEASE_MAJOR="${OWRT_DISTRIB_RELEASE%%.*}"
    return 0
  }
  
  # Prints: tar | apk | unknown
  owrt_install_channel_recommended() {
    if ! owrt_release_load; then
      printf '%s\n' unknown
      return 0
    fi
  
    case "$OWRT_RELEASE_MAJOR" in
      ''|*[!0-9]*)
        if command -v apk >/dev/null 2>&1; then
          printf '%s\n' apk
        else
          printf '%s\n' unknown
        fi
        ;;
      0|1|2|3|4|5|6|7|8|9|1[0-9]|2[0-4])
        printf '%s\n' tar
        ;;
      *)
        if command -v apk >/dev/null 2>&1; then
          printf '%s\n' apk
        else
          printf '%s\n' tar
        fi
        ;;
    esac
  }
  
  owrt_apk_package_installed() {
    command -v apk >/dev/null 2>&1 || return 1
    apk info -e xfree-toolbox >/dev/null 2>&1
  }

  # --- embed lib/install-channel.sh (build-time; do not edit) ---
  # shellcheck shell=sh
  # Unified install/update channel: apk (OpenWrt 25+) vs tar.
  # Sets XFREE_CHANNEL_REASON on resolve.
  
  _xfree_install_channel_lib_dir() {
    if [ -n "${ROOT_DIR:-}" ] && [ -f "${ROOT_DIR}/lib/owrt-release.sh" ]; then
      printf '%s\n' "${ROOT_DIR}/lib"
      return 0
    fi
    CDPATH= cd -- "$(dirname -- "$0")" && pwd -P
  }
  
  _xfree_install_channel_owrt_lib="$(_xfree_install_channel_lib_dir)/owrt-release.sh"
  if [ -f "$_xfree_install_channel_owrt_lib" ]; then
    # shellcheck disable=SC1090
    . "$_xfree_install_channel_owrt_lib"
  fi
  
  # Prints OpenWrt version line for check/update UI (best-effort).
  xfree_print_openwrt_version_line() {
    if command -v owrt_release_load >/dev/null 2>&1 && owrt_release_load; then
      printf '[*] OpenWrt         : %s %s (major=%s)\n' \
        "${OWRT_DISTRIB_ID:-OpenWrt}" "${OWRT_DISTRIB_RELEASE:-?}" "${OWRT_RELEASE_MAJOR:-?}"
      return 0
    fi
    printf '[*] OpenWrt         : <unknown>\n'
  }
  
  # Prints: apk | tar
  # Env: USE_TAR=1, XFREE_FORCE_CHANNEL=apk|tar (optional overrides).
  # Priority: force → apk package installed → OS version (25+ → apk) → tar.
  xfree_resolve_update_channel() {
    _force="${XFREE_FORCE_CHANNEL:-}"
    if [ -z "$_force" ] && [ "${USE_TAR:-0}" = "1" ]; then
      _force=tar
    fi
    if [ -n "$_force" ]; then
      XFREE_CHANNEL_REASON="forced: $_force"
      printf '%s\n' "$_force"
      return 0
    fi
  
    if command -v owrt_apk_package_installed >/dev/null 2>&1; then
      if owrt_apk_package_installed 2>/dev/null; then
        XFREE_CHANNEL_REASON="apk package installed"
        printf '%s\n' apk
        return 0
      fi
    elif command -v apk >/dev/null 2>&1; then
      _pkg="${XFREE_APK_PACKAGE_NAME:-xfree-toolbox}"
      if apk info -e "$_pkg" >/dev/null 2>&1; then
        XFREE_CHANNEL_REASON="apk package installed"
        printf '%s\n' apk
        return 0
      fi
    fi
  
    _rec=unknown
    if command -v owrt_install_channel_recommended >/dev/null 2>&1; then
      _rec="$(owrt_install_channel_recommended)"
    fi
  
    case "$_rec" in
      apk)
        if command -v apk >/dev/null 2>&1; then
          XFREE_CHANNEL_REASON="OpenWrt 25+ recommended"
          printf '%s\n' apk
          return 0
        fi
        XFREE_CHANNEL_REASON="OpenWrt 25+ but apk command missing"
        printf '%s\n' tar
        return 0
        ;;
      tar)
        XFREE_CHANNEL_REASON="OpenWrt ≤24"
        printf '%s\n' tar
        return 0
        ;;
      *)
        if command -v apk >/dev/null 2>&1; then
          XFREE_CHANNEL_REASON="unknown OpenWrt version, apk present"
          printf '%s\n' apk
          return 0
        fi
        XFREE_CHANNEL_REASON="unknown OpenWrt version, no apk"
        printf '%s\n' tar
        return 0
        ;;
    esac
  }
  
  # Parse toolbox version from VERSION (0.1.0+789) or apk (0.1.0-r789 / xfree-toolbox-0.1.0-r789 …).
  # Sets XFREE_TB_VER_MAJOR/MINOR/PATCH/BUILD. Same build number: 0.1.0+N == 0.1.0-rN.
  xfree_toolbox_version_parse() {
    _in="${1:-}"
    XFREE_TB_VER_MAJOR=""
    XFREE_TB_VER_MINOR=""
    XFREE_TB_VER_PATCH=""
    XFREE_TB_VER_BUILD=""
    _in="$(printf '%s' "$_in" | tr -d '\r' | awk '{print $1; exit}')"
    [ -n "$_in" ] || return 1
    _semver="$(printf '%s' "$_in" | sed -n 's/.*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')"
    [ -n "$_semver" ] || return 1
    XFREE_TB_VER_MAJOR="${_semver%%.*}"
    _rest="${_semver#*.}"
    XFREE_TB_VER_MINOR="${_rest%%.*}"
    XFREE_TB_VER_PATCH="${_rest#*.}"
    _build="$(printf '%s' "$_in" | sed -n 's/.*+\([0-9][0-9]*\).*/\1/p')"
    if [ -z "$_build" ]; then
      _build="$(printf '%s' "$_in" | sed -n 's/.*-r\([0-9][0-9]*\).*/\1/p')"
    fi
    XFREE_TB_VER_BUILD="${_build:-0}"
    return 0
  }
  
  # stdout: -1 (a<b), 0 (equal), 1 (a>b). Unparsable a → -1; unparsable b → 1.
  xfree_toolbox_version_cmp() {
    _a_maj=0 _a_min=0 _a_pat=0 _a_bld=0
    _b_maj=0 _b_min=0 _b_pat=0 _b_bld=0
    if xfree_toolbox_version_parse "$1"; then
      _a_maj="$XFREE_TB_VER_MAJOR"
      _a_min="$XFREE_TB_VER_MINOR"
      _a_pat="$XFREE_TB_VER_PATCH"
      _a_bld="$XFREE_TB_VER_BUILD"
    else
      printf '%s\n' '-1'
      return 0
    fi
    if xfree_toolbox_version_parse "$2"; then
      _b_maj="$XFREE_TB_VER_MAJOR"
      _b_min="$XFREE_TB_VER_MINOR"
      _b_pat="$XFREE_TB_VER_PATCH"
      _b_bld="$XFREE_TB_VER_BUILD"
    else
      printf '%s\n' '1'
      return 0
    fi
    if [ "$_a_maj" -lt "$_b_maj" ]; then printf '%s\n' '-1'; return 0; fi
    if [ "$_a_maj" -gt "$_b_maj" ]; then printf '%s\n' '1'; return 0; fi
    if [ "$_a_min" -lt "$_b_min" ]; then printf '%s\n' '-1'; return 0; fi
    if [ "$_a_min" -gt "$_b_min" ]; then printf '%s\n' '1'; return 0; fi
    if [ "$_a_pat" -lt "$_b_pat" ]; then printf '%s\n' '-1'; return 0; fi
    if [ "$_a_pat" -gt "$_b_pat" ]; then printf '%s\n' '1'; return 0; fi
    if [ "$_a_bld" -lt "$_b_bld" ]; then printf '%s\n' '-1'; return 0; fi
    if [ "$_a_bld" -gt "$_b_bld" ]; then printf '%s\n' '1'; return 0; fi
    printf '%s\n' '0'
  }
  
  xfree_toolbox_version_ge() {
    _cmp="$(xfree_toolbox_version_cmp "$1" "$2")"
    [ "$_cmp" = "0" ] || [ "$_cmp" = "1" ]
  }
  
  xfree_toolbox_version_from_tree() {
    _td="${1:-${XFREE_TOOLBOX_TARGET_DIR:-${TARGET_DIR:-/root/xfree-toolbox}}}"
    _vf="$_td/VERSION"
    if [ -f "$_vf" ]; then
      head -n1 "$_vf" | tr -d '\r\n\t '
      return 0
    fi
    printf '%s' ""
  }
  
  # If tree VERSION is already >= feed line, do not apk add/upgrade (would downgrade tar 0.1.0+N to older 0.1.0-rM).
  xfree_apk_skip_if_tree_newer_than_feed() {
    _feed_line="${1:-}"
    [ -n "$_feed_line" ] || return 1
    _local_ver="$(xfree_toolbox_version_from_tree "${2:-}")"
    [ -n "$_local_ver" ] || return 1
    xfree_toolbox_version_ge "$_local_ver" "$_feed_line"
  }
  
  # First apk list line for exact package name (not luci-app-xfree-toolbox when pkg=xfree-toolbox).
  xfree_apk_first_pkg_line() {
    _pkg="${1:-}"
    [ -n "$_pkg" ] || return 0
    awk -v pkg="$_pkg" '
      index($0, pkg "-") == 1 {
        c = substr($0, length(pkg) + 2, 1)
        if (c ~ /[0-9]/) { print; exit }
      }
    '
  }
  
  # After `apk update`. Sets:
  #   XFREE_APK_CHECK_INSTALLED  — apk version or empty
  #   XFREE_APK_CHECK_AVAILABLE  — first matching feed/upgrade line or empty
  #   XFREE_APK_CHECK_ACTION     — none | upgrade | add
  # add = package not in apk world, but feed has it (tar-only on OpenWrt 25+).
  xfree_apk_probe_feed_update() {
    _pkg="${1:-${XFREE_APK_PACKAGE_NAME:-xfree-toolbox}}"
    XFREE_APK_CHECK_INSTALLED=""
    XFREE_APK_CHECK_AVAILABLE=""
    XFREE_APK_CHECK_ACTION=none
  
    command -v apk >/dev/null 2>&1 || return 1
  
    if apk info -e "$_pkg" >/dev/null 2>&1; then
      XFREE_APK_CHECK_INSTALLED="$(apk info -e "$_pkg" 2>/dev/null | sed -n '1p')"
      [ -n "$XFREE_APK_CHECK_INSTALLED" ] || XFREE_APK_CHECK_INSTALLED="$_pkg"
      XFREE_APK_CHECK_AVAILABLE="$(apk list -u 2>/dev/null | xfree_apk_first_pkg_line "$_pkg" || true)"
      if [ -n "$XFREE_APK_CHECK_AVAILABLE" ]; then
        XFREE_APK_CHECK_ACTION=upgrade
      fi
    else
      XFREE_APK_CHECK_AVAILABLE="$(apk list 2>/dev/null | xfree_apk_first_pkg_line "$_pkg" || true)"
      if [ -n "$XFREE_APK_CHECK_AVAILABLE" ]; then
        XFREE_APK_CHECK_ACTION=add
      fi
    fi
  
    case "${XFREE_APK_CHECK_ACTION:-none}" in
      add|upgrade)
        if xfree_apk_skip_if_tree_newer_than_feed "$XFREE_APK_CHECK_AVAILABLE"; then
          XFREE_APK_CHECK_ACTION=none
        fi
        ;;
    esac
    return 0
  }
  
  # Print [*] lines for --check-only / menu. Caller already ran apk update.
  xfree_apk_print_feed_check() {
    _pkg="${1:-${XFREE_APK_PACKAGE_NAME:-xfree-toolbox}}"
    xfree_apk_probe_feed_update "$_pkg" || return 1
    _inst="${XFREE_APK_CHECK_INSTALLED:-}"
    [ -n "$_inst" ] || _inst="<не установлен>"
    printf '[*] Package         : %s\n' "$_pkg"
    printf '[*] Installed       : %s\n' "$_inst"
    printf '[*] Available       : %s\n' "${XFREE_APK_CHECK_AVAILABLE:-<none>}"
    printf '[*] Action          : %s\n' "${XFREE_APK_CHECK_ACTION:-none}"
    case "${XFREE_APK_CHECK_ACTION:-none}" in
      upgrade|add) printf '[*] Upgradable      : yes\n' ;;
      *) printf '[*] Upgradable      : no\n' ;;
    esac
    return 0
  }

  # --- embed lib/apk-registry.sh (build-time; do not edit) ---
  # shellcheck shell=sh
  # Apk registry (pubkey + repositories.d) for xfree-toolbox on OpenWrt 25+.
  
  xfree_apk_registry_repo_file() {
    _dir="${ROUTER_APK_REPOS_DIR:-${APK_REPOS_DIR:-/etc/apk/repositories.d}}"
    _name="${ROUTER_APK_REPO_FILE:-${APK_REPO_FILE:-xfree-toolbox.list}}"
    printf '%s/%s\n' "$_dir" "$_name"
  }
  
  xfree_apk_registry_pubkey_file() {
    _dir="${ROUTER_APK_KEYS_DIR:-${APK_KEYS_DIR:-/etc/apk/keys}}"
    _name="${XFREE_APK_PUBKEY_NAME:-${PUBKEY_BASENAME:-xfree-toolbox.pub}}"
    printf '%s/%s\n' "$_dir" "$_name"
  }
  
  xfree_apk_registry_normalize_feed_url() {
    _base="${1:-}"
    [ -n "$_base" ] || return 1
    case "$_base" in
      */packages.adb) printf '%s\n' "$_base" ;;
      *) printf '%s/packages.adb\n' "${_base%/}" ;;
    esac
  }
  
  xfree_apk_registry_feed_url() {
    xfree_apk_registry_normalize_feed_url "${FEED_BASE:-${XFREE_APK_FEED_PUBLIC_BASE:-}}"
  }
  
  xfree_apk_feed_state_file() {
    printf '%s/apk-feed.env\n' "${XFREE_STATE_ROOT:-/etc/xfree-toolbox}"
  }
  
  # Direct raw.githubusercontent.com — apk/uclient-fetch does not follow 30x
  # (github.com/releases/download and github.com/.../raw/... both redirect).
  xfree_apk_feed_github_public_base() {
    if [ -n "${XFREE_APK_FEED_GITHUB_PUBLIC_BASE:-}" ]; then
      printf '%s\n' "${XFREE_APK_FEED_GITHUB_PUBLIC_BASE%/}"
      return 0
    fi
    printf 'https://raw.githubusercontent.com/%s/%s\n' \
      "${XFREE_APK_FEED_GITHUB_REPO:-XFree/xfree-toolbox-releases}" \
      "${XFREE_APK_FEED_GITHUB_BRANCH:-${XFREE_APK_FEED_GITHUB_TAG:-main}}"
  }
  
  xfree_apk_feed_load_state() {
    XFREE_APK_FEED_SOURCE="${XFREE_APK_FEED_SOURCE:-cloud}"
    _sf="$(xfree_apk_feed_state_file)"
    if [ -r "$_sf" ]; then
      # shellcheck disable=SC1090
      . "$_sf"
    fi
    case "${XFREE_APK_FEED_SOURCE:-}" in
      github|cloud) ;;
      *) XFREE_APK_FEED_SOURCE=cloud ;;
    esac
  }
  
  xfree_apk_feed_save_source() {
    _src="${1:-}"
    case "$_src" in
      cloud|github) ;;
      *) return 1 ;;
    esac
    _sf="$(xfree_apk_feed_state_file)"
    mkdir -p "$(dirname "$_sf")" || return 1
    printf "XFREE_APK_FEED_SOURCE='%s'\n" "$_src" >"$_sf" || return 1
    XFREE_APK_FEED_SOURCE="$_src"
  }
  
  # Infer cloud|github from repositories.d, else from env (GitHub factory injects github).
  xfree_apk_feed_infer_source() {
    _repo="$(xfree_apk_registry_repo_file)"
    if [ -f "$_repo" ] && grep -qE 'raw\.githubusercontent\.com/' "$_repo" 2>/dev/null; then
      printf '%s\n' github
      return 0
    fi
    if [ -f "$_repo" ]; then
      printf '%s\n' cloud
      return 0
    fi
    case "${XFREE_APK_FEED_SOURCE:-cloud}" in
      github) printf '%s\n' github ;;
      *) printf '%s\n' cloud ;;
    esac
  }
  
  # Persist source on first install. Existing apk-feed.env is sticky unless XFREE_APK_FEED_SOURCE_EXPLICIT=1.
  xfree_apk_feed_seed_source() {
    _sf="$(xfree_apk_feed_state_file)"
    if [ -r "$_sf" ] && [ "${XFREE_APK_FEED_SOURCE_EXPLICIT:-0}" != "1" ]; then
      xfree_apk_feed_load_state
      return 0
    fi
    _src="${XFREE_APK_FEED_SOURCE:-}"
    if [ "${XFREE_APK_FEED_SOURCE_EXPLICIT:-0}" != "1" ]; then
      _src="$(xfree_apk_feed_infer_source)"
    fi
    case "$_src" in
      cloud|github) ;;
      *) _src=cloud ;;
    esac
    xfree_apk_feed_save_source "$_src"
  }
  
  xfree_apk_feed_tar_url() {
    xfree_apk_feed_load_state
    case "$XFREE_APK_FEED_SOURCE" in
      github)
        printf '%s/%s\n' "$(xfree_apk_feed_github_public_base)" "${ARCHIVE_NAME:-xfree-toolbox.tar.gz}"
        ;;
      *)
        printf '%s\n' "${UPDATE_URL:-${XFREE_UPDATE_URL:-}}"
        ;;
    esac
  }
  
  # Factory installer: GitHub raw when overlay is github (self-update must not wget Nextcloud).
  xfree_apk_feed_install_url() {
    _name="${XFREE_INSTALL_SCRIPT_NAME:-${INSTALL_SCRIPT_NAME:-install-from-cloud.sh}}"
    xfree_apk_feed_load_state
    case "$XFREE_APK_FEED_SOURCE" in
      github)
        printf '%s/%s\n' "$(xfree_apk_feed_github_public_base)" "$_name"
        ;;
      *)
        _factory="${FACTORY_PUBLIC_BASE:-${XFREE_FACTORY_PUBLIC_BASE:-}}"
        [ -n "$_factory" ] || return 1
        printf '%s/%s\n' "${_factory%/}" "$_name"
        ;;
    esac
  }
  
  xfree_apk_registry_feed_url_for_source() {
    _src="${1:-cloud}"
    case "$_src" in
      github)
        xfree_apk_registry_normalize_feed_url "$(xfree_apk_feed_github_public_base)"
        ;;
      cloud|*)
        xfree_apk_registry_normalize_feed_url "${FEED_BASE:-${XFREE_APK_FEED_PUBLIC_BASE:-}}"
        ;;
    esac
  }
  
  xfree_apk_feed_active_url() {
    xfree_apk_feed_load_state
    xfree_apk_registry_feed_url_for_source "$XFREE_APK_FEED_SOURCE"
  }
  
  xfree_apk_feed_source_label() {
    xfree_apk_feed_load_state
    case "$XFREE_APK_FEED_SOURCE" in
      github) printf '%s' 'GitHub' ;;
      *) printf '%s' 'Nextcloud' ;;
    esac
  }
  
  # Host for DNS/health probes (recover-apk-network). Not a download URL.
  xfree_apk_feed_probe_host() {
    xfree_apk_feed_load_state
    case "$XFREE_APK_FEED_SOURCE" in
      github) printf '%s\n' 'raw.githubusercontent.com' ;;
      *) printf '%s\n' 'xfree-cloud.duckdns.org' ;;
    esac
  }
  
  xfree_apk_feed_is_enabled() {
    _repo="$(xfree_apk_registry_repo_file)"
    [ -f "$_repo" ] || return 1
    grep -qE '^[[:space:]]*https?://' "$_repo"
  }
  
  xfree_apk_feed_restore_off() {
    _repo="$(xfree_apk_registry_repo_file)"
    _off="${_repo}.off"
    if [ -f "$_off" ] && [ ! -f "$_repo" ]; then
      mv "$_off" "$_repo" || return 1
    fi
    return 0
  }
  
  xfree_apk_feed_enable() {
    xfree_apk_feed_restore_off || true
    _url="$(xfree_apk_feed_active_url)" || return 1
    _repo="$(xfree_apk_registry_repo_file)"
    mkdir -p "$(dirname "$_repo")" || return 1
    printf '%s\n' "$_url" >"$_repo" || return 1
    chmod 0644 "$_repo" 2>/dev/null || true
    return 0
  }
  
  xfree_apk_feed_disable() {
    _repo="$(xfree_apk_registry_repo_file)"
    if [ ! -f "$_repo" ]; then
      _url="$(xfree_apk_feed_active_url)" || return 1
      mkdir -p "$(dirname "$_repo")" || return 1
      printf '# xfree-toolbox apk feed (disabled)\n# %s\n' "$_url" >"$_repo" || return 1
      chmod 0644 "$_repo" 2>/dev/null || true
      return 0
    fi
    _tmp="${_repo}.tmp.$$"
    awk '
      /^[[:space:]]*#/ { print; next }
      /^[[:space:]]*https?:\/\// { print "# " $0; next }
      { print }
    ' "$_repo" >"$_tmp" || {
      rm -f "$_tmp" 2>/dev/null || true
      return 1
    }
    mv -f "$_tmp" "$_repo"
  }
  
  xfree_apk_feed_set_source() {
    xfree_apk_feed_save_source "${1:-}" || return 1
    if xfree_apk_feed_is_enabled; then
      xfree_apk_feed_enable
    fi
  }
  
  xfree_apk_registry_pubkey_url() {
    if [ -n "${PUB_KEY_URL:-}" ]; then
      printf '%s\n' "$PUB_KEY_URL"
      return 0
    fi
    _basename="${XFREE_APK_PUBKEY_NAME:-${PUBKEY_BASENAME:-xfree-toolbox.pub}}"
    xfree_apk_feed_load_state
    case "$XFREE_APK_FEED_SOURCE" in
      github)
        printf '%s/%s\n' "$(xfree_apk_feed_github_public_base)" "$_basename"
        return 0
        ;;
    esac
    _factory="${FACTORY_PUBLIC_BASE:-${XFREE_FACTORY_PUBLIC_BASE:-}}"
    [ -n "$_factory" ] || return 1
    printf '%s/%s\n' "${_factory%/}" "$_basename"
  }
  
  # Last path segment of public.php/dav/files/<token>/…
  xfree_apk_registry_share_token() {
    _url="${1:-}"
    _url="${_url%/}"
    [ -n "$_url" ] || return 1
    _token="${_url##*/}"
    [ -n "$_token" ] || return 1
    printf '%s\n' "$_token"
  }
  
  # True when factory base points at the tar share (common misconfig: pubkey 404).
  xfree_apk_registry_factory_looks_like_tar_url() {
    _factory="${1:-${FACTORY_PUBLIC_BASE:-${XFREE_FACTORY_PUBLIC_BASE:-}}}"
    _update="${2:-${UPDATE_URL:-${XFREE_UPDATE_URL:-}}}"
    _ft=""
    _ut=""
    _ft="$(xfree_apk_registry_share_token "$_factory" 2>/dev/null || true)"
    _ut="$(xfree_apk_registry_share_token "$_update" 2>/dev/null || true)"
    [ -n "$_ft" ] && [ -n "$_ut" ] && [ "$_ft" = "$_ut" ]
  }
  
  xfree_apk_registry_default_factory_base() {
    printf '%s\n' "${XFREE_APK_FACTORY_DEFAULT:-https://xfree-cloud.duckdns.org/public.php/dav/files/L982AaEEYAHYtTj}"
  }
  
  xfree_apk_registry_configured() {
    [ -f "$(xfree_apk_registry_repo_file)" ] \
      && [ -f "$(xfree_apk_registry_pubkey_file)" ]
  }
  
  xfree_apk_registry_https_fetch() {
    _dst="$1"
    _url="$2"
  
    [ -n "$_url" ] || return 1
    XFREE_APK_REGISTRY_LAST_FETCH_URL="$_url"
  
    if command -v curl >/dev/null 2>&1; then
      if curl --http1.1 -fL --connect-timeout 25 --max-time 180 -o "$_dst" "$_url" 2>/dev/null \
        && [ -s "$_dst" ]; then
        return 0
      fi
      if curl --http1.1 -fL -k --connect-timeout 25 --max-time 180 -o "$_dst" "$_url" \
        && [ -s "$_dst" ]; then
        return 0
      fi
      return 1
    fi
  
    if command -v wget >/dev/null 2>&1; then
      if wget -T 25 -O "$_dst" "$_url" 2>/dev/null && [ -s "$_dst" ]; then
        return 0
      fi
      wget --no-check-certificate -T 25 -O "$_dst" "$_url" && [ -s "$_dst" ]
      return $?
    fi
  
    return 1
  }
  
  # Idempotent: ensure pubkey + feed list. Returns 0 when registry is ready.
  xfree_ensure_apk_registry() {
    _repo="$(xfree_apk_registry_repo_file)"
    _pub="$(xfree_apk_registry_pubkey_file)"
    _keys_dir="${ROUTER_APK_KEYS_DIR:-${APK_KEYS_DIR:-/etc/apk/keys}}"
    _repos_dir="${ROUTER_APK_REPOS_DIR:-${APK_REPOS_DIR:-/etc/apk/repositories.d}}"
    _feed_url=""
    _pub_url=""
    _pub_tmp=""
    _had=0
  
    command -v apk >/dev/null 2>&1 || return 1
  
    xfree_apk_feed_seed_source || true
  
    if xfree_apk_registry_configured; then
      XFREE_APK_REGISTRY_STATUS=configured
      return 0
    fi
  
    _feed_url="$(xfree_apk_feed_active_url)" || return 1
    _pub_url="$(xfree_apk_registry_pubkey_url)" || return 1
  
    mkdir -p "$_keys_dir" "$_repos_dir" || return 1
  
    _pub_tmp="${TMPDIR:-/tmp}/xfree-registry-pubkey.$$"
    if ! xfree_apk_registry_https_fetch "$_pub_tmp" "$_pub_url"; then
      rm -f "$_pub_tmp" 2>/dev/null || true
      if command -v warn >/dev/null 2>&1; then
        warn "Не удалось скачать pubkey apk: $_pub_url"
        if xfree_apk_registry_factory_looks_like_tar_url; then
          warn "XFREE_FACTORY_PUBLIC_BASE совпадает с tar share (XFREE_UPDATE_URL); ключ на factory share"
        fi
      fi
      xfree_apk_feed_load_state
      _default_factory="$(xfree_apk_registry_default_factory_base)"
      _default_pub="${_default_factory%/}/${XFREE_APK_PUBKEY_NAME:-${PUBKEY_BASENAME:-xfree-toolbox.pub}}"
      if [ "${XFREE_APK_FEED_SOURCE:-}" = github ]; then
        rm -f "$_pub_tmp" 2>/dev/null || true
        return 1
      fi
      if [ "$_pub_url" != "$_default_pub" ] \
        && xfree_apk_registry_https_fetch "$_pub_tmp" "$_default_pub"; then
        if command -v warn >/dev/null 2>&1; then
          warn "Pubkey взят с factory по умолчанию: $_default_pub"
          warn "Исправьте XFREE_FACTORY_PUBLIC_BASE в config.sh (не подставляйте XFREE_UPDATE_URL)"
        fi
        FACTORY_PUBLIC_BASE="$_default_factory"
        XFREE_FACTORY_PUBLIC_BASE="$_default_factory"
      else
        rm -f "$_pub_tmp" 2>/dev/null || true
        return 1
      fi
    fi
  
    cp "$_pub_tmp" "$_pub" || {
      rm -f "$_pub_tmp" 2>/dev/null || true
      return 1
    }
    chmod 0644 "$_pub" 2>/dev/null || true
    rm -f "$_pub_tmp" 2>/dev/null || true
  
    printf '%s\n' "$_feed_url" >"$_repo" || return 1
    chmod 0644 "$_repo" 2>/dev/null || true
  
    XFREE_APK_REGISTRY_STATUS=auto-configured
    if command -v info >/dev/null 2>&1; then
      info "Apk registry: $_pub, $_repo"
    fi
    return 0
  }

}

xfree_load_install_channel_lib() {
  xfree_load_cloud_embedded_libs
}

xfree_load_apk_registry_lib() {
  xfree_load_cloud_embedded_libs
}

xfree_install_channel() {
  xfree_load_install_channel_lib
  xfree_resolve_update_channel
}

# Установка из распакованного tar: bootstrap (копия в TARGET_DIR) или self-update (swap с backup).
_tar_bootstrap_extra_flags() {
  if [ "$RESTORE_ACTIVE_PROFILE_FROM_STATE" -eq 1 ] || [ -d "$STATE_ROOT" ]; then
    printf '%s' '--restore-active-profile-from-state'
  fi
}

run_tar_install_from_tree() {
  _src="$1"
  _bootstrap="$_src/system/install-bootstrap.sh"
  _su="$_src/system/self-update.sh"
  _extra="$(_tar_bootstrap_extra_flags)"

  if [ -n "${XFREE_DOWNLOAD_ETAG:-}" ]; then
    export XFREE_INSTALLED_TAR_ETAG="$XFREE_DOWNLOAD_ETAG"
    export XFREE_INSTALLED_TAR_LASTMOD="${XFREE_DOWNLOAD_LASTMOD:-}"
  fi

  if [ ! -f "$TARGET_DIR/menu.sh" ]; then
    if xfree_apk_installed; then
      die "Пакет $APK_PKG_NAME уже в apk, но $TARGET_DIR/menu.sh отсутствует. На OpenWrt 25+ запустите install-from-cloud без --use-tar (канал apk) или: apk upgrade $APK_PKG_NAME"
    fi
    info "Установка с нуля → install-bootstrap.sh"
    [ -f "$_bootstrap" ] || die "В архиве нет system/install-bootstrap.sh"
    # shellcheck disable=SC2086
    sh "$_bootstrap" --source-dir "$_src" --preserve-profiles $_extra
    return 0
  fi

  if [ "$PRESERVE_PROFILES" -eq 1 ]; then
    info "Обновление → self-update.sh (profiles сохранены)"
    [ -f "$_su" ] || die "В архиве нет system/self-update.sh"
    sh "$_su" --source-dir "$_src" --preserve-profiles
    return 0
  fi

  info "Переустановка → install-bootstrap.sh"
  [ -f "$_bootstrap" ] || die "В архиве нет system/install-bootstrap.sh"
  # shellcheck disable=SC2086
  sh "$_bootstrap" --source-dir "$_src" --preserve-profiles $_extra
}

xfree_apk_installed() {
  if command -v owrt_apk_package_installed >/dev/null 2>&1; then
    owrt_apk_package_installed
    return $?
  fi
  command -v apk >/dev/null 2>&1 || return 1
  apk info -e "$APK_PKG_NAME" >/dev/null 2>&1
}

xfree_apk_sanitize_world_qpins() {
  _world="/etc/apk/world"
  _tmp="/tmp/xfree-apk-world.$$"
  _backup=""

  [ -f "$_world" ] || return 0

  sed -E 's/><Q[[:alnum:]+\/=._-]+$//' "$_world" >"$_tmp" 2>/dev/null || {
    rm -f "$_tmp" 2>/dev/null || true
    warn "Не удалось проверить /etc/apk/world на устаревшие Q-пины"
    return 0
  }

  if cmp -s "$_world" "$_tmp" 2>/dev/null; then
    rm -f "$_tmp" 2>/dev/null || true
    return 0
  fi

  _backup="${_world}.xfree-bak.$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
  cp "$_world" "$_backup" 2>/dev/null || _backup=""
  mv "$_tmp" "$_world"

  if [ -n "$_backup" ]; then
    info "apk world: удалены устаревшие Q-пины (backup: $_backup)"
  else
    info "apk world: удалены устаревшие Q-пины"
  fi
}

xfree_apk_run_pkg_op() {
  _mode="$1"
  _tmp_log="/tmp/xfree-apk-${_mode}.$$"
  _rc=0

  if [ "$_mode" = "upgrade" ]; then
    apk upgrade "$APK_PKG_NAME" 2>&1 | tee "$_tmp_log" || _rc=$?
  else
    apk add "$APK_PKG_NAME" 2>&1 | tee "$_tmp_log" || _rc=$?
  fi

  if [ "$_rc" -eq 0 ]; then
    rm -f "$_tmp_log" 2>/dev/null || true
    return 0
  fi

  if xfree_apk_installed && grep -q "The following packages are no longer available from a repository:" "$_tmp_log" 2>/dev/null; then
    warn "apk $_mode вернул ошибку из-за недоступных world-пакетов, но $APK_PKG_NAME установлен; продолжаю"
    rm -f "$_tmp_log" 2>/dev/null || true
    return 0
  fi

  rm -f "$_tmp_log" 2>/dev/null || true
  return "$_rc"
}

# Только проверка обновления (exit 0 — нет, 10 — есть). Для system/menu.gen.sh.
run_apk_check_only() {
  command -v apk >/dev/null 2>&1 || die "apk не найден (OpenWrt 25+)"

  if command -v xfree_ensure_apk_registry >/dev/null 2>&1; then
    xfree_ensure_apk_registry || {
      warn "Не удалось настроить apk registry"
      return 1
    }
  elif [ ! -f "$APK_REPOS_DIR/$APK_REPO_FILE" ]; then
    warn "Реестр apk не настроен ($APK_REPOS_DIR/$APK_REPO_FILE)"
    return 1
  fi

  [ "$SILENT" -eq 0 ] && info "Проверка обновления apk ($APK_PKG_NAME)"
  apk update --force-missing-repositories 2>&1 || warn "apk update: см. UNTRUSTED / реестр"

  printf '[*] Channel         : apk\n'
  if command -v xfree_apk_print_feed_check >/dev/null 2>&1; then
    xfree_apk_print_feed_check "$APK_PKG_NAME" || return 1
  else
    warn "lib/install-channel.sh без xfree_apk_print_feed_check"
    return 1
  fi

  case "${XFREE_APK_CHECK_ACTION:-none}" in
    add)
      success "Пакет apk не установлен — в фиде есть $APK_PKG_NAME (apk add, дальше apk upgrade)"
      exit 10
      ;;
    upgrade)
      success "Доступно обновление (apk)"
      exit 10
      ;;
    *)
      success "Обновлений apk нет"
      exit 0
      ;;
  esac
}

should_use_apk_check_only() {
  [ "$CHANNEL" = apk ] || return 1
  [ "$FORCE_CHANNEL" != tar ] || return 1
  return 0
}

xfree_https_fetch() {
  _dst="$1"
  _url="$2"
  _wget_extra="${3:-}"

  if command -v curl >/dev/null 2>&1; then
    if curl --http1.1 -fL --connect-timeout 25 --max-time 180 -o "$_dst" "$_url" 2>/dev/null \
      && [ -s "$_dst" ]; then
      return 0
    fi
    warn "curl: повтор с --insecure (нет доверенных CA на роутере)"
    curl --http1.1 -fL -k --connect-timeout 25 --max-time 180 -o "$_dst" "$_url" \
      && [ -s "$_dst" ]
    return $?
  fi

  if command -v wget >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    if wget -T 25 $_wget_extra -O "$_dst" "$_url" 2>/dev/null && [ -s "$_dst" ]; then
      return 0
    fi
    warn "wget: повтор с --no-check-certificate (нет доверенных CA на роутере)"
    # shellcheck disable=SC2086
    wget --no-check-certificate -T 25 $_wget_extra -O "$_dst" "$_url" \
      && [ -s "$_dst" ]
    return $?
  fi

  die "Нужен curl или wget"
}

xfree_wget() {
  _dst="$1"
  _url="$2"
  info "wget → $_dst"
  xfree_https_fetch "$_dst" "$_url" || die "wget не удался: $_url"
}

# Скачать tar. ETag из заголовков — если клиент умеет (curl -D / GNU wget -S);
# на OpenWrt wget = uclient-fetch, -S нет — обычный wget, метку доберёт PROPFIND.
xfree_install_download_tar() {
  _dst="$1"
  _url="$2"

  XFREE_DOWNLOAD_ETAG=""
  XFREE_DOWNLOAD_LASTMOD=""

  if command -v xfree_download_tar_archive >/dev/null 2>&1; then
    if xfree_download_tar_archive "$_dst" "$_url"; then
      [ -n "${XFREE_DOWNLOAD_ETAG:-}" ] && info "Tar ETag (download): $XFREE_DOWNLOAD_ETAG"
      return 0
    fi
    warn "Скачивание с захватом ETag (lib) не удалось — пробую обычный wget"
  fi

  xfree_wget "$_dst" "$_url"
}

# После tar payload: записать local ETag (lib из TARGET_DIR или inline fallback).
xfree_install_persist_tar_etag() {
  _etag="${1:-${XFREE_DOWNLOAD_ETAG:-}}"
  _lastmod="${2:-${XFREE_DOWNLOAD_LASTMOD:-}}"

  [ -n "$_etag" ] || {
    _have=""
    if [ -f "$TARGET_DIR/.update-etag" ]; then
      _have="$(head -n1 "$TARGET_DIR/.update-etag" | tr -d '\r\n')"
    fi
    if [ -n "$_have" ]; then
      return 0
    fi
    if command -v xfree_stamp_installed_tar_etag >/dev/null 2>&1; then
      xfree_stamp_installed_tar_etag "$TARGET_DIR" "${UPDATE_URL:-}"
      return 0
    fi
    warn "local ETag не сохранён: ETag не пришёл в заголовках скачивания tar"
    return 0
  }

  if command -v xfree_update_etag_load_lib >/dev/null 2>&1; then
    xfree_update_etag_load_lib "$TARGET_DIR" || true
  elif [ -f "$TARGET_DIR/lib/update-etag.sh" ]; then
    # shellcheck disable=SC1090
    . "$TARGET_DIR/lib/update-etag.sh"
  fi

  if command -v xfree_stamp_installed_tar_etag >/dev/null 2>&1; then
    xfree_stamp_installed_tar_etag "$TARGET_DIR" "$UPDATE_URL" "$_etag" "$_lastmod"
    return 0
  fi

  mkdir -p "$TARGET_DIR" 2>/dev/null || true
  printf '%s\n' "$_etag" > "$TARGET_DIR/.update-etag"
  if [ -n "$_lastmod" ]; then
    printf '%s\n' "$_lastmod" > "$TARGET_DIR/.update-lastmodified"
  fi
  info "Сохранён local ETag: $_etag"
}

trim_trailing_slash() {
  _v="$1"
  while [ -n "$_v" ]; do
    case "$_v" in
      */) _v="${_v%/}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$_v"
}

xfree_install_script_public_url() {
  if command -v xfree_apk_feed_install_url >/dev/null 2>&1; then
    _u="$(xfree_apk_feed_install_url 2>/dev/null || true)"
    if [ -n "$_u" ]; then
      printf '%s\n' "$_u"
      return 0
    fi
  fi
  _base="$(trim_trailing_slash "${FACTORY_PUBLIC_BASE:-}")"
  [ -n "$_base" ] || _base="$(trim_trailing_slash "${FEED_BASE:-}")"
  printf '%s/%s\n' "$_base" "$INSTALL_SCRIPT_NAME"
}

CHANNEL=""
FORCE_CHANNEL=""
RUN_REGISTRY=-1
RUN_TAR=0
RUN_APK_PAYLOAD=0
RUN_APK_UPDATE=-1
OPEN_MENU=0
PRESERVE_PROFILES=1
RESTORE_ACTIVE_PROFILE_FROM_STATE=0
REGISTRY_ONLY=0
CHECK_ONLY=0
SKIP_SELF_UPDATE=0
SILENT=0
PUB_KEY_URL=""
TAR_URL_EXPLICIT=0
XFREE_APK_FEED_SOURCE_EXPLICIT=0
APPLY_TEMPLATE_NAME=""
APPLY_PROFILE_NAME=""
APPLY_MODE="instantiate"
FORCE=0
SKIP_INSTANTIATE=0
# Фаза для trap (apk / apply-template / …).
_xfree_install_failed_phase=""

set_active_profile_in_config() {
  _profile_name="$1"
  if command -v common_set_active_profile_in_config >/dev/null 2>&1; then
    common_set_active_profile_in_config "$TARGET_DIR" "$_profile_name" || return 1
  else
    _profile_dir_rel="profiles/$_profile_name"
    _tmp_file="$TARGET_DIR/config.sh.tmp.$$"
    _config_file="$TARGET_DIR/config.sh"

    if [ -f "$_config_file" ]; then
      awk -v profile="$_profile_name" -v profile_dir="$_profile_dir_rel" '
        BEGIN { got_profile=0; got_dir=0 }
        /^[[:space:]]*#/ { print; next }
        index($0, "XFREE_PROFILE_DIR") > 0 {
          if (got_dir == 0) {
            print "XFREE_PROFILE_DIR=\047" profile_dir "\047"
            got_dir=1
          }
          next
        }
        index($0, "XFREE_PROFILE") > 0 {
          if (got_profile == 0) {
            print "XFREE_PROFILE='\''" profile "'\''"
            got_profile=1
          }
          next
        }
        { print }
        END {
          if (got_profile == 0) {
            print "XFREE_PROFILE='\''" profile "'\''"
          }
          if (got_dir == 0) {
            print "XFREE_PROFILE_DIR=\047" profile_dir "\047"
          }
        }
      ' "$_config_file" >"$_tmp_file"
    else
      {
        printf "XFREE_PROFILE='%s'\n" "$_profile_name"
        printf "XFREE_PROFILE_DIR='%s'\n" "$_profile_dir_rel"
      } >"$_tmp_file"
    fi
    mv "$_tmp_file" "$_config_file"
  fi
  # Drop stale session values from early load_base_config (`:=` default).
  if command -v common_profile_env_clear_overrides >/dev/null 2>&1; then
    common_profile_env_clear_overrides
  else
    unset PROFILE_DIR XFREE_PROFILE XFREE_PROFILE_DIR
  fi
  XFREE_PROFILE="$_profile_name"
  XFREE_PROFILE_DIR="profiles/$_profile_name"
  export XFREE_PROFILE XFREE_PROFILE_DIR
}

xfree_read_template_ref_from_meta() {
  _meta="$1"
  [ -f "$_meta" ] || return 1
  awk -F= '
    /^[[:space:]]*TEMPLATE_REF[[:space:]]*=/ {
      sub(/^[[:space:]]*TEMPLATE_REF[[:space:]]*=[[:space:]]*/, "", $0)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      gsub(/^"|"$/, "", $0)
      gsub(/^'\''|'\''$/, "", $0)
      print
      exit
    }
  ' "$_meta" 2>/dev/null
}

# Готовый materialized-профиль (EXPORT-META + iface-routing).
xfree_profile_dir_is_materialized() {
  _pd="$1"
  [ -d "$_pd" ] || return 1
  [ -f "$_pd/EXPORT-META.txt" ] || return 1
  [ -d "$_pd/iface-routing" ] || return 1
  return 0
}

# --apply-mode sync: копирование только списков (не полный шаблон), затем тот же apply с prepare.
xfree_resolve_apply_sync_defaults() {
  _root="$TARGET_DIR"
  if [ ! -f "$_root/config.sh" ] && [ -f "$ROOT_DIR/config.sh" ]; then
    _root="$ROOT_DIR"
  fi
  [ -f "$_root/lib/common.sh" ] || die "--apply-mode sync: toolbox не установлен (нет lib/common.sh в $_root)"

  if [ -z "$APPLY_PROFILE_NAME" ]; then
    APPLY_PROFILE_NAME="$(common_active_profile_name "$_root" 2>/dev/null || true)"
    [ -n "$APPLY_PROFILE_NAME" ] || die "--apply-mode sync: активный профиль не найден в config.sh"
  fi

  case "$APPLY_PROFILE_NAME" in
    *[!A-Za-z0-9._-]*|'') die "Некорректное имя профиля: $APPLY_PROFILE_NAME" ;;
  esac

  _profile_dir="$(common_profile_dir "$_root" "$APPLY_PROFILE_NAME" 2>/dev/null || true)"
  [ -n "$_profile_dir" ] && [ -d "$_profile_dir" ] \
    || die "--apply-mode sync: профиль '$APPLY_PROFILE_NAME' не найден: $_profile_dir"

  if [ -z "$APPLY_TEMPLATE_NAME" ]; then
    _meta="$_profile_dir/EXPORT-META.txt"
    [ -f "$_meta" ] || die "--apply-mode sync: нет EXPORT-META.txt для профиля '$APPLY_PROFILE_NAME'"
    APPLY_TEMPLATE_NAME="$(xfree_read_template_ref_from_meta "$_meta")"
    [ -n "$APPLY_TEMPLATE_NAME" ] \
      || die "--apply-mode sync: TEMPLATE_REF отсутствует в $_meta"
    [ "$SILENT" -eq 0 ] && info "apply sync: шаблон=$APPLY_TEMPLATE_NAME (из EXPORT-META профиля $APPLY_PROFILE_NAME)"
  elif [ "$SILENT" -eq 0 ]; then
    info "apply sync: шаблон=$APPLY_TEMPLATE_NAME, профиль=$APPLY_PROFILE_NAME"
  fi

  case "$APPLY_TEMPLATE_NAME" in
    *[!A-Za-z0-9._-]*|'') die "Некорректное имя шаблона: $APPLY_TEMPLATE_NAME" ;;
  esac
}

# Живой tail лога apply-template до завершения bg-task (как ui_bg_task_follow_log без whiptail).
# После запуска фона всегда: консоль и SSH без TTY.
install_cloud_follow_apply_log() {
  _log="${1:-${XFREE_BG_ROOT:-/tmp/xfree-background-tasks}/apply-template.log}"
  _bg_lib="$TARGET_DIR/lib/background-tasks.sh"
  _bg_root="${XFREE_BG_ROOT:-/tmp/xfree-background-tasks}"
  _pid=""

  if [ -f "$_bg_lib" ]; then
    # shellcheck disable=SC1090
    . "$_bg_lib" 2>/dev/null || true
    export XFREE_TOOLBOX_ROOT="$TARGET_DIR"
    if bg_tasks_is_running 2>/dev/null; then
      _pid="${BG_TASK_PID:-}"
    fi
  fi
  if [ -z "$_pid" ] && [ -f "$_bg_root/pid" ]; then
    _pid="$(cat "$_bg_root/pid" 2>/dev/null || true)"
    case "$_pid" in
      '' | *[!0-9]*) _pid="" ;;
      *)
        kill -0 "$_pid" 2>/dev/null || _pid=""
        ;;
    esac
  fi

  if [ ! -f "$_log" ]; then
    warn "Лог apply-template не найден: $_log"
    return 1
  fi

  if [ -z "$_pid" ]; then
    warn "Фоновая задача apply-template: pid неизвестен; последние строки лога:"
    tail -n 80 "$_log" 2>/dev/null || true
    info "Живой лог: tail -f $_log"
    return 0
  fi

  info "Живой лог apply-template (pid=$_pid). Ctrl+C — только выход из просмотра, задача в фоне продолжится."
  printf '\n' >&2
  tail -n 100 -f "$_log" 2>/dev/null &
  _tail_pid=$!
  _install_cloud_follow_trap() {
    kill "$_tail_pid" 2>/dev/null || true
    wait "$_tail_pid" 2>/dev/null || true
  }
  trap '_install_cloud_follow_trap; exit 130' INT

  while kill -0 "$_pid" 2>/dev/null; do
    sleep 1
  done
  sleep 1
  _install_cloud_follow_trap
  trap - INT

  _status=""
  _last_meta="${XFREE_BG_LAST_META_FILE:-$_bg_root/meta.last}"
  if [ -f "$_last_meta" ]; then
    # shellcheck disable=SC1090
    . "$_last_meta" 2>/dev/null || true
    _status="${STATUS:-}"
  fi
  if [ -n "$_status" ]; then
    if [ "$_status" = "done" ]; then
      success "apply-template завершён (status=$_status)"
      printf '\n--- последние строки лога ---\n'
      tail -n 30 "$_log" 2>/dev/null || true
      return 0
    fi
    warn "apply-template завершён (status=$_status); проверьте хвост лога"
    printf '\n--- последние строки лога ---\n'
    tail -n 30 "$_log" 2>/dev/null || true
    return 1
  fi
  info "apply-template завершён (pid $_pid вышел)"
  printf '\n--- последние строки лога ---\n'
  tail -n 30 "$_log" 2>/dev/null || true
  return 0
}

# Дождаться завершения фонового apply без live-tail (если pid не найден для follow).
install_cloud_wait_apply_done() {
  _bg_lib="$TARGET_DIR/lib/background-tasks.sh"
  _bg_root="${XFREE_BG_ROOT:-/tmp/xfree-background-tasks}"
  _pid=""
  _deadline=$(( $(date +%s 2>/dev/null || echo 0) + 7200 ))

  if [ -f "$_bg_lib" ]; then
    # shellcheck disable=SC1090
    . "$_bg_lib" 2>/dev/null || true
    export XFREE_TOOLBOX_ROOT="$TARGET_DIR"
  fi

  # Brief wait for pid file after launch.
  _i=0
  while [ "$_i" -lt 30 ]; do
    if command -v bg_tasks_is_running >/dev/null 2>&1 && bg_tasks_is_running 2>/dev/null; then
      _pid="${BG_TASK_PID:-}"
      break
    fi
    if [ -f "$_bg_root/pid" ]; then
      _pid="$(cat "$_bg_root/pid" 2>/dev/null || true)"
      case "$_pid" in
        '' | *[!0-9]*) _pid="" ;;
        *)
          kill -0 "$_pid" 2>/dev/null && break
          _pid=""
          ;;
      esac
    fi
    sleep 1
    _i=$((_i + 1))
  done

  [ -n "$_pid" ] || {
    warn "Не удалось дождаться pid apply-template"
    return 1
  }

  info "Ожидание apply-template (pid=$_pid)…"
  while kill -0 "$_pid" 2>/dev/null; do
    _now="$(date +%s 2>/dev/null || echo 0)"
    if [ "$_now" -gt 0 ] && [ "$_now" -gt "$_deadline" ]; then
      warn "Таймаут ожидания apply-template"
      return 1
    fi
    sleep 2
  done

  _status=""
  _last_meta="${XFREE_BG_LAST_META_FILE:-$_bg_root/meta.last}"
  if [ -f "$_last_meta" ]; then
    # shellcheck disable=SC1090
    . "$_last_meta" 2>/dev/null || true
    _status="${STATUS:-}"
  fi
  if [ "$_status" = "done" ] || [ -z "$_status" ]; then
    [ "$_status" = "done" ] && success "apply-template завершён (status=done)"
    return 0
  fi
  warn "apply-template завершён (status=$_status)"
  return 1
}

# Belt-and-suspenders: ensure applied-profile.env matches the profile we just applied
# (covers older apply-template.sh on router that never wrote the marker).
install_cloud_mark_applied_profile() {
  _name="${1:-}"
  [ -n "$_name" ] || return 0
  if command -v common_write_applied_profile >/dev/null 2>&1; then
    common_write_applied_profile "$_name" || \
      warn "Не удалось записать applied-profile.env ($_name)"
    return 0
  fi
  _state="${XFREE_STATE_ROOT:-/etc/xfree-toolbox}"
  mkdir -p "$_state" 2>/dev/null || true
  {
    printf '%s\n' "# Last profile applied to the system (install-from-cloud)."
    printf '%s\n' "XFREE_APPLIED_PROFILE=$_name"
    printf '%s\n' "XFREE_APPLIED_AT_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || true)"
  } >"$_state/applied-profile.env.tmp" 2>/dev/null || return 0
  mv -f "$_state/applied-profile.env.tmp" "$_state/applied-profile.env" 2>/dev/null || true
}

# Копия из пакета (не factory /tmp): SCRIPT_DIR == $TARGET_DIR/system.
xfree_running_installed_copy() {
  [ -n "$TARGET_DIR" ] && [ -d "$TARGET_DIR/system" ] || return 1
  _tb_system="$(CDPATH= cd -- "$TARGET_DIR/system" && pwd -P)" || return 1
  [ "$SCRIPT_DIR" = "$_tb_system" ]
}

# Factory wget: после feed+пакета всегда передать управление установленному toolbox (тот же argv).
xfree_exec_installed_toolbox() {
  _why="${1:-}"
  _tb_ifc="$TARGET_DIR/system/install-from-cloud.sh"
  if xfree_running_installed_copy; then
    return 0
  fi
  [ -f "$_tb_ifc" ] || die "toolbox не установлен: нет $_tb_ifc (сначала установка пакета)"
  [ "$SILENT" -eq 0 ] && info "передача управления toolbox${_why:+ ($_why)} → $_tb_ifc"
  export XFREE_INSTALL_HANDED_OFF=1
  trap - EXIT
  _xfree_install_cleanup_armed=0
  # shellcheck disable=SC2086
  eval "exec sh \"$_tb_ifc\" $XFREE_HANDOFF_ARGS"
}

# На установленном toolbox файл пайплайна может быть старше функции apply.
xfree_pipeline_defines_apply() {
  _f="${1:-}"
  [ -n "$_f" ] && [ -f "$_f" ] || return 1
  grep -q 'templates_apply_update_pipeline()' "$_f"
}

xfree_refresh_toolbox_for_pipeline() {
  [ "${SKIP_SELF_UPDATE:-0}" = "1" ] && return 1
  _su="$TARGET_DIR/system/self-update.sh"
  [ -f "$_su" ] || return 1
  info "toolbox без канонического пайплайна — обновляю пакет…"
  sh "$_su" --preserve-profiles
}

# apply-template через lib/bg-task-run.sh (LED + lock), как в templates/menu.sh.
launch_apply_template_background() {
  _apply="$1"
  _profile_dir="$2"
  _profile_name="${3:-$(basename -- "$_profile_dir")}"
  shift 3 2>/dev/null || true
  _apply_extra="$*"
  _bg_run="$TARGET_DIR/lib/bg-task-run.sh"
  _bg_lib="$TARGET_DIR/lib/background-tasks.sh"
  _log="${XFREE_BG_ROOT:-/tmp/xfree-background-tasks}/apply-template.log"
  _launch_log="/tmp/xfree-install-cloud-apply-launch.log"

  [ -f "$_bg_run" ] || die "Не найден lib/bg-task-run.sh: $_bg_run"
  chmod +x "$_bg_run" "$_apply" 2>/dev/null || true

  if [ -f "$_bg_lib" ]; then
    if (
      # shellcheck disable=SC1090
      . "$_bg_lib" 2>/dev/null
      export XFREE_TOOLBOX_ROOT="$TARGET_DIR"
      bg_tasks_is_running
    ); then
      warn "Фоновая задача уже выполняется; apply-template не запущен (см. ${XFREE_BG_ROOT:-/tmp/xfree-background-tasks})"
      return 1
    fi
  fi

  info "apply-template в фоне (LED); лог: $_log"
  (
    # Do not inherit stale XFREE_PROFILE=default from install-from-cloud load_base_config.
    unset XFREE_PROFILE XFREE_PROFILE_DIR PROFILE_DIR
    export XFREE_PROFILE="$_profile_name"
    export XFREE_PROFILE_DIR="profiles/$_profile_name"
    export PROFILE_DIR="$_profile_dir"
    export XFREE_APPLY_PROFILE_DIR="$_profile_dir"
    export XFREE_TOOLBOX_ROOT="$TARGET_DIR"
    # shellcheck disable=SC2086
    sh "$_bg_run" apply-template --log "$_log" -- sh "$_apply" $_apply_extra
  ) >>"$_launch_log" 2>&1 &

  sleep 1
  if [ -f "$_bg_lib" ]; then
    if (
      # shellcheck disable=SC1090
      . "$_bg_lib" 2>/dev/null
      export XFREE_TOOLBOX_ROOT="$TARGET_DIR"
      bg_tasks_is_running
    ); then
      _pid="$(cat "${XFREE_BG_ROOT:-/tmp/xfree-background-tasks}/pid" 2>/dev/null || true)"
      info "apply-template pid=${_pid:-?}"
      return 0
    fi
  fi
  warn "apply-template мог не стартовать; см. $_launch_log и $_log"
  return 1
}

# jq, unzip, curl, whiptail, … — до menu.sh / prepare-template (как при старте menu.sh).
xfree_ensure_base_packages_for_toolbox() {
  _root="${1:-$TARGET_DIR}"
  _ensure="$_root/system/ensure-base-packages.sh"
  if [ ! -f "$_ensure" ]; then
    warn "Пропуск базовых пакетов: не найден $_ensure"
    return 0
  fi
  chmod +x "$_ensure" 2>/dev/null || true
  [ "$SILENT" -eq 0 ] && info "Проверка базовых пакетов OpenWrt…"
  _flags="--yes --root $_root"
  [ "$SILENT" -eq 1 ] && _flags="$_flags --silent"
  # shellcheck disable=SC2086
  sh "$_ensure" $_flags || die "ensure-base-packages не удался (см. install.sh выше)"
}

# Как install-bootstrap / self-update / postinst: WPS hotplug после установки payload.
xfree_ensure_wps_button_hooks() {
  _root="${1:-$TARGET_DIR}"
  _hooks="$_root/system/hardware/install-button-hooks.sh"

  if [ ! -f "$_hooks" ]; then
    warn "Пропуск WPS hotplug: не найден $_hooks"
    return 0
  fi
  chmod +x "$_hooks" 2>/dev/null || true
  [ "$SILENT" -eq 0 ] && info "WPS hotplug: установка /etc/hotplug.d/button/90-xfree-wps-sync-apply…"
  if sh "$_hooks" --ensure --quiet "$_root"; then
    [ "$SILENT" -eq 0 ] && success "WPS hotplug установлен"
    return 0
  fi
  warn "WPS hotplug: install-button-hooks --install завершился с ошибкой (включите вручную: Система → WPS)"
  return 1
}

# xft / usb-modem-power-cycle в PATH (apk postinst делает то же; apply-only и tar — нет).
xfree_ensure_router_commands() {
  _root="${1:-$TARGET_DIR}"
  _cmd="$_root/system/router-commands.sh"
  if [ ! -f "$_cmd" ]; then
    warn "Пропуск команд PATH: не найден $_cmd"
    return 0
  fi
  chmod +x "$_cmd" 2>/dev/null || true
  if [ -f "$_root/system/router-commands-lib.sh" ]; then
    # shellcheck disable=SC1091
    . "$_root/system/router-commands-lib.sh"
    if router_cmd_ensure_all "$_root" "${XFREE_LAUNCHER_NAME:-xft}"; then
      [ "$SILENT" -eq 0 ] && success "Команды toolbox в PATH"
      return 0
    fi
  fi
  [ "$SILENT" -eq 0 ] && info "Команды toolbox: xft, usb-modem-power-cycle…"
  if sh "$_cmd" --install; then
    [ "$SILENT" -eq 0 ] && success "Команды toolbox в PATH"
    return 0
  fi
  warn "Не удалось установить xft в PATH (Система → установить команды или: ln -sfn $_root/menu.sh /usr/bin/xft)"
  return 1
}

# Перед apply на установленном toolbox: self-update (apk/tar), как в меню «Обновить и применить» / WPS.
# Factory /tmp не вызывает apply сам: после пакета exec установленной копии.
xfree_upgrade_toolbox_if_needed() {
  _root="${1:-$TARGET_DIR}"
  if [ "${SKIP_SELF_UPDATE:-0}" = "1" ]; then
    [ "$SILENT" -eq 0 ] && info "Пропуск self-update (--no-self-update)"
    return 0
  fi
  if [ "${XFREE_PIPELINE_UPGRADED:-0}" = "1" ]; then
    [ "$SILENT" -eq 0 ] && info "Пропуск self-update: уже выполнен в pipeline"
    return 0
  fi
  _su="$_root/system/self-update.sh"
  [ -f "$_su" ] || return 0

  _su_check_args="--silent --check-only --preserve-profiles"
  _su_upgrade_args="--silent --preserve-profiles"
  if [ "$FORCE_CHANNEL" = "tar" ]; then
    _su_check_args="$_su_check_args --use-tar"
    _su_upgrade_args="$_su_upgrade_args --use-tar"
  fi

  _rc=0
  # shellcheck disable=SC2086
  sh "$_su" $_su_check_args >/dev/null 2>&1 || _rc=$?
  case "$_rc" in
    0) return 0 ;;
    10) ;;
    *)
      warn "self-update --check-only: exit $_rc (продолжаем без upgrade)"
      return 0
      ;;
  esac

  [ "$SILENT" -eq 0 ] && info "Доступно обновление toolbox — self-update"
  # shellcheck disable=SC2086
  sh "$_su" $_su_upgrade_args || die "self-update не удался"
}

# APPLY_ONLY + tar: self-update --check-only (ETag). Exit 10 → нужен tar payload в этом вызове.
xfree_apply_only_tar_update_available() {
  _su="${1:-$TARGET_DIR}/system/self-update.sh"
  [ -f "$_su" ] || return 1
  _args="--silent --check-only --preserve-profiles"
  [ "$FORCE_CHANNEL" = "tar" ] && _args="$_args --use-tar"
  _rc=0
  # shellcheck disable=SC2086
  sh "$_su" $_args >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 10 ]
}

usage() {
  _install_url="$(xfree_install_script_public_url)"
  cat <<EOF
Usage: $(basename "$0") [options]

Автовыбор канала по версии OpenWrt (см. system/install-channel.sh):
  25+ (apk)  — реестр (ключ + feed), затем apk add/upgrade $APK_PKG_NAME
  24.x (tar) — wget tar + install-bootstrap / self-update (те же флаги, без отдельного one-liner)

Options:
  --feed-base <url>     Папка apk-фида Nextcloud (…/packages.adb)
  --factory-base <url>  Папка factory (…/xfree-toolbox.pub + install-from-cloud.sh)
  --source cloud|github Источник фида (по умолчанию: зеркало установщика; потом /etc/xfree-toolbox/apk-feed.env)
  --tar-url <url>       URL tar.gz
  --pub-key-url <url>   Ключ с другого URL
  --registry-only       Только реестр apk (OpenWrt 25+)
  --use-tar             На 25+ принудительно tar вместо apk-пакета (в т.ч. с --apply-template на уже установленном toolbox)
  --apk-only            Только реестр + apk (без tar)
  --no-registry         Не настраивать /etc/apk
  --no-self-update      С --apply-template: не apk add/upgrade и не качать cloud tar (локальный deploy)
  --no-apk-update       Без apk update
  --replace-profiles    Устарел: profiles/ не перезаписываются из архива
  --restore-active-profile-from-state  После bootstrap — restore-profile-from-state.sh
  --check-only          Только проверить (tar: ETag; apk: upgrade или apk add если пакет ещё не в world), exit 10 если есть обновление
  --silent              Меньше служебных сообщений (для menu)
  --apply-template <id> Создать/обновить profile из profile-templates/<id> и применить.
                        id: default (Warp), default-with-proton (Warp+Proton),
                        default-with-proton-ai (все AI через Proton).
                        wget /tmp: поставить/обновить пакет, затем exec копии из toolbox.
                        В пакете — тот же пайплайн, что меню «Обновить» / «Пересоздать»:
                        upgrade → upstream → copy → apply-template (prepare один раз).
  --apply-profile <name> Имя профиля (по умолчанию: для sync — активный из config.sh; для instantiate — имя шаблона)
  --apply-mode <mode>   instantiate (default) | sync
                         без --force: instantiate = создать (copy, если профиля ещё нет)
                         sync = «Обновить и применить» (только списки, живой config/)
                         sync без --apply-template: шаблон из TEMPLATE_REF активного профиля (EXPORT-META.txt)
                         sync с --apply-template: новый шаблон → профиль; TEMPLATE_REF в EXPORT-META обновится
  --force               «Пересоздать и применить»: instantiate --force, шаблон целиком.
                        Как пункт меню «Пересоздать». С --apply-mode sync не сочетается (берётся instantiate).
  --menu                Базовые пакеты, затем menu.sh (нужен ssh -t)
  -h, --help

Установка с нуля (OpenWrt 24.x и 25+; URL в одну строку, без переносов):
  wget -O /tmp/$INSTALL_SCRIPT_NAME "$_install_url"
  chmod +x /tmp/$INSTALL_SCRIPT_NAME
  sh /tmp/$INSTALL_SCRIPT_NAME --menu
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tar-url)
      shift
      [ "$#" -gt 0 ] || die "--tar-url требует URL"
      UPDATE_URL="$1"
      TAR_URL_EXPLICIT=1
      ;;
    --tar-url=*)
      UPDATE_URL="${1#*=}"
      TAR_URL_EXPLICIT=1
      ;;
    --source)
      shift
      [ "$#" -gt 0 ] || die "--source требует cloud или github"
      case "$1" in
        cloud|github) XFREE_APK_FEED_SOURCE="$1" ;;
        *) die "--source: ожидается cloud или github" ;;
      esac
      XFREE_APK_FEED_SOURCE_EXPLICIT=1
      ;;
    --source=*)
      case "${1#*=}" in
        cloud|github) XFREE_APK_FEED_SOURCE="${1#*=}" ;;
        *) die "--source: ожидается cloud или github" ;;
      esac
      XFREE_APK_FEED_SOURCE_EXPLICIT=1
      ;;
    --feed-base)
      shift
      [ "$#" -gt 0 ] || die "--feed-base требует URL"
      FEED_BASE="$1"
      ;;
    --feed-base=*)
      FEED_BASE="${1#*=}"
      ;;
    --pub-key-url)
      shift
      [ "$#" -gt 0 ] || die "--pub-key-url требует URL"
      PUB_KEY_URL="$1"
      ;;
    --pub-key-url=*)
      PUB_KEY_URL="${1#*=}"
      ;;
    --registry-only) REGISTRY_ONLY=1 ;;
    --use-tar) FORCE_CHANNEL=tar ;;
    --apk-only) FORCE_CHANNEL=apk ;;
    --no-registry) RUN_REGISTRY=0 ;;
    --no-self-update)
      SKIP_SELF_UPDATE=1
      RUN_TAR=0
      RUN_APK_PAYLOAD=0
      ;;
    --no-apk-update) RUN_APK_UPDATE=0 ;;
    --replace-profiles)
      echo "[!] --replace-profiles устарел: profiles/ не перезаписываются из архива." >&2
      PRESERVE_PROFILES=1
      ;;
    --preserve-profiles) PRESERVE_PROFILES=1 ;;
    --restore-active-profile-from-state) RESTORE_ACTIVE_PROFILE_FROM_STATE=1 ;;
    --check-only) CHECK_ONLY=1 ;;
    --silent) SILENT=1 ;;
    --apply-template)
      shift
      [ "$#" -gt 0 ] || die "--apply-template требует имя шаблона"
      APPLY_TEMPLATE_NAME="$1"
      ;;
    --apply-template=*)
      APPLY_TEMPLATE_NAME="${1#*=}"
      ;;
    --apply-profile)
      shift
      [ "$#" -gt 0 ] || die "--apply-profile требует имя профиля"
      APPLY_PROFILE_NAME="$1"
      ;;
    --apply-profile=*)
      APPLY_PROFILE_NAME="${1#*=}"
      ;;
    --apply-mode)
      shift
      [ "$#" -gt 0 ] || die "--apply-mode требует значение: instantiate|sync"
      APPLY_MODE="$1"
      ;;
    --apply-mode=*)
      APPLY_MODE="${1#*=}"
      ;;
    --force) FORCE=1 ;;
    --follow-log | --no-follow-log)
      # Совместимость: лог apply всегда на экран после старта фона.
      ;;
    --menu) OPEN_MENU=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "Неизвестный аргумент: $1"
      ;;
  esac
  shift || true
done

UPDATE_URL="$(trim_trailing_slash "$UPDATE_URL")"
FEED_BASE="$(trim_trailing_slash "$FEED_BASE")"

# --force = меню «Пересоздать и применить» (instantiate --force), не sync.
if [ "$FORCE" -eq 1 ] && [ -n "$APPLY_TEMPLATE_NAME" ]; then
  if [ "$APPLY_MODE" = "sync" ]; then
    warn "--force: это «Пересоздать и применить» (instantiate --force); --apply-mode sync отключён"
  fi
  APPLY_MODE="instantiate"
fi

if [ "$APPLY_MODE" = "sync" ]; then
  xfree_resolve_apply_sync_defaults
fi

if [ -n "$APPLY_TEMPLATE_NAME" ]; then
  case "$APPLY_TEMPLATE_NAME" in
    *[!A-Za-z0-9._-]*|'')
      die "Некорректное имя шаблона для --apply-template: $APPLY_TEMPLATE_NAME"
      ;;
  esac
  if [ -z "$APPLY_PROFILE_NAME" ]; then
    APPLY_PROFILE_NAME="$APPLY_TEMPLATE_NAME"
  fi
  case "$APPLY_PROFILE_NAME" in
    *[!A-Za-z0-9._-]*|'')
      die "Некорректное имя профиля для --apply-profile: $APPLY_PROFILE_NAME"
      ;;
  esac
  [ "$CHECK_ONLY" -eq 0 ] || die "--apply-template несовместим с --check-only"
  [ "$REGISTRY_ONLY" -eq 0 ] || die "--apply-template несовместим с --registry-only"
  case "$APPLY_MODE" in
    instantiate|sync) ;;
    *) die "Некорректный --apply-mode: $APPLY_MODE (ожидается instantiate|sync)" ;;
  esac
else
  [ -z "$APPLY_PROFILE_NAME" ] || die "--apply-profile работает только вместе с --apply-template или --apply-mode sync"
  [ "$APPLY_MODE" = "instantiate" ] || die "--apply-mode sync требует установленный toolbox с активным профилем и EXPORT-META.txt"
  [ "$FORCE" -eq 0 ] || die "--force в этом скрипте работает только вместе с --apply-template"
fi

# APPLY_ONLY только у копии из пакета: factory /tmp должен apk/tar, затем exec toolbox.
# Иначе новый wget вызывает пайплайн в старом дереве (функции нет → not found).
APPLY_ONLY=0
if [ -n "$APPLY_TEMPLATE_NAME" ] && xfree_running_installed_copy; then
  if [ -f "$TARGET_DIR/menu.sh" ] && [ -f "$TARGET_DIR/lib/common.sh" ]; then
    APPLY_ONLY=1
  fi
fi

# Не использовать «A && B || die» — при CHECK_ONLY=1 первая часть ложна и срабатывает die.
if [ "$CHECK_ONLY" -eq 0 ] && [ "$APPLY_ONLY" -eq 0 ] && [ "$SKIP_SELF_UPDATE" -eq 0 ]; then
  command -v wget >/dev/null 2>&1 || die "Нужен wget"
fi

CHANNEL="${FORCE_CHANNEL:-}"
if [ -z "$CHANNEL" ]; then
  if [ "$SKIP_SELF_UPDATE" -eq 1 ]; then
    # Factory --no-self-update: только handoff, канал не нужен (и не тянем lib со старого toolbox).
    CHANNEL=unknown
  else
    CHANNEL="$(xfree_install_channel)"
  fi
fi
_owrt_ver=""
if [ -f /etc/openwrt_release ]; then
  _owrt_ver="$(. /etc/openwrt_release 2>/dev/null && printf '%s %s' "${DISTRIB_ID:-OpenWrt}" "${DISTRIB_RELEASE:-?}")"
elif [ -f /etc/os-release ]; then
  _owrt_ver="$(. /etc/os-release 2>/dev/null && printf '%s %s' "${NAME:-OpenWrt}" "${OPENWRT_VERSION:-${VERSION_ID:-?}}")"
fi
[ "$SILENT" -eq 0 ] && info "xfree-toolbox install-from-cloud"
[ "$SILENT" -eq 0 ] && [ -n "$_owrt_ver" ] && info "OpenWrt: $_owrt_ver — канал: $CHANNEL"

case "$CHANNEL" in
  apk)
    [ "$RUN_REGISTRY" -eq -1 ] && RUN_REGISTRY=1
    if [ "$FORCE_CHANNEL" = "tar" ]; then
      RUN_TAR=1
      RUN_APK_PAYLOAD=0
      RUN_APK_UPDATE=0
    else
      RUN_TAR=0
      RUN_APK_PAYLOAD=1
      [ "$RUN_APK_UPDATE" -eq -1 ] && RUN_APK_UPDATE=1
    fi
    ;;
  tar)
    RUN_REGISTRY=0
    RUN_TAR=1
    RUN_APK_PAYLOAD=0
    RUN_APK_UPDATE=0
    ;;
  unknown)
    if command -v apk >/dev/null 2>&1; then
      warn "Версия OpenWrt не определена — apk найден, используем канал apk"
      RUN_REGISTRY=1
      RUN_TAR=0
      RUN_APK_PAYLOAD=1
      [ "$RUN_APK_UPDATE" -eq -1 ] && RUN_APK_UPDATE=1
    else
      warn "Версия OpenWrt не определена — используем tar"
      RUN_REGISTRY=0
      RUN_TAR=1
      RUN_APK_PAYLOAD=0
      RUN_APK_UPDATE=0
    fi
    ;;
esac

# CHANNEL выше перезаписывает RUN_APK_PAYLOAD; --no-self-update и handoff с factory должны побеждать.
if [ "$SKIP_SELF_UPDATE" -eq 1 ] || [ "${XFREE_INSTALL_HANDED_OFF:-0}" = "1" ]; then
  RUN_REGISTRY=0
  RUN_APK_PAYLOAD=0
  RUN_APK_UPDATE=0
  RUN_TAR=0
  if [ "$SILENT" -eq 0 ] && [ -n "$APPLY_TEMPLATE_NAME" ] && [ "$SKIP_SELF_UPDATE" -eq 1 ]; then
    info "apply-template без self-update (--no-self-update)"
  fi
elif [ "$APPLY_ONLY" -eq 1 ]; then
  RUN_REGISTRY=0
  RUN_APK_PAYLOAD=0
  RUN_APK_UPDATE=0
  if [ "$FORCE_CHANNEL" = "tar" ]; then
    RUN_TAR=1
    [ "$SILENT" -eq 0 ] && info "Toolbox установлен — обновление через tar (--use-tar), затем apply-template"
  elif [ "$CHANNEL" = tar ]; then
    if xfree_apply_only_tar_update_available "$TARGET_DIR/system/self-update.sh"; then
      RUN_TAR=1
      [ "$SILENT" -eq 0 ] && info "Доступно обновление toolbox (tar) — скачиваю архив перед apply-template"
    else
      RUN_TAR=0
      [ "$SILENT" -eq 0 ] && info "Toolbox актуален (tar ETag) — apply-template без перекачки архива"
    fi
  else
    RUN_TAR=0
    [ "$SILENT" -eq 0 ] && info "Toolbox установлен — apply-template (upgrade в пайплайне пакета)"
  fi
elif [ -n "$APPLY_TEMPLATE_NAME" ] && [ "$CHANNEL" = tar ] && [ "$FORCE_CHANNEL" != "tar" ] \
  && [ -f "$TARGET_DIR/menu.sh" ] && [ -f "$TARGET_DIR/lib/common.sh" ]; then
  # Factory /tmp на 24.x: пакет уже есть — tar только если ETag говорит «есть обновление».
  if xfree_apply_only_tar_update_available "$TARGET_DIR/system/self-update.sh"; then
    RUN_TAR=1
    [ "$SILENT" -eq 0 ] && info "Доступно обновление toolbox (tar) — скачиваю архив, затем toolbox"
  else
    RUN_TAR=0
    [ "$SILENT" -eq 0 ] && info "Toolbox актуален (tar ETag) — передаю управление без перекачки архива"
  fi
fi

if [ "$REGISTRY_ONLY" -eq 1 ]; then
  RUN_TAR=0
  RUN_APK_PAYLOAD=0
fi

if [ "$CHECK_ONLY" -eq 0 ] && [ "$RUN_TAR" -eq 1 ]; then
  command -v wget >/dev/null 2>&1 || die "Нужен wget (скачивание tar)"
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  if should_use_apk_check_only; then
    xfree_load_apk_registry_lib
    xfree_apk_feed_seed_source || true
    run_apk_check_only
  fi
  _su="$TARGET_DIR/system/self-update.sh"
  if [ ! -f "$_su" ] && [ -f "$SCRIPT_DIR/self-update.sh" ]; then
    _su="$SCRIPT_DIR/self-update.sh"
  fi
  [ -f "$_su" ] || die "check-only: нет $_su (сначала установите toolbox)"
  exec sh "$_su" --check-only ${SILENT:+--silent}
fi

_xfree_install_cleanup_armed=0
_xfree_tar_tmp_dir=""

xfree_restart_dns_minimal() {
  _root="${ROOT_DIR:-}"
  if [ -x /etc/init.d/https-dns-proxy ]; then
    _svc="${HTTPS_DNS_PROXY_SERVICE_LIB:-$_root/https-dns-proxy/lib/service.sh}"
    if [ -f "$_svc" ]; then
      # shellcheck disable=SC1090
      . "$_svc"
      https_dns_proxy_restart_service restart
    else
      /etc/init.d/https-dns-proxy restart 2>/dev/null || true
    fi
  fi
  if [ -x /etc/init.d/dnsmasq ]; then
    /etc/init.d/dnsmasq restart 2>/dev/null || true
  fi
}

xfree_install_failed_cleanup() {
  _rc=$?
  if [ -n "${_xfree_tar_tmp_dir:-}" ]; then
    rm -rf "$_xfree_tar_tmp_dir" 2>/dev/null || true
    _xfree_tar_tmp_dir=""
  fi
  [ "$_rc" -eq 0 ] && exit 0
  [ "$_xfree_install_cleanup_armed" = "1" ] || exit "$_rc"
  warn "Установка прервана (код $_rc)."
  case "${_xfree_install_failed_phase:-}" in
    apk|registry)
      warn "apk «Failed to send request: Operation not permitted» обычно = сбой DNS/маршрута, не права root."
      xfree_restart_dns_minimal || true
      _recover=""
      for _cand in "$TARGET_DIR/system/recover-apk-network.sh" "/root/xfree-toolbox/system/recover-apk-network.sh"; do
        if [ -f "$_cand" ]; then
          _recover="$_cand"
          break
        fi
      done
      if [ -n "$_recover" ]; then
        warn "Без перезагрузки: sh $_recover"
        warn "  (с полным сбросом сети: sh $_recover --full)"
      fi
      ;;
    apply-template)
      warn "Сбой на этапе apply-template — сеть обычно ни при чём."
      warn "Частые причины: profiles/<имя> уже существует (--force), неполный каталог после прошлого сбоя, занята фоновая задача apply."
      warn "Проверка: ls -la $TARGET_DIR/profiles/$APPLY_PROFILE_NAME; tail -f ${XFREE_BG_TASK_LOG_FILE:-/tmp/xfree-background-tasks/apply-template.log}"
      ;;
    *)
      warn "См. сообщения выше; при сбое apk — recover-apk-network.sh."
      ;;
  esac
  exit "$_rc"
}

trap xfree_install_failed_cleanup EXIT
_xfree_install_cleanup_armed=1

if [ "$RUN_REGISTRY" -eq 1 ]; then
  xfree_load_apk_registry_lib
  xfree_apk_feed_seed_source || true
  FEED_URL="$(xfree_apk_feed_active_url)" || die "Нужен --feed-base (XFREE_APK_FEED_PUBLIC_BASE) или источник GitHub"
  xfree_apk_registry_pubkey_url >/dev/null \
    || die "Нужен --factory-base (XFREE_FACTORY_PUBLIC_BASE) или GitHub pubkey для ключа подписи"
fi

if [ "$RUN_TAR" -eq 1 ] && [ "$TAR_URL_EXPLICIT" -eq 0 ]; then
  xfree_load_apk_registry_lib
  xfree_apk_feed_seed_source || true
  _tar_src="$(xfree_apk_feed_tar_url 2>/dev/null || true)"
  [ -n "$_tar_src" ] && UPDATE_URL="$(trim_trailing_slash "$_tar_src")"
fi

[ "$SILENT" -eq 0 ] && info "Каталог: $TARGET_DIR"
[ "$SILENT" -eq 0 ] && [ "$RUN_REGISTRY" -eq 1 ] && info "Реестр apk: $FEED_URL"
[ "$SILENT" -eq 0 ] && [ "$RUN_TAR" -eq 1 ] && info "Tar: $UPDATE_URL"
[ "$SILENT" -eq 0 ] && [ "$RUN_APK_PAYLOAD" -eq 1 ] && info "Пакет apk: $APK_PKG_NAME"

# --- 1) Реестр (только OpenWrt 25+ / канал apk) ---
if [ "$RUN_REGISTRY" -eq 1 ]; then
  if ! command -v apk >/dev/null 2>&1; then
    die "Реестр apk требует OpenWrt 25+ (команда apk отсутствует)"
  fi
  xfree_ensure_apk_registry || die "Не удалось настроить apk registry"
  REMOTE_PUB="$(xfree_apk_registry_pubkey_file)"
  REMOTE_REPO="$(xfree_apk_registry_repo_file)"
  success "Ключ: $REMOTE_PUB"
  success "Feed: $REMOTE_REPO"
  cat "$REMOTE_REPO"
fi

if [ "$REGISTRY_ONLY" -eq 1 ]; then
  if [ "$RUN_APK_UPDATE" -ne 0 ] && command -v apk >/dev/null 2>&1; then
    info "apk update…"
    apk update --force-missing-repositories 2>&1 || warn "apk update: см. UNTRUSTED / ci/publish-apk-feed.sh"
  fi
  success "Реестр настроен (--registry-only)"
  exit 0
fi

# --- 2a) Установка через apk (25+) ---
if [ "$RUN_APK_PAYLOAD" -eq 1 ]; then
  _xfree_install_failed_phase="apk"
  xfree_apk_sanitize_world_qpins
  if [ "$RUN_APK_UPDATE" -ne 0 ]; then
    info "apk update…"
    apk update --force-missing-repositories 2>&1 || warn "apk update с предупреждением (часто UNTRUSTED index)"
  fi
  if xfree_apk_installed; then
    info "apk upgrade $APK_PKG_NAME…"
    xfree_apk_run_pkg_op upgrade || apk add --allow-untrusted "$APK_PKG_NAME" 2>&1 || \
      die "apk upgrade $APK_PKG_NAME не удался"
  else
    info "apk add $APK_PKG_NAME…"
    xfree_apk_run_pkg_op add || apk add --allow-untrusted "$APK_PKG_NAME" 2>&1 || \
      die "apk add $APK_PKG_NAME не удался (проверьте реестр и подпись packages.adb)"
  fi
  success "Пакет $APK_PKG_NAME установлен → $TARGET_DIR"
  export XFREE_PIPELINE_UPGRADED=1
fi

# --- 2b) Установка/обновление через tar ---
if [ "$RUN_TAR" -eq 1 ]; then
  [ -n "$UPDATE_URL" ] || die "Не задан tar URL"
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/xfree-cloud-install.XXXXXX")"
  _xfree_tar_tmp_dir="$TMP_DIR"

  xfree_install_download_tar "$TMP_DIR/$ARCHIVE_NAME" "$UPDATE_URL"
  mkdir -p "$TMP_DIR/new"
  tar -xzf "$TMP_DIR/$ARCHIVE_NAME" -C "$TMP_DIR/new" || die "tar распаковка не удалась"
  find "$TMP_DIR/new" -type f -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true

  run_tar_install_from_tree "$TMP_DIR/new"
  xfree_install_persist_tar_etag
  rm -rf "$TMP_DIR"
  _xfree_tar_tmp_dir=""
  success "Установка/обновление (tar) завершена"
  export XFREE_PIPELINE_UPGRADED=1
fi

# Factory /tmp на этом заканчивает: feed и пакет. Меню, apply, хуки — только копия из toolbox.
if [ "${XFREE_APPLY_INNER:-0}" != "1" ]; then
  xfree_exec_installed_toolbox "post-install"
fi

if [ -f "$TARGET_DIR/menu.sh" ]; then
  xfree_ensure_router_commands "$TARGET_DIR" || true
  xfree_ensure_wps_button_hooks "$TARGET_DIR" || true
  if [ -f "$TARGET_DIR/system/hardware/usb-power-watch-upgrade.sh" ]; then
    sh "$TARGET_DIR/system/hardware/usb-power-watch-upgrade.sh" --on-deploy --quiet "$TARGET_DIR" \
      >>/tmp/xfree-postinst.log 2>&1 || true
  fi
fi

if [ "$OPEN_MENU" -eq 1 ] || [ -n "$APPLY_TEMPLATE_NAME" ]; then
  xfree_ensure_base_packages_for_toolbox "$TARGET_DIR"
fi

if [ "$OPEN_MENU" -eq 1 ]; then
  [ -z "$APPLY_TEMPLATE_NAME" ] || die "--menu и --apply-template нельзя использовать вместе"
  [ -f "$TARGET_DIR/menu.sh" ] || die "menu.sh не найден: $TARGET_DIR"
  if ! [ -t 1 ] || ! ( : >/dev/tty ) 2>/dev/null; then
    die "Меню whiptail нужен интерактивный TTY (ssh -t). Пример: ssh -t root@<router> '… && sh /tmp/install-from-cloud.sh --menu'. Или на роутере: cd $TARGET_DIR && ./menu.sh"
  fi
  cd "$TARGET_DIR" && exec sh ./menu.sh
fi

if [ -n "$APPLY_TEMPLATE_NAME" ]; then
  _xfree_install_failed_phase="apply-template"
  _run_canonical_pipeline=0
  if [ "${XFREE_APPLY_INNER:-0}" != "1" ]; then
    _pipe="$TARGET_DIR/templates/update-and-apply-pipeline.sh"
    [ -f "$_pipe" ] || die "Не найден канонический пайплайн: $_pipe"
    if ! xfree_pipeline_defines_apply "$_pipe"; then
      xfree_refresh_toolbox_for_pipeline || true
    fi
    if xfree_pipeline_defines_apply "$_pipe"; then
      _run_canonical_pipeline=1
    else
      warn "канонический пайплайн в toolbox устарел (нет templates_apply_update_pipeline) — copy+apply напрямую. Обновите пакет xfree-toolbox."
    fi
  fi
  if [ "$_run_canonical_pipeline" = "1" ]; then
    info "apply-template: тот же пайплайн, что «Обновить» / «Пересоздать» (upgrade → upstream → copy → apply)"
    if [ "$FORCE" -eq 1 ]; then
      info "режим: Пересоздать (--force, instantiate, шаблон целиком)"
    elif [ "$APPLY_MODE" = "sync" ]; then
      info "режим: Обновить (--apply-mode sync, только списки)"
    else
      info "режим: Создать (instantiate без --force)"
    fi
    sh "$_pipe" \
      "$TARGET_DIR" "$APPLY_TEMPLATE_NAME" "$APPLY_PROFILE_NAME" \
      "$SILENT" 1 \
      "install-from-cloud: $APPLY_TEMPLATE_NAME" \
      "$APPLY_MODE" "$FORCE" \
      || die "пайплайн apply-template не удался для $APPLY_TEMPLATE_NAME"
  else
  _instantiate="$TARGET_DIR/templates/instantiate-profile-from-template.sh"
  _sync="$TARGET_DIR/templates/sync-profile-from-template.sh"
  _apply="$TARGET_DIR/templates/apply-template.sh"
  _profile_dir="$TARGET_DIR/profiles/$APPLY_PROFILE_NAME"
  _apply_extra=""

  [ -f "$_instantiate" ] || die "Не найден instantiate-profile-from-template.sh: $_instantiate"
  [ -f "$_sync" ] || die "Не найден sync-profile-from-template.sh: $_sync"
  [ -f "$_apply" ] || die "Не найден apply-template.sh: $_apply"
  [ -x "$_instantiate" ] || chmod +x "$_instantiate" 2>/dev/null || true
  [ -x "$_sync" ] || chmod +x "$_sync" 2>/dev/null || true
  [ -x "$_apply" ] || chmod +x "$_apply" 2>/dev/null || true

  if [ "$APPLY_MODE" = "instantiate" ] && [ -e "$_profile_dir" ]; then
    if ! xfree_profile_dir_is_materialized "$_profile_dir"; then
      warn "Профиль $_profile_dir неполный (нет EXPORT-META или iface-routing) — удаляем перед instantiate"
      rm -rf "$_profile_dir"
    elif [ "$FORCE" -eq 0 ]; then
      _existing_ref="$(xfree_read_template_ref_from_meta "$_profile_dir/EXPORT-META.txt" 2>/dev/null || true)"
      if [ "$_existing_ref" = "$APPLY_TEMPLATE_NAME" ]; then
        info "Профиль уже из шаблона $APPLY_TEMPLATE_NAME — пропуск instantiate, только apply-template"
        SKIP_INSTANTIATE=1
      else
        die "Профиль уже существует: $_profile_dir (TEMPLATE_REF=${_existing_ref:-?}, нужен --force или другой --apply-profile)"
      fi
    fi
  fi

  info "apply-template: шаблон=$APPLY_TEMPLATE_NAME, профиль=$APPLY_PROFILE_NAME, режим=$APPLY_MODE${FORCE:+ force=$FORCE}"
  case "$APPLY_MODE" in
    instantiate)
      if [ "$SKIP_INSTANTIATE" -eq 0 ]; then
        # prepare делает apply-template; иначе zapret+Proton guest дважды и guest до https-dns.
        if [ "$FORCE" -eq 1 ]; then
          sh "$_instantiate" --template "$APPLY_TEMPLATE_NAME" --profile "$APPLY_PROFILE_NAME" --force --copy-only
        else
          sh "$_instantiate" --template "$APPLY_TEMPLATE_NAME" --profile "$APPLY_PROFILE_NAME" --copy-only
        fi
      fi
      ;;
    sync)
      if [ "$FORCE" -eq 1 ]; then
        warn "--force не применяется в --apply-mode sync (это «Обновить», не «Пересоздать»)"
      fi
      info "apply-mode sync: копирование списков из шаблона (живые config/ сохраняются), затем apply с prepare"
      sh "$_sync" --template "$APPLY_TEMPLATE_NAME" --profile "$APPLY_PROFILE_NAME"
      ;;
  esac
  [ -d "$_profile_dir" ] || die "Профиль не создан: $_profile_dir"
  set_active_profile_in_config "$APPLY_PROFILE_NAME"
  info "Активный профиль в config.sh: $APPLY_PROFILE_NAME"
  _apply_log="${XFREE_BG_TASK_LOG_FILE:-${XFREE_BG_ROOT:-/tmp/xfree-background-tasks}/apply-template.log}"
  if [ "${XFREE_BG_TASK:-0}" = "1" ]; then
    unset XFREE_PROFILE XFREE_PROFILE_DIR PROFILE_DIR
    export XFREE_PROFILE="$APPLY_PROFILE_NAME"
    export XFREE_PROFILE_DIR="profiles/$APPLY_PROFILE_NAME"
    export PROFILE_DIR="$_profile_dir"
    export XFREE_APPLY_PROFILE_DIR="$_profile_dir"
    export XFREE_APPLY_TEMPLATE_LOG_FILE="$_apply_log"
    info "apply-template (в текущей фоновой задаче; лог $_apply_log)"
    # shellcheck disable=SC2086
    if sh "$_apply" $_apply_extra; then
      install_cloud_mark_applied_profile "$APPLY_PROFILE_NAME"
      xfree_ensure_router_commands "$TARGET_DIR" || true
      success "Шаблон $APPLY_TEMPLATE_NAME → профиль $APPLY_PROFILE_NAME; apply-template завершён"
    else
      die "apply-template не удался для профиля $APPLY_PROFILE_NAME"
    fi
  elif launch_apply_template_background "$_apply" "$_profile_dir" "$APPLY_PROFILE_NAME" $_apply_extra; then
    success "Шаблон $APPLY_TEMPLATE_NAME → профиль $APPLY_PROFILE_NAME; apply-template в фоне (LED, лог $_apply_log)"
    _apply_ok=0
    install_cloud_follow_apply_log "$_apply_log" && _apply_ok=1
    if [ "$_apply_ok" -eq 1 ]; then
      install_cloud_mark_applied_profile "$APPLY_PROFILE_NAME"
    else
      warn "apply-template завершился с ошибкой — applied-profile не обновлён (config.sh уже: $APPLY_PROFILE_NAME)"
    fi
  else
    warn "Профиль $APPLY_PROFILE_NAME готов, но apply-template не запущен (занята другая фоновая задача или ошибка старта)"
    exit 1
  fi
  fi
fi

success "install-from-cloud готов"
