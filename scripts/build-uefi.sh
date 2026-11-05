#!/bin/bash
# Build Mu-Silicium UEFI for tapas with the topaz-woa patches, for booting Windows from the SD card.
# Usage: scripts/build-uefi.sh <workdir> <out.img> [RELEASE|DEBUG]
# Differences from topaz-woa's own build:
#  - AbSlot.c GPT writes disabled: this UEFI never writes to UFS (slot attributes stay as ABL set them).
#  - DSDT: unmodified topaz-woa XHCI DSDT (the SD card SDC2 node was removed after 12 failed SD boot tests).
#  - mu_v4pack.sh uses AOSP mkbootimg from <workdir>/mkbootimg instead of a hard-coded path.
set -euo pipefail
W=$(realpath -m "$1"); OUT=$(realpath -m "$2"); TARGET=${3:-RELEASE}
HERE=$(cd "$(dirname "$0")" && pwd)
MU_COMMIT=e5f9ec06            # topaz-woa known-good pin (submodules: Basecore bb557081, ACPI 9abca7f9, Binaries 203fb36b)
TOPAZ_COMMIT=bfe5c15fd63e0038826d84dcbd2a1ff814d52654
mkdir -p "$W"; cd "$W"

[ -d Mu-Silicium ] || git clone -q https://github.com/Project-Silicium/Mu-Silicium
git -C Mu-Silicium checkout -q $MU_COMMIT
git -C Mu-Silicium submodule update --init --recursive --jobs 8 --depth 1 ||
    git -C Mu-Silicium submodule update --init --recursive --jobs 8

[ -d topaz-woa ] || git clone -q https://github.com/MakrSas/topaz-woa
git -C topaz-woa checkout -q $TOPAZ_COMMIT
[ -d mkbootimg ] || git clone -q --depth 1 https://android.googlesource.com/platform/system/tools/mkbootimg

U=topaz-woa/uefi
# no UFS writes from the UEFI
sed -i 's/s = Bio->WriteBlocks (Bio, Bio->Media->MediaId, [^;]*;/s = EFI_WRITE_PROTECTED; \/* tapas-woa: UFS read-only *\//' $U/TopazOtgDxe/AbSlot.c
if grep -q 'WriteBlocks' $U/TopazOtgDxe/*.c; then echo "WriteBlocks still present" >&2; exit 1; fi
sed -i "s#/home/makr/work/topaz/mkbootimg_src#$W/mkbootimg#g" $U/mu_v4pack.sh


bash $U/build_topaz_uefi.sh "$W/Mu-Silicium" "$OUT" "$TARGET"
sha256sum "$OUT"
