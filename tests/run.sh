#!/bin/sh
set -u

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
want="${1:-}"

total_pass=0
total_fail=0
files=0

for case_file in "$HERE"/cases/*.sh; do
    [ -f "$case_file" ] || continue
    name=$(basename "$case_file" .sh)
    [ -n "$want" ] && [ "$want" != "$name" ] && continue
    files=$(( files + 1 ))

    printf '\n== %s\n' "$name"
    out=$(sh "$case_file" 2>&1)
    rc=$?
    printf '%s\n' "$out" | grep -v '^__COUNTS__'

    if [ "$rc" -ne 0 ]; then
        printf '    DIED %s exited %d — assertions after that point never ran\n' "$name" "$rc"
        total_fail=$(( total_fail + 1 ))
    fi

    counts=$(printf '%s\n' "$out" | sed -n 's/^__COUNTS__ //p')
    p=$(printf '%s' "$counts" | cut -d' ' -f1)
    f=$(printf '%s' "$counts" | cut -d' ' -f2)
    case "$p" in ''|*[!0-9]*) p=0 ;; esac
    case "$f" in ''|*[!0-9]*) f=0 ;; esac
    total_pass=$(( total_pass + p ))
    total_fail=$(( total_fail + f ))
done

if [ "$files" -eq 0 ]; then
    printf 'no case files matched %s\n' "${want:-*}" >&2
    exit 2
fi

printf '\n---------------------------------------------\n'
printf '%d passed, %d failed, across %d case file(s)\n' "$total_pass" "$total_fail" "$files"

if [ "$total_fail" -gt 0 ]; then
    printf 'FAILED\n'
    exit 1
fi

if [ "$total_pass" -eq 0 ]; then
    printf 'FAILED — 0 assertions ran. Every case SKIPped or died.\n' >&2
    printf 'Check tests/topology.sh: a variable some case needs is unset.\n' >&2
    exit 1
fi
printf 'OK\n'
