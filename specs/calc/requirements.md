# Requirements: calc

## Introduction

`calc` is an expression calculator with variables and user-defined
functions (`f(x) = x^2 + 1`). It is the first dual-mode project of the
loup-cmd series: one `host.dual` source runs in three lanes, interpreted by
`loup run`, as a native binary, and as a Wasm desktop package, and a parity
test checks that the three print the same thing. Expressions come from the
command line or, one per line, from standard input.

## Requirements

### Requirement 1: Input

**User Story:** As a shell user, I want to evaluate expressions given as
arguments or piped in, so that I can use calc on the command line and in
scripts.

#### Acceptance Criteria

1. WHEN calc is given EXPRESSION arguments, THE program SHALL treat each one
   as a line of input, in order; a newline inside an argument SHALL start
   another line.
2. WHEN calc is given no EXPRESSION argument, THE program SHALL read
   standard input to the end and treat each line as a line of input; a final
   newline SHALL NOT add an empty line.
3. THE program SHALL run all lines in one session, so variables and
   functions defined on one line are visible on later lines.
4. WHEN a line holds several statements separated by `;`, THE program SHALL
   run them in order. Empty statements and lines SHALL be ignored, and `#`
   SHALL start a comment that runs to the end of the line.

### Requirement 2: Expressions

**User Story:** As a user, I want the usual arithmetic with the usual
precedence, so that expressions mean what they look like.

#### Acceptance Criteria

1. THE program SHALL accept decimal numbers (`12`, `2.5`, `.5`, `1.`,
   `1e3`, `2.5E-3`), names, parentheses, and calls `NAME(ARG, ...)`.
2. THE program SHALL support, loosest first: comparisons `== != < <= > >=`
   (giving 1 or 0), `+ -`, `* / %`, unary `-` and `+`, `^` (power), and
   postfix `!` (factorial).
3. `+ - * / %` and the comparisons SHALL be left-associative; `^` SHALL be
   right-associative and bind tighter than unary minus (`-2^2` is -4,
   `2^3^2` is 512, `2^-1` is 0.5).
4. THE program SHALL provide the constants `pi`, `e` and `ans` (the last
   printed value, initially 0) and the functions `abs ceil floor round trunc
   sqrt exp ln log sin cos tan atan` (one argument), `min` and `max` (one or
   more) and `if(COND, THEN, ELSE)`, which evaluates only the branch it takes.

### Requirement 3: Variables and functions

**User Story:** As a user, I want to name values and define my own
functions, including recursive ones.

#### Acceptance Criteria

1. WHEN a statement is `NAME = EXPR`, THE program SHALL store the value of
   EXPR in the variable NAME and print nothing.
2. WHEN a statement is `NAME(P1, ..., Pn) = EXPR`, THE program SHALL define
   the function NAME with the distinct parameter names P1..Pn and print
   nothing; a later definition SHALL replace an earlier one.
3. WHEN a user function is called, THE program SHALL bind its parameters to
   the argument values; inside the body parameters SHALL shadow variables,
   and other names SHALL be looked up when the call runs.
4. WHEN user-function calls nest more than 200 deep, THE program SHALL stop
   with `recursion too deep`.
5. WHEN a statement assigns to `pi`, `e` or `ans`, or defines a function
   named like a built-in function, THE program SHALL report an error.

### Requirement 4: Output

**User Story:** As a user, I want readable results with a precision I can
choose.

#### Acceptance Criteria

1. WHEN a statement is an expression, THE program SHALL print its value on a
   line of its own and store it in `ans`.
2. THE program SHALL round values to 12 significant digits by default, or to
   N with `-p N` / `--precision N` (1 to 17), and drop trailing zeros.
3. WHEN the decimal exponent X of the rounded value is below -6 or at least
   the precision, THE program SHALL use scientific notation (`1.5e+21`,
   `1e-7`); otherwise plain notation.
4. THE program SHALL print infinities as `inf` and `-inf`, and zero
   (including negative zero) as `0`.

### Requirement 5: Errors and exit status

**User Story:** As a script author, I want clear errors and reliable exit
statuses.

#### Acceptance Criteria

1. WHEN a line has a syntax error, THE program SHALL print
   `calc: LINE:COLUMN: MESSAGE` on standard error and run none of that line.
2. WHEN a statement fails to evaluate (division by zero, an undefined name,
   a wrong number of arguments, a domain error such as `sqrt(-1)`, `ln(0)`,
   a fractional power of a negative number or the factorial of a fraction),
   THE program SHALL print `calc: LINE: MESSAGE` on standard error, skip the
   rest of that line and continue with the next line.
3. THE program SHALL exit with status 0 when every statement succeeded, 1
   when any failed, and 2 on a usage error.
4. WHEN an unknown option or an invalid precision is given, THE program
   SHALL print `calc: MESSAGE` and `Try 'calc --help' for more information.`
   on standard error and exit with status 2.
5. Options SHALL come before the first expression; `--` SHALL end them; an
   argument that starts with `-` followed by a digit, `.` or `(` SHALL be an
   expression.

### Requirement 6: Three lanes from one source

**User Story:** As a Loup developer, I want to see one `host.dual` program
run interpreted, native and as Wasm with identical results.

#### Acceptance Criteria

1. THE sources SHALL be `@mode(host.dual)` and avoid the constructs that
   Wasm builds of Loup 1.26.0 trap on; `make lint` SHALL reject `i"..."`,
   `//`, `char.of` and `parseFloat` under `source/`.
2. `make parity` SHALL run a corpus of inputs through `loup run`, the native
   binary and the Wasm desktop package and compare standard output, standard
   error and exit status with the expected transcripts.
3. The elementary functions SHALL be computed in Loup itself, so that the
   interpreter, which has no libm, gives the same digits as the other lanes.
