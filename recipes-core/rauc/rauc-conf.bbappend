FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SLOTGUARD_COMPATIBLE ?= ""

do_install[prefuncs] += "slotguard_rpi_require_compatible"
python slotguard_rpi_require_compatible() {
    if not d.getVar("SLOTGUARD_COMPATIBLE"):
        bb.fatal(
            "meta-slotguard-rpi: no RAUC `compatible` configured.\n"
            "  This layer ships none on purpose: `compatible` is what decides\n"
            "  which update bundles this device will ever install, and a default\n"
            "  would make your device accept bundles built for another product.\n"
            "  Set SLOTGUARD_COMPATIBLE in your own layer, e.g.\n"
            "    SLOTGUARD_COMPATIBLE = \"my-product-rpi\"\n"
            "  See recipes-core/rauc/rauc-conf.bbappend."
        )
}

do_install:append() {
    if [ -f ${D}${nonarch_libdir}/rauc/system.conf ]; then
        sed -i "s|^compatible=.*|compatible=${SLOTGUARD_COMPATIBLE}|" \
            ${D}${nonarch_libdir}/rauc/system.conf
    fi
}

PACKAGE_ARCH = "${MACHINE_ARCH}"
