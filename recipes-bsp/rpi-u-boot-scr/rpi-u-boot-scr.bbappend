inherit slotguard-bootscript

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append:rpi = " file://slotguard-launch.cmd"

SLOTGUARD_ROOTPART_A = "2"
SLOTGUARD_ROOTPART_B = "3"
SLOTGUARD_ROOTDEV    = "/dev/mmcblk0p"

SLOTGUARD_ATTEMPTS   = "3"
