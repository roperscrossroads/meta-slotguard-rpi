require recipes-kernel/linux/linux_slotguard.inc

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:rpi = " file://headless-trim.cfg"

SRC_URI:append:rpi = " file://i2c-builtin.cfg"

do_configure:append:rpi() {
    cfg="${B}/.config"
    if [ ! -f "$cfg" ]; then
        bbfatal "linux-raspberrypi: no .config at ${B} after do_configure — \
headless-trim.cfg cannot be verified, and an unverifiable guard is not a \
passing one."
    fi

    for sym in CONFIG_DRM CONFIG_FB CONFIG_SOUND CONFIG_SND CONFIG_NFS_FS \
               CONFIG_USB_GADGET; do
        if grep -q "^$sym=" "$cfg"; then
            bbfatal "linux-raspberrypi: $sym is still enabled after \
headless-trim.cfg. Something selects it, so the fragment line was dropped \
silently and the kernel did not shrink. Found: $(grep "^$sym=" "$cfg")"
        fi
    done

    for sym in CONFIG_USB CONFIG_USB_SERIAL CONFIG_USB_DWC2 \
               CONFIG_SERIAL_AMBA_PL011 \
               CONFIG_EXT4_FS CONFIG_SQUASHFS CONFIG_DM_VERITY; do
        if ! grep -qE "^$sym=(y|m)$" "$cfg"; then
            bbfatal "linux-raspberrypi: $sym is not enabled. headless-trim.cfg \
has removed something load-bearing — a disabled parent took it along. This is \
the failure the trim guard exists for: a smaller kernel that cannot reach its \
own radios, console, power controller or update slots. Found: \
$(grep "^$sym" "$cfg" || echo 'not set at all')"
        fi
    done

    for sym in CONFIG_I2C CONFIG_I2C_CHARDEV CONFIG_I2C_BCM2835; do
        if ! grep -q "^$sym=y\$" "$cfg"; then
            bbfatal "linux-raspberrypi: $sym is not built in (=y). i2c-builtin.cfg \
requires it: with CONFIG_I2C_CHARDEV=m nothing loads i2c-dev, /dev/i2c-1 never \
appears, and the power controller cannot be addressed at all. Found: \
$(grep "^$sym" "$cfg" || echo 'not set at all')"
        fi
    done

}
