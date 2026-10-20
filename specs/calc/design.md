# Design: calc

## Overview

`main()` passes `runtime.args()` to `cli.app.run`, which parses the options,
handles `--help` and `--version`, and calls `commands.calc.run_calc`. That
collects the input lines and runs them through one `Session`. Each line goes
through four stages:

```text
text --lexer--> tokens --Pratt parser--> statements (AST enums) --evaluator--> values --format--> text
```

Everything up to printing is pure: `calc_lines` returns a transcript of
values and error messages, and only `run_calc` prints.

## Modules

| Module | Contents |
|---|---|
| `source/main.loup` | entry point: `run(runtime.args())` |
| `source/appinfo.loup` | name, version, summary, exit statuses |
| `source/cli/args.loup` | `Options`, `parse_args`, `parse_precision`, `looks_like_expression` |
| `source/cli/usage.loup` | `usage()` help text, `version_line()` |
| `source/cli/app.loup` | `run()`: parse, help/version, run, map exceptions to status 1 |
| `source/commands/calc.loup` | `input_lines`, `split_input`, `calc_lines` (→ `Transcript`), `error_text`, `run_calc` |
| `source/engine/lexer.loup` | `TokenKind` enum, `Token`, `tokenize` (→ `Lexed`), `number_value` |
| `source/engine/ast.loup` | `Node` and `Stmt` enums, `show`/`show_stmt` (parenthesised rendering) |
| `source/engine/parser.loup` | the Pratt parser: `parse_expr(min_bp)`, `parse_line` (→ `Parsed`) |
| `source/engine/eval.loup` | `Session`, `run_line` (→ `LineResult`), `eval_node`, `binary`, `power`, `call_builtin` |
| `source/engine/mathlib.loup` | `exp`, `ln`, `log10`, `sin`, `cos`, `tan`, `atan`, `pow_int`, `factorial`, rounding |
| `source/engine/format.loup` | `format_number(x, precision)`, `to_decimal`, `round_decimal` |

### Lexer

`tokenize` scans one line into `Number`, `Name`, `Op`, `LParen`, `RParen`,
`Comma`, `Assign`, `Semi` and a final `End` token, each with its 1-based
column. A number literal keeps up to 18 significant digits as an integer
mantissa and is scaled by powers of ten (exact up to 10^22), because
`system.text.parseFloat` does not link natively and traps in Wasm.

### Parser

A Pratt parser. `parse_expr(min_bp)` parses a prefix (number, name, call,
parenthesised expression, unary `-`/`+` with right binding power 40) and
then folds in infix operators while their left binding power is at least
`min_bp`:

| Operators | Left bp | Right bp |
|---|---|---|
| `== != < <= > >=` | 10 | 11 |
| `+ -` | 20 | 21 |
| `* / %` | 30 | 31 |
| `^` | 51 | 50 (right-associative) |
| postfix `!` | 60 | — |

A statement is parsed as an expression first; if `=` follows, a `Var`
target becomes `Stmt.Assign` and a `Call` whose arguments are all names
becomes `Stmt.Define`. Nesting is limited to 64 levels.

Syntax errors are `Err(message)` with the column stored in the parser
(`error_col`): native builds of Loup 1.26.0 misread a struct carried in
`Err` when the `Ok` type is an enum.

### Evaluator

`eval_node(session, node, locals, depth)` returns `Result[float, string]`
and matches on the `Node` variants. Names resolve to parameters (`locals`),
then `pi` and `e`, then session variables (including `ans`). A user call
evaluates the arguments, binds them to the parameters in a fresh frame and
evaluates the body with `depth + 1` (at most 200). `if` is a special form
that evaluates one branch only.

Every `match` that builds a value is written in statement form, with a
`return` in each arm: in native builds a `match` expression whose arm
builds a new string returns freed memory.

### Math and formatting

`loup run` on Linux x86-64 has no libm (`exp`, `log`, `sin` from
`core.math` are missing), so `mathlib` computes them with argument
reduction and series: `exp` (r = x − k·ln2, Taylor series, scale by 2^k),
`ln` (x = m·2^k, 2·atanh series), `sin`/`cos` (Cody–Waite reduction by
π/2, Taylor series), `atan` (reduction to |x| ≤ tan(π/8), series).
Non-integer powers are `exp(y·ln x)`; integer powers use repeated squaring.
Only `+ - * /`, comparisons and `floor` are used, so all lanes give
the same bits.

`format_number` starts from `str(x)` (the shortest round-trip decimal,
identical in every lane), rounds its digits half-up to the precision, and
chooses plain or scientific notation like `%g`, with scientific notation
for exponents below -6.

## What this example shows

- One `host.dual` source, three lanes: `loup run`, `loup build --target
  native`, and `loup-bootstrap build --target desktop` (Wasm plus a
  launcher), checked against each other by `make parity`.
- The Wasm-safe subset of Loup 1.26.0, enforced by `make lint`: no `i"..."`
  (strings are joined with `+`), no `//`, no `char.of`, no `parseFloat`;
  also no unary minus on variables (`0.0 - x`) and no ordering comparisons
  of strings, which parity would catch.
- A lexer, a Pratt parser, an AST of recursive enums and a tree-walking
  evaluator, with `Result` and `?` for errors.

## Deviations from the roadmap

- No interactive REPL (T2): standard input is read to the end, then run.
- Transcendental functions are computed in Loup, not taken from
  `core.math`, so the interpreted lane can run them.

## Error handling

Syntax errors and evaluation errors are values (`Parsed.error`,
`Err(message)`), reported per line with the line number (and column for
syntax errors); the next line still runs. An unexpected exception is
reported as `calc: MESSAGE` with status 1.

## Testing

- `tests/args_test.loup`: options, precision forms and range, `--`,
  negative numbers as expressions.
- `tests/lexer_test.loup`: token kinds, columns, numbers, comments, errors.
- `tests/parser_test.loup`: precedence, associativity, unary and postfix
  operators, statements, syntax errors, the nesting limit.
- `tests/eval_test.loup`: sessions, `ans`, user functions, shadowing, late
  binding, recursion and its limit, lazy `if`, error messages.
- `tests/mathlib_test.loup`: the elementary functions against reference
  values.
- `tests/format_test.loup`: rounding, carries, notation, special values.
- `tests/calc_test.loup`, `tests/app_test.loup`: transcripts and exit
  statuses.
- `tests/e2e.sh`: the native binary, byte for byte.
- `tests/parity.sh` with `tests/parity/`: four corpora and five argument
  cases through all three lanes.
