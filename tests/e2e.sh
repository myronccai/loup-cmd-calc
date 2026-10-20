#!/usr/bin/env bash
# End-to-end tests: run the built binary and compare its standard output
# (byte for byte) and exit status with the expected ones.
#
# usage: tests/e2e.sh BINARY

set -u
BIN=$1
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# check_file NAME STATUS EXPECTED_FILE [ARGS...]
# Runs BINARY ARGS... with standard input from the file named by $IN
# (default: /dev/null) and compares standard output with EXPECTED_FILE.
check_file() {
    local name=$1 want_status=$2 want_file=$3
    shift 3
    "$BIN" "$@" < "${IN:-/dev/null}" > "$TMP/out" 2> "$TMP/err"
    local status=$?
    if [ "$status" -eq "$want_status" ] && cmp -s "$want_file" "$TMP/out"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $name (exit $status, expected $want_status)"
        diff <(od -c "$want_file") <(od -c "$TMP/out") | sed 's/^/    /' | head -20
        sed 's/^/    stderr: /' "$TMP/err" | head -5
    fi
}

# check NAME STATUS EXPECTED_STDOUT [ARGS...]
# As check_file, with the expected output given as a string. Bash strings
# cannot hold NUL bytes; use check_file for output that contains them.
check() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    check_file "$name" "$want_status" "$TMP/want" "$@"
}

# check_err NAME STATUS EXPECTED_STDERR [ARGS...]
# Like check, but compares standard error (standard output must be empty).
check_err() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want_err"
    shift 3
    "$BIN" "$@" < "${IN:-/dev/null}" > "$TMP/out" 2> "$TMP/err"
    local status=$?
    if [ "$status" -eq "$want_status" ] && [ ! -s "$TMP/out" ] && cmp -s "$TMP/want_err" "$TMP/err"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $name (exit $status, expected $want_status)"
        diff "$TMP/want_err" "$TMP/err" | sed 's/^/    /' | head -10
        sed 's/^/    stdout: /' "$TMP/out" | head -5
    fi
}

# Expressions as arguments
check "one expression"     0 $'7\n'                    '1 + 2 * 3'
check "several"            0 $'1024\n1.41421356237\n'  '2^10' 'sqrt(2)'
check "shared session"     0 $'21\n'                   'x = 6 * 7' 'x / 2'
check "statements"         0 $'4\n16\n'                'y = 4; y; y ^ 2'
check "assignment silent"  0 ''                        'z = 1'
check "user function"      0 $'10\n'                   'f(x) = x^2 + 1' 'f(3)'
check "recursion"          0 $'3628800\n'              'fact(n) = if(n <= 1, 1, n * fact(n - 1)); fact(10)'
check "ans"                0 $'5\n6\n'                 '5' 'ans + 1'
check "comment"            0 $'3\n'                    '1 + 2  # three'
check "empty argument"     0 ''                        ''
check "newline in arg"     0 $'1\n2\n'                 $'1\n2'
check "negative number"    0 $'-4\n'                   '-2^2'
check "negative decimal"   0 $'-0.5\n'                 '-.5'
check "negative paren"     0 $'-3\n'                   '-(1 + 2)'
check "double dash"        0 $'-1\n'                   -- '-pi/pi'
check "options then --"    0 $'0.333\n'                -p 3 -- '1/3'
check "dash after expr"    0 $'1\n-1\n'                '1' '-1'

# Precision
check "default 12 digits"  0 $'0.3\n0.333333333333\n'  '0.1 + 0.2' '1/3'
check "-p 17"              0 $'0.30000000000000004\n'  -p 17 '0.1 + 0.2'
check "-pN"                0 $'3.14\n'                 -p3 'pi'
check "--precision N"      0 $'2.7183\n'               --precision 5 'e'
check "--precision=N"      0 $'0.3\n'                  --precision=1 '1/3'
check "scientific"         0 $'1.23456789012e+12\n1e-7\n' '1234567890123' '1e-7'
check "inf"                0 $'inf\n'                  '1e308 * 10'

# Standard input
printf '# a comment\nx = 2\nx ^ 10\n\nsqrt(x * 8)\n' > "$TMP/batch"
IN="$TMP/batch" check "stdin batch"  0 $'1024\n4\n'
printf '1 + 1' > "$TMP/nonl"
IN="$TMP/nonl" check "no final newline" 0 $'2\n'
IN=/dev/null check "empty stdin"       0 ''
printf '1\r\n2\r\n' > "$TMP/crlf"
IN="$TMP/crlf" check "CRLF lines"      0 $'1\n2\n'
printf '1/0\n2\n' > "$TMP/fail"
IN="$TMP/fail" check "error keeps going" 1 $'2\n'
IN="$TMP/fail" check_err "error message"  1 $'calc: 1: division by zero\n' '1/0'
echo '5' > "$TMP/ignored"
IN="$TMP/ignored" check "args win over stdin" 0 $'1\n' '1'

# Errors (status 1) and their messages
check_err "syntax error"       1 $'calc: 1:4: unexpected end of input\n'               '1 +'
check_err "column"             1 $'calc: 1:7: expected \')\' but found end of input\n' '(1 + 2'
check_err "bad character"      1 $'calc: 1:3: unexpected character \'$\'\n'           '2 $ 3'
check_err "undefined variable" 1 $'calc: 1: undefined variable \'q\'\n'               'q'
check_err "undefined function" 1 $'calc: 1: undefined function \'g\'\n'               'g(1)'
check_err "arity"              1 $'calc: 1: sqrt() takes 1 argument, got 2\n'         'sqrt(1, 2)'
check_err "domain"             1 $'calc: 1: sqrt() of a negative number\n'            'sqrt(-1)'
check_err "built-in name"      1 $'calc: 1: cannot assign to built-in name \'e\'\n'   'e = 2'
check_err "recursion limit"    1 $'calc: 1: recursion too deep (more than 200 nested calls)\n' 'r(n) = r(n + 1); r(0)'
check_err "second argument"    1 $'calc: 2: division by zero\n'                       'x = 1' 'x / 0'

# Options and usage errors (status 2)
check "version"            0 $'calc (loup-cmd-calc) 0.1.0\n'  --version
check "-V"                 0 $'calc (loup-cmd-calc) 0.1.0\n'  -V
"$BIN" --help > "$TMP/help" 2>&1
if head -1 "$TMP/help" | grep -q '^usage: calc \[OPTION\]... \[EXPRESSION\]...$'; then
    pass=$((pass + 1))
else
    fail=$((fail + 1)); echo "FAIL: --help first line"; head -3 "$TMP/help"
fi
check_err "unknown option"     2 $'calc: unknown option \'-x\'\nTry \'calc --help\' for more information.\n' -x
check_err "missing precision"  2 $'calc: option \'-p\' requires an argument\nTry \'calc --help\' for more information.\n' -p
check_err "bad precision"      2 $'calc: invalid precision \'0\' (expected 1 to 17)\nTry \'calc --help\' for more information.\n' -p 0 1
check_err "precision too big"  2 $'calc: invalid precision \'18\' (expected 1 to 17)\nTry \'calc --help\' for more information.\n' --precision=18 1

echo "e2e: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
