# Build, check and test commands for calc.
#
# On Linux x86-64 `loup` is the self-hosted driver and `loup-bootstrap` is
# Stage0; `check` and `test` need Stage0 there, and so does the Wasm build.
# On macOS, Windows and Linux arm64 both names run Stage0, so these targets
# work unchanged.
#
# calc runs in three lanes from the same source:
#   interpreted   loup run source/main.loup -- ARGS
#   native        build/calc ARGS                  (make build)
#   Wasm          build/pkg/bin/main -- ARGS       (make wasm)
# `make parity` runs a corpus through all three and compares the results.

APP            ?= calc
LOUP           ?= loup
LOUP_BOOTSTRAP ?= loup-bootstrap
BUILD_DIR      ?= build
BIN            := $(BUILD_DIR)/$(APP)
PKG            := $(BUILD_DIR)/pkg
WASM_BIN       := $(PKG)/bin/main
SOURCES        := package.lppkg $(shell find source -name '*.loup')
ARGS           ?=
TEST_ARGS      ?=

# Constructs that build to Wasm but trap at run time in Loup 1.26.0:
# i"..." interpolation, the // operator, char.of and parseFloat.
WASM_UNSAFE    := (^|[^A-Za-z0-9_"])i"|//|char\.of|parseFloat

.PHONY: all run check lint test build wasm e2e parity ci clean

all: build

# Run from source, e.g. `make run ARGS="'2^10' 'sqrt(2)'"`.
run:
	$(LOUP) run source/main.loup -- $(ARGS)

# Type-check source/main.loup and every module it imports.
check:
	$(LOUP_BOOTSTRAP) check --no-color

# Keep source/ in the subset that the Wasm lane runs correctly.
lint:
	@if grep -rnE '$(WASM_UNSAFE)' source; then \
	    echo "lint: the lines above use a construct that traps in Wasm builds"; \
	    exit 1; \
	fi
	@echo "lint: source/ is Wasm-safe"

# Tests import project modules by their path under source/ (`from cli.args
# import (...)`), the same way the sources do, so source/ goes on LOUPPATH.
# Narrow the run with TEST_ARGS, e.g. `make test TEST_ARGS="--filter parse"`.
# --no-parallel: parallel test threads have small stacks, which the
# recursion tests (200 nested calc calls) overflow; `parallel = false` in
# package.lppkg is not honoured by Loup 1.26.0.
test:
	LOUPPATH=source$${LOUPPATH:+:$$LOUPPATH} $(LOUP_BOOTSTRAP) test --no-parallel $(TEST_ARGS)

# Native executable (needs clang). Windows writes $(BIN).exe.
build: $(BIN)

$(BIN): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(LOUP) build --target native -o $@

# Wasm desktop package: build/pkg/bin/main (a launcher) runs
# build/pkg/lib/main.wasm. Needs a release install of Loup, which ships the
# launcher in bin/launchers/.
wasm: $(WASM_BIN)

$(WASM_BIN): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	rm -rf $(PKG)
	$(LOUP_BOOTSTRAP) build --target desktop -o $(PKG)

# End-to-end tests: run the built binary and compare its output and exit
# status with the expected ones.
e2e: $(BIN)
	bash tests/e2e.sh $(BIN)

# Run tests/parity/ through all three lanes and compare each with the
# expected output.
parity: $(BIN) $(WASM_BIN)
	bash tests/parity.sh "$(LOUP)" $(BIN) $(WASM_BIN)

# Everything CI runs, ending with a smoke test of the built binary.
ci: lint check test build e2e parity
	$(BIN) --version

clean:
	rm -rf $(BUILD_DIR) .temp .loup-cache
