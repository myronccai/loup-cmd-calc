#!/usr/bin/env bash
# Parity tests: run the same inputs through the three lanes that calc is
# built for, and compare each lane's standard output, standard error and
# exit status with the expected transcript in tests/parity/*.out.
#
#   interpreted   LOUP run source/main.loup -- ARGS
#   native        NATIVE_BIN ARGS
#   Wasm          WASM_BIN -- ARGS     (the desktop package's launcher)
#
# usage: tests/parity.sh LOUP NATIVE_BIN WASM_BIN [--update]
# With --update, the native lane's transcripts are written as the expected
# ones (review the diff before committing them).

set -u
LOUP=$1
NATIVE=$2
WASM=$3
UPDATE=${4:-}
DIR=tests/parity
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# Cases: NAME|STDIN-FILE|ARGS (ARGS split on spaces; '_' is an empty arg list).
# The *.calc files are read from standard input; the others pass arguments.
cases=(
    "arith|$DIR/arith.calc|_"
    "functions|$DIR/functions.calc|_"
    "errors|$DIR/errors.calc|_"
    "format|$DIR/format.calc|_"
    "precision-17|$DIR/format.calc|-p 17"
    "precision-3|$DIR/functions.calc|--precision=3"
    "arguments|/dev/null|x=6*7 x/2 -x+1 sqrt(x)"
    "version|/dev/null|--version"
    "bad-option|/dev/null|-q 1"
)

# run_lane LANE STDIN ARGS... > transcript
run_lane() {
    local lane=$1 input=$2
    shift 2
    case $lane in
        interpreted) "$LOUP" run source/main.loup -- "$@" < "$input" > "$TMP/out" 2> "$TMP/err" ;;
        native)      "$NATIVE" "$@" < "$input" > "$TMP/out" 2> "$TMP/err" ;;
        wasm)        "$WASM" -- "$@" < "$input" > "$TMP/out" 2> "$TMP/err" ;;
    esac
    local status=$?
    cat "$TMP/out"
    echo "--- stderr"
    cat "$TMP/err"
    echo "--- exit status $status"
}

for entry in "${cases[@]}"; do
    IFS='|' read -r name input argline <<< "$entry"
    args=()
    if [ "$argline" != "_" ]; then
        read -r -a args <<< "$argline"
    fi
    expected="$DIR/$name.out"
    if [ "$UPDATE" = "--update" ]; then
        run_lane native "$input" "${args[@]}" > "$expected"
        echo "updated $expected"
        continue
    fi
    for lane in interpreted native wasm; do
        run_lane "$lane" "$input" "${args[@]}" > "$TMP/$lane"
        if cmp -s "$expected" "$TMP/$lane"; then
            pass=$((pass + 1))
        else
            fail=$((fail + 1))
            echo "FAIL: $name ($lane lane)"
            diff "$expected" "$TMP/$lane" | sed 's/^/    /' | head -20
        fi
    done
done

[ "$UPDATE" = "--update" ] && exit 0
echo "parity: $pass passed, $fail failed (3 lanes x ${#cases[@]} cases)"
[ "$fail" -eq 0 ]
