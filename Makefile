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

ifdef config
	ifeq (,$(filter $(config),debug release))
		$(error Unknown configuration "$(config)")
	endif
endif

ifeq ($(config),release)
	PONYC = $(COMPILE_WITH)
else
	PONYC = $(COMPILE_WITH) --debug
endif

SOURCE_FILES := $(shell find $(SRC_DIR) -name '*.pony')
CLI_SOURCE_FILES := $(shell find $(CLI_SRC_DIR) -name '*.pony')

test: lint-source unit-tests cli

determinism: $(cli_binary)
	tools/determinism/check.sh $(cli_binary)

differential: $(cli_binary)
	tools/differential/run.sh $(cli_binary)

unit-tests: $(tests_binary)
	$^ --sequential

cli: $(cli_binary)

$(tests_binary): $(SOURCE_FILES) | $(BUILD_DIR)
	$(GET_DEPENDENCIES_WITH)
	$(PONYC) -o $(BUILD_DIR) -b hefermotor_tests $(SRC_DIR)

$(cli_binary): $(SOURCE_FILES) $(CLI_SOURCE_FILES) | $(BUILD_DIR)
	$(GET_DEPENDENCIES_WITH)
	$(PONYC) -o $(BUILD_DIR) -b hefermotor $(CLI_SRC_DIR)

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
	rm -rf $(BUILD_DIR)

$(docs_dir): $(SOURCE_FILES)
	rm -rf $(docs_dir)
	$(GET_DEPENDENCIES_WITH)
	$(BUILD_DOCS_WITH) --output build $(SRC_DIR)

docs: $(docs_dir)

TAGS:
	ctags --recurse=yes $(SRC_DIR) $(CLI_SRC_DIR)

all: test

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

.PHONY: all cli clean determinism differential docs lint-source \
  regen-token-kinds TAGS test \
  unit-tests
