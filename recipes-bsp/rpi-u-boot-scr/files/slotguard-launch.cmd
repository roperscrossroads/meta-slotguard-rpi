
# ── The DTB comes from the firmware, not from the slot ─────────────────────
#
# The single biggest difference from the other board, and getting it wrong
# would be quiet. On the RK3506 the DTB is loaded from inside the selected
# rootfs slot so that it rolls back with its kernel. Here the VideoCore
# firmware has already loaded the DTB, applied every config.txt overlay to it,
# and handed it to U-Boot at ${fdt_addr}.
#
# Loading a per-slot DTB over that would discard the overlays — including, on a
# board that sets it, dtoverlay=disable-bt, which is what keeps the serial
# console on the PL011 rather than the clock-dependent mini UART. The symptom
# would be a console that garbles under load on a node whose last way in is that
# console.
#
# The cost, stated: the DTB is therefore not slot-scoped. It lives on the shared
# boot partition, RAUC does not manage it, and a rollback returns the kernel
# without returning the DTB. A kernel/DTB ABI break across an update is
# consequently not recoverable by rollback alone.
fdt addr ${fdt_addr}

# Keep the firmware's own arguments and append ours.
#
# cmdline.txt carries hardware setup this script has no business re-deriving
# (UART count, USB and memory parameters). Ours go last because the kernel takes
# the final occurrence of a repeated key — so root= and rauc.slot= win over
# anything the firmware set without needing to parse or strip it.
fdt get value fwargs /chosen bootargs

# ro: the rootfs slots are read-only, all persistent state is on /data.
# panic=10: self-reboot rather than hang forever.
# rauc.slot: read by rauc-mark-good.service to confirm which slot booted.
setenv bootargs "${fwargs} root=/dev/mmcblk0p${rootpart} rootfstype=ext4 rootwait ro panic=10 rauc.slot=${raucslot}"

# ── Per-slot kernel ────────────────────────────────────────────────────────
# From the selected slot's /boot, not the shared boot partition, so a kernel
# update is atomic with its rootfs and rolls back with it. U-Boot reads ext4 via
# the generic `load`.
if load @@BOOT_MEDIA@@ 0:${rootpart} ${kernel_addr_r} /boot/@@KERNEL_IMAGETYPE@@; then
  @@KERNEL_BOOTCMD@@ ${kernel_addr_r} - ${fdt_addr}
fi

# ── Last resort: the factory kernel on the boot partition ──────────────────
#
# Reached only when the selected slot has no loadable kernel. Without this the
# node is simply dead and the card has to come out — which for an unattended
# node is the failure the whole layer is trying to avoid.
#
# The kernel is already there and costs nothing to use: meta-raspberrypi's
# IMAGE_BOOT_FILES puts `uImage` on p1 next to u-boot.bin and boot.scr. No image
# change was needed to gain this path, only the decision to try it.
#
# It is never updated, and that is the point. RAUC manages the rootfs slots and
# nothing else, so this copy stays as flashed — the last line of defence must
# not depend on either slot being intact. On a board whose bootloader falls
# through to distro_bootcmd, the equivalent is the extlinux path with a factory
# kernel on its own boot partition.
#
# ── It sets rauc.slot=A explicitly, which a distro_bootcmd fallback does not ─
# meta-slotguard's A/B core warns against letting boot.scr simply return: bootcmd
# then runs distro_bootcmd, and "a factory fallback typically pins slot A and
# sets no rauc.slot=, so RAUC comes up not knowing which slot it is on and
# mark-good then acts on a guess. Alive but blind." (slotguard-ab.cmd.in, and
# meta-slotguard's ROLLBACK.md §3.1 at more length.)
#
# Nothing forces that limitation here — this fallback is part of the script, so
# it names the slot it is actually booting. A node on this path is degraded, but
# it is not lying to RAUC about where it is.
#
# The honest caveat: this pairs a flash-time kernel with a slot rootfs that may
# have been updated since, and modules live in the rootfs at
# /lib/modules/<version>. If the slot's kernel version has moved on, its modules
# will not match and hardware that needs them will be missing. Alive and
# reachable to be repaired remotely still beats a card that must be collected.
echo "RAUC: slot ${raucslot} has no loadable kernel at /boot/@@KERNEL_IMAGETYPE@@"
echo "RAUC: falling back to the factory kernel on the boot partition, slot A"

setenv bootargs "${fwargs} root=/dev/mmcblk0p2 rootfstype=ext4 rootwait ro panic=10 rauc.slot=A"

if load @@BOOT_MEDIA@@ 0:1 ${kernel_addr_r} @@KERNEL_IMAGETYPE@@; then
  @@KERNEL_BOOTCMD@@ ${kernel_addr_r} - ${fdt_addr}
fi

echo "RAUC: the factory kernel is missing from the boot partition too"
echo "RAUC: nothing left to try - the card must be recovered externally"
