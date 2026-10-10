require recipes-kernel/linux/linux_slotguard.inc

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# This layer takes nothing out of the Pi kernel. What a product does not need
# (display and sound on a headless node, say) is that product's decision and
# lives in its own layer, with its own guard that the removal took effect. What
# is here is what the update stack and its boards cannot work without, and the
# guard below holds whatever a deployment's fragments do.
SRC_URI:append:rpi = " file://i2c-builtin.cfg"

do_configure:append:rpi() {
    cfg="${B}/.config"
    if [ ! -f "$cfg" ]; then
        bbfatal "linux-raspberrypi: no .config at ${B} after do_configure — \
the kernel config cannot be verified, and an unverifiable guard is not a \
passing one."
    fi

    for sym in CONFIG_USB CONFIG_USB_SERIAL CONFIG_USB_DWC2 \
               CONFIG_SERIAL_AMBA_PL011 \
               CONFIG_EXT4_FS CONFIG_SQUASHFS CONFIG_DM_VERITY; do
        if ! grep -qE "^$sym=(y|m)$" "$cfg"; then
            bbfatal "linux-raspberrypi: $sym is not enabled. A config fragment \
has removed something load-bearing — a disabled parent took it along. This is \
the failure this guard exists for: a smaller kernel that cannot reach its \
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
