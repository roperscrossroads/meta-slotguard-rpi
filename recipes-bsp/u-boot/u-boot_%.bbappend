
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:rpi = " file://slotguard-env.cfg"

SLOTGUARD_BOOTM_LEN ?= "0x1000000"

do_configure:append:rpi() {
    cfg="${B}/.config"
    if [ ! -f "$cfg" ]; then
        bbfatal "u-boot: no .config at ${B} after do_configure — slotguard-env.cfg \
cannot be verified, and an unverifiable guard is not a passing one."
    fi

    for sym in CONFIG_ENV_IS_IN_MMC CONFIG_ENV_REDUNDANT; do
        if ! grep -q "^$sym=y" "$cfg"; then
            bbfatal "u-boot: $sym is not set in the merged config — \
slotguard-env.cfg did not apply. The environment would stay in a single FAT file, \
so a torn write during a scheduled power cut could leave no valid copy of \
BOOT_ORDER at all."
        fi
    done

    if ! grep -q "^CONFIG_ENV_OFFSET_REDUND=0x408000$" "$cfg"; then
        bbfatal "u-boot: CONFIG_ENV_OFFSET_REDUND is not 0x408000. wic blanks \
64 KiB at 4 MiB to cover both copies and fw_env.config names both offsets; \
another value puts the redundant copy where nothing else looks. Found: \
$(grep '^CONFIG_ENV_OFFSET_REDUND' "$cfg" || echo 'not set at all')"
    fi

    if ! grep -q "^CONFIG_SYS_BOOTM_LEN=${SLOTGUARD_BOOTM_LEN}\$" "$cfg"; then
        bbfatal "u-boot: CONFIG_SYS_BOOTM_LEN is not ${SLOTGUARD_BOOTM_LEN}. The Pi \
defconfig ships 0x800000 (8 MiB), which cannot relocate this image's ~8.9 MiB \
uncompressed uImage: bootm refuses and resets the board, which re-enters \
U-Boot, decrements the slot counter and tries again — condemning both slots \
for a fault that is in neither. Found: \
$(grep '^CONFIG_SYS_BOOTM_LEN' "$cfg" || echo 'not set at all')"
    fi

    if grep -q "^CONFIG_ENV_IS_IN_FAT=y" "$cfg"; then
        bbfatal "u-boot: CONFIG_ENV_IS_IN_FAT is still enabled alongside \
ENV_IS_IN_MMC. slotguard-env.cfg disables it with '# CONFIG_ENV_IS_IN_FAT is not \
set' — 'CONFIG_ENV_IS_IN_FAT=n' is silently ignored by kconfig."
    fi
}

do_deploy:append:rpi() {
    dd if=/dev/zero of=${DEPLOYDIR}/uboot-env-blank.bin bs=1024 count=64 2>/dev/null
}
