
TESTS_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
LAYER_DIR=$(CDPATH='' cd -- "$TESTS_DIR/.." && pwd)

: "${UNITS_DIR:=}"
: "${RPI_DIR:=}"
: "${RPI_UNITS_DIR:=}"
: "${OPS_UNITS_DIR:=}"
: "${PYDIR:=}"

[ -f "$TESTS_DIR/topology.sh" ] && . "$TESTS_DIR/topology.sh"

PASS=0
FAIL=0
CURRENT=""

_emit_counts() { printf '__COUNTS__ %d %d\n' "$PASS" "$FAIL"; }
trap _emit_counts EXIT

need_dir() {
    for _n in "$@"; do
        eval "_v=\${$_n:-}"
        if [ -z "$_v" ] || [ ! -d "$_v" ]; then
            printf '    SKIP %s not available in this repo (%s unset or missing)\n' \
                "$(basename "$0" .sh)" "$_n"
            exit 0
        fi
    done
}

have() {
    [ -n "${1:-}" ] && [ -e "$1" ] && return 0
    printf '    SKIP not in this repo: %s\n' "${2:-${1:-<unset>}}"
    return 1
}

ok()   { PASS=$(( PASS + 1 )); printf '    ok   %s\n' "$1"; }
notok() {
    FAIL=$(( FAIL + 1 ))
    printf '    FAIL %s\n' "$1"
    [ -n "${2:-}" ] && printf '         %s\n' "$2"
    return 0
}

assert_eq() {
    if [ "$1" = "$2" ]; then ok "$3"; else notok "$3" "expected [$1], got [$2]"; fi
}

assert_contains() {
    case "$1" in
        *"$2"*) ok "$3" ;;
        *)      notok "$3" "expected to find [$2]" ;;
    esac
}

assert_not_contains() {
    case "$1" in
        *"$2"*) notok "$3" "did NOT expect to find [$2]" ;;
        *)      ok "$3" ;;
    esac
}

assert_file_exists() {
    if [ -e "$1" ]; then ok "$2"; else notok "$2" "missing: $1"; fi
}

assert_file_absent() {
    if [ -e "$1" ]; then notok "$2" "should not exist: $1"; else ok "$2"; fi
}

describe() { CURRENT="$1"; printf '  %s\n' "$1"; }

fixture_new() {
    F=$(mktemp -d "${TMPDIR:-/tmp}/site-test.XXXXXX") || exit 1
    mkdir -p "$F/data" "$F/pstore" "$F/proc" "$F/bin" "$F/log"
    printf 'BOOT_IMAGE=/boot/zImage root=/dev/mmcblk0p2 ro panic=10 rauc.slot=A\n' > "$F/proc/cmdline"
    printf '1234.56 2000.00\n' > "$F/proc/uptime"
    mkdir -p "$F/etc"
    printf 'ID=test-node\nVERSION_ID=1.0\n' > "$F/etc/os-release"
    printf '%s' "$F"
}

fixture_rm() { [ -n "${1:-}" ] && [ -d "$1" ] && rm -rf -- "$1"; }

stub() {
    _f="$1"; _n="$2"; shift 2
    {
        printf '#!/bin/sh\n'
        printf 'printf "%%s\\n" "$*" >> "%s/log/%s"\n' "$_f" "$_n"
        printf '%s\n' "$*"
    } > "$_f/bin/$_n"
    chmod +x "$_f/bin/$_n"
}

stub_log() { cat "$1/log/$2" 2>/dev/null || true; }

run_unit() {
    _f="$1"; _s="$2"; shift 2
    RUN_OUT=$(
        PATH="$_f/bin:$PATH" \
        SLOT_STATE_DIR="$_f/data/boot-slot-health" \
        PSTORE_DIR="$_f/pstore" \
        PSTORE_DEST="$_f/data/pstore" \
        PROC_CMDLINE="$_f/proc/cmdline" \
        DATA_DIR="$_f/data" \
        PROC_UPTIME="$_f/proc/uptime" \
        ETC_OSRELEASE="$_f/etc/os-release" \
        DEV_KMSG="$_f/log/kmsg" \
        GUARD_DEV="$_f/sys-block-mmcblk0" \
        UPDATE_CANARY="$_f/update-canary.raucb" \
        sh "$UNITS_DIR/$_s" "$@" 2>&1
    )
    RUN_RC=$?
    return 0
}

set_slot()   { printf 'BOOT_IMAGE=/boot/zImage ro rauc.slot=%s\n' "$2" > "$1/proc/cmdline"; }
set_uptime() { printf '%s.00 2000.00\n' "$2" > "$1/proc/uptime"; }

pstore_panic() { printf 'kernel panic - not syncing\n' > "$1/pstore/dmesg-ramoops-0"; }

pstore_console() { printf '%s\n' "$2" > "$1/pstore/console-ramoops-0"; }

pstore_cold() { rm -f "$1"/pstore/* 2>/dev/null || true; }

kmsg_log() { cat "$1/log/kmsg" 2>/dev/null || true; }
