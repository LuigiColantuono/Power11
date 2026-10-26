#!/system/bin/sh
MODDIR=${0%/*}

# Remember what this boot runs with, so the WebUI can tell what needs a reboot
sh "$MODDIR/power11.sh" boot_state
# ro.* blur props must be set before SurfaceFlinger starts
sh "$MODDIR/power11.sh" blur_props
