#!/system/bin/sh
SKIPUNZIP=0

ui_print " "
ui_print "  ┌─────────────────────────────────────┐"
ui_print "  │               Power11               │"
ui_print "  │  Bring back the old gem from        │"
ui_print "  │  Android 11.                        │"
ui_print "  └─────────────────────────────────────┘"
ui_print " "

if [ "$KSU" != "true" ] && [ "$APATCH" != "true" ]; then
  ui_print "! Built for KernelSU Next, continuing anyway."
fi

if [ "$API" -lt 31 ]; then
  abort "! Android 12 or newer required (found SDK $API)."
fi

if [ -z "$(getprop ro.miui.ui.version.name)$(getprop ro.mi.os.version.name)" ]; then
  ui_print "! Not a Xiaomi ROM: the module may have no effect."
fi

DATADIR=/data/adb/power11
mkdir -p "$DATADIR"

# Take over from "AOSP Power Menu" (v1/v2, id aosp_powermenu)
OLD=/data/adb/modules/aosp_powermenu
if [ -d "$OLD" ]; then
  ui_print "- Replacing AOSP Power Menu (old version)"
  # Its uninstall script would re-enable the HyperOS menu: drop it first
  rm -f "$OLD/uninstall.sh"
  touch "$OLD/remove"
  [ -s /data/adb/aosp_powermenu/disabled_components ] \
    && cat /data/adb/aosp_powermenu/disabled_components >> "$DATADIR/disabled_components"
  grep -q '^enabled=0' /data/adb/aosp_powermenu/config 2>/dev/null && echo "enabled=0" >> "$DATADIR/config"
  grep '^blur' /data/adb/aosp_powermenu/config 2>/dev/null >> "$DATADIR/config"
  cmd overlay disable com.luigicolantuono.aosppowermenu.overlay >/dev/null 2>&1
  cmd overlay disable com.android.shell:aosppm_blur >/dev/null 2>&1
  rm -rf /data/adb/aosp_powermenu
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in power11.sh post-fs-data.sh service.sh action.sh uninstall.sh watcher.sh p11cmd.sh; do
  set_perm "$MODPATH/$f" 0 0 0755
done

ui_print " "
ui_print "- After reboot:"
ui_print "  1. Open Vector/LSPosed, enable Power11"
ui_print "     with scope System UI"
ui_print "  2. Restart SystemUI from the Power11 WebUI"
ui_print "  3. Pick items and order in the WebUI"
ui_print " "
