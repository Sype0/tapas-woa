#!/usr/bin/bash
# update_device.sh for BCD-SYS: tapas SD card (mmcblk1) GPT GUIDs. ESP = p1 "esp", Windows = p3 "win" (from scripts/sd-part.sh)
DISK=BA98F02E-E9FF-4E18-A842-D72831D8BFAD
ESP=F653557C-E01C-41DD-A2EE-74FD05E9D952
WIN=B298BD6C-0450-42CE-85FA-7E3821AFE8BB
endian () { v=$1; i=${#v}; while [ $i -gt 0 ]; do i=$[$i-2]; echo -n ${v:$i:2}; done; echo; }
guid_bytes () { IFS=- read -a a <<< "$1"; echo $(endian ${a[0]})$(endian ${a[1]})$(endian ${a[2]})${a[3]}${a[4]}; }
case "$1" in *esp*) P=$ESP;; *) P=$WIN;; esac
pb=$(guid_bytes $P | sed "s/.\{2\}/&,/g;s/,$//"); db=$(guid_bytes $DISK | sed "s/.\{2\}/&,/g;s/,$//")
printf "hex:3:00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,06,00,00,00,00,00,00,00,48,00,00,00,00,00,00,00,$pb,00,00,00,00,00,00,00,00,$db,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00\n"
