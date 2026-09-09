#!/bin/sh
# shellcheck disable=SC2016
. "$(dirname "$0")/../lib.sh"

LAUNCH="$SLOTGUARD_LAUNCH_FRAGMENT"
WKS="$AB_WKS"
ENVCFG="$RPI_DIR/recipes-bsp/u-boot/files/slotguard-env.cfg"
SCRBB="$RPI_DIR/recipes-bsp/rpi-u-boot-scr/rpi-u-boot-scr.bbappend"
KBB="$RPI_DIR/recipes-kernel/linux/linux-raspberrypi_%.bbappend"
SYSCONF="$SLOTGUARD_MACHINE_SYSCONF"

describe "the pieces of the Pi integration all ship"
for f in "$LAUNCH" "$WKS" "$ENVCFG" "$SCRBB" "$KBB" "$SYSCONF"; do
    assert_file_exists "$f" "$(basename "$f")"
done

describe "the launch fragment does not re-decide the slot"
_l=$(cat "$LAUNCH")
assert_not_contains "$_l" "BOOT_ORDER"  "no slot ordering in the launch fragment"
assert_not_contains "$_l" "setexpr BOOT_" "no attempt counter is touched"
assert_contains "$_l" '${rootpart}' "it uses the slot the core chose"
assert_contains "$_l" '${raucslot}' "and passes it to the kernel as rauc.slot="

describe "every bootargs line sets panic="
_total=$(printf '%s\n' "$_l" | grep -cE '^[[:space:]]*(setenv bootargs|fdt set /chosen bootargs)')
_withp=$(printf '%s\n' "$_l" | grep -E '^[[:space:]]*(setenv bootargs|fdt set /chosen bootargs)' | grep -c 'panic=')
if [ "$_total" -eq 0 ]; then
    notok "the launch fragment defines bootargs" "no bootargs line found"
elif [ "$_total" -eq "$_withp" ]; then
    ok "all $_total bootargs line(s) set panic="
else
    notok "every bootargs line sets panic=" \
        "only $_withp of $_total — the path that can hang forever is the one that will"
fi

describe "the DTB comes from the firmware, not from the slot"
assert_contains "$_l" 'fdt addr ${fdt_addr}' "the firmware's FDT address is used"
assert_not_contains "$_l" "/boot/*.dtb" "no per-slot DTB is loaded over it"

describe "the partition map agrees between the kickstart, the script and RAUC"
_w=$(cat "$WKS")
for lbl in rootfsA rootfsB; do
    assert_contains "$_w" "--label $lbl" "$lbl is its own partition"
done
assert_contains "$_w" "data" "and data is a partition of its own"

_a=$(sed -n 's/^SLOTGUARD_ROOTPART_A[[:space:]]*=[[:space:]]*"\([0-9]*\)".*/\1/p' "$SCRBB" | head -1)
_b=$(sed -n 's/^SLOTGUARD_ROOTPART_B[[:space:]]*=[[:space:]]*"\([0-9]*\)".*/\1/p' "$SCRBB" | head -1)
assert_eq "2" "$_a" "slot A is partition 2"
assert_eq "3" "$_b" "slot B is partition 3"
assert_contains "$(cat "$SYSCONF")" "mmcblk0p$_a" "RAUC's slot A names the same partition"
assert_contains "$(cat "$SYSCONF")" "mmcblk0p$_b" "RAUC's slot B names the same partition"

describe "boot-attempts agrees between RAUC and the bootloader"
_sg=$(sed -n 's/^SLOTGUARD_ATTEMPTS[[:space:]]*=[[:space:]]*"\([0-9]*\)".*/\1/p' "$SCRBB" | head -1)
_ra=$(sed -n 's/^boot-attempts=//p' "$SYSCONF" | head -1)
assert_eq "$_ra" "$_sg" "SLOTGUARD_ATTEMPTS matches system.conf boot-attempts"
if [ -n "$_ra" ] && [ "$_ra" -ge 2 ] 2>/dev/null; then
    ok "boot-attempts is $_ra — a failed install leaves $((_ra - 1)) further tries"
else
    notok "boot-attempts leaves room after one failure" \
        "got '${_ra:-unset}'; 1 strands the device on a single bad boot"
fi

describe "the shipped compatible is a placeholder, not a product identity"

_compat=$(sed -n 's/^compatible=//p' "$SYSCONF" | head -1)
case "$_compat" in
    *UNCONFIGURED*) ok "system.conf ships a placeholder compatible ($_compat)" ;;
    "")             notok "system.conf declares a compatible" "no compatible= line" ;;
    *)              notok "system.conf ships a placeholder compatible" \
                          "found a concrete identity: $_compat" ;;
esac

_RCB="$RPI_DIR/recipes-core/rauc/rauc-conf.bbappend"
if have "$_RCB" "the rpi rauc-conf bbappend"; then
    _rcb=$(cat "$_RCB")
    assert_contains "$_rcb" "SLOTGUARD_COMPATIBLE" \
        "the compatible comes from SLOTGUARD_COMPATIBLE"
    assert_contains "$_rcb" "bb.fatal" \
        "and the build refuses when it is unset, rather than guessing"
    assert_contains "$_rcb" 's|^compatible=.*|' \
        "and the substitution is anchored, so it cannot match the prose above it"
fi

describe "the keyring path is this Yocto series', not the other one's"
_kp=$(sed -n 's|^path=||p' "$SYSCONF" | head -1)
case "$_kp" in
    /usr/lib/rauc/*) ok "the keyring is at the wrynose location ($_kp)" ;;
    /etc/rauc/*)     notok "the keyring is at the wrynose location" \
                       "[$_kp] is scarthgap's — on wrynose nothing installs there and no CA loads" ;;
    *)               notok "the keyring is at the wrynose location" "[${_kp:-unset}]" ;;
esac

describe "the A/B fragments are reached by require, not an exported layer path"
_k=$(cat "$KBB")
assert_contains "$_k" "require recipes-kernel/linux/linux_slotguard.inc" \
    "the kernel bbappend requires meta-slotguard's fragment include"

_kcode=$(printf '%s\n' "$_k" | grep -vE '^[[:space:]]*#')
assert_not_contains "$_kcode" "TOWER_SITE_LAYERDIR" "no exported layer directory in the code"
assert_contains "$(cat "$SCRBB")" "inherit slotguard-bootscript" \
    "the boot script is composed from the shared core"
