# loup-cmd-calc

An expression calculator in [Loup](https://code-craft.ai/references/loup):
variables, user-defined functions (`f(x) = x^2 + 1`), recursion through
`if(...)`, built from a lexer, a Pratt parser, an AST of enums and an
evaluator. One source runs interpreted, as a native binary and as Wasm.

Part of the **loup-cmd** series of example applications: classic Linux and
Windows commands, and projects for each Loup execution mode, each in its own
repository under [myronccai](https://github.com/myronccai?tab=repositories&q=loup-cmd).
This one is a `host.dual` project: the same `.loup` files run in three
lanes, and a parity test checks that the lanes agree.

## Requirements

- [Loup Lite](https://github.com/code-craft-ai-company/loup-releases) 1.26.0
  or later, from the release installer (the Wasm lane needs the
  launcher it ships in `bin/launchers/`); see [Installing Loup Lite](#installing-loup-lite).
- `make`, and `clang` 17 or later for the native build.

## Installing Loup Lite

This example is built and tested with **Loup Lite**, the free public build of
the Loup toolchain from [Code Craft AI](https://code-craft.ai), meant for
education and training. Code Craft AI publishes the official builds,
installers and signed checksums at
**<https://github.com/code-craft-ai-company/loup-releases>**, for Linux
(x86-64, arm64), macOS (Apple silicon, Intel) and Windows (x86-64).

Linux and macOS:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
```

Windows (PowerShell):

```powershell
irm https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.ps1 | iex
```

The installer picks the archive for your machine, checks it against the
release's `SHA256SUMS`, unpacks it into `~/.loup`
(`%LOCALAPPDATA%\Programs\Loup` on Windows) and puts its `bin` directory on
your `PATH`; it needs no administrator rights. You get `loup`, the Stage0
compiler `loup-bootstrap` and the Wasm runtime `loup-launcher`. Open a new
shell and check:

```sh
loup --version             # loup 1.26.0 or later
```

CI installs the exact version it tests with, 1.26.0. To do the same:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/download/v1.26.0/loup-install.sh | sh -s -- --version 1.26.0
```

To install by hand, download your platform's archive from the
[releases page](https://github.com/code-craft-ai-company/loup-releases/releases),
check it against `SHA256SUMS`, unpack it anywhere and add its `bin` directory to
`PATH`. The [loup-releases README](https://github.com/code-craft-ai-company/loup-releases#verify-a-download)
explains how to verify the Sigstore signature on `SHA256SUMS`.

Loup Lite leaves out Loup's cryptography library and the full set of Loup
packages; this example needs neither. Commercial use of Loup needs a
license: <https://code-craft.ai/loup/license>.

## Usage

```sh
make build                         # native binary: build/calc
make wasm                          # Wasm desktop package: build/pkg/bin/main
make ci                            # lint, check, unit tests, build, e2e, parity
make run ARGS="'2^10' 'sqrt(2)'"   # run from source with loup run
```

```text
$ build/calc '1 + 2 * 3' '2^10' '-2^2' 'sqrt(2)'
7
1024
-4
1.41421356237
$ build/calc 'r = 3' 'pi * r^2'
28.2743338823
$ build/calc 'f(x) = x^2 + 1' 'f(3)' 'f(f(1))'
10
5
$ build/calc 'fact(n) = if(n <= 1, 1, n * fact(n - 1))' 'fact(20)' '170!'
2.43290200818e+18
7.25741561531e+306
$ build/calc -p 17 '0.1 + 0.2'
0.30000000000000004
$ printf 'x = 2\nx ^ 10\nsqrt(x) # a comment\n1 / 0\nans + 1\n' | build/calc; echo "exit $?"
1024
1.41421356237
calc: 4: division by zero
2.41421356237
exit 1
$ build/calc '1 +' '(2'; echo "exit $?"
calc: 1:4: unexpected end of input
calc: 2:3: expected ')' but found end of input
exit 1
$ build/calc --version
calc (loup-cmd-calc) 0.1.0
```

Each argument is one line of input; with no argument, calc reads standard
input to the end and runs it line by line. All lines share one session.

- Statements, separated by `;` or newlines (`#` starts a comment):
  `EXPR` prints its value and stores it in `ans`; `NAME = EXPR` sets a
  variable; `NAME(A, B) = EXPR` defines a function. Assignments and
  definitions print nothing.
- Operators, loosest first: `== != < <= > >=` (1 or 0), `+ -`, `* / %`,
  unary `- +`, `^` (right-associative, so `2^3^2` is 512 and `-2^2` is -4),
  postfix `!`.
- Constants `pi`, `e`, `ans`. Functions `abs ceil floor round trunc sqrt exp
  ln log sin cos tan atan`, `min(...)`, `max(...)`, and `if(COND, THEN,
  ELSE)`, which evaluates only the branch it takes, so user functions can
  recurse (at most 200 calls deep).
- Function bodies read other variables when they are called:
  `k = 2; f(x) = k * x; k = 10; f(5)` prints 50.

Options: `-p N`, `--precision N` (significant digits, 1 to 17, default 12),
`-h`/`--help`, `-V`/`--version`. Options come before the first expression
and `--` ends them; an argument that starts with `-` and a digit, `.` or `(`
is an expression (`calc -2^2`), anything else needs `--` (`calc -- -pi`).

Results are rounded to the precision and printed in plain notation, or in
scientific notation when the exponent is below -6 or at least the precision
(`1e-7`, `1.23456789012e+12`). Infinities print as `inf` and `-inf`.

Exit status: `0` if every statement succeeded, `1` if any failed (each
failure is reported as `calc: LINE[:COLUMN]: MESSAGE` and the next line
still runs), `2` for a usage error.

## What this example shows

The point of a `host.dual` program is that one source has several ways to
run. calc uses three of them:

| Lane | Command | Built by |
|---|---|---|
| interpreted | `loup run source/main.loup -- ARGS` | nothing to build |
| native | `build/calc ARGS` | `loup build --target native` (clang) |
| Wasm | `build/pkg/bin/main -- ARGS` | `loup-bootstrap build --target desktop` |

```text
$ loup run source/main.loup -- 'sin(pi/6)' 'atan(1)*4' 'exp(1)'
0.5
3.14159265359
2.71828182846
$ build/calc 'sin(pi/6)' 'atan(1)*4' 'exp(1)'
0.5
3.14159265359
2.71828182846
$ build/pkg/bin/main -- 'sin(pi/6)' 'atan(1)*4' 'exp(1)'
0.5
3.14159265359
2.71828182846
```

`make parity` runs four corpora (`tests/parity/*.calc`) and five argument
cases through all three lanes and compares standard output, standard error
and exit status with `tests/parity/*.out`: 27 runs that must all match. It
is part of `make ci`, locally and in GitHub Actions.

Getting there meant keeping to the subset of Loup 1.26.0 that every lane
runs the same way:

- **Wasm traps** at run time on `i"..."` interpolation and the `//`
  operator, so strings are joined with `+`; `make lint` rejects both (and
  `char.of` and `parseFloat`, which also trap) anywhere under `source/`.
  Unary minus on a variable and `<` on strings trap too, so the code writes
  `0.0 - x` and compares characters through `index_of`; parity catches
  anything lint cannot.
- **The interpreter has no libm**: `exp`, `ln`, `sin`, `cos`, `atan` from
  `core.math` are missing under the self-hosted `loup run`, so
  `source/engine/mathlib.loup` computes them with argument reduction and
  series, using only arithmetic that every lane evaluates bit for bit.
- **Number parsing and printing** are done by hand too: literals are
  scaled from an integer mantissa (`parseFloat` does not link natively), and
  results are rounded on the decimal digits of `str(x)`.
- **Native codegen gaps** shaped the parser and evaluator: every `match`
  that builds a string returns from each arm, and syntax errors carry their
  column in the parser rather than in a struct inside `Err`.

The Wasm package is a directory: `bin/main` is the launcher, `lib/main.wasm`
the 130 KB module, and `loup-package.json` the manifest. Copy it anywhere
and run `bin/main`. Like `loup run`, the launcher keeps arguments that start
with `--` only after a first `--`, so the parity script always passes one.

Deviation from the roadmap: there is no interactive REPL, because standard
input can only be read whole (T2); calc runs piped input as a batch.

## Layout

```text
source/main.loup              # entry point
source/appinfo.loup           # name, version, exit statuses
source/cli/args.loup          # options
source/cli/usage.loup         # --help and --version text
source/cli/app.loup           # run(): parse, dispatch, exit status
source/commands/calc.loup     # input lines, transcript, printing
source/engine/lexer.loup      # tokens with columns, number literals
source/engine/ast.loup        # Node and Stmt enums
source/engine/parser.loup     # the Pratt parser
source/engine/eval.loup       # sessions, evaluation, built-ins
source/engine/mathlib.loup    # exp, ln, sin, cos, tan, atan in plain Loup
source/engine/format.loup     # significant-digit formatting
tests/*_test.loup             # unit tests (make test)
tests/e2e.sh                  # end-to-end tests of build/calc (make e2e)
tests/parity.sh, tests/parity # three-lane parity corpus (make parity)
specs/calc/                   # requirements, design, tasks
```

[AGENTS.md](AGENTS.md) has every build and test command and the conventions
for changing the code.

## License

[MIT](LICENSE), copyright 2026 Code Craft AI LLC. The Loup skill in
[`skills/loup-programmer/`](skills/loup-programmer/) is copied from the Loup
project and is not covered by this license; it keeps the Loup project's terms.
