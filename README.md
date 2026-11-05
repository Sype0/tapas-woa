# tapas-woa

Windows on ARM for the Redmi Note 12 4G (tapas/topaz), **booted from the SD card**: userdata and the UFS partition
table are never touched. Based on [MakrSas/topaz-woa](https://github.com/MakrSas/topaz-woa) (Mu-Silicium UEFI patches
and Windows drivers), which installs Windows to UFS instead.

- `scripts/build-uefi.sh`: Mu-Silicium UEFI with the topaz-woa patches; GPT writes from the UEFI disabled.
- CI (`.github/workflows/uefi.yml`) publishes the image as release `uefi-latest`.
- Test: `fastboot boot Mu-tapas-v4-RELEASE.img` (RAM only).
