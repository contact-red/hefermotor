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
  `tools/differential/cases` and every package beside that `ponyc`

## Usage

```text
hefermotor check [<target>] [--path=DIR ...] [--json]
```

`hefermotor check` discovers a program's packages through their `use`
declarations, in ponyc's search order, and groups them as ponyc does; a
few shapes of `use` line the M0 scanner does not read are listed as
known gaps in `tools/differential/cases`. `<target>` is a package
directory, or a package name found through the search roots, and
defaults to the current directory. The search roots are the packages
beside the `ponyc` on `PATH`, then each `--path`, then `PONYPATH`, then
`/usr/local/lib` and `/opt/local/lib`, in ponyc's order. Diagnostics go
to stderr in ponyc's shape; `--json` prints one document to stdout
instead. The exit code is 0 with nothing to report, 1 with diagnostics,
2 when the run could not start, and 70 for an internal error.

The parser bounds its recursion at a depth that needs 3 MiB of stack
per scheduler thread, and the runtime sizes each thread's stack from
`ulimit -s`. So `hefermotor check` refuses to start, with exit 2, when
the soft limit is below 3072 KiB, and also when it is unlimited,
because the C library's default thread stack then applies: 2 MiB on
glibc, 128 KiB on musl. Run it under `ulimit -s 8192`.
