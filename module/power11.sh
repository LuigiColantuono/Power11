#!/system/bin/sh
# Power11 - core logic
#
# 1. AOSP menu: SystemUI loads the power menu through its plugin framework.
#    On HyperOS/MIUI the plugin APK (miui.systemui.plugin) registers a service
#    for the GlobalActions plugin action. Disabling it makes SystemUI fall
#    back to its built-in AOSP GlobalActionsDialogLite.
# 2. Items, order, grid: the Power11 LSPosed/Vector module (system/app)
#    hooks SystemUI and reads Settings.Global power11_items/power11_columns
#    every time the menu opens.
# 3. Reboot entries: the hook drops power11_<cmd> files in SystemUI's data
#    dir; watcher.sh (root) runs them.
#
# Usage: power11.sh <command> [args]
#   enable | disable | toggle   switch the AOSP power menu on/off
#   items <csv>                 menu items in order (live)
#   columns <n>                 grid columns, 0 = ROM default (live)
#   blur <0|1>                  force window blur support (reboot)
#   blur_radius <px>            blur strength, 0 = ROM default (live)
#   status | scan               JSON for the WebUI
#   restart | reboot <target>   restart SystemUI / reboot device
#   boot | log

MODDIR=${0%/*}
DATADIR=/data/adb/power11
CONFIG="$DATADIR/config"
STATE="$DATADIR/disabled_components"
BOOTSTATE="$DATADIR/boot_state"
LOG="$DATADIR/log.txt"

AOSP_ACTION=com.android.systemui.action.PLUGIN_GLOBAL_ACTIONS
APP_PKG=com.luigicolantuono.power11
SYSTEMUI_DATA=/data/user_de/0/com.android.systemui
BLUR_OVERLAY=com.android.shell:power11_blur
DEFAULT_ITEMS=emergency,lockdown,power,restart

mkdir -p "$DATADIR"
touch "$STATE"

log() {
  echo "[$(date '+%F %T')] $*" >> "$LOG"
  if [ "$(wc -l < "$LOG")" -gt 300 ]; then
    tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
  fi
}

# ------------------------------------------------------------------ config

get_cfg() {
  v=$(grep "^$1=" "$CONFIG" 2>/dev/null | tail -n 1 | cut -d= -f2-)
  echo "${v:-$2}"
}

set_cfg() {
  if grep -q "^$1=" "$CONFIG" 2>/dev/null; then
    sed -i "s|^$1=.*|$1=$2|" "$CONFIG"
  else
    echo "$1=$2" >> "$CONFIG"
  fi
}

init_config() {
  [ -f "$CONFIG" ] && return
  printf 'enabled=1\nitems=%s\ncolumns=2\nblur=0\nblur_radius=0\n' "$DEFAULT_ITEMS" > "$CONFIG"
}

# The hook reads these; written on every boot in case settings were reset
push_settings() {
  settings put global power11_items "$(get_cfg items "$DEFAULT_ITEMS")"
  settings put global power11_columns "$(get_cfg columns 2)"
}

# ------------------------------------------------------------------ plugin

# System packages that look like SystemUI plugins (excluding SystemUI itself)
plugin_packages() {
  pm list packages -s 2>/dev/null | sed 's/^package://' \
    | grep -i 'systemui' | grep -vx 'com.android.systemui'
}

# The AOSP plugin action plus any vendor-specific power menu variant
plugin_actions() {
  {
    echo "$AOSP_ACTION"
    for pkg in $(plugin_packages); do
      dumpsys package "$pkg" 2>/dev/null \
        | grep -oE 'Action: "[^"]+"' | sed 's/^Action: "//; s/"$//' \
        | grep -iE 'GLOBAL_?ACTIONS|POWER_?MENU'
    done
  } | sort -u
}

# Enabled vendor components that currently provide the power menu
find_targets() {
  for action in $(plugin_actions); do
    cmd package query-services --brief -a "$action" 2>/dev/null \
      | grep '/' | tr -d ' \t'
  done | grep -v '^com\.android\.systemui/' | sort -u
}

disable_plugin() {
  changed=0
  for c in $(find_targets); do
    if pm disable "$c" >/dev/null 2>&1; then
      grep -qx "$c" "$STATE" || echo "$c" >> "$STATE"
      log "Disabled $c"
      changed=$((changed + 1))
    else
      log "ERROR: could not disable $c"
    fi
  done
  [ -s "$STATE" ] || log "No power menu plugin found to disable"
  echo "$changed"
}

enable_plugin() {
  changed=0
  while read -r c; do
    [ -n "$c" ] || continue
    pm enable "$c" >/dev/null 2>&1 && log "Enabled $c"
    changed=$((changed + 1))
  done < "$STATE"
  : > "$STATE"
  echo "$changed"
}

# ------------------------------------------------------------------ blur

# 0x05 = TYPE_DIMENSION; complex value in px with radix 23p0
apply_blur_radius() {
  radius=$(get_cfg blur_radius 0)
  if [ "$radius" -gt 0 ] && [ "$(get_cfg enabled 1)" = "1" ]; then
    cmd overlay fabricate --target com.android.systemui --name power11_blur \
      com.android.systemui:dimen/max_window_blur_radius 0x05 $((radius << 8)) >/dev/null 2>&1 \
      && cmd overlay enable "$BLUR_OVERLAY" >/dev/null 2>&1 \
      && log "Blur radius set to ${radius}px" \
      || log "ERROR: blur radius overlay not supported on this ROM"
  else
    cmd overlay disable "$BLUR_OVERLAY" >/dev/null 2>&1
  fi
}

# Runs in post-fs-data, before SurfaceFlinger starts
apply_blur_props() {
  rp=resetprop
  command -v resetprop >/dev/null || rp=/data/adb/ksu/bin/resetprop
  $rp ro.surface_flinger.supports_background_blur 1
  $rp ro.config.avoid_gfx_accel false
  $rp persist.sysui.disableBlur false
}

# ------------------------------------------------------------------ hook

# The hook writes SystemUI's pid on start; a match means it is loaded now
hook_active() {
  [ "$(cat "$SYSTEMUI_DATA/power11_alive" 2>/dev/null)" = "$(pidof com.android.systemui)" ]
}

start_watcher() {
  pkill -f "$MODDIR/watcher.sh" 2>/dev/null
  nohup sh "$MODDIR/watcher.sh" >/dev/null 2>&1 &
}

# ------------------------------------------------------------------ actions

restart_systemui() {
  pid=$(pidof com.android.systemui)
  [ -n "$pid" ] && kill $pid
  log "SystemUI restarted"
}

update_description() {
  prop="$MODDIR/module.prop"
  [ -f "$prop" ] || return
  if [ -s "$STATE" ]; then
    if hook_active; then
      desc="✅ Active · custom menu ready"
    else
      desc="✅ Active · enable Power11 in Vector/LSPosed for custom items"
    fi
  elif [ "$(get_cfg enabled 1)" = "1" ]; then
    desc="⚠️ No HyperOS power menu plugin found. Open the WebUI for details."
  else
    desc="⏸️ Paused · HyperOS power menu in use"
  fi
  sed -i "s|^description=.*|description=$desc|" "$prop"
}

turn_on() {
  set_cfg enabled 1
  n=$(disable_plugin)
  apply_blur_radius
  update_description
  echo "$n"
}

turn_off() {
  set_cfg enabled 0
  n=$(enable_plugin)
  apply_blur_radius
  update_description
  echo "$n"
}

# Called from service.sh once boot is complete
boot() {
  [ "$(get_cfg blur 0)" = "1" ] && settings put global disable_window_blurs 0
  push_settings
  start_watcher
  if [ "$(get_cfg enabled 1)" = "1" ]; then
    # Re-applied every boot: after an OTA the plugin may be back
    # or under a different component name
    n=$(turn_on)
  else
    n=$(turn_off)
  fi
  [ "${n:-0}" -gt 0 ] && restart_systemui
  # Hook status in the description, once SystemUI is back up
  (sleep 15; update_description) &
}

# ------------------------------------------------------------------ json

json_list() {
  first=1
  printf '['
  for item in "$@"; do
    [ $first -eq 1 ] || printf ','
    printf '"%s"' "$item"
    first=0
  done
  printf ']'
}

json_bool() { [ "$1" = "1" ] && echo true || echo false; }

status() {
  blur=$(get_cfg blur 0)
  boot_blur=$(grep '^blur=' "$BOOTSTATE" 2>/dev/null | cut -d= -f2)
  [ "$blur" = "${boot_blur:-0}" ] && bp=0 || bp=1
  [ -s "$STATE" ] && active=1 || active=0
  hook_active && hook=1 || hook=0
  pm path "$APP_PKG" >/dev/null 2>&1 && app=1 || app=0

  rom=$(getprop ro.mi.os.version.name)
  [ -n "$rom" ] && rom="HyperOS $rom" || rom="MIUI $(getprop ro.miui.ui.version.name)"
  device=$(getprop ro.product.marketname)
  [ -n "$device" ] || device=$(getprop ro.product.model)

  printf '{"version":"%s",' "$(grep '^version=' "$MODDIR/module.prop" | cut -d= -f2)"
  printf '"enabled":%s,"active":%s,' "$(json_bool "$(get_cfg enabled 1)")" "$(json_bool $active)"
  printf '"hook":%s,"app":%s,' "$(json_bool $hook)" "$(json_bool $app)"
  printf '"components":%s,' "$(json_list $(cat "$STATE"))"
  printf '"items":%s,' "$(json_list $(get_cfg items "$DEFAULT_ITEMS" | tr ',' ' '))"
  printf '"columns":%s,' "$(get_cfg columns 2)"
  printf '"blur":%s,"blur_pending":%s,' "$(json_bool "$blur")" "$(json_bool $bp)"
  printf '"blur_radius":%s,' "$(get_cfg blur_radius 0)"
  printf '"blur_supported":%s,' "$(json_bool "$(getprop ro.surface_flinger.supports_background_blur)")"
  printf '"device":"%s","rom":"%s","android":"%s","sdk":"%s"}\n' \
    "$device" "$rom" "$(getprop ro.build.version.release)" "$(getprop ro.build.version.sdk)"
}

# Slow (dumpsys): only for the diagnostics panel
scan() {
  pgrep -f "$MODDIR/watcher.sh" >/dev/null && watcher=running || watcher=stopped
  printf '{"plugins":%s,' "$(json_list $(plugin_packages))"
  printf '"available":%s,' "$(json_list $(find_targets))"
  printf '"watcher":"%s"}\n' "$watcher"
}

# ------------------------------------------------------------------ main

init_config

case "$1" in
  enable)  turn_on ;;
  disable) turn_off ;;
  toggle)
    if [ "$(get_cfg enabled 1)" = "1" ]; then turn_off; else turn_on; fi ;;
  items)
    # Only known keys, so nothing odd reaches settings
    clean=$(echo "$2" | tr ',' '\n' | grep -xE '[a-z]+' | paste -sd, -)
    set_cfg items "$clean"
    push_settings ;;
  columns)
    case "$2" in 0|2|3|4) set_cfg columns "$2"; push_settings ;; esac ;;
  blur)
    set_cfg blur "$2"
    [ "$2" = "1" ] && settings put global disable_window_blurs 0 ;;
  blur_radius)
    set_cfg blur_radius "$2"
    apply_blur_radius ;;
  blur_props) [ "$(get_cfg blur 0)" = "1" ] && apply_blur_props ;;
  boot_state) printf 'blur=%s\n' "$(get_cfg blur 0)" > "$BOOTSTATE" ;;
  boot)    boot ;;
  status)  status ;;
  scan)    scan ;;
  restart) restart_systemui ;;
  reboot)
    log "Reboot: ${2:-system}"
    case "$2" in
      recovery|bootloader) reboot "$2" ;;
      softreboot) setprop ctl.restart zygote ;;
      *) reboot ;;
    esac ;;
  log)     cat "$LOG" 2>/dev/null ;;
  *)       sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
