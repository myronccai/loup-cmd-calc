# AGENTS.md

This repository is `calc`, an expression calculator with variables and
user-defined functions written in the Loup programming language, as part of
the loup-cmd series of example applications. It is a `host.dual` project:
the same sources run under `loup run`, as a native executable and as a Wasm
desktop package, and `make parity` checks that the three agree.

## Skills

| Skill | Location | Use it when |
|-------|----------|-------------|
| `loup-programmer` | [skills/loup-programmer/SKILL.md](skills/loup-programmer/SKILL.md) | Writing, reviewing, debugging or explaining Loup code: `.lpscr`, `.loup`, `.lphc`, `.lpweb` or `.lpfree` source files, `.lppkg` manifests, `@mode(...)` directives, or the `loup` / `loup-bootstrap` commands. |

Read `skills/loup-programmer/SKILL.md` before writing or changing any Loup code
in this repository. It links to detailed references under
`skills/loup-programmer/references/` for syntax, types and ownership, execution
modes and projects, errors and diagnostics, the standard library, and common
mistakes. Load those only as needed.

## Code layout

```text
.
├── package.lppkg                # Loup manifest: name, version, toolchain, [build] entry, [test] pattern
├── Makefile                     # run, check, lint, test, build, wasm, e2e, parity, ci, clean
├── source/                      # all Loup code; modules import each other by path from here
│   ├── main.loup                # entry point: func main() calls run(runtime.args())
│   ├── appinfo.loup             # APP_NAME, APP_VERSION, APP_SUMMARY, exit statuses
│   ├── cli/
│   │   ├── args.loup            # struct Options, parse_args(): -p/--precision, --help, --version, --
│   │   ├── usage.loup           # usage(), version_line()
│   │   └── app.loup             # run(): parse, --help/--version, run_calc, exit status
│   ├── commands/
│   │   └── calc.loup            # input_lines(), calc_lines() -> Transcript, run_calc()
│   └── engine/
│       ├── lexer.loup           # TokenKind, Token, tokenize() -> Lexed, number_value()
│       ├── ast.loup             # enum Node, enum Stmt, show()
│       ├── parser.loup          # Pratt parser: parse_expr(min_bp), parse_line() -> Parsed
│       ├── eval.loup            # Session, run_line() -> LineResult, eval_node(), built-ins
│       ├── mathlib.loup         # exp, ln, sin, cos, tan, atan, pow_int, factorial
│       └── format.loup          # format_number(x, precision)
├── tests/
│   ├── *_test.loup              # unit tests: func test_*(): void
│   ├── e2e.sh                   # end-to-end tests of the native binary
│   ├── parity.sh                # runs tests/parity/ through all three lanes
│   └── parity/                  # *.calc inputs and *.out expected transcripts
├── specs/calc/                  # requirements.md, design.md, tasks.md
├── skills/loup-programmer/      # the Loup skill and its references
├── .github/workflows/ci.yml     # installs Loup and runs `make ci`
└── build/                       # build output (git-ignored): calc, pkg/
```

## Build, run and test

Prerequisites: Loup 1.26.0 from the release installer (`loup` and
`loup-bootstrap` on `PATH`, and the Wasm launcher in `bin/launchers/`),
`make`, and `clang` 17 or later for native builds.

Loup Lite comes from <https://github.com/code-craft-ai-company/loup-releases>;
[README.md](README.md#installing-loup-lite) has the install commands.

| Task | Command | Notes |
|------|---------|-------|
| Run from source | `make run ARGS="'2^10' 'x = 3; x * x'"` | `loup run source/main.loup -- ARGS` |
| Type-check | `make check` | checks `source/main.loup` and every module it imports; tests are not checked |
| Wasm-safe lint | `make lint` | greps `source/` for `i"`, `//`, `char.of`, `parseFloat` |
| Run all tests | `make test` | every `tests/*_test.loup`, sequentially |
| Run matching tests | `make test TEST_ARGS="--filter parse"` | tests whose name contains `parse` |
| Run one test file | `make test TEST_ARGS="--file tests/eval_test.loup"` | |
| Build | `make build` | native binary at `build/calc` |
| Build Wasm | `make wasm` | desktop package at `build/pkg`; run `build/pkg/bin/main -- ARGS` |
| End-to-end tests | `make e2e` | runs `tests/e2e.sh build/calc`: output compared byte for byte |
| Parity | `make parity` | `tests/parity.sh`: interpreted, native and Wasm against `tests/parity/*.out` |
| Update parity outputs | `bash tests/parity.sh loup build/calc build/pkg/bin/main --update` | rewrites `*.out` from the native lane; review the diff |
| Everything CI runs | `make ci` | lint, check, test, build, e2e, parity, then `build/calc --version` |
| Clean | `make clean` | removes `build/`, `.temp/` and `.loup-cache/` |

Run `make ci` before reporting a change as done. `loup run`, the native
build and the Wasm build do not support the same things, so a change can
pass `make test` and still fail `make build` or `make parity`.

Do not call `loup test` or `loup check` directly on Linux x86-64. There `loup`
is the self-hosted driver: it refuses `check`, and its test runner cannot
resolve this project's imports. The Makefile uses `loup-bootstrap` (Stage0) for
both, and for the Wasm build, and sets `LOUPPATH=source` for tests. Tests run
with `--no-parallel`: the parallel runner's threads have small stacks.

## Making a change

1. Update the spec in `specs/calc/` (see [specs/README.md](specs/README.md)).
2. Change the code under `source/`.
3. Add or update unit tests in `tests/`, cases in `tests/e2e.sh`, and inputs
   in `tests/parity/` (then update the expected transcripts).
4. Run `make ci`.
5. Tick the finished tasks in `specs/calc/tasks.md`.

Keep behaviour in pure functions that return values (`calc_lines` returns
the whole transcript) so unit tests can check it; only `run_calc` prints.

## Conventions

- Every source file is `@mode(host.dual)` with the `.loup` extension. Only
  `source/main.loup` has a `main()`.
- Stay in the Wasm-safe subset under `source/`: no `i"..."` (join with `+`),
  no `//`, no `char.of`, no `parseFloat`, no unary minus on a variable
  (`0.0 - x`), no `<`/`>` between strings, no `core.math.isNan` (`x != x`),
  no `exp`/`log`/`sin`/... from `core.math` (the interpreter lacks them; use
  `engine.mathlib`). Tests are not built to Wasm and may use interpolation.
- Native-build pitfalls: write a `match` that builds a string in statement
  form with a `return` in each arm; do not put a struct in `Err` when the
  `Ok` type is an enum; read a `dict[string, float]` with `containsKey` and
  `d[k]`, not `get`.
- Modules import each other by path from `source/`:
  `from engine.parser import (parse_line);`. Tests import them the same way.
  Do not use relative imports (`from .args import ...`): the self-hosted
  `loup run` on Linux x86-64 fails on them.
- Struct fields read from another module must be `pub`; fields that are
  assigned must be `var` (Stage0 enforces it).
- Keep `APP_VERSION` in `source/appinfo.loup` equal to `version` in
  `package.lppkg`.
- The skill's examples use the `loup init` layout (`src/`, `tests/`, and
  `from ..src.x import` in tests). This project uses `source/` and
  `tests/` with plain imports; follow this file.
- The skill documents toolchain 1.25.1; this project targets 1.26.0. When
  they disagree, trust the toolchain's behaviour.
