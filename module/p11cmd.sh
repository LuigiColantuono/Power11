#!/system/bin/sh
# inotifyd handler: $1 = event, $2 = directory, $3 = file name
case "$3" in
  power11_recovery|power11_bootloader|power11_softreboot) rm -f "$2/$3" ;;
  *) exit 0 ;;
esac

exec sh "${0%/*}/power11.sh" reboot "${3#power11_}"
