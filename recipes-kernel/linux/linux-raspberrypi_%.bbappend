require recipes-kernel/linux/linux_slotguard.inc

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:rpi = " file://headless-trim.cfg"

# USB device (gadget) mode is trimmed with the rest unless a deployment opts in.
# "1" keeps it, and the guard below then requires it to be a MODULE: nothing
# loads it unless a device tree puts the controller in peripheral mode, so the
# kernel image does not grow and a host-mode node behaves exactly as before.
SLOTGUARD_RPI_USB_GADGET ?= "0"
SRC_URI:append:rpi = "${@'' if d.getVar('SLOTGUARD_RPI_USB_GADGET') == '1' else ' file://no-usb-gadget.cfg'}"

SRC_URI:append:rpi = " file://i2c-builtin.cfg"

do_configure:append:rpi() {
    cfg="${B}/.config"
    if [ ! -f "$cfg" ]; then
        bbfatal "linux-raspberrypi: no .config at ${B} after do_configure — \
headless-trim.cfg cannot be verified, and an unverifiable guard is not a \
passing one."
    fi

    trimmed="CONFIG_DRM CONFIG_FB CONFIG_SOUND CONFIG_SND CONFIG_NFS_FS"
    if [ "${SLOTGUARD_RPI_USB_GADGET}" != "1" ]; then
        trimmed="$trimmed CONFIG_USB_GADGET"
    fi
    for sym in $trimmed; do
        if grep -q "^$sym=" "$cfg"; then
            bbfatal "linux-raspberrypi: $sym is still enabled after \
headless-trim.cfg. Something selects it, so the fragment line was dropped \
silently and the kernel did not shrink. Found: $(grep "^$sym=" "$cfg")"
        fi
    done

    if [ "${SLOTGUARD_RPI_USB_GADGET}" = "1" ]; then
        if ! grep -q '^CONFIG_USB_GADGET=m$' "$cfg"; then
            bbfatal "linux-raspberrypi: SLOTGUARD_RPI_USB_GADGET is 1, so \
CONFIG_USB_GADGET must be =m — kept, and never built in. Found: \
$(grep '^CONFIG_USB_GADGET' "$cfg" || echo 'not set at all')"
        fi
    fi

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
