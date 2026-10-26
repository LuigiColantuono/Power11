#!/system/bin/sh
# Runs the reboot entries of the power menu. SystemUI has no permission to
# reboot into recovery/bootloader, so the hook creates power11_<cmd> in its
# own data dir (writable only by SystemUI and root) and this root process
# acts on it. inotifyd sleeps until a file appears: no polling.
MODDIR=${0%/*}
DIR=/data/user_de/0/com.android.systemui

BB=/data/adb/ksu/bin/busybox
[ -x "$BB" ] || BB=$(command -v busybox)

rm -f "$DIR"/power11_recovery "$DIR"/power11_bootloader "$DIR"/power11_softreboot

while true; do
  if [ -d "$DIR" ] && [ -n "$BB" ] && "$BB" --list | grep -qx inotifyd; then
    # Returns only if the directory goes away (e.g. SystemUI data cleared)
    "$BB" inotifyd "$MODDIR/p11cmd.sh" "$DIR:n"
    sleep 5
  else
    # Fallback without inotifyd
    for f in "$DIR"/power11_recovery "$DIR"/power11_bootloader "$DIR"/power11_softreboot; do
      [ -e "$f" ] && sh "$MODDIR/p11cmd.sh" n "$DIR" "${f##*/}"
    done
    sleep 1
  fi
done
