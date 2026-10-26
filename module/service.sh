#!/system/bin/sh
MODDIR=${0%/*}

until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 2
done
# Let SystemUI finish loading its plugins
sleep 8

sh "$MODDIR/power11.sh" boot
