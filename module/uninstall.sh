#!/system/bin/sh
# Component, overlay and settings state live in Android itself and outlive
# the module, so they must be undone explicitly. uninstall.sh may run before
# the package manager is up, so the cleanup waits for boot in the background.
nohup sh -c '
  until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
  STATE=/data/adb/power11/disabled_components
  if [ -f "$STATE" ]; then
    while read -r c; do
      [ -n "$c" ] && pm enable "$c" >/dev/null 2>&1
    done < "$STATE"
  fi
  cmd overlay disable com.android.shell:power11_blur >/dev/null 2>&1
  pm uninstall com.luigicolantuono.power11 >/dev/null 2>&1
  settings delete global power11_items >/dev/null 2>&1
  settings delete global power11_columns >/dev/null 2>&1
  rm -f /data/user_de/0/com.android.systemui/power11_*
  rm -rf /data/adb/power11
  pid=$(pidof com.android.systemui) && kill $pid
' >/dev/null 2>&1 &
