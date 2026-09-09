#!/bin/sh
. "$(dirname "$0")/../lib.sh"

SANDBOX="$LAYER_DIR/.artifacts/uboot-sandbox-rpi/u-boot"
SANDBOX_DTB="$LAYER_DIR/.artifacts/uboot-sandbox-rpi/u-boot.dtb"
BOOTCMD_IN="${SLOTGUARD_BOOTCMD:-}"
SCR_BBAPPEND="$RPI_DIR/recipes-bsp/rpi-u-boot-scr/rpi-u-boot-scr.bbappend"

if ! have "$BOOTCMD_IN" "the composed boot.cmd.in — needs SLOTGUARD_DIR"; then
    printf '    (set SLOTGUARD_DIR to a meta-slotguard checkout to run this)\n'
    exit 0
fi
ok "the composed boot.cmd.in is present"
assert_file_exists "$SCR_BBAPPEND" "the bbappend that makes it win is present"

if [ ! -x "$SANDBOX" ] || [ ! -f "$SANDBOX_DTB" ]; then
    printf '  SKIPPED: no Pi sandbox U-Boot at %s\n' "${SANDBOX#"$LAYER_DIR"/}"
    printf '  Without it the Pi boot script is covered by nothing at all — it is\n'
    printf '  newer than the board one and has never run on hardware. Build it:\n'
    printf '      bitbake mc:rpi0:u-boot   # in the wrynose tree, once\n'
    printf '      then copy the resulting u-boot and u-boot.dtb into that directory\n'
    exit 0
fi

BOOTCMD_TEXT=$(sed -e 's/@@KERNEL_IMAGETYPE@@/uImage/' \
                   -e 's/@@KERNEL_BOOTCMD@@/bootm/' \
                   -e 's/@@BOOT_MEDIA@@/mmc/' "$BOOTCMD_IN")

assert_not_contains "$BOOTCMD_TEXT" '@@' \
    "every placeholder was substituted — a leftover @@ would be a syntax error"

RPI_COMMON="${SLOTGUARD_RPI_MULTICONFIG:-}"
if have "$RPI_COMMON" "the Pi multiconfig (the integrator's layer)"; then
    assert_contains "$(cat "$RPI_COMMON")" 'RPI_USE_U_BOOT = "1"' \
        "the multiconfig really does select U-Boot, which is what makes it uImage/bootm"
fi

ub() {
    "$SANDBOX" -d "$SANDBOX_DTB" -c "$1" 2>&1
}

boot_cmd_with() {
    ub "$1
$BOOTCMD_TEXT
echo ===ENV===
printenv BOOT_ORDER
printenv BOOT_A_LEFT
printenv BOOT_B_LEFT
printenv raucslot
printenv rootpart"
}

describe "FIDELITY: the binary is MAINLINE, not the board's vendor fork"
fid=$(ub 'setexpr T 3 - 1; printenv T')
assert_contains "$fid" "T=2" "setexpr formats without a 0x prefix (mainline)"
assert_not_contains "$fid" "T=0x2" "...and specifically NOT the fork's hex form"

fid2=$(ub 'if test 0x2 -gt 0; then echo GT_TRUE; else echo GT_FALSE; fi')
assert_contains "$fid2" "GT_TRUE" "test strips the 0x, so -gt 0 is TRUE (mainline)"

case "$fid$fid2" in
    *T=2*GT_TRUE*) ;;
    *)
        printf '\n  FIDELITY CHECK FAILED — refusing to run behavioural cases.\n'
        printf '  This binary shows the VENDOR fork semantics, which means the\n'
        printf '  wrong source was built and every assertion below would describe\n'
        printf '  a bootloader the Pi does not have.\n'
        exit 1
        ;;
esac

describe "a first boot with an empty environment picks A and decrements it"
out=$(boot_cmd_with '')
assert_contains "$out" "raucslot=A"   "slot A is chosen"
assert_contains "$out" "rootpart=2"   "which is partition 2"
assert_contains "$out" "BOOT_A_LEFT=2" "A's attempts went 3 -> 2 BEFORE booting"
assert_contains "$out" "BOOT_B_LEFT=3" "B is untouched"

describe "a spent slot is skipped and the next one taken"
out=$(boot_cmd_with 'setenv BOOT_ORDER "A B"; setenv BOOT_A_LEFT 0; setenv BOOT_B_LEFT 3')
assert_contains "$out" "raucslot=B"   "A is exhausted, so B is chosen"
assert_contains "$out" "rootpart=3"   "which is partition 3"
assert_contains "$out" "BOOT_B_LEFT=2" "B's attempts were decremented"

describe "BOTH slots spent restores the order and boots A anyway"
out=$(boot_cmd_with 'setenv BOOT_ORDER "A"; setenv BOOT_A_LEFT 0; setenv BOOT_B_LEFT 0')
assert_contains "$out" "nothing bootable" "it says so"
assert_contains "$out" "raucslot=A"      "and boots A rather than stopping"
assert_contains "$out" 'BOOT_ORDER=A B'  "BOOT_ORDER is rebuilt, not just the counters"
assert_contains "$out" "BOOT_A_LEFT=2"   "A gets 2, because this pass IS its first attempt"

assert_contains "$out" "BOOT_B_LEFT=3"   "and B is restored to a full 3, or it is never tried again"

describe "a one-shot request forces a slot without spending an attempt"
out=$(boot_cmd_with 'setenv BOOT_ORDER "A B"; setenv BOOT_A_LEFT 3; setenv BOOT_B_LEFT 3; setenv BOOT_REQUEST B')
assert_contains "$out" "forcing slot B"  "the request is honoured"
assert_contains "$out" "raucslot=B"      "B is booted"
assert_contains "$out" "BOOT_A_LEFT=3"   "A's counter is untouched"
assert_contains "$out" "BOOT_B_LEFT=3"   "and so is B's — a diagnostic boot, not a policy change"

describe "...and it is CLEARED before it is acted on"
assert_contains "$out" "consumed and cleared" "the request is consumed"
req=$(ub "setenv BOOT_REQUEST B
$BOOTCMD_TEXT
echo ===ENV===
printenv BOOT_REQUEST")
assert_not_contains "$req" "BOOT_REQUEST=B" "BOOT_REQUEST does not survive the run"

describe "the kernel load fails here, and the documented fall-through happens"
out=$(boot_cmd_with '')
assert_contains "$out" "has no loadable kernel" "it reports which slot failed"

assert_contains "$out" "falling back to the factory kernel" \
    "the last-resort path is attempted rather than the node simply dying"
assert_contains "$out" "factory kernel is missing from the boot partition too" \
    "and only THEN does it give up"
assert_contains "$out" "recovered externally" "saying the card must be collected"

slot_line=$(printf '%s\n' "$out" | grep -n 'has no loadable kernel' | head -1 | cut -d: -f1)
fb_line=$(printf '%s\n' "$out" | grep -n 'falling back to the factory' | head -1 | cut -d: -f1)
if [ -n "$slot_line" ] && [ -n "$fb_line" ] && [ "$slot_line" -lt "$fb_line" ]; then
    ok "the slot kernel is tried BEFORE the factory one"
else
    notok "the slot kernel is tried BEFORE the factory one" \
        "slot message at line ${slot_line:-none}, fallback at ${fb_line:-none}"
fi

describe "the fallback names the slot it is actually booting"
code=$(printf '%s\n' "$BOOTCMD_TEXT" | grep -v '^[[:space:]]*#')
assert_contains "$code" 'rauc.slot=A' "the fallback bootargs declare slot A"
assert_contains "$code" 'root=/dev/mmcblk0p2' "matching the partition it boots"

describe "BOTH spellings of zero count as exhausted"
for zero in 0 0x0; do
    out=$(boot_cmd_with "setenv BOOT_ORDER \"A B\"; setenv BOOT_A_LEFT $zero; setenv BOOT_B_LEFT 3")
    assert_contains "$out" "raucslot=B" "A spelled '$zero' is exhausted, so B is taken"
done

describe "BOOT_ORDER decides preference, not the slot letter"
out=$(boot_cmd_with 'setenv BOOT_ORDER "B A"; setenv BOOT_A_LEFT 3; setenv BOOT_B_LEFT 3')
assert_contains "$out" "raucslot=B"    "B is first in BOOT_ORDER, so B boots"
assert_contains "$out" "rootpart=3"    "and root is its partition"
assert_contains "$out" "BOOT_A_LEFT=3" "A keeps its full budget, untouched"

describe "an INCOMPLETE BOOT_ORDER is repaired, not obeyed"
out=$(boot_cmd_with 'setenv BOOT_ORDER "A"; setenv BOOT_A_LEFT 0; setenv BOOT_B_LEFT 3')
assert_contains "$out" "nothing bootable"  "the truncated order leaves nothing selectable"
assert_contains "$out" 'BOOT_ORDER=A B'    "so the order is REBUILT, which is the repair"
assert_contains "$out" "BOOT_B_LEFT=3"     "B's budget is restored rather than assumed"

describe "a forced slot works even when that slot is exhausted"
out=$(boot_cmd_with 'setenv BOOT_ORDER "A B"; setenv BOOT_A_LEFT 3; setenv BOOT_B_LEFT 0; setenv BOOT_REQUEST B')
assert_contains "$out" "forcing slot B" "the request is honoured despite B being spent"
assert_contains "$out" "raucslot=B"     "B boots"
assert_contains "$out" "BOOT_B_LEFT=0"  "and its counter is still not touched"

describe "an unknown one-shot request degrades to a normal boot"
out=$(boot_cmd_with 'setenv BOOT_ORDER "A B"; setenv BOOT_A_LEFT 3; setenv BOOT_B_LEFT 3; setenv BOOT_REQUEST loader')
assert_contains "$out" "consumed and cleared" "the unknown verb is still consumed"
assert_contains "$out" "raucslot=A"           "and selection proceeds normally"
assert_contains "$out" "BOOT_A_LEFT=2"        "spending an attempt exactly as an ordinary boot does"

describe "rootpart is never derived from the environment"
code=$(printf '%s\n' "$BOOTCMD_TEXT" | grep -v '^[[:space:]]*#')
assert_contains "$code" 'setenv rootpart 2' "slot A's partition is a literal"
assert_contains "$code" 'setenv rootpart 3' "slot B's partition is a literal"
# shellcheck disable=SC2016
assert_not_contains "$code" 'setenv rootpart ${' \
    "and nothing assigns rootpart from a variable"
