# hefermotor

A semantic analyzer for Pony, built beside ponyc rather than inside it. It
parses a program, resolves names, extracts signatures, checks method bodies
and reference capabilities, and reports diagnostics. It generates no code.

## Status

Pre-release. The M0 skeleton is being built; nothing checks Pony code yet.
See `docs/design.md` for the design and the decision log.

## Building

* Install [corral](https://github.com/ponylang/corral) and
  [ponyc](https://github.com/ponylang/ponyc)
* `make` builds the tests and the `hefermotor` command into
  `build/debug/` and runs the tests
* `build/debug/hefermotor check <dir>` checks a package
