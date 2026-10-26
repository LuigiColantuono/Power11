#!/system/bin/sh
MODDIR=${0%/*}
DATADIR=/data/adb/power11

sh "$MODDIR/power11.sh" toggle >/dev/null

if grep -q '^enabled=1' "$DATADIR/config"; then
  if [ -s "$DATADIR/disabled_components" ]; then
    echo "✅ Power11 enabled"
  else
    echo "⚠️ No HyperOS power menu plugin found to replace."
    echo "   Open the WebUI for diagnostics."
  fi
else
  echo "⏸️ HyperOS power menu restored"
fi

echo "- Restarting SystemUI..."
sh "$MODDIR/power11.sh" restart
echo "- Done. Open the power menu to try it."
