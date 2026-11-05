#!/bin/sh
# Write Windows 11 ARM64 (22621, UUP ESDs) to the tapas SD card from the Alpine chroot.
# Usage (inside the chroot, as root):  install-win-sd.sh <uup-dir> <step>...
#   steps: prep | format | apply | boot | system | all
# <uup-dir>: the uupdump file set (edition ESD + *.ESD packages + the non-update *.cab FODs in cab/).
# SD layout (scripts/sd-part.sh): p1 "esp" FAT32 (UEFI Shell + test logs), p2 "msr", p3 "win" (NTFS here).
# Only /dev/block/mmcblk1 is touched; every step re-checks that p3 is the 14.3G "win" partition on it.
set -eu
UUP=$(realpath "$1"); shift
HERE=$(cd "$(dirname "$0")/.." && pwd)
SD=/dev/block/mmcblk1; ESP=${SD}p1; WIN=${SD}p3
ESD=$UUP/professional_tr-tr.esd
T=/tmp/winsd; mkdir -p $T
# wimlib's --ref globs are case-sensitive: the package ESDs are *.ESD, the edition ESD is *.esd, and the
# language/FOD blobs only exist in the cabs (converted to WIMs by "prep", like uupdump's converter does).
REFS="--ref=$UUP/*.esd --ref=$UUP/*.ESD --ref=$UUP/cabwim/*.wim"

do_prep() {   # cab -> uncompressed WIM, used only as a blob source
    mkdir -p "$UUP/cabwim"
    for c in "$UUP"/cab/*.cab; do
        n=$(basename "$c" .cab); [ -f "$UUP/cabwim/$n.wim" ] && continue
        rm -rf $T/cx; mkdir -p $T/cx
        cabextract -q -d $T/cx "$c"
        wimcapture $T/cx "$UUP/cabwim/$n.wim" --compress=none --no-acls >/dev/null
    done
    rm -rf $T/cx
}

check_sd() {
    [ "$(cat /sys/class/block/mmcblk1p3/size)" = 29884416 ] || { echo "p3 size mismatch: not our SD" >&2; exit 1; }
    [ "$(cat /sys/class/block/mmcblk1p3/start)" = 649216 ] || { echo "p3 start mismatch" >&2; exit 1; }
    [ "$(cat /sys/class/block/mmcblk1p1/start)" = 2048 ] || { echo "p1 start mismatch" >&2; exit 1; }
    ! grep -q mmcblk1 /proc/mounts || { echo "SD is mounted" >&2; exit 1; }
}

edition_index() {   # the Professional image in the edition ESD
    wiminfo "$ESD" | awk '/^Index:/{i=$2} /^Edition ID:/{if ($3=="Professional") print i}' | head -1
}

do_format() {
    check_sd
    mkntfs -f -Q -L Windows -p 649216 $WIN
}

do_apply() {
    check_sd
    idx=$(edition_index); echo "applying index $idx"
    wimapply "$ESD" "$idx" $WIN $REFS
}

do_boot() {
    check_sd
    idx=$(edition_index)
    rm -rf $T/src $T/esp; mkdir -p $T/src $T/esp/EFI/Microsoft/Boot
    wimextract "$ESD" "$idx" /Windows/Boot/EFI /Windows/Boot/Fonts /Windows/System32/config/SOFTWARE \
        $REFS --dest-dir=$T/src --preserve-dir-structure --no-acls
    cp -r $T/src/Windows/Boot/EFI/. $T/esp/EFI/Microsoft/Boot/
    cp -r $T/src/Windows/Boot/Fonts $T/esp/EFI/Microsoft/Boot/

    # BCD with BCD-SYS (jpz4085/BCD-SYS) generators + our SD GUIDs (bcd/update_device.sh)
    B=$T/bcd-sys; rm -rf $B; cp -r "$HERE/bcd-sys/Linux" $B; cp -r "$HERE/bcd-sys/Templates" $B/
    cp "$HERE/bcd/update_device.sh" $B/
    cp $B/Templates/BCD-NEW $T/BCD
    hivexregedit --merge --prefix BCD00000001 $T/BCD $B/Templates/winload.reg
    (cd $B && bash ./winload.sh $T/src $T/esp uefi false true false "" tr-tr false false) > $T/winload.txt
    hivexsh -w -f $T/winload.txt $T/BCD
    # test signing (16000049) on the Windows loader, like topaz-woa; boot manager timeout 0
    def=$(printf 'cd Objects\\{9dea862c-5cdd-4e70-acc1-f32b344d4795}\\Elements\\23000003\nlsval Element\nunload\n' | hivexsh $T/BCD | tr -d '"')
    printf 'cd Objects\\%s\\Elements\nadd 16000049\ncd 16000049\nsetval 1\nElement\nhex:3:01\ncommit\nunload\n' "$def" | hivexsh -w $T/BCD
    printf 'cd Objects\\{9dea862c-5cdd-4e70-acc1-f32b344d4795}\\Elements\\25000004\nsetval 1\nElement\nhex:3:00,00,00,00,00,00,00,00\ncommit\nunload\n' | hivexsh -w $T/BCD
    cp $T/BCD $T/esp/EFI/Microsoft/Boot/BCD
    echo "default loader: $def"

    export MTOOLS_SKIP_CHECK=1
    mdeltree -i $ESP ::/EFI/Microsoft 2>/dev/null || true
    mcopy -s -i $ESP $T/esp/EFI/Microsoft ::/EFI/
    mcopy -o -i $ESP "$HERE/esp/startup.nsh" ::/EFI/BOOT/startup.nsh
    mcopy -o -i $ESP "$HERE/esp/startup.nsh" ::/startup.nsh
    mdir -i $ESP -/ ::/EFI | tail -3
}

do_system() {   # sdbus + sdstor as boot-start drivers (SDC2 is QCOM24BF in our DSDT)
    # hivexsh "setval" REPLACES ALL VALUES of a key, so write the complete 22621 service values
    # (copied from the image's untouched SYSTEM hive), only Start changed 3 -> 0.
    check_sd
    ntfscat $WIN /Windows/System32/config/SYSTEM > $T/SYSTEM
    owners() { printf '%s' "$1.inf" | od -An -tx1 -v | tr -s ' \n' ' ' | sed 's/^ //;s/ $//' |
        awk '{for(i=1;i<=NF;i++) printf "%s,00,", $i; print "00,00,00,00"}'; }
    {
    printf 'cd ControlSet001\\Services\\sdbus\nsetval 8\n'
    printf 'ImagePath\nexpandstring:\\SystemRoot\\System32\\drivers\\sdbus.sys\nType\ndword:1\nStart\ndword:0\nErrorControl\ndword:1\nGroup\nstring:System Bus Extender\nTag\ndword:5\nOwners\nhex:7:%s\nBootFlags\ndword:8\n' "$(owners sdbus)"
    printf 'cd \\ControlSet001\\Services\\sdstor\nsetval 7\n'
    printf 'ImagePath\nexpandstring:\\SystemRoot\\System32\\drivers\\sdstor.sys\nType\ndword:1\nStart\ndword:0\nErrorControl\ndword:1\nDisplayName\nstring:@sdstor.inf,%%sdstor_ServiceDesc%%;SD Storage Port Driver\nOwners\nhex:7:%s\nBootFlags\ndword:8\n' "$(owners sdstor)"
    printf 'commit\n'
    } | hivexsh -w $T/SYSTEM
    for s in sdbus sdstor; do printf 'cd ControlSet001\\Services\\%s\nlsval\n' $s | hivexsh $T/SYSTEM; done
    ntfscp -f $WIN $T/SYSTEM /Windows/System32/config/SYSTEM
}

for step in "$@"; do
    case $step in
        prep) do_prep ;; format) do_format ;; apply) do_apply ;; boot) do_boot ;; system) do_system ;;
        all) do_prep; do_format; do_apply; do_boot; do_system ;;
        *) echo "unknown step $step" >&2; exit 1 ;;
    esac
    echo "== $step done"
done
