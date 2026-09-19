config ?= debug

PACKAGE := hefermotor
GET_DEPENDENCIES_WITH := corral fetch
CLEAN_DEPENDENCIES_WITH := corral clean
COMPILE_WITH := corral run -- ponyc
BUILD_DOCS_WITH := corral run -- pony-doc

BUILD_DIR ?= build/$(config)
SRC_DIR ?= $(PACKAGE)
CLI_SRC_DIR := hefermotor_main
tests_binary := $(BUILD_DIR)/hefermotor_tests
cli_binary := $(BUILD_DIR)/hefermotor
docs_dir := build/$(PACKAGE)-docs
source_check := tools/imports/check.sh
source_check_testdata := tools/imports/testdata
grammar_guard := tools/grammar/guard.py
grammar_guard_testdata := tools/grammar/testdata
# parse.StackNeed() in KiB; test-stack fails when the two differ.
stack_need_kib := 3072
stack_fixture := hefermotor/discover/testdata/roots

ifdef config
	ifeq (,$(filter $(config),debug release))
		$(error Unknown configuration "$(config)")
	endif
endif

SOURCE_FILES := $(shell find $(SRC_DIR) -name '*.pony')
CLI_SOURCE_FILES := $(shell find $(CLI_SRC_DIR) -name '*.pony')

test: lint-source unit-tests cli syntax-fixtures

determinism: $(cli_binary)
	tools/determinism/check.sh $(cli_binary)

differential: $(cli_binary)
	tools/differential/run.sh $(cli_binary)

unit-tests: $(tests_binary)
	$^ --sequential

cli: $(cli_binary)

# The parse tests of both builds under the smallest stack the command
# accepts, each run checked to have found tests; then the release
# command over a fixture that checks clean must accept that stack,
# refuse one KiB less, and refuse an unlimited limit where the hard
# limit allows one. That pins stack_need_kib to parse.StackNeed().
test-stack: build/debug/hefermotor_tests build/release/hefermotor_tests \
  build/release/hefermotor
	ulimit -s $(stack_need_kib) && \
	  build/debug/hefermotor_tests --sequential --only=parse/ \
	  > build/debug/test-stack.txt && \
	  grep -q "Passed: [1-9]" build/debug/test-stack.txt
	ulimit -s $(stack_need_kib) && \
	  build/release/hefermotor_tests --sequential --only=parse/ \
	  > build/release/test-stack.txt && \
	  grep -q "Passed: [1-9]" build/release/test-stack.txt
	cd $(stack_fixture) && ulimit -s $(stack_need_kib) && \
	  $(CURDIR)/build/release/hefermotor check real --path=.
	cd $(stack_fixture) && ulimit -s $$(( $(stack_need_kib) - 1 )) && \
	  $(CURDIR)/build/release/hefermotor check real --path=. \
	  2> $(CURDIR)/build/release/test-stack-refusal.txt; \
	  test $$? -eq 2 && \
	  grep -q "KiB stack" $(CURDIR)/build/release/test-stack-refusal.txt
	if [ "$$(ulimit -H -s)" = unlimited ]; then \
	  cd $(stack_fixture) && ulimit -s unlimited && \
	  $(CURDIR)/build/release/hefermotor check real --path=. \
	  2> $(CURDIR)/build/release/test-stack-unlimited.txt; \
	  test $$? -eq 2 && grep -q "unlimited" \
	  $(CURDIR)/build/release/test-stack-unlimited.txt; \
	fi

build/%/hefermotor_tests: $(SOURCE_FILES) | build/%
	$(GET_DEPENDENCIES_WITH)
	$(COMPILE_WITH) $(if $(filter release,$*),,--debug) \
	  -o build/$* -b hefermotor_tests $(SRC_DIR)

syntax_binary := build/release/syntax
SYNTAX_SOURCE_FILES := $(wildcard tools/syntax/*.pony)
syntax_fixtures := $(sort $(wildcard tools/syntax/fixtures/*.pony))

syntax: $(syntax_binary)

build/%/syntax: $(SOURCE_FILES) $(SYNTAX_SOURCE_FILES) | build/%
	$(GET_DEPENDENCIES_WITH)
	$(COMPILE_WITH) $(if $(filter release,$*),,--debug) \
	  -o build/$* -b syntax tools/syntax

# Each fixture's `--tree` output against the expected output beside it,
# and every fifth mutant of the fixtures, in their sorted order, against
# the committed sample under `fixtures/mutants/`.
syntax-fixtures: $(BUILD_DIR)/syntax
	test -n "$(syntax_fixtures)"
	for f in $(syntax_fixtures); do \
	  $(BUILD_DIR)/syntax --tree $$f > $(BUILD_DIR)/fixture.tree || exit 1; \
	  diff $${f%.pony}.tree $(BUILD_DIR)/fixture.tree || exit 1; \
	done
	rm -rf $(BUILD_DIR)/mutants
	$(BUILD_DIR)/syntax --mutants $(syntax_fixtures) \
	  --emit $(BUILD_DIR)/mutants --every 5
	diff -r tools/syntax/fixtures/mutants $(BUILD_DIR)/mutants

# The parser over every stdlib file and every mutant of each, a sample
# of the mutants against ponyc's verdict, the token digests, and the
# timings; with PONYC_SRC set, the checkout's examples, full-program
# tests and tools as well. Release builds, since the numbers are
# recorded.
corpus: $(syntax_binary) build/release/hefermotor
	tools/syntax/run.sh $(syntax_binary) build/release/hefermotor

# The programs in a ponyc checkout's unit tests as sample cases for the
# differential harness, extracted into the build directory.
corpus-cases: build/release/hefermotor
	test -n "$(PONYC_SRC)" || \
	  { echo "set PONYC_SRC=<ponyc checkout>"; exit 2; }
	rm -rf build/corpus
	tools/corpus/extract_corpus.py "$(PONYC_SRC)" build/corpus
	tools/differential/run.sh build/release/hefermotor build/corpus/sample-*

# Lexer agreement with ponyc over the stdlib beside the ponyc on PATH.
# Needs a ponyc checkout (PONYC_SRC) and its built static libraries
# (PONYC_LIB, the directory holding libponyc-standalone.a); never in CI.
ponyc_dump := build/release/ponyc_dump
ponyc_bin := $(shell dirname "$$(readlink -f "$$(command -v ponyc)")")
stdlib_dir := $(ponyc_bin)/../packages

token-agreement: check-ponyc-vars $(syntax_binary) $(ponyc_dump)
	find "$(stdlib_dir)" -name '*.pony' | sort | \
	  xargs tools/agreement/check.py $(syntax_binary) $(ponyc_dump)

# One digest per stdlib package of its non-trivia token kinds, in
# `tools/syntax/token_digest/`, committed so that re-running the target
# after a lexer change diffs; regenerated in the ponyc-bump procedure.
token-digest: $(syntax_binary)
	rm -rf tools/syntax/token_digest
	tools/syntax/token_digest.sh $(syntax_binary) "$(stdlib_dir)" \
	  tools/syntax/token_digest

check-ponyc-vars:
	test -n "$(PONYC_SRC)" -a -n "$(PONYC_LIB)" || \
	  { echo "set PONYC_SRC=<ponyc checkout> PONYC_LIB=<its lib dir>"; \
	    exit 2; }

# Rebuilt when the checkout's lexer or the library changes, so a bump
# never compares against the previous ponyc's lexer.
$(ponyc_dump): tools/agreement/ponyc_dump.c tools/agreement/gen_tk_names.py \
  $(PONYC_SRC)/src/libponyc/ast/token.h $(PONYC_SRC)/src/libponyc/ast/lexer.c \
  $(PONYC_LIB)/libponyc-standalone.a | build/release
	tools/agreement/gen_tk_names.py "$(PONYC_SRC)" > build/release/tk_names.h
	gcc -O2 -o $@ tools/agreement/ponyc_dump.c -Ibuild/release \
	  -I"$(PONYC_SRC)/src/libponyc" -I"$(PONYC_SRC)/src" \
	  -I"$(PONYC_SRC)/src/common" "$(PONYC_LIB)/libponyc-standalone.a" \
	  "$(PONYC_LIB)/libponyrt-pic.a" -lstdc++ -lm -lz -lpthread -ldl -latomic

build/%/hefermotor: $(SOURCE_FILES) $(CLI_SOURCE_FILES) | build/%
	$(GET_DEPENDENCIES_WITH)
	$(COMPILE_WITH) $(if $(filter release,$*),,--debug) \
	  -o build/$* -b hefermotor $(CLI_SRC_DIR)

# Each check must first exit 1 over its own test tree with exactly the
# expected report before its result on the real tree is trusted.
lint-source: | $(BUILD_DIR)
	$(source_check) $(source_check_testdata) \
	  $(source_check_testdata)/deps.txt > $(BUILD_DIR)/source-check.txt; \
	  test $$? -eq 1
	diff $(BUILD_DIR)/source-check.txt $(source_check_testdata)/expected.txt
	$(source_check) . tools/imports/deps.txt
	$(grammar_guard) $(grammar_guard_testdata) \
	  > $(BUILD_DIR)/grammar-guard.txt; test $$? -eq 1
	diff $(BUILD_DIR)/grammar-guard.txt $(grammar_guard_testdata)/expected.txt
	$(grammar_guard) $(SRC_DIR)/parse

# A step of the ponyc-bump procedure in docs/design.md.
regen-token-kinds:
	test -n "$(PONYC_SRC)" || \
	  { echo "set PONYC_SRC=<ponyc checkout>"; exit 2; }
	tools/tokens/gen_token_kinds.py "$(PONYC_SRC)" \
	  $(SRC_DIR)/parse/token_kind.pony

clean:
	$(CLEAN_DEPENDENCIES_WITH)
	rm -rf build

$(docs_dir): $(SOURCE_FILES)
	rm -rf $(docs_dir)
	$(GET_DEPENDENCIES_WITH)
	$(BUILD_DOCS_WITH) --output build $(SRC_DIR)

docs: $(docs_dir)

TAGS:
	ctags --recurse=yes $(SRC_DIR) $(CLI_SRC_DIR)

all: test

# Named, not a pattern: `build/%` would also match the binaries.
build/debug build/release:
	mkdir -p $@

.PHONY: all cli clean corpus corpus-cases determinism differential docs \
  lint-source check-ponyc-vars regen-token-kinds syntax syntax-fixtures \
  TAGS test test-stack token-agreement token-digest unit-tests
