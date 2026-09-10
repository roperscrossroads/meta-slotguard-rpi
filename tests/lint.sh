#!/bin/sh
set -u

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
LAYER=$(CDPATH='' cd -- "$HERE/.." && pwd)
UNITS="$LAYER/recipes-core"

LINT_ROOTS="${LINT_ROOTS:-}"
[ -f "$HERE/topology.sh" ] && . "$HERE/topology.sh"
if [ -z "$LINT_ROOTS" ]; then
    LINT_ROOTS="$LAYER"
    for _d in "$LAYER"/meta-*; do
        [ -f "$_d/conf/layer.conf" ] && LINT_ROOTS="$LINT_ROOTS $_d"
    done
fi
UNITS_NESTED="$LINT_ROOTS"

if ! command -v shellcheck >/dev/null 2>&1; then
    if [ "${LINT_STRICT:-0}" = "1" ]; then
        printf 'shellcheck not installed and LINT_STRICT=1 — FAILING.\n' >&2
        exit 1
    fi
    printf 'shellcheck not installed — SKIPPING the bashism gate.\n'
    printf 'This is the check that catches "works in bash, dies on busybox".\n'
    printf 'Install it:  apt install shellcheck   (or: pip install shellcheck-py)\n'
    exit 0
fi

rc=0
units_linted=0

_candidates=""
for _root in $UNITS_NESTED; do
    _candidates="$_candidates $_root/recipes-*/*/files/* $_root/recipes-*/*/files/*/*"
done

# shellcheck disable=SC2086  # word-splitting the glob list is the point
for f in $_candidates "$UNITS"/*/files/* "$UNITS"/*/files/*/* \
         "$HERE"/run.sh "$HERE"/lint.sh "$HERE"/cases/*.sh \
         "$LAYER"/bench/*.sh; do
    [ -f "$f" ] || continue
    case "$f" in *.service|*.conf|*.rules|*.mount) continue ;; esac
    head -n 1 "$f" | grep -q '^#!.*sh' || continue
    printf '  %s\n' "${f#"$LAYER"/}"
    case "$f" in
        */files/*)
            units_linted=$(( units_linted + 1 ))
            shellcheck -s sh -e SC1091 "$f" || rc=1 ;;
        *)
            shellcheck -e SC1091 "$f" || rc=1 ;;
    esac
done

if [ "$units_linted" -eq 0 ] && [ "${LINT_EXPECT_UNITS:-}" = "0" ]; then
    printf '  (0 shipped unit scripts — declared by tests/topology.sh, not inferred)\n'
elif [ "$units_linted" -eq 0 ]; then
    printf '\nlint FAILED: no unit scripts were checked at all.\n'
    printf '  If this layer genuinely ships none, declare it:\n'
    printf '    LINT_EXPECT_UNITS=0   # in tests/topology.sh\n'
    printf '  UNITS=%s\n' "$UNITS"
    printf '  UNITS_NESTED=%s\n' "$UNITS_NESTED"
    printf '  The shipped scripts are what matter here; linting only the test\n'
    printf '  files is worse than useless because it still exits 0.\n'
    exit 1
fi
[ "$units_linted" -gt 0 ] && printf '  (%d shipped unit scripts checked)\n' "$units_linted"

if [ "$rc" -ne 0 ]; then
    printf '\nlint FAILED\n'
    exit 1
fi
printf '\nlint OK\n'
