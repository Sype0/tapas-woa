set -e
D=/dev/block/mmcblk1
grep -q mmcblk1 /proc/mounts && { echo MOUNTED; exit 1; }
printf '%s\n' 'label: gpt' 'first-lba: 2048' \
 'size=300MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="esp"' \
 'size=16MiB, type=E3C9E316-0B5C-4DB8-817D-F92DF00215AE, name="msr"' \
 'type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name="win"' | sfdisk -q --wipe always $D
blockdev --rereadpt $D; sleep 2
sfdisk -l $D | tail -5
sm unmount public:179,1 2>/dev/null || true; sleep 1
if grep mmcblk1 /proc/mounts; then echo VOLD MOUNTED p1; exit 1; fi
mkfs.fat -F 32 -n ESP ${D}p1 >/dev/null
export MTOOLS_SKIP_CHECK=1
mmd -i ${D}p1 ::/EFI ::/EFI/BOOT
mcopy -i ${D}p1 shellaa64.efi ::/EFI/BOOT/BOOTAA64.EFI
mcopy -i ${D}p1 startup.nsh ::/EFI/BOOT/startup.nsh
mcopy -i ${D}p1 startup.nsh ::/startup.nsh
mcopy -i ${D}p1 tapas-esp.txt ::/tapas-esp.txt
mdir -i ${D}p1 -/ ::/
