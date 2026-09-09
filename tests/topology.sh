_ROOT="${LAYER_DIR:-${LAYER:-}}"
[ -n "$_ROOT" ] || _ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

RPI_DIR="$_ROOT"

KERNEL_BBAPPENDS="$_ROOT/recipes-kernel/linux/linux-raspberrypi_%.bbappend"
AB_WKS="$_ROOT/files/wic/rpi-sd-ab.wks"

SLOTGUARD_LAUNCH_FRAGMENT="$_ROOT/recipes-bsp/rpi-u-boot-scr/files/slotguard-launch.cmd"

SLOTGUARD_DIR="${SLOTGUARD_DIR:-}"

LINT_EXPECT_UNITS=0
LINT_ROOTS="$_ROOT"

if [ -n "${SLOTGUARD_DIR:-}" ]; then
    _SG_BD="$SLOTGUARD_DIR/recipes-bsp/slotguard-boot/files"
    SLOTGUARD_BOOTCMD="$_ROOT/tests/.composed/boot.cmd.in"
    if [ ! -f "$SLOTGUARD_BOOTCMD" ] \
       || [ "$_SG_BD/slotguard-ab.cmd.in" -nt "$SLOTGUARD_BOOTCMD" ] \
       || [ "$SLOTGUARD_LAUNCH_FRAGMENT" -nt "$SLOTGUARD_BOOTCMD" ]; then
        python3 "$_SG_BD/slotguard-compose.py" \
            --core   "$_SG_BD/slotguard-ab.cmd.in" \
            --launch "$SLOTGUARD_LAUNCH_FRAGMENT" \
            --out    "$SLOTGUARD_BOOTCMD" \
            || rm -f "$SLOTGUARD_BOOTCMD"
    fi
    BOOT_SCRIPTS="$SLOTGUARD_BOOTCMD"
fi

SLOTGUARD_REQUEST_MODES=""

RAUC_SYSCONFS="$_ROOT/recipes-core/rauc/files/rpi/system.conf"
SLOTGUARD_MACHINE_SYSCONF="$_ROOT/recipes-core/rauc/files/rpi/system.conf"
