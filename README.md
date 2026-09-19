# hefermotor

A semantic analyzer for Pony, built beside ponyc rather than inside it. It
parses a program, resolves names, extracts signatures, checks method bodies
and reference capabilities, and reports diagnostics. It generates no code.

## Status

Pre-release. The M0 skeleton is complete; nothing after package discovery
checks Pony code yet. See `docs/design.md` for the design and the
decision log.

## Building

* Install [corral](https://github.com/ponylang/corral),
  [ponyc](https://github.com/ponylang/ponyc) and python3
* `make` runs the source check, builds the tests and the `hefermotor`
  command into `build/debug/`, and runs the tests
* `make determinism` checks, with the `ponyc` on `PATH`, that two runs
  give one document and that a package's export hash does not depend on
  where the package sits
* `make differential` compares verdicts, package sets and group
  partitions with the `ponyc` on `PATH` over the fixtures in
  `tools/differential/cases` and every package beside that `ponyc`, and
  on the `syntax-*` fixtures the positions of the parse errors; needs
  python3
* `make token-agreement PONYC_SRC=<ponyc checkout> PONYC_LIB=<its lib
  dir>` compares the lexer's token kinds with ponyc's lexer's over
  every stdlib file beside the `ponyc` on `PATH`, linking
  `tools/agreement/ponyc_dump.c` against the checkout's
  `libponyc-standalone.a`; needs gcc
* `make corpus` runs the parser over every stdlib file beside the
  `ponyc` on `PATH` and 48 single-edit mutants of each, checking every
  tree's invariants, then compares a sample of the mutants with that
  `ponyc`'s verdict at `--pass=parse`, compares every stdlib module's
  items and types with that `ponyc`'s parse-pass AST
  (`tools/syntax/agree.py`), compares the token digests with
  `tools/syntax/token_digest/`, and times `hefermotor check` over the
  stdlib; with `PONYC_SRC=<ponyc checkout>` the checkout's `examples/`,
  `test/full-program-tests/` and `tools/` are checked too and the
  full-program tests go through the AST comparison
* `make corpus-cases PONYC_SRC=<ponyc checkout>` extracts the programs
  in the checkout's `test/libponyc/*.cc` into `build/corpus/` and
  compares the parser's verdict on each with the `ponyc` on `PATH` at
  `--pass=parse`
* `make token-digest` writes one digest per stdlib package of its token
  kinds to `tools/syntax/token_digest/`
* `make syntax` builds `build/release/syntax`, whose `--tree` prints a
  file's parse tree and diagnostics, `--shape` prints its items and
  types in the shape of ponyc's AST, `--check` parses files and their
  mutants and checks every tree's invariants, and `--mutants --emit`
  writes a sample of the mutants as fixture packages;
  `tools/syntax/main.pony` has the details

## Usage

```text
hefermotor check [<target>] [--path=DIR ...] [--json]
```

`hefermotor check` discovers a program's packages through their `use`
declarations, in ponyc's search order, and groups them as ponyc does.
`<target>` is a package directory, or a package name found through the
search roots, and defaults to the current directory. The search roots
are the packages beside the `ponyc` on `PATH`, then each `--path`, then
`PONYPATH`, then `/usr/local/lib` and `/opt/local/lib`, in ponyc's
order. Diagnostics go to stderr in ponyc's shape; `--json` prints one
document to stdout instead. The exit code is 0 with nothing to report, 1 with diagnostics,
2 when the run could not start, and 70 for an internal error.

The parser bounds its recursion at a depth that needs 3 MiB of stack
per scheduler thread, and the runtime sizes each thread's stack from
`ulimit -s`. So `hefermotor check` refuses to start, with exit 2, when
the soft limit is below 3072 KiB, and also when it is unlimited,
because the C library's default thread stack then applies: 2 MiB on
glibc, 128 KiB on musl. Run it under `ulimit -s 8192`.
