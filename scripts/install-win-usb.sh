#!/bin/sh
# Copy the Windows install from the tapas SD card (scripts/install-win-sd.sh) to a USB stick and make it
# bootable, for booting Windows over USB OTG (inbox USBXHCI/USBSTOR; BootDriverFlags is already 0x1c).
# Usage (inside the Alpine chroot, as root):  install-win-usb.sh <usb-disk> <expected-size-in-sectors> <step>...
#   steps: part | esp | clone | bcd | nosd | all
# The USB disk must be given explicitly and its size must match, so a wrong /dev/block/sdX is refused.
# Layout like the SD: p1 "esp" FAT32 300M, p2 "msr" 16M, p3 "win" NTFS (rest).
# GPT GUIDs are fixed here so the BCD device elements can be rewritten from the SD GUIDs (bcd/update_device.sh).
set -eu
USB=$1; SIZE=$2; shift 2
HERE=$(cd "$(dirname "$0")/.." && pwd)
SD=/dev/block/mmcblk1
T=/tmp/winusb; mkdir -p $T
# SD GUIDs (bcd/update_device.sh) -> USB GUIDs
SD_DISK=BA98F02E-E9FF-4E18-A842-D72831D8BFAD; USB_DISK=7A3C5E21-4B1D-4C8E-9F02-3D5A6B7C8D01
SD_ESP=F653557C-E01C-41DD-A2EE-74FD05E9D952;  USB_ESP=7A3C5E21-4B1D-4C8E-9F02-3D5A6B7C8D11
SD_WIN=B298BD6C-0450-42CE-85FA-7E3821AFE8BB;  USB_WIN=7A3C5E21-4B1D-4C8E-9F02-3D5A6B7C8D33
n=$(basename $USB)
case $n in sd[g-z]) ;; *) echo "$USB is not a removable sdX disk (UFS is sda-sdf)" >&2; exit 1 ;; esac
[ "$(cat /sys/class/block/$n/size)" = "$SIZE" ] || { echo "size mismatch: $USB is not the stick" >&2; exit 1; }
readlink -f /sys/class/block/$n | grep -q /usb || { echo "$USB is not on USB" >&2; exit 1; }
! grep -q "^$USB" /proc/mounts || { echo "$USB is mounted" >&2; exit 1; }
ESP=${USB}1; WIN=${USB}3

do_part() {
    printf '%s\n' 'label: gpt' "label-id: $USB_DISK" 'first-lba: 2048' \
     "size=300MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, uuid=$USB_ESP, name=\"esp\"" \
     'size=16MiB, type=E3C9E316-0B5C-4DB8-817D-F92DF00215AE, name="msr"' \
     "type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=$USB_WIN, name=\"win\"" | sfdisk -q --wipe always $USB
    blockdev --rereadpt $USB; sleep 2
    sfdisk -l $USB | tail -4
    mkfs.fat -F 32 -n ESP $ESP >/dev/null
}

do_esp() {   # Windows boot files straight as the removable-media loader (no UEFI Shell, no nouhs)
    export MTOOLS_SKIP_CHECK=1
    rm -rf $T/esp; mkdir -p $T/esp
    mcopy -s -i ${SD}p1 ::/EFI/Microsoft $T/esp/
    mmd -i $ESP ::/EFI ::/EFI/BOOT 2>/dev/null || true
    mcopy -s -o -i $ESP $T/esp/Microsoft ::/EFI/
    mcopy -o -i $ESP $T/esp/Microsoft/Boot/bootmgfw.efi ::/EFI/BOOT/BOOTAA64.EFI
    mdir -i $ESP -/ ::/EFI | tail -3
}

do_clone() {   # NTFS copy of the SD's p3 (used clusters only), then grow it to the whole partition
    ntfsclone -f --overwrite $WIN ${SD}p3
    ntfsresize -f -P -b $WIN <<EOF
y
EOF
    ntfsinfo -m $WIN | grep -E "Volume Size|Volume Name"
}

do_bcd() {   # swap the SD GUIDs for the USB GUIDs in the BCD device elements (same byte length)
    export MTOOLS_SKIP_CHECK=1
    mcopy -o -i $ESP ::/EFI/Microsoft/Boot/BCD $T/BCD
    python3 -I - $T/BCD $SD_DISK $USB_DISK $SD_ESP $USB_ESP $SD_WIN $USB_WIN <<'EOF'
import sys, uuid
f = sys.argv[1]; b = open(f, 'rb').read()
for i in range(2, 8, 2):
    o, n = uuid.UUID(sys.argv[i]).bytes_le, uuid.UUID(sys.argv[i + 1]).bytes_le
    c = b.count(o); print(sys.argv[i], '->', sys.argv[i + 1], c, 'times')
    if c == 0: sys.exit('GUID not found in BCD')
    b = b.replace(o, n)
open(f, 'wb').write(b)
EOF
    mcopy -o -i $ESP $T/BCD ::/EFI/Microsoft/Boot/BCD
}

do_nosd() {   # SD stack off on the USB copy (sdbus crashes with SDBUS_INTERNAL_ERROR on tapas SDC2)
    ntfscat $WIN /Windows/System32/config/SYSTEM > $T/SYSTEM
    printf 'Windows Registry Editor Version 5.00\r\n\r\n[HKEY_LOCAL_MACHINE\\SYSTEM\\ControlSet001\\Services\\sdbus]\r\n"Start"=dword:00000004\r\n\r\n[HKEY_LOCAL_MACHINE\\SYSTEM\\ControlSet001\\Services\\sdstor]\r\n"Start"=dword:00000004\r\n' > $T/nosd.reg
    hivexregedit --merge --prefix 'HKEY_LOCAL_MACHINE\SYSTEM' $T/SYSTEM $T/nosd.reg
    for s in sdbus sdstor USBXHCI USBHUB3 USBSTOR UASPStor; do
        printf '%s ' $s; hivexget $T/SYSTEM "\\ControlSet001\\Services\\$s" Start; done
    hivexget $T/SYSTEM '\ControlSet001\Control' BootDriverFlags
    ntfscp -f $WIN $T/SYSTEM /Windows/System32/config/SYSTEM
}

for step in "$@"; do
    case $step in
        part) do_part ;; esp) do_esp ;; clone) do_clone ;; bcd) do_bcd ;; nosd) do_nosd ;;
        all) do_part; do_esp; do_clone; do_bcd; do_nosd ;;
        *) echo "unknown step $step" >&2; exit 1 ;;
    esac
    echo "== $step done"
done
