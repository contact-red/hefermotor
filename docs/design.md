# hefermotor design log

The design is [discussion #1](https://github.com/contact-red/hefermotor/discussions/1):
the architecture restated, the repository layout, the consumer and type
sketches, the first ten tasks, and how the design was produced. This file is
the record later work starts from: each decision that deviates
from or refines the project brief (called the prompt below), the contracts a milestone must keep, and
the rules that have no other home. Section, sketch, task and decision numbers
below refer to that document. Every claim about ponyc cites a repo-relative
path and line at commit `6a0bfa80b`.

## Divergences from the prompt

Each point where this design narrows, expands or changes what the
prompt literally says. Current behaviour is the prompt's text; proposed
is this design. A withdrawn number stays in place and says so.

1. **The unit of scheduling and of signature analysis is the dependency
   group (strongly connected component); the unit of body increment is
   the package.** Prompt: "the package is the unit of increment ...
   scheduled over the package dependency DAG". Proposed: the `use`
   graph is condensed with Tarjan's algorithm as ponyc does
   (`src/libponyc/pkg/package.c:1589-1653`), ported with an explicit
   stack; a package outside any cycle is a group of one; a group's
   assemble, resolve and signature extraction run together; export data
   and its hash stay per package; and from M3 a member's bodies are
   re-checked iff the member's own source hash, the configuration hash,
   or any export hash in its group or in the group's dependency closure
   changed. Why: the stdlib has real `use` cycles, so a DAG scheduler
   cannot order it; inside a cycle A's export depends on B's which
   depends on A's, so "re-analyze A alone" cannot produce a consistent
   pair; but bodies consume signatures, the prompt's own insight, so a
   body edit in one member need not re-check the others. The stdlib's
   partition, from ponyc's own dump (`ponyc -V3 --pass=reach stdlib`,
   run on the ponyup tree) and an independent
   scan, re-run at the final review on both the checkout and the
   ponyup tree: 30 groups over the 38 packages reachable from `stdlib`
   (12 in the four multi-member groups plus 26 singletons;
   `builtin_test` is among them, `packages/stdlib/_test.pony:10, 50`;
   the tree's 41 `.pony` directories minus the three `benchmarks`);
   four groups have more than one member: {`collections`, `pony_test`,
   `random`, `time`}, 4 members, 38 files, 232,414 bytes; {`capsicum`,
   `files`, `term`}, 3 members, 26 files, 205,150 bytes;
   {`collections/persistent`, `itertools`, `pony_check`}, 3 members, 27
   files, 371,002 bytes; {`net`, `net/notifier`}, 2 members, 105 files,
   1,168,197 bytes, 31.3% of the stdlib. The only cycle with no test
   file on either edge is `files` and `capsicum`; every other cycle has
   at least one edge from a `_test.pony`. Two audiences: a project that only uses the stdlib has
   singleton groups of its own and the stdlib's four multi-member
   groups are cold work cached once; a stdlib contributor's edit to a
   signature in `time` re-runs the four-member group's signature phase
   (232 KB of source) and re-checks one package's bodies. The prompt's
   M4 acceptance, "touches exactly one package's body phase and
   re-emits nothing downstream", is true per member for bodies and
   false for the signature phase of a member of a cycle; this design
   reads it as a ceiling, not a target; Red chose the package as the
   unit and the prompt is not restated (Decision 9). The evidence is in section 10.
2. **The signature firewall is void inside a group for analysis, and
   holds for bodies.** Prompt: "downstream packages consume only export
   data". Proposed: members of one group see each other's parsed files
   during assemble, resolve and signature extraction; between groups
   only `ExportData` crosses; and M3's body check consumes signatures
   through export data even for in-group members, which is what makes
   Divergence 1's per-member body key sound. Recorded as principle 4's
   one exception; the staged alternative (names of all members, then
   per-unit signatures, then bodies) is M2's to reopen behind the
   `traits`-pass question (section 6).
3. **Withdrawn.** An earlier draft narrowed a group's inputs to the exports of
   the packages its members `use` directly. ponyc resolves a method on
   a nominal type against that type's definition wherever it lives
   (`src/libponyc/type/lookup.c:72-98`: `ast_t* def =
   (ast_t*)ast_data(type); ... ast_get(def, name, NULL)`), so a body in
   `c` that holds a `b.Bar` returned by `a` needs `b`'s signatures
   although `c` never `use`s `b`. A group is handed the export data of
   every package in every group it transitively depends on, which is
   the prompt's own reading and no longer a divergence. (Divergence 4
   is what keeps that wider hand-off from cascading.)
4. **An export's bytes never embed its dependencies' export hashes, the
   build configuration's hash, or its own source hash.** Prompt is
   silent. Proposed constraint on M2: those live in the scheduler's
   records and in M4's cache keys, never in the bytes, or every
   signature change cascades through every transitive dependent's
   export hash and the firewall never cuts.
5. **Discovery parses only the `use` section of each file; the full
   parse is the first fan-out step of each group's run.** Prompt:
   pipeline step 1 is "lex + parse each file (parallel, per-file)" per
   package "in DAG order". Proposed: the graph is defined by `use`
   lines inside the files, so discovery must read them, but it reads
   them through `Parse.uses_only`, the module grammar's `use` section
   rule with an early stop (`src/libponyc/ast/parser.c:1310-1319`:
   `SEQ("use command", use)` precedes `SEQ(... class_def)`), the same
   grammar `Parse.apply` runs to the end of the file, synchronously,
   over every file it reaches; the scheduler fans `Parse.apply` out per
   file as the first step of each group's run, so a cached group in M4
   never parses. One grammar, two entry points, one representation of
   `use`. Why: a synchronous discovery that parsed every file would put
   the whole parse on one core in front of every run, warm or cold.
   Cost accepted: the `use` section is lexed twice on a cold run. M0's
   body of `uses_only` is a line scanner whose skip rule reproduces
   ponyc's 30-group partition of the stdlib exactly (verified against ponyc's dump); its known gaps are oracle fixtures,
   not unit tests.
6. **`builtin` gets an explicit dependency edge from every other
   package, added by discovery.** Not a divergence from ponyc's graph,
   which has the edge: ponyc loads `builtin` first
   (`package.c:1036-1038`), the sugar pass inserts a `use "builtin"`
   node into every other module (`src/libponyc/pass/sugar.c:159-167`),
   and the scope pass, which runs after sugar (`src/libponyc/pass/
   pass.h:226-230`), turns every `use` into a dependency edge
   (`src/libponyc/pass/scope.c:83-97`). hefermotor has no sugar pass,
   so `Discover` adds the edge itself.
7. **Exit codes are 0 / 1 / 2 with 70 for a crash, and the CLI presets
   70 before scheduling.** ponyc returns `ok ? 0 : -1`
   (`src/ponyc/main.c:171`). Proposed: 0 nothing to report; 1 the run
   completed and reported at least one diagnostic; 2 the run could not
   start (usage error, `builtin` not found or not loadable); 70 an
   internal error: set by the fulfil handler when the report holds an
   `internal/*` diagnostic (Decision 5), set by `_Unreachable()`, and
   set by the CLI before it calls the front door so that a run whose
   promise is never fulfilled does not fall through to `Env`'s default
   of 0 (`packages/builtin/env.pony:31-35`). Only the fulfil handler
   sets 0 or 1. Why: the differential harness compares
   verdict classes and must never score a crash as a rejection or an
   acceptance.
8. **A failure to load the root is a diagnostic, not a startup
   failure; a `builtin` that is located but cannot be loaded is a
   startup failure.** Proposed: a missing, empty or unreadable root
   produces a `Program` with `builtin` only and one
   `discover/root-not-loaded` diagnostic, exit 1, because ponyc rejects
   those inputs (`package.c:1075, 229-235, 1197-1202`) and the harness
   must see a rejection. A `builtin` directory that is located but that
   `ReadPackage` rejects is `BuiltinNotLoaded(dir, reason)`, exit 2,
   because the user fixes `--path`, not their code, and because a
   `Program` whose `builtin` has no package behind it would leave every
   discovery-added edge dangling and the "`builtin` is the first group"
   invariant false. ponyc rejects that input with 255; the harness
   aborts on exit 2 rather than scoring the case.
9. **Withdrawn (Decision 4).** The candidate let a package load
   without an unreadable file. Red chose ponyc parity: ponyc reports
   `can't open file <path>` for the file (`source.c:17`, `package.c:150-156`),
   keeps reading the others (310-314, `r &=`), then fails the package
   load (1186-1192), so the package is absent and a dependent's `use`
   is "can't load package". hefermotor does the same: the per-file
   diagnostic plus `CantLoadPackage(locator, FilesUnreadable)` at the
   `use`, `RootFailed` for the root, `BuiltinNotLoaded` for `builtin`.
   Principle 7 is not breached: the run still completes and reports;
   the package is simply not analysed, as it would not be by ponyc.
10. **No severity, no secondary notes, no cycle diagnostic in M0.** The
    prompt's "structured diagnostics" is narrowed to what M0 produces:
    ponyc's frontend has only errors, the one M0 note (found-not-dir,
    `package.c:1077-1079`) is folded into the message, and ponyc
    accepts package cycles. Each is additive later.
    `Report.has_errors()` is `diagnostics.size() > 0`; until severity
    exists every diagnostic is an error, so the exit-code row is a
    promise about errors, and when severity arrives `has_errors` keeps
    its name and its meaning.
11. **`--json` ships in M0, and carries the export digest.** The prompt
    lists JSON output under pipeline step 7, not under M0. Proposed: a
    minimal versioned document (`"format": 1`; `export_digest`;
    `packages`, each with its `export_hash`; `groups`; `diagnostics`)
    because two M0 tools consume it: the determinism harness, which
    compares the digest across two directory layouts and needs the
    value to leave the process, and the discovery oracle that compares
    hefermotor's package set with ponyc's `Building x -> y` lines. The
    bump rule: additive keys never bump `"format"`; a rename, removal
    or semantic change bumps it; both harnesses assert the number.
12. **Test files stay in their packages.** Not a divergence from the
    prompt but from an obvious shortcut: dropping `_test.pony` would
    make the stdlib nearly a DAG at the cost of checking a different
    program from the one ponyc compiles, and `pony_check ->
    itertools` is in non-test code (`packages/pony_check/gen_obj.pony`).
13. **`PackageName` is a display name; nothing names a package inside
    export data in M0.** Prompt: entities are "identified by a stable
    hash of their path and content". Proposed: ponyc's qualified name
    is computed for diagnostics and JSON only; the stub export carries
    a format version and the source hash; package and group order are
    by `PackageDir`; what identifies a package across a cache boundary
    is M2's hardest open item, with four constraints (Decision 8,
    open). Why: the
    name moves with the checkout basename, the reach order and the
    locator spelling (`package.c:1084-1149`), and an absolute
    locator's qualified name is an absolute path. An earlier draft required an ordering key that is "a function of content and
    graph"; this design departs from that wording by choice: the order
    is run-local (`PackageDir`), because a content-keyed order moves
    with every body edit, so an export writer that iterated it into
    bytes would produce an order that changes when no signature does.
    The rule that replaces
    it has no exception, no run-local order may enter export bytes,
    and task 10's determinism run proves it for M0's stub for paths,
    for dependency order and for member order.
14. **The build configuration is an input of every phase after
    discovery, and a term of every cache key.** Prompt: a package is
    re-analyzed iff "(a) any of its source files' content hashes
    changed, or (b) any dependency's export data hash changed".
    Proposed: also (c) the `BuildConfig` hash changed. Why: ponyc
    evaluates every guard name first as a platform flag and then as a
    user `-D` flag (`src/libponyc/pkg/ifdef.c:142-158`:
    `os_is_target(name, release, ...)`, else `is_userflag_defined`);
    FFI declarations are guarded (`packages/files/file.pony:1-16`) and
    M2's export must carry them, so an export is a function of the
    configuration. Discovery is not: the package scheme forbids guards
    (`src/libponyc/pkg/use.c:34`), so `Program` is
    configuration-independent and `BuildConfig` travels beside it. No
    `-D` or `--debug` flag in M0; nothing evaluates a guard yet; the
    CLI builds the host default. One divergence recorded for M2:
    ponyc's `runtimestats` and `runtimestatsmessages` flags are
    constants of its own build (`src/libponyc/pkg/platformfuns.c:
    116-136`) and are matched before user flags (`ifdef.c:152-158`),
    so `-Druntimestats` does not set them there; hefermotor has no
    ponyc build to read and evaluates those two names from `defines`.
15. **Export data will carry an unhashed presentation part beside the
    hashed signature part, and a decoded view beside its bytes; both
    arrive in M2.** Prompt: export data is "a serialized,
    deterministic, content-hashed record of every ... signature".
    Proposed: `ExportData.signature` is hashed and is what invalidation
    and downstream analysis key on; in M2 a presentation part (entity
    to file basename and byte span, docstring text) is written to the
    same cache entry and never hashed, and a decoded `val` view is
    built once per export per run, by the emitter on the fresh path
    and by the loader on the M4 path, so a resolver never decodes
    `builtin`'s export once per consuming group. Why: M5's hover and
    definition-at-span must be answerable from an unchanged
    dependency's export without re-analysis, and a docstring edit must
    not move the signature hash. M0's `ExportData` has `signature` and
    `hash` only (Decision 10); the rule that `hash` covers `signature`
    alone is what lets M2 add both parts without moving any hash.
16. **The root and `builtin` are located by ponyc's compile-target
    branch, so `builtin/` in the base directory shadows every search
    root.** Parity with ponyc, not a divergence from it (`find_path`,
    `package.c:462-464`: `from == NULL || ast_id(from) == TK_PROGRAM`
    gives `base = NULL`; 472 tries the target relative to the current
    directory; 486 skips the `pony_packages` walks; 507-515 falls
    through to the search paths unless the locator is explicitly
    relative). Recorded because the base directory is tried before the
    stdlib slot and every search root, on both sides, and because the
    harness must know that `cd /anywhere && hefermotor check
    collections` resolves through the slot as `ponyc collections`
    does. The base directory is an explicit input of discovery; for
    the CLI it is the process's current directory, so the sentence
    above stays true for the CLI; M5 passes the workspace root.
17. **The `is_subtype` memo is per body chunk, not process-local.**
    Prompt, step 6: "a memoized pairwise `is_subtype` cache — this
    cache is process-local, keyed by content hashes". Proposed: a phase
    is a `fun` on a primitive over `val` inputs and cannot hold state
    across calls, so the memo's one home under the contract is a `ref`
    map allocated inside one `Step.apply` and dropped with it; the unit
    of work is therefore a chunk of one member's bodies large enough
    for the memo to pay, and a `val` snapshot of one chunk's memo may
    be passed forward to a later chunk, which principle 2 permits
    ("built once by a phase and passed forward"). Recorded for M3 and
    absorbed into this document; the prompt is not restated
    (Decision 9).
18. **`hefermotor check` with no target checks `.`.** Prompt:
    `hefermotor check <path>`. Proposed: the target argument defaults to
    `"."`, as ponyc with no argument compiles `"."`
    (`src/ponyc/main.c:133-135`); `"."` is not explicitly relative
    (`is_path_relative`, `package.c:1734`), so it resolves at
    `find_path`'s step 2.
19. **The stdlib slot is derived from the `ponyc` on `PATH`, not from
    hefermotor's own location.** ponyc puts the `packages/` directory
    beside its own binary first in the search list
    (`package.c:827-856`; #3779). hefermotor has no stdlib of its own
    to sit beside, so `command` finds `ponyc` on `PATH`, resolves it
    through symlinks (ponyup's `bin/ponyc` is a symlink into a
    versioned directory) and takes that binary's `../packages` as the
    first search root, ahead of `--path` and `PONYPATH` (Decision 2).
    The failure mode: a `PATH` whose first `ponyc` is not the one the
    user means picks that ponyc's stdlib silently; the differential
    harness compares the slot with the `Building builtin ->` line of
    the ponyc it invokes (task 10), and a user can see the directory
    in the JSON document's `packages[]`. No `ponyc` on `PATH` means no
    slot and the roots as before.

## Constraints on M1

Constraints on M1 fixed now:

- `diag.Span` is byte offsets, so whatever `SyntaxTree` stores, the
  parse phase's diagnostics and `UseDecl` spans are offsets at the
  boundary.
- The tree M1 hands across the parse boundary answers `offset(i)` in
  O(1): pony-lsp2's `SyntaxTree.offset` is O(i)
  (`pony_syntax/syntax_tree.pony:61-77`), M2/M3 emit diagnostics at
  nodes reached by index and M5 converts node to offset on every
  request. Storing
  an offset in place of the width in the existing `(kind, U32, U32)`
  tuple costs no extra bytes; the per-node span stays a bare integer
  pair and `Span` is built only when a diagnostic is emitted.
- The tree's element type stays a tuple of primitives and machine
  words. `trace_array_elements` emits no per-element loop only when
  `gentrace_needed` is false for the element type
  (`src/libponyc/codegen/genprim.c:640-655`), and
  `make_might_reference_actor` is constant true in this
  ponyc (`src/libponyc/codegen/gendesc.c:267-272`), so an element
  carrying a class or an `Any` would trace a million elements on every
  `val` send of a tree.
- pony-lsp2's `_Module` rule (`pony_syntax/grammar.pony:24-40`) accepts
  a `use` after a type definition silently where ponyc's module rule
  (`parser.c:1310-1319`) rejects it, the exact point the M0 `Parse`
  contract fixes; M1 changes `_Module`, not merely adds an early stop.
  The case goes into `docs/ponyc-divergences.md` now, since the
  quarried code gets it wrong.
- The quarried parser's roughly 75 `SyntaxDiagnostic(offset, width,
  message)` sites map to one cause per family (`SyntaxExpected(what)`,
  `_MaxNesting`), not one per site; the offset change is inside
  `Parser.build`.
- The M0 scanner's known gaps are oracle fixtures in the differential
  harness (task 10), never unit tests that would encode the wrong
  answer.

## Boundary decisions, invariants and records for M2 to M5

| Boundary | Decision |
|---|---|
| Unit of scheduling and of signature analysis | the group (SCC); a package wherever there is no cycle |
| Unit of body increment (M3/M4) | the package: member M's bodies are re-checked iff M's source hash, the configuration hash, or any export hash in M's group or in the group's `needs` changed; `GroupResult.bodies` is per member; a per-file key is recorded as M4's option (below); Red chose the package, with the file as a later refactor if needed (Decision 9) |
| Unit of export data and its hash | the package |
| Firewall inside a group | void for assemble/resolve/signatures — members see each other's parsed files; holds for bodies — M3 consumes signatures through export data even in-group; holds at group edges |
| What crosses a group edge | the export data of every package in every group in `Group.needs`, the transitive closure, in package order; `builtin` always. Closure sizes on the stdlib: a `collections` user is handed 5 exports, `files` 13, `net` 19, `http_client` 27; the total over a stdlib run is measured by task 9 |
| A group's non-body work | single-threaded inside `GroupAnalysis.apply`. What bounds a cold check is the critical path: `builtin` → {`collections`, `pony_test`, `random`, `time`} → {`collections/persistent`, `itertools`, `pony_check`} → {`net`, `net/notifier`} → `http_client` → `stdlib`, six groups, 2,211,460 bytes, 59% of the stdlib; the four multi-member groups are 4, 3, 3 and 2 members. M2 may split around a per-file-or-type `Step` inside a package once the `traits` question is answered, and doing so touches `schedule` |
| Build configuration | `BuildConfig val` in `source`, a hash only in M0 (`host()` hashes a fixed string; the target vocabulary arrives in M2, Decision 10), built by the CLI into `CheckCommand`, travels beside `Program` (discovery is configuration-independent: the package scheme forbids guards, `use.c:34`), into `Schedule` and every `GroupAnalysis.apply`; its hash is a term of every cache key and of M2's export identity and never enters export bytes |
| Base directory | an explicit input of `Discover` and of `Run`; a file system has no current directory; the CLI passes the process cwd, a test a literal, M5 the workspace root |
| Export data | `signature` and its `hash` in M0; M2 adds an unhashed presentation part (locations, docstrings) in the same cache entry and a decoded view built once per export per run (Decision 10); `hash` covers `signature` alone, so `export_digest` and the M4 keys see signature hashes only, now and then |
| Test files | part of the package, as ponyc reads them |
| Where parse runs | `Parse.uses_only` in discovery, per file, synchronous; `Parse.apply` fanned per file as the first step of each group's run, through the injected step; a cached group never parses |
| Who reports parse diagnostics | `Parse.apply` alone; `uses_only` reports nothing, so discovery never reports a syntax error; `_GroupRun` merges every `ParsedFile.diagnostics` into the `GroupResult` it reports, and that is the only path into the `Report` on a fresh run |
| Where actors sit | `_Scheduler`, `_GroupRun`, `_Task`, `_Collect`, all private to `schedule`; `_ReadySet` and `_Slots` are plain classes and never panic |
| Contract violations and panics | no panic on a reachable violation (Decision 5): a refused `complete`, a stalled ready set, or an analysis answering for the wrong packages is an `InternalError` diagnostic (`internal/*`) in the `Report`, the scheduler stops launching and fulfils, and the CLI exits 70; `_Unreachable()` (private, one `_unreachable.pony` per package that needs it, `schedule` in M0) only for branches the type system cannot prove and no input reaches |
| Identity within a run | `PackageDir` (realpath; private constructor; `eq`/`lt`/`hash` over path) |
| Identity across a cache boundary | `ContentHash` (opaque; private constructor; one `U64` from the runtime's SipHash-2-4, Decision 1; an identity, not an integrity check) |
| Cross-boundary package identity | open for M2 with four constraints (below); `PackageName` is display only |
| What is hashed | a file: its content only, `content.hash64()` directly; a package: `(name, content hash)` per file in name order through `HashBuilder` (a package with an unreadable file never loads, Decision 4); an export: its signature part; a configuration: a fixed string in M0, its canonical rendering from M2 |
| Run-local order | package order is `PackageDir`; group order is Kahn over that; neither, and no source-hash-derived order, may enter export bytes. A run-local key by choice, departing from an earlier draft's "function of content and graph" wording (Divergence 13) |
| A diagnostic's file | `(dir, name)` with `path()` derived; a cached entry stores `name` and offsets, never `dir`; the order sorts by `path()` |
| What discovery may read | anything `find_path` reaches, as ponyc does (section 5); dependencies trusted as compiling them would; confinement is a policy inside `Locate`/`LocateTarget` if ever wanted |
| How phases are kept pure | capabilities enforce `val` in, `val` out, no `?`; `tools/imports/deps.txt` and the five rules of `tools/imports/check.sh`, checked by `make lint-source` under `make test` after the check rejects its own `testdata/`, cover what they do not; `time`, `random`, `process`, `net` banned everywhere; `files` only in the four non-phase files `deps.txt` lists; `use @` and FFI calls only in a package's `_unreachable.pony` |
| Diagnostic ordering | one sort in `_ReadySet.report()` under `DiagnosticOrder`, a total order over what a renderer sees; the stdlib `Sort` is quadratic and its recursion depth is O(n) on sorted input, and after M1 the report's input is per-file sorted lists concatenated, so `sort.MergeSort` replaces it at every sort site in M1 (its first task), not at M3 as first planned |
| Error vocabulary | cause objects behind `DiagnosticCause`, `InternalError` among them; closed unions per layer where a field or return admits exactly those cases (`LocateFailure`, `ReadFailure` with `FilesUnreadable`, `LoadFailure`, `BuiltinFailure`, `_CompleteError`) |
| Run could not start | a usage error, `BuiltinNotFound(reason)` or `BuiltinNotLoaded(dir, reason)`, exit 2; everything about the input is a diagnostic |
| Exit codes | 0 / 1 / 2; the CLI presets 70 before scheduling; the fulfil handler sets 70 when `has_internal_errors()`, else 1 or 0; `_Unreachable()` exits 70; `has_errors` is "at least one diagnostic" until severity exists |
| Output | text diagnostics on stderr in ponyc's shape; `--json` document on stdout with `export_digest` and per-package `export_hash`; groups compared as sets; control characters escaped and invalid UTF-8 replaced in JSON only |
| Library front door | `Check(program, config)` at `use "hefermotor"`; `schedule.Schedule` public for tests that inject a step or an analysis; an in-repo consumer package (`command`, M5's server) takes the front door as a `Checker` parameter |

Invariants, with how each is held:

- A `PackageDir` is a realpath directory that existed at load time: by
  construction (private constructor; only `Locate`, `LocateTarget` and
  their shared helper build one).
- A `SourceFile`'s hash is of its own content: by construction (the
  constructor computes `content.hash64()`).
- `ExportData.hash == H(signature)`, and nothing M2 adds beside
  `signature` enters it: by construction (every constructor computes
  it over `signature` alone; none takes a hash).
- `BuildConfig.hash` is computed by its constructor and by nothing
  else: by construction (`host()` hashes a fixed string in M0; M2's
  constructor hashes the canonical rendering).
- `Package.files` is sorted bytewise by name whatever order `entries`
  gave; `Program.groups` are in canonical topological order;
  `Group.members`, `DepExports.entries` and `Report.exports` are in
  `PackageDir` order: by construction in `Discover`, `Condense` and
  `_ReadySet`, pinned by tests, including two that insert the memory
  fixture's files in reverse and assert identical `source_hash`es
  (task 6) and an identical `export_digest` and JSON document (task 9).
- `Group.needs` is the transitive closure of dependency groups and
  `deps_for(g)` hands exactly their members' exports: by construction
  in `Condense` and `_ReadySet`, pinned by Sketch C's first test
  through the hand-driven loop and by `_TestScheduleHandsClosureExports`
  through the shell.
- A `GroupResult` recorded for a group has exactly the group's members'
  exports in order: checked in `complete`, reported as
  `_ExportsMismatch`, pinned by Sketch C's second test.
- If `done()` is false and no group is running, `ready()` is
  non-empty: by construction (`needs` is acyclic after Tarjan),
  asserted in the hand-driven loop, and reported as
  `internal/scheduler-stalled` by `_Scheduler` if it ever fails.
- `Report.diagnostics` is sorted under `DiagnosticOrder`: by
  construction; arrival order never reaches the output; parse
  diagnostics reach it through `_GroupRun` alone, pinned by
  `_NotingParse`.
- Fan-out results are stored at their input index, never appended in
  arrival order: by construction in `_Slots`, pinned by a test that
  delivers in reverse; the per-member parse rejoin is pinned by
  `_CheckingAnalysis`.
- Nothing run-local, no name, no dependency hash, no configuration
  hash and no source hash enters M2's signature bytes: by convention
  (`PackageDir` has no `string()`; `PackageName` is never passed to a
  writer; package order is documented run-local), proven for paths,
  for dependency order and for member order, for the M0 stub, by task
  10's three-layout determinism run, which reads the digest from the
  `--json` document.
- The report promise is fulfilled exactly once and never rejected,
  on a contract violation too: `_Scheduler`'s state union (`_Running
  | _Draining | _Done`); a violation is noted and the promise
  fulfilled once nothing is running; a `finished` in `_Done` is
  `_Unreachable()` because each private `_GroupRun` sends once; the
  fulfil lambdas cannot raise; the CLI's preset 70 makes a promise
  that never fulfils visible, and a rejected promise leaves 70 in
  place (tested).
- `builtin` is the only initially ready group and always the first:
  every other package has an edge to it and it has no package-scheme
  `use` of its own (grep of `^use "` over `packages/builtin/*.pony` is
  empty), so its edge is never in a cycle; and it is always a loaded
  package, because a `builtin` that will not load ends discovery.
  Sketch D's JSON and `_Fixture` assume it; task 6 pins it.
- `Program` is a function of `(fs, roots, base, target)` and not of
  the configuration: by construction (no edge is conditional; the
  file system has no current directory); `BuildConfig` is not a field
  of `Program`.
- Output carries absolute paths: text and JSON both, as ponyc's output
  does (`package.c:155`); Decision 7. Inside the process a location is
  `(dir, name)`, and only the renderers join them.

### Deliberately open for M2

Deferred from M0 by Decision 10, with the reasons they were designed:
the export's decoded `val` view beside its bytes, built once per
export per run (by the emitter on the fresh path, by the loader on the
M4 path), because a group receives its whole closure's exports (13 for
a `files` user, 27 for `http_client`) and a bytes-only form would have
M2's resolver decode `builtin`'s export once per consuming group, or
cache the decode somewhere principle 2 forbids; the export's unhashed
presentation part (entity to file basename plus byte span, docstring
text; deterministic because `Package.files` is sorted by name; written
to the same cache entry; its writer the only code that sees docstrings
and spans), because M5's hover and definition-at-span must be
answerable from an unchanged dependency's export and a docstring edit
must not move the signature hash; and `BuildConfig`'s fields: target
os, arch, word size and endianness as closed unions with ponyc's
`unknown_*` members (`src/libponyc/pkg/platformfuns.h:10-28`,
`buildflagset.c:11-48`),
`native128` (`genopt.cc:1360-1365`), `release` (default true,
`main.c:78`; `--debug` clears it, `options.c:300`), sorted
deduplicated `defines`, `bsd()` and `posix()` derived from the OS as
ponyc derives them (`genopt.cc:1239-1244, 1281-1287`), no `riscv`
(not a guard name), a `canonical()` rendering the hash covers, and
`host()` read from the builtin `Platform` primitive; `runtimestats`
and `runtimestatsmessages` evaluated from `defines` (Divergence 14).
The export record schema for both parts, kept equal to the bytes by
the round-trip test M2 owes the prompt. How
entity hashes are derived: a *path* hash distinct from `ContentHash`,
because inside a group A's signatures mention B's entities and vice
versa, so a content-derived identity would be circular (rustc
separates `DefPathHash` from `Fingerprint` for the same reason),
rooted at the cross-boundary package identity, not at a
content-derived key. Text versus binary encoding. How a cycle's
members reference each other. How FFI declarations (`use @name[...]`,
over a hundred in `builtin` alone) are carried under a configuration:
they are package-visible and guarded (`ifdef.c:207-330`), so export
data includes them and its bytes are a function of `BuildConfig`. Flag
evaluation as `os_is_target` over `BuildConfig`'s fields plus the
defines, and the `-D`/`--debug` flags that arrive with it. Whether
ponyc's `traits` pass makes a unit's exported method set depend on
other units' signatures: the gate on a per-file-or-type signature
`Step` inside a package and on the staged firewall. That no judgment
may depend on member order. The "queryable semantic model" the prompt
promises, whose home is reserved now by name (a package
`hefermotor/model` holding a `SemanticModel` per package, created in
M2, not in M0, with the export's presentation part as its first home)
so M2 does not build it inside `AnalyzeGroup` and drop it. The
presentation
producer: the one writer that sees docstrings and spans. And, hardest,
a **cross-boundary package identity** that is (a)
machine-independent, (b) independent of checkout location, root
basename, reach order and locator spelling, (c) stable across body
edits (or entity path hashes cannot root at it), and (d) sound under
qualified-name collisions; M4's cache entry, which maps a member's
export by `source_hash`, is one more consumer of it (Decision 8, open).

### Recorded for M3

The memo's scope is one `Step.apply`: a `ref` map allocated inside the
call and dropped with it. A `BodyTask` is a chunk of one member's
bodies, K chunks per member with K near the scheduler thread count,
each chunk sharing one memo and one `val` scope built once per member;
chunks never span files; `_Slots` rejoins chunks in index order. A
`val` snapshot of one chunk's memo may be passed forward to a later
chunk (an option). `BodyResult` carries the typed spans M5's
hover-type-at-span reads. Body checking consumes signatures through
export data even for in-group members. `ContentHash` at file, package,
export and entity frequency is fine; it must not become the per-node
identity inside a tree. The actor-per-task versus bounded-pool question is
decided with the first heavy fan-out caller, on task 9's numbers.

### Deliberately open for M4

Recorded now so M2's bytes never include what the keys already cover.
The two keys, written out:

```text
K_sig(G)   = H( "sig/1",
                config.hash,
                sorted { m.source_hash  : m in G.members },
                sorted { export_hash(p) : p in members of G.needs } )

K_body(M)  = H( "body/1",
                config.hash,
                M.source_hash,
                sorted { export_hash(p) : p in G.members },
                sorted { export_hash(p) : p in members of G.needs } )
                                         where M is a member of G
```

`sorted` is by `ContentHash.lt`, so neither key depends on package
order, on names, or on directories; both are functions of contents,
the graph and the configuration. Every term that can move `K_sig`
except another member's source hash also moves `K_body` (a member's
export hash is a function of `K_sig`'s inputs), which is exactly
Divergence 1's rule; a change to another member's body moves `K_sig`
(the group re-runs its signature phase) and not `K_body(M)`. Both keys
draw on the one closure `deps_for` already computes plus the group's
own result; there is no third mechanism, and the closure key and the
per-member key do not pull against each other (on the warm one-body edit: `K_sig` miss, four exports whose hashes are
unchanged, `K_body` hit for the three untouched members). Neither
key's terms are in any export's bytes (Divergence 4).

What an entry holds. Under `K_sig(G)`: the group's exports (with the
presentation part once M2 adds it), parse diagnostics and signature
diagnostics. Under
`K_body(M)`: the member's body diagnostics. Entries must hold
diagnostics because a `K_sig` hit skips `GroupAnalysis` and
`_GroupRun`, the only path into the `Report` on a fresh run, does not
run for a cached group; without them a warm run would either drop the
group's diagnostics (a program ponyc rejects would exit 0 and the
harness would file a hefermotor bug) or re-run every group that had
one. An entry stores each diagnostic's `name` and offsets and never
its `dir`, which is re-attached at read from the group's members; the
`Location` type holds that by construction. Two constraints on that
re-attachment: a cached diagnostic's location may name a file outside
the emitting member, since nothing in M2's open list forbids a
signature diagnostic located in a dependency's file; and `name` alone
is ambiguous across members (every member of {`collections`,
`pony_test`, `random`, `time`} has a `_test.pony`). So the
by-`source_hash` bucketing below is by the member that *owns* the
file, not the member whose analysis emitted the diagnostic, and a
diagnostic in a file of the dependency closure is bucketed under that
dependency's `source_hash`. Discovery's own
diagnostics (`Nowhere`, a root failure, an unreadable file's
`FileOnly`) are never cached because discovery always runs in full,
`uses_only` included; the cache holds exports, presentation and
phase diagnostics, never a `use` list.

An entry maps each member's export, and its diagnostics, by the
member's `source_hash`, never by position or directory: the keys are
order-independent but `GroupResult.exports` in member order is not,
and task 10's third layout reorders a group's members. Residual: two
members with equal `source_hash` collide under that map; it needs the
cross-boundary identity Decision 8 leaves open.

The entry layout puts the signature hash and a length-prefixed
signature part first, presentation after, so a hit can be verified and
its hash taken without reading presentation, and M2's presentation
part may be loaded lazily in M5. Presentation
cannot go stale under a `K_sig` hit because every input to
presentation is an input to `K_sig`.

The per-file body key is recorded as M4's option, not as the intended
key:

```text
K_body(M, f) = H( "body/1", config.hash, f.hash,
                  sorted { export_hash(p) : p in G.members },
                  sorted { export_hash(p) : p in members of G.needs } )
```

Every signature a body in `f` can reach is in the group's or the
closure's exports, both already terms of the key; `SourceFile.hash`
exists; chunks never span files, so the option stays open. For the
one-body edit in `collections/map.pony` it cuts the warm re-check
from 285 bodies to 33, and for `net` from 4,767 to about 55. It is not adopted because it
qualifies principle 1 one step further than Divergence 1 does, and
this key is the place not to grow the design without Red. Red chose the package, with the file as a later
refactor if it is needed (Decision 9); the option stays recorded here
and "chunks never span files" stays as the constraint that keeps it
possible. The prompt's "touches exactly one package's body phase" is
read as a ceiling, not a target.

The trust model. The cache is trusted exactly as the source tree is;
`ContentHash` is an identity, not an integrity check; a cache shared
across trust domains needs a separate decision, a verified-on-read
format or a real cryptographic digest, not a wider SipHash. The cache
directory must be no more writable than the tree it serves; a shared
or world-writable location is the trust-domain crossing that separate
decision covers. A package with an unreadable file never loads
(Decision 4), so no partial package is ever hashed or cached. The SCC
is also the unit a future backend would have to compile together.

### Fixed for M1

The constraints on M1 above: `Span` is byte offsets at the boundary; `offset(i)`
in O(1) with an offset stored in place of the width; the tree's
element type stays a tuple of primitives and machine words so a `val`
send traces in O(1); pony-lsp2's `_Module` is changed to reject a
`use` after a type as ponyc's module rule does; the roughly 75
free-text `SyntaxDiagnostic` sites map to one cause per family; the
stub's known gaps are oracle fixtures, never unit tests; and the
`uses_only`/`apply` equivalence test gains its real inputs (the ponyc
`packages/` tree, M1's broken-file corpus, a pony_check generator of
`use` sections with injected syntax errors).

### Notes for M5

An internal error reaches a server as data, an `internal/*`
diagnostic in the `Report`; only `_Unreachable()` ends the process,
and only on a branch no input can reach (Decision 5). What a run that
never reports means to a server: the CLI's preset-70
mechanism relies on process quiescence, which a server never reaches,
so the server needs its own sentinel per request. The streaming of
many diagnostics to stderr. One root per `Program`; tz's `tz` +
`tz_main` are two `Program`s sharing nothing (record, do not decide).
`Discover`'s synchronous signature and `SourceFile`'s
constructor-computed hash are what an editor-buffer overlay would
change. The trust trigger above must be re-applied.

### The cold-check ceiling

A group's assemble, resolve and signature work runs on one core, and
groups run one after another along the dependency chain, so the cold
check of the stdlib is bounded below by the six-group critical path
`builtin` → {`collections`, `pony_test`, `random`, `time`} →
{`collections/persistent`, `itertools`, `pony_check`} → {`net`,
`net/notifier`} → `http_client` → `stdlib`: 2,211,460 bytes, 59% of
the stdlib (about 3.73 MB; the exact total differs between the
checkout and the ponyup tree and is measured by task 9), on one core
at a time, whatever the core count. The numbers ponyc's own passes give for scale, measured in an
earlier project: `--pass=expr` takes 1.53 s on `collections` and 6.15 s
on `stdlib` (ponyc 0.69.1, 64 cores), and scope through refer is 17%
of `collections`' compile time (pony-lsp2 `DESIGN.md:98`). hefermotor's
own numbers are unmeasured until task 9, which prints the chain and
its bytes beside the timing. Along the chain `builtin`, `http_client`
and `stdlib` are singletons and `net` is 95% one member, so a
per-member seam would shorten almost none of it; the seam kept open is
per file or type inside a package (Sketch E).

Measured at the end of M0 over the ponyup tree (ponyc
nightly-20260915, 64 cores, release build of a probe that calls
`Discover` then `Check` with the stub phases): discovery of the
stdlib reads 462 files, 3,707,445 bytes, into 30 groups over 38
packages in 63 to 70 ms; the four multi-member groups are the four
from ponyc's dump above; the
critical path is the six groups above, 2,208,733 bytes on that tree;
the check itself, one `_Task` per file for the `use` scan plus the
stub analysis, takes 23 to 28 ms, so spawning an actor per stdlib file
costs nothing measurable at M0's volumes. The time to the first
group's start is the discovery time: the scheduler launches `builtin`
at once. The debug CLI build checks the stdlib end to end in about
0.23 s.

## Decisions

Red answered the ten questions the design raised. Each entry gives
the question as it stood, Red's answer verbatim, and what the answer
changed in this document. Q8 stays open for M2.

**Decision 1. Hash width.** The question: the runtime's SipHash-2-4
key is a compiled-in constant visible to everyone (`fun.c:6-9`), so
`ContentHash` is an identity, not an integrity check, and the width
choice was about accidental collisions (N²/2⁶⁵ at 64 bits) and about
depending on a runtime constant nothing pins. Red: "64 bit."
Applied: `ContentHash` stores one `U64` from the runtime's `hash64`;
the 128-bit port is gone from task 2 and from the type sketch; the
trust model stands as recorded (the cache is trusted exactly as the
source tree is; a cache shared across trust domains needs a separate
decision, not a wider hash); task 2's external vectors still pin the
runtime key so a change to it is caught.

**Decision 2. Where the stdlib lives.** The question: ponyc puts its
stdlib next to its binary and first in the search list
(`package.c:827-856`; #3779), so `--path`/`PONYPATH` cannot shadow it;
hefermotor had no such slot. Red: "<ponyc on path>/../packages".
Applied: `command` derives a stdlib slot from the `ponyc` found on
`PATH`, resolved through symlinks first (ponyup's `bin/ponyc` is a
symlink into a versioned directory, so the real binary is found before
`../packages` is taken), and `SearchRoots.with_stdlib` puts it first
in the search list, so `--path` and `PONYPATH` cannot shadow it, as
for ponyc. No `ponyc` on `PATH` means no slot and the roots stand as
before. The failure mode, a wrong `ponyc` on `PATH` picking a wrong
stdlib silently, is recorded as Divergence 19, and the differential
harness checks that its own ponyc and hefermotor's slot name the same
`builtin` directory (task 10). `builtin/` in the base directory still
shadows the slot, as ponyc's target branch shadows its own
(Divergence 16).

**Decision 3. Binary names.** The question: tz names the test binary
after the package. Red: "hefermotor is the tool, hefermotor_tests for
the tests." Applied: the CLI binary is `build/<config>/hefermotor`,
built from the `hefermotor_main` package with `-b hefermotor`; the
test binary is `build/<config>/hefermotor_tests`, built from the
umbrella with `-b hefermotor_tests`. The Makefile deviates from tz's
`tests_binary := $(BUILD_DIR)/$(PACKAGE)` at exactly those two lines.
The binary package keeps the name `hefermotor_main`: it names the
package that holds `actor Main`, which still reads right.

**Decision 4. An unreadable file inside a package.** The question:
keep the resilient behaviour (diagnostic, package loads without the
file) or match ponyc and fail the package load. Red: "Fail the
package". Applied, from `package.c:137-160, 220-320, 1186-1202`: an
unreadable file is reported as `can't open file <path>` at the
file (`source_open`, `source.c:17`; `parse_source_file`, 150-156); `parse_files_in_dir` goes on
through the other files and returns false (310-314, `r &=`);
`package_load` then marks the package `PRESERVE` and returns NULL
(1186-1192), so the package is absent from the program and a
dependent's `use` gets "can't load package" (`scope.c:87`); for the
root, the compile fails. hefermotor does the same: one
`discover/unreadable-file` diagnostic per unreadable file, plus the
package's load failing with the new `ReadFailure` variant
`FilesUnreadable`, which reaches the `use` site as
`CantLoadPackage(locator, FilesUnreadable)`, the root as `RootFailed`,
and `builtin` as `BuiltinNotLoaded` (exit 2). The package is not a
member of any group. Divergence 9 is withdrawn; "`NoPonySources` when
nothing readable remains" is subsumed, since the load fails on the
first unreadable file. The M4 note that said the continuation cannot
poison the cache is replaced: no partial package is ever hashed or
cached. One parity note for `docs/ponyc-divergences.md`: ponyc's
second `use` of a directory whose parse failed gets the preserved
package back from `ast_get` (`package.c:1155-1157`) with no second
error; hefermotor reports every `use` of it.

**Decision 5. Panics.** The question: where the panic primitives live,
and whether a long-lived server dying on an internal panic is
intended. Red: "No panics". The reading applied: the library never ends the process on a contract violation
that is reachable, that is, one an injected `GroupAnalysis` or `Step`,
or a bug in `Condense`, could provoke. `IllegalState` is gone. A
violation reported by `_ReadySet.complete` (a result for a group that
is not running; exports that are not the members' in order), a
stalled ready set, or an analysis returning results for the wrong
packages becomes an `InternalError` cause with an `internal/*` code,
carried in the `Report` like any diagnostic; the scheduler records it,
stops launching, and fulfils the promise with what it has, so
"fulfilled exactly once" still holds; `Report.has_internal_errors()`
is true when one is present, and the CLI exits 70 on it. The 70
preset for a promise that is never fulfilled stays. `_Unreachable()`
stays for branches the type system cannot prove and that no input can
reach (a private `_Task` sending twice; `_GroupRun.parsed` arriving a
second time; an array lift in `_Slots.take` after every slot is
filled), per Red's own rule: private, one copy of `_unreachable.pony`
per package that needs it, exiting 70. Because ponyc's FFI declaration
is package-wide (`ifdef.c:270-275`), the source check's FFI-call rule
is what keeps another file of that package from calling `@exit`. The
shared `panic` package is gone from the layout, the diagram and
`deps.txt`. For M5 the consequence is that an internal error reaches
the server as data and only `_Unreachable()` ends the process.

**Decision 6. Python in CI.** Red: "Fine". Python arrives in CI with
M1's parser tooling and M3's `tools/corpus`; M0 stays shell only.

**Decision 7. What leaves the process.** The question listed
everything a run prints or echoes: package directories in the JSON
document, source lines in text mode, OS error strings, the target and
the offending argument on errors, dependency paths in every
`file:line:col` prefix, and that `BuildConfig`'s rendering stays out.
Red: "Everything you think is useful, we can always trim later".
Applied: the inventory stands as ponyc parity; trimming (a
`--relative-paths` flag or similar) is recorded as a later flag with
no single base for dependency paths, not as an M0 task.

**Decision 8. Cross-boundary package identity.** Red: "Discuss
later". Stays open for M2, with its four constraints and its
consumers (entity path hashes root at it; M4's cache entry maps a
member's export and diagnostics by `source_hash`, and two members
with identical file names and contents collide under that map).

**Decision 9. The unit of body increment, and whether the prompt is
restated.** The question: package or file as the unit of body
increment, and whether to restate the M4 criterion and principles 1,
4 and step 6 in the prompt. Red: "Start with package. If we need to
go to file later we can refactor." Applied: the package is the unit
of body increment; the per-file key stays in the M4 note as an option
with its numbers (285 → 33 bodies on the warm one-body edit in
`collections/map.pony`), and "chunks never span files" stays as the
constraint that keeps it possible; the prompt is not restated; the
differences (Divergences 1, 2 and 17) are absorbed into this document.

**Decision 10. Three M0 types with no M0 reader.** The question:
`BuildConfig`'s target vocabulary, `ExportView` and the
`presentation` part of `ExportData` shipped in M0 with nothing reading
them, kept only so that a cache-key term is not retrofitted across
every phase signature later. Red: "wait for M2". Applied: M0 keeps
the signatures shaped to accept them and nothing more. `BuildConfig`
is a `val` with only a `hash`, and `host()` hashes a fixed string
until M2 defines the rendering; the target vocabulary, `canonical()`,
`defines`, `bsd()` and `posix()` move to the M2 open list with their
ponyc citations. `ExportData` has `signature` and `hash` only; the
decoded view and the presentation part move to the M2 open list with
their reasons (a resolver must not decode `builtin`'s export once per
consuming group; M5's hover must be answerable from an unchanged
dependency's export). Divergence 15 is kept as the record of what M2
adds and why.

## M1

The M1 design is Discussion #13; this section records what each M1
task decided or measured, and the working answers to the design's seven
open tensions (Discussion #13, section 11) until Red rules on them.

Working answers taken at the start of M1, each the direction the design's
evaluation leaned and each reversible in one place: the `.cc` corpus is
quarried behind `PONYC_SRC` (T1); a missing closer is always reported at
the opener, with no suppression rule (T2); the per-file budget is 500
kept `expected` and `unterminated` records (T3); CI clones ponyc at a
pinned commit for the drift gate and the test corpus (T4); a file over
`U32.max_value()` bytes is refused at the read (T5); the depth-refusal
region stays an `NdError` (T6); a locator holding a raw newline is what
the lexer produced (T7).

1. **The sort, the path order and the renderer window.** `sort.MergeSort`
   is a stable bottom-up merge sort with one auxiliary array and no
   recursion, used at every sort site. The stdlib `Sort` takes its
   pivots from the ends: on presorted input it recurses as deep as the
   array and runs in quadratic time. Measured for Discussion #13
   (section 10): 29.7 s and 30 GB for 233,000 presorted diagnostics, and
   a segfault at 200,000 presorted strings under an 8 MiB stack; the
   review of this task measured the same inputs under `MergeSort` at
   126 ms and 139 ms in a release build with flat memory. After M1 the
   report's input is per-file sorted lists concatenated.
   `DiagnosticOrder` compares two files' paths through `_PathOrder`,
   which returns `Equal` at once for two locations that share a file's
   `dir` and `name` objects and otherwise walks the joined path byte by
   byte without building it; the order is unchanged. `RenderText` prints
   at most 200 bytes of a source line around the caret, with `...` at
   each cut edge, and takes the line as a shared view of the source
   rather than a copy, so a one-line file with many diagnostics renders
   in time linear in the diagnostics rather than in their product with
   the line. The sort tests sort 300,000 presorted and 100,000 shuffled
   `USize` entries, sizes above the 200,000 at which the stdlib sort
   crashed; `USize` stands in for diagnostics because the sort's passes
   do not depend on the element type; the sorts themselves take about
   150 ms in a debug build.
2. **The lexer and the token kinds, verbatim.** `parse/_lexer.pony` and
   `parse/string_literal.pony` are pony-lsp2's `lexer.pony` and
   `string_literal.pony` with the lexer's types made package-private and
   nothing else changed; `parse/token_kind.pony` is generated by
   `tools/tokens/gen_token_kinds.py` from a ponyc checkout, and its
   header names the commit and the SHA-256 of `lexer.c` it came from.
   The lexer's own tests are pony-lsp2's, with their names changed to
   this project's `package/area: description` form and the lexer's
   renames applied; one test is added, pinning that `_Symbols` holds
   every fixed-text symbol kind the lexer can produce, and the
   longest-first test becomes a prefix-order test, because `_Symbols`
   is now emitted in ponyc's table order, the order ponyc's own scan
   takes its first match in, rather than sorted by length. The
   generator reads the tables and `newline_symbols` from the checkout's
   HEAD, so the header's commit and digest describe one file, and it
   refuses a table entry whose kind nothing can produce. `NOTICE` carries ponyc's
   BSD-2 notice and names the ported material: the token tables are
   ponyc's text, and the licence's first clause requires the notice on
   a redistribution of the source. Whether M0's ports of ponyc's
   algorithms (`find_path`, `package_dependency_groups`) need naming
   too is open.
3. **The parser, the grammar and the tree, verbatim.** pony-lsp2's
   `parser.pony`, `grammar.pony`, `type_grammar.pony`,
   `expr_grammar.pony`, `expr_atom.pony`, `expr_control.pony`,
   `_expr_mode.pony` and `token_sets.pony` land as `_`-prefixed files
   with `Parser`, `TokenSets` and the grammar's entry point (now
   `_ParseModule`) made package-private and task 2's `_TokenStream`
   name applied; `syntax_tree.pony` and `syntax_diagnostic.pony` land
   byte for byte and `node_kind.pony` with one comment renamed to
   `_Parser.wrap_from`, all three public, `SyntaxDiagnostic` included:
   it is the type of `SyntaxTree`'s public `diagnostics` field, making
   it private would edit two of the three, no public entry point
   produces a `SyntaxTree` yet, and task 7 deletes the type. Two
   sentences of the quarry's prose were cut or corrected: `_Members`'
   docstring gave a language server as the reason for accepting fields
   after methods, and the nesting test's docstring said parentheses
   meet the limit at 249 where the test uses 1249. Other rationale in
   the quarry that names editor features (outline, folding, hover,
   selection) is left as written. `Parse.apply` runs `_ParseModule`
   over the file and drops the tree and the records, so the harnesses
   that run on every PR run the parser over the stdlib from this task.
   `tools/grammar/guard.py` (pony-lsp2's `grammar_guard.py`, with a
   one-pass scan for non-code, `too_deep` as the only guard, `_Rule(p,
   ...)` as the only edge shape, a refusal of a directory with no rule,
   and a self-test tree it must fail before the real tree is trusted)
   runs under `lint-source`: 67 rules, 7 guarded, no unguarded
   recursion cycle. The tree and grammar tests are pony-lsp2's with
   their names in this project's form. Measured: `hefermotor check`
   over the stdlib went from 0.23 s to 0.69 s in a debug build (0.4 s
   release) and from 34 MB to 155–185 MB peak RSS, on 64 cores; per
   file the peak is 1.1–1.5 KB per token, held until the file's
   behaviour ends, with `_Symbols()` rebuilt per symbol the largest
   share (task 4 makes the symbol table a field); the deepest grammar
   recursion over the stdlib is 23. The 2500 limit refuses before a
   crash only when each scheduler thread has about 2.6 MB of stack:
   under glibc `ulimit -s 2048` a file of 2100 nested default-argument
   objects (`object fun f(x: A =` repeated; twelve frames per level,
   the heaviest shape) segfaults, and
   under musl with an unlimited limit the runtime's 128 KiB threads
   crash at 150 nested parentheses; task 5 adds the refusal Divergence
   5 of Discussion #13 describes.
4. **The on-demand lexer.** `_TokenStream.token(i)` scans forward
   until token `i` exists and returns it, `(TkEof, 0)` at and past the
   end; the end-of-source token is never stored, so `_scanned()` is the
   number of real tokens scanned. There is no `size()`; the parser's
   `_peek` and `flush_trivia` stop at the first kind `token(i)` returns
   that is not trivia, and `bump` emits the `TkEof` once and then
   nothing, as the quarry's did with the end token stored.
   `nth` is deleted with its one caller: `_Use` now commits after an
   identifier as ponyc's optional `use_name` does (`parser.c:1293-1297`,
   where `TK_ASSIGN` is `SKIP`, not optional), so `use x "a"` keeps the
   `use` with `x` as its name and records `expected =` at the string,
   where the quarry wrapped `x "a"` in an `NdError` and recorded
   `expected a package path or an FFI declaration` at `x`; a `use x`
   followed by a top-level keyword ends there, as ponyc's failed use
   resumes at the keyword, so the next item is not lost. The
   symbol table is a `let` field built once. Each refused token is in a
   sparse failure list as `(token index, LexFailure, offset, length)`,
   read through a cursor (`next_failure`, `take_failure`) that nothing
   in the parser calls yet; `causes.pony` holds the three `LexFailure`
   members the lexer distinguishes today (`UnterminatedLiteral`,
   `UnterminatedComment`, `UnrecognizedCharacter` with its byte) and
   task 9 adds the other eight with `LexError`. The property over
   arbitrary bytes and access sequences compares `token(i)` with a
   test-only eager scan, the quarry's loop written over the lexer's
   scanning helpers, so the property fails on a fault in the state
   carried between calls; it also checks every failure record against
   the scan. Its sources are built from fragments (`//`, `/*`, `"""`,
   a newline before a symbol with a newline form) as well as bytes,
   and its sizes are drawn explicitly, because pony_check's `array_of`
   with a lower bound of zero gives sizes that are almost always below
   three. A note for task 9: the failure list is unbounded and holds an
   object per `UnrecognizedCharacter`, about 75 bytes per refused byte
   for the file's life, where the budget keeps at most 500 records.
   Measured over the stdlib: release `hefermotor check` 0.4 s to 0.21 s
   and peak RSS 155–185 MB to 83–92 MB, the per-symbol table rebuild
   gone; debug 0.70–0.80 s, within the noise of task 3's 0.69 s.
5. **`skip_to`, the resync sets and the stack.** `_Parser.skip_to`
   wraps every token up to the next one in its resync set in an
   `NdError` and opens nothing when the current token is the end or in
   the set, so an `NdError` holds at least one token and none in the
   set; `error_and_recover` is `expected` then `skip_to`, and
   `too_deep` records and skips the same way. `nesting_close` holds
   `top_level` and the method starts as well as the closers and the
   end, so a refusal inside a body costs that body and not the file.
   `_Object` and `_Lambda` are guarded: an object literal in a default
   argument of an object literal's method, and a lambda in a lambda's
   parameter default or capture value, are cycles the term rule alone
   counted once per level, so at 2500 descents they needed 3,712 KiB
   and 2,896 KiB of stack in a release build; guarded, the heaviest
   shape is an object literal in a `match` case (whose pattern rule
   bypasses the term rule) at 2,023 KiB release, then a lambda type's
   type-parameter default at 1,953 KiB, the object literal in a default
   argument at 1,868 KiB and the FFI call at 1,560 KiB; the debug
   maximum is 1,581 KiB, measured by bisecting `ulimit -s` over a
   program parsing each shape 3000 deep. `parse.StackNeed()` is 3 MiB,
   not Discussion #13's 2 MiB: 2 MiB would sit 25 KiB above the
   heaviest shape and a compiler change could cross it. A refusal in a
   member list or argument list is followed by one per sibling region
   the enclosing loop parses at the limit, so an over-deep object
   literal 3000 deep is refused 1,751 times; the counts are pinned per
   shape in the recovery tests, and task 7's rule that `parse/nesting`
   records are never dropped by the budget is to be read against them.
   `StackCheck` in `command` reads the soft `RLIMIT_STACK`,
   `PTHREAD_STACK_MIN` and the C library's default thread stack,
   computes what the runtime computes, and `Run`, which takes it as a
   collaborator so that the command tests do not read the shell's
   limit, exits 2 naming `ulimit -s` before discovery when the result
   is below the need; under glibc an unlimited soft limit gives 2 MiB
   threads, so `ulimit -s unlimited` is refused too. `make test-stack`
   runs the parse tests of the debug and the release build under
   `ulimit -s 3072` and requires the release command to accept that
   limit, refuse one KiB less and refuse an unlimited limit where the
   hard limit allows one, which pins the Makefile's number to
   `StackNeed`; every CI job that runs the command sets `ulimit -s
   8192` when the limit is unlimited, and the test job runs `make
   test-stack` after `make`. The recovery tests parse one input per
   shape family 3000 deep (the nesting constructs `_Shapes` lists, the
   chains, and two token floods 30,000 long) to a sound tree, refused
   the pinned number of times where the shape descends and not where
   it chains.

   The `skip_to` sites as the code stands, each with why the loop
   around it cannot spin now that `skip_to` may consume nothing:

   | Site | Resync set | Consumes because | Parent |
   |---|---|---|---|
   | `_Module` loop: not `use`, not an entity keyword, not the end | `top_level` | the branches excluded `use` and the entities, which is the whole set | `NdModule` |
   | `_Use`: the specifier is not a string or `@` (after `TkId` with the `=` absent and a top-level keyword or the end next, `_Use` returns without recovering) | `top_level` | may consume nothing (`use` then `use "z"`): then no `NdError`, and the module loop takes the token; `_Use` bumped `use` before | `NdUse` |
   | `_Members` loop: not a field or method start, not `end`, not a top-level keyword, not the end | `member_or_top_level` | the loop and the branches excluded the whole set | `NdMembers` |
   | `too_deep` in `_RawSeq`, `_Assignment`, `_Term`, `_ParamPattern`, `_ConstExpr`, `_IdSeq`, `_TypeRule`, `_Object`, `_Lambda` | `nesting_close` | the caller returns on refusal; a closer, member start or entity keyword current consumes nothing and no `NdError` opens; every loop reaching a guarded rule consumed a separator first or is `_RawSeq`, whose no-progress branch takes a token that ends nothing | whatever is open |
   | `_RawSeq`'s no-progress branch: a token that starts no expression and ends no sequence | that token | it consumes it | `NdSeq` |

   The use section rule, the members contexts and the `_ClassDef`
   guard of Discussion #13's section 5 are task 10's.
6. **The tuple, `Node`, `TreeCheck` and `--tokens`.** An element is
   `(SyntaxKind, U32 offset, U32 subtree size)`; width is derived from
   the next element's offset, the parser emits offsets and `build`
   compacts the array. `SyntaxTree._create` holds the `SourceFile`;
   the public surface is `file`, `size`, `root`, `nodes`, `path_to`
   and `reprint` (and `diagnostics` until task 7), with `_node`,
   `_kind`, `_offset`, `_size`, `_finish` and `_elements`
   package-private; `walk`, `is_leaf(i)`, `children(i)`, `text(i)` and
   the O(i) `offset(i)` are gone. `Node` carries the tree and an index,
   every method total, equal only within one tree object. `path_to` is
   half-open with the `TkEof` exception. `TreeCheck` is one pass with a
   stack of open nodes over the six tree rows, `OneRoot` also requiring
   element 0 to be an `NdModule`; with widths derived, a
   changed size or offset moves bytes between neighbours rather than
   losing them, so the counterfactuals are a root that stops short, a
   last element that is not the end, a subtree that overruns or is
   empty, an offset that goes back, a node whose offset is not its
   first child's, and an empty node off its place, each with its exact
   violation set. `DiskFileSystem.read` refuses a file over
   `U32.max_value()` bytes with `Denied("file is 4 GiB or larger")`,
   which fails the package as an unreadable file does; the
   `FileTooLarge` member T5 proposed is not added, since `Denied`
   already carries the reason as text; the test makes a sparse file of
   that length. `Parse.tree(file)` returns the tree for tools until task 11
   puts it on `ParsedFile`. `tools/syntax --tokens` prints
   `ponyc_name()` per leaf that is not trivia or the end token, which
   ponyc's dumper stops before, one file per behaviour so that a
   file's tree is collected before the next is read; `tools/agreement/`
   holds
   `ponyc_dump.c` and `check.py` from pony-lsp2 and `gen_tk_names.py`,
   which reads ponyc's `token.h`; `make token-agreement PONYC_SRC=...
   PONYC_LIB=...` builds the dumper against `libponyc-standalone.a`
   and compares over the stdlib beside the `ponyc` on `PATH`: 465
   files, 465 agree. Measured: the stdlib is 3,724,593 bytes and
   1,301,593 elements (0.35 per byte, 20.8 MB at 16 bytes each); a
   program reading and parsing every file on one scheduler thread
   takes 272 ms in release, of which the per-file `compact()` is about
   20, and a `Node` walk of every element 48 ms more, about 37 ns a
   node; Discussion #13 section 10 recorded 0.16 s for pony-lsp2's
   parser over the same corpus in its own harness, and the difference
   has not been traced. `hefermotor check` over the stdlib in release
   is 0.24 s, as after task 4. Found while measuring: a tuple type
   that holds a `TokenKind` and a `NodeKind` (145 and 77 members) in
   an array cost ponyc seven minutes of type checking in the recovery
   tests, from task 5; the test now keeps the kinds in an array of
   their own, and the compile is back to 75 s.

7. **Parser diagnostics as causes; `Parse.apply` reports.**
   `causes.pony` holds `SyntaxExpected(what, found)`,
   `SyntaxUnterminated(what, before)`, `NestingTooDeep(what, limit)`
   and `SyntaxLimit(limit)`; `SyntaxDiagnostic` and the tree's
   `diagnostics` field are gone, and `_ParseModule` returns the tree
   with the records. `_Records` keeps them in emission order under the
   budget (500 `parse/expected` and `parse/unterminated` per file, then
   one `SyntaxLimit` at the file) and the dedupe (an expectation at the
   significant token the last expectation was noted at is dropped);
   `ParsedFile` sorts them under `DiagnosticOrder`, so `hefermotor
   check` reports parse errors from this task. `expected` records
   nothing at a `TkLexError`, whose record is the lexer's (task 9), and
   positions an expectation at the end of the file at the last
   significant token. `too_deep` records `NestingTooDeep` over the
   refused token, and at the end of the file at the last significant
   token with width 0, as `expected` does. `NestingTooDeep.message` is
   a sentence, "WHAT nested past the grammar depth limit of N", since
   it renders on its own line with no "expected" frame. Every `what` is ponyc's rule description, probed at
   `--pass=parse` and quoted in the tests: the sequence rule and the
   type rule take the site's noun and thread it to the atom, so a
   missing type is "field type", "return type", "parameter type",
   "provided type", "type argument", "type constraint", "variable
   type", "capture type", "viewpoint" or "iftype clause" by its site;
   "value" after an operator or a `;`, "assign rhs" after `=`,
   "expression" after a prefix operator or `consume`, "formal argument
   value" after `#`; a rule whose first token is a name reports its
   caller's noun where ponyc's not-found propagation would ("type
   parameter", "parameter", "capture", "named argument", "iterator
   name", "with expression"); a closer is its own text. Deviations
   from the design's task text, each recorded here: `SyntaxUnterminated`
   has no producer until task 8's `close`, so the budget's unterminated
   leg is tested through `_Records` only; `_emit` does not read the
   lexer's failure list, since the cause it would record is task 9's.
   Entry conditions changed to match ponyc's rules: every optional rule
   is entered only where its first token can start it, as ponyc's `OPT
   RULE` is (parameter lists on `TkId` or `...`, positional arguments,
   array elements and a jump's value on `_TokenSets.expr_start`, a case
   pattern on `_TokenSets.case_pattern_start`, which has no control
   keyword but `while` and `for` so that `| if guard =>` is a guard, a
   lambda's parameters on `TkId`, a lambda type's on
   `_TokenSets.type_start`), so `f(,)` records `expected )` at `,` as
   ponyc does and `return ;` ends the sequence at the jump and reports
   at the `;` from the member list, where ponyc's restart check does; a
   sequence stops after a jump, as ponyc's `SEQ_STOP_AFTER_CHILD` does;
   a `;` with nothing after it records `expected value`; and a prefix
   operator in a case pattern keeps the case mode, as ponyc's
   `caseprefix` recurses through `caseparampattern`, so `| -if` records
   `expected expression` where the old normal mode parsed a
   conditional. The gates also change three `_Shapes` refusal counts
   from 2 to 1: the unwinding rule no longer re-enters its list at the
   resync token and refuses again. The three sets the gates test are
   built once per `_Parser` (`at_expr_start` and its siblings): built
   per call, at every call expression among other sites, they added
   10-15% to the sum of `Parse.tree` over the stdlib's files in a debug
   build, and caching them recovers most of that. Divergences 16 and 17 of Discussion #13 are in
   `docs/ponyc-divergences.md`. `TreeCheck` takes the diagnostics and gains
   `ErrorLeafOnly`, `ErrorNonEmpty`, `ErrorAtDiagnostic` (with a
   third exception until task 9: an error node whose first token is a
   lexer refusal), `ErrorParent`, `ErrorNoEntity`, `ErrorNoMemberStart`,
   `ErrorNoUseInSection`, `DiagnosticInFile` and `DiagnosticsOrdered`,
   each with a hand-built counterfactual; it holds over every fixture,
   truncation, sweep and shape, and over a file that reaches the
   budget and then nests past the limit, where the `NestingTooDeep`
   beside the `SyntaxLimit` is what excuses the refused region's error
   node under an entity. hefermotor names the token found where ponyc
   names the token before ("expected ), found ," against ponyc's
   "expected ) after ("); the positions agree in every probe.

8. **Unterminated constructs and the position checks.** `_Parser.open`
   takes a construct's opening token as an `_Opener` and `close`
   emits the closer or records `SyntaxUnterminated(what, before)` over
   the opener, at the 18 sites that serve ponyc's 21 ported `TERMINATE`
   rules with ponyc's strings (`_Lambda` serves both lambda forms,
   `_ArrayLit` both array forms, `_TypeArgs` both `typeargs` and
   `ffi_ret_typeargs`); the closers ponyc reads with `SKIP` keep
   `expect`. The record is unconditional (T2's working answer) and is
   not noted for the dedupe, so a rule that fails on the token found
   in the closer's place still records there, which is what keeps
   every error node at a record. `before` is that token, or the last
   significant token at the end of the file, where ponyc's `Info:`
   frame points in every probe. Unconditional means the record is also
   made for a closer the source has but the rules inside stopped short
   of, as in `{(,) => 1 }`, where a lambda's header has no sequence to
   resynchronise in; ponyc's `TERMINATE` does the same, and divergence
   14 and T2's cost now name that shape, which the design's T2 text
   did not. `_Opener` is a tuple, not an object, since every call and
   control structure takes one. Divergences 13 and 14 of Discussion
   #13 are in `docs/ponyc-divergences.md`. The harness
   scores a `syntax-*` fixture at `--pass=parse` on the verdict and,
   when both reject, on positions: ponyc's set must be a subset of
   hefermotor's `parse/` positions (`positions.py` turns a document's
   byte offsets into ponyc's `path:line:col:`), hefermotor's count
   must equal the fixture's `EXPECT`, and the first-position agreement is summed
   on the summary line; `KNOWN_GAP` lists a set of classes. Twelve
   fixtures: nine agree, `syntax-junk-in-closed-if` and
   `syntax-lexerror-at-closer` (a lexer refusal in a closer's place,
   which `close` records over unlike `expected`) are `positions` gaps
   (divergence 13, and the lexer's record until task 9), `syntax-depth` a `verdict`
   gap (divergence 15); first-position agreement 9 of 11.
   `syntax-unterminated` holds one entity per construct, and ponyc
   reports all 21 in one run at the positions hefermotor reports.
   Tests: the 21-row table finds each row's opener and last token in
   its source; `foo(` records the opener alone, `foo(1,` the opener
   and the argument, sorted opener first; junk in an open `if` two
   records and in a closed `if` one; `fun f(` at the end of the file
   one expectation at the `(`; `foo(1 "` one record until task 9; 600
   open calls 500 records and the limit. The `EXPECT` counts of the
   junk fixtures are baselined under the quarried item grammar and are
   re-baselined in task 10.

9. **Lexer diagnostics and string values.** `LexError(failure)` with
   code `parse/lex`, over the eleven `LexFailure` members, each check
   ported from its `lexer.c` site: `_integer` is `lex_integer` with a
   `U128` accumulator and `mulc`/`addc` for ponyc's overflow test,
   `_escape` is `escape` with its three faults, `_triple_string`
   carries the below-the-opener check, `_character` the empty-literal
   check. A refusal inside a literal is recorded at the escape with
   the literal's token index and the literal keeps its kind; a refused
   number covers the bytes ponyc consumed before refusing, and scanning
   goes on from the next byte, so every byte still lies in one token.
   `_Parser._emit` records the stream's failures for the token it
   emits, in cursor order, so lexer records reach `_Records` in the
   order the parser reads and the sort puts a lexer record before a
   parser record at a later byte. `ErrorAtDiagnostic` loses its
   lexer-refusal exception: a refused token's record starts at the
   token. Messages are ponyc's texts through a `message` on every
   member; `_Byte` renders a source byte as itself when printable
   ASCII and as `\xNN` otherwise. `StringLiteralValue` ports
   `normalise_string` line by line, the cut clipped by the line's
   length with its newline as ponyc's `memmove` clips it, and decodes
   a `\x` escape as its code point UTF-8 encoded (`append_utf8`), where
   the quarried code pushed the raw byte; a refused escape drops out
   of the value; `of(node)` is added, still without a caller until the
   views. Deviations from the task text, each recorded here: the
   design's note that a BOM is three errors on both sides is wrong on
   ponyc's side, whose parser stops at the first refused token, so the
   entry in `docs/ponyc-divergences.md` says that; ponyc's unicode-range
   message formats the rest of the source (`%8s`), recorded as a
   divergence rather than matched. Two ponyc bugs found by the review
   and recorded in that entry, not fixed here: a `\` followed by a
   newline inside a literal leaves every later line ponyc reports one
   short, and a `\` as the last byte aborts a ponyc built with
   assertions. `push_utf32` writes U+FFFD for a surrogate escape where
   ponyc's `append_utf8` writes the code point's bytes, so `_decode`
   encodes by hand. `make token-agreement` re-run: 465
   files, 465 agree. `make token-digest` writes one digest per stdlib
   package of its `--tokens` output to `tools/syntax/token_digest/`
   (41 packages, deterministic across two runs), for task 13's `make
   corpus` to compare and the bump procedure to regenerate. Fixtures:
   `syntax-lex-underscore`, `-escape`, `-dollar`,
   `-unterminated-string`, `-triple-not-below` and `-bom` (EXPECT 3,
   ponyc's `1:1` among them); `syntax-lexerror-at-closer`'s gap
   closes and its EXPECT becomes 2. Tests: one per failure at ponyc's
   position over twenty-one sources; the refused extents; the overflow
   boundary in three bases; the byte rule on every byte-carrying
   member; a lexer record before a parser record, and an escape inside
   an open `if` beside the opener; the `lexer.cc` triple-string cases
   with a `\r\n` leading newline, a whitespace line shorter than the
   indent, and a one-line literal; `"\q"` decodes to nothing.

10. **Fidelity of the item grammar.** `_Module` is `_ModulePrefix`
    (the module opened, the package docstring, `_UseSection`) then the
    entity loop, so the two entry points of task 11 run one prefix
    rule; `_UseSection` ends only at an entity keyword or the end and
    takes anything else that is not `use` as an error item resynced to
    `top_level`; `_Use` commits after its name and skips the rest of
    the command to `top_level` when the `=` is absent; `_UseFFI` reads
    `_FfiRetTypeArgs` and `_FfiParams`, which carry ponyc's annotation
    slot after each type argument and each parameter and are otherwise
    `_TypeArgs` and `_Params` under the same node kinds; `_Members(p,
    ctx)` with `_InEntity` (ends at an entity keyword or the end;
    resyncs to a member start or an entity, so a stray `end` or `use`
    is one error item) and `_InObject` (ends at `end` as well), and a
    method-seen flag that reports `expected method` at a field's
    keyword and parses the field; `_ClassDef` opens the member list
    unless an entity keyword or the end is next, so a `use` after an
    entity is the list's error item and the members after it are kept
    (`UsesFirst` in `TreeCheck` pins that no command follows an
    entity). `_ClassDef`, `_Method`, `_Params` and `_TypeParams`
    re-read against `parser.c:1130-1330`: no other optional was
    missing. `_What` holds the two module-level nouns. Deviations from
    the task text: `_ParseModule` stays as the primitive that builds
    the parser and runs `_Module`, since task 11 reshapes the entry
    points; the junk fixtures' `EXPECT` counts did not change, so no
    re-baseline. The `skip_to` table in task 5's entry describes the
    quarried rules; the item-level rows of the design's recovery
    table (Discussion #13, section 5) are what the code keeps now.
    Probes at `--pass=parse` are quoted in each item
    test's docstring; ponyc's restart text is "after type, interface,
    trait, primitive, class or actor definition" at every member-level
    site, which is its `SEQ` description rather than the `SKIP` noun
    the design named, and the noun hefermotor uses there stays "field
    or method". Tests: `_test_items.pony` with a skeleton snapshot
    (kinds, trivia left out) per item rule with its optionals present
    and absent and an error form; the stray `end`, the `use` between
    members and after the last member, the object literal's `end` and
    its field-after-method with no `end`, the field after a method in
    a trait, the `var` that is a local, the junk between commands, and
    the FFI annotation lines of ponyc's `ffi-struct-by-value` test.
    Fixtures: the six named in the task, each agreeing with ponyc on
    position, and `syntax-field-after-method-in-object`, a `positions`
    gap: in an object literal that has its `end`, ponyc reports the
    literal unterminated at `object` where hefermotor reports the
    field's keyword. The design's divergence 10 (junk between `use`
    commands) turned out to be parity: ponyc's `use` restart check
    skips to the next command and reads on, as hefermotor does; the
    entry in `docs/ponyc-divergences.md` records that. `_Shape` takes
    a `trivia` flag and `_Skeleton` is `_Shape` without it. Full
    harness: 95 compared, 0 differ.

11. **The boundary: `ParsedFile`, `uses_only`, the stubs.**
    `ParsedFile(tree, diagnostics)` with `file()` and `uses()`;
    `_UsesOf` reads the module's `NdUse` children (a command with a
    string literal among its direct children; an alias from
    `NdUseName`; the guard is the one node after `if`; the span runs
    from the keyword to the guard's or the literal's end, so a guard
    cut by an entity keyword leaves `guard` `None` and the span at the
    literal). `Parse.uses_only` is `_uses_only(file, stream)`: the
    prefix rule, then `_Parser.stop`, which flushes the pending trivia
    and emits a `TkEof` at the stop offset, then `build`, the records
    discarded. `_Parser` takes its stream, for the laziness test.
    `_use_scanner.pony`, `_ParseModule` and the stub test are gone; the
    three test stubs run `parse.Parse`; the five-row malformed-command
    table replaces the scanner's test, each row's ponyc line quoted,
    with the raw-newline row (`use "c` runs to the next quote,
    T7's working answer). The six scanner gaps closed: the harness
    reported each `known gap closed` and their markers are removed.
    Measured single-threaded over the stdlib's 465 files (best of
    seven, release): the M0 scanner read the sections in 0.64 ms, the
    prefix parse reads them in 5.9 ms, and the full parse, which lexes
    every token, takes 271 ms (the full lex alone was 114 ms in the
    design's pricing; not re-measured, since the full parse, which
    includes the lex, bounds it); `hefermotor check` over the stdlib,
    release build,
    is 0.20–0.21 s on `main` and the branch alike, with the trees now
    kept in every `ParsedFile` (max RSS 118–126 MB on the branch
    against 114–123 on `main`).
    Deviation from the task text: the equivalence of the two entry
    points over the stdlib is not a unit test, since the test binary
    has no path to the ponyc packages; it was run by an ad-hoc scratch
    program over all 465 files (362 commands, none differing) and task
    13's `tools/syntax --check` is where it runs from then on. The unit
    test compares them over the tree fixtures and the
    flush-against-keyword inputs, and the laziness test pins that
    `uses_only` scans no token past the first entity keyword.
    A guard that is one string literal is the guard, not a second
    locator: `_UsesOf` takes whatever node follows `if`. A node now
    ends at its last real token as it begins at its first:
    `_Parser.finish`, `wrap_from` and `chain_wrap` leave trailing
    trivia to the enclosing node, and `finish` moves a node that
    consumed nothing before the trivia flushed ahead of it, so a guard
    cut inside an expression (`use "a" if x -` then a newline) spans
    `x -` and not the newline the failed operand's rule read past;
    every node's span on incomplete input ends the same way, which the
    views will rely on.

12. **The properties.** `_test_properties.pony` over four seeds in
    `_test_seeds.pony` (a use section with entities of every kind;
    fields, methods and an object literal; control structures and
    lambdas; type grammar and FFI), each pinned clean with its entity
    and member counts. Three properties, 300 to 400 samples each. The
    use-section generator draws one to five well-formed commands (a
    plain, an escaped or a triple-quoted locator; an alias or none; a
    guard that is an identifier, a parenthesised expression or none)
    and one fault from the design's closed set (junk before a line,
    the specifier deleted, the alias without `=`, the guard cut by the
    entity keyword, a `use` alone, the last line's quote unterminated)
    and asserts the surviving commands' locators, aliases and guards,
    one diagnostic at the fault's offset, the two entry points'
    agreement and `TreeCheck`. The byte-level property mutates a seed
    by a truncation, a four-byte deletion or an insertion of `"`, `(`,
    `end` or `/*` at a byte drawn within that seed, and asserts
    `TreeCheck` empty and the entry points equal, with pony_check's
    shrinking. The token-level property deletes, duplicates or inserts
    a token at a slot drawn within that seed's tokens, computed once
    per seed, and asserts the entity and member counts against the
    outcome table. The property's first run over the seeds showed two
    of the design's rows wrong, where the design said a wrong row
    would show: "any other leaf deleted or duplicated" is not 0 for
    members, since a token whose absence ends a method body early
    (`match`, `(`, `=>`, `|`, an annotation's `\`, a parameter's
    name, and more) leaves the locals after that point to the member
    list as fields, an object literal whose parse breaks leaves its
    fields as locals, and a field's value cut short reads the `var`
    and `let` fields after it as local declarations; and "a member's
    keyword deleted" is not exactly −1, since the member's locals
    become fields except those an earlier local's value takes. The
    table now has exact rows for a deleted or duplicated entity
    keyword (±1, and −members for the first entity), a duplicated
    member keyword (+1) and an insertion's entity delta (0, or +1 for
    an entity keyword), and a range for the member delta of everything
    else: from minus the fields at or after the token in its innermost
    object literal and the run of `var`/`let` fields after its field,
    to plus the locals at or after it in its member (a deleted member
    keyword: −1 to −1 plus its locals); outside a member the range is
    zero. Each range is what locality means: an edit's effect on the
    member count is confined to the member it sits in and, inside a
    field's value, the fields after it. The review's exhaustive run of
    every token edit on every seed (10,842 edits) found one row gap
    the first ten property runs had a 2% chance per run of drawing: an
    `end` inserted before an object literal's field keyword ends the
    literal, so a member keyword inside a literal now carries the
    literal's fields; the same run found the ranges are bounds and not
    vacuous (the exact rows, a quarter of the edits, assert a change;
    the ranged rows are met at both edges), and that a parser that
    ignored every edit would pass the ranged rows, which is what a
    bound means. `_TestTokenEditRows` runs fifteen edits on the
    members seed with their exact deltas, one per row and one per
    mechanism the ranges bound. Two departures from the sketch: with
    the ranges every edit has a row, so the generator's failure on a
    rowless edit has nothing to fire on and is not written; and a
    byte-level sample is one edit rather than the sketch's batch of
    eight, so that a failing sample shrinks to one edit. The three
    properties run in 1.5 s together (the token property was 9.3 s
    before its tokens were computed once per seed and its messages
    built only on failure); a 400-sample run draws about 4% of the
    token edits and 2% of the byte mutants, so the exhaustive
    enumeration, at about 7 s, is the stronger check and is not in the
    suite. Ten consecutive runs of the three properties passed after
    the table was corrected; the grammar mutation `_InEntity` ending
    at `end` failed the token property and the row test, and the use
    section resyncing at entities failed the token, byte and
    use-section properties.

13. **`tools/syntax` and `make corpus`.** The tool gains `--tree`
    (the elements in pre-order with kind, offset, width and a leaf's
    quoted text, then the diagnostics), `--check` (one actor per file,
    one behaviour per parse so that one tree is live per actor; the
    file and its 48 mutants through `TreeCheck` and the two `use`
    readers; violations in file order, the parameters and the
    diagnostic-count distribution on the summary lines) and
    `--mutants [--emit <dir> --every N]`, and takes a directory for
    every `.pony` file under it. The mutants are the design's: at eight
    cut points at k/9 of the file, a truncation, a four-byte deletion
    and an insertion of `"`, `(`, `end` or `/*`, numbered by operation
    then cut point, so `--every 101`, prime to 48, samples every edit.
    `tools/syntax/run.sh` (`make corpus`, in the differential CI job)
    runs `--check` over the packages beside the ponyc on `PATH` and,
    with `PONYC_SRC`, the checkout's `examples/`,
    `test/full-program-tests/` and `tools/`, and fails unless the
    summary line counts every `.pony` file `find` sees, since a run
    whose actors never all report exits 0 without one; emits the
    sample and scores it with `tools/differential/run.sh`, which gains
    the `sample-` kind: the verdict at `--pass=parse`, gated, where
    hefermotor's verdict is whether the document holds a `parse/`
    diagnostic (ponyc's parse pass resolves no `use`, so an edited
    locator must not count), and two rates summed on the summary
    line and recorded, how often every ponyc position is a hefermotor
    position and how often the lowest positions agree; fails unless
    at least one sampled mutant was rejected, since a sample no edit
    reached agrees trivially; regenerates the token digests through
    `tools/syntax/token_digest.sh` and diffs them; and times
    `hefermotor check stdlib`. Under `make test`: two fixtures under
    `tools/syntax/fixtures/` (excluded from the import check) pin
    `--tree`'s output, one well formed and one with a `(` never
    closed, a tab, a non-ASCII byte and an unterminated string; every
    fifth of their 96 mutants is committed under `fixtures/mutants/`
    and diffed against a fresh `--emit`, pinning the six operations,
    the cut arithmetic, the labels and the stride; and two `sample-`
    cases under `tools/differential/cases/` pin the kind's verdict
    rule, one with an unresolvable `use` that scores `both accept`
    and one parse error. Measured on the stdlib slot (465 files,
    release): 22,320 mutants, no violation and no `use` reader
    disagreement; 5,540,028 lines parsed in 8.1–8.3 s of CPU on one
    thread (665k–684k lines/s/core over two runs, `TreeCheck` and the
    prefix parse included) and 0.8 s real on eight (14.8 s of CPU, 188 MB max RSS
    against 50 MB on one); the distribution over the mutants was
    0: 10,844, 1: 6,446, 2: 1,680, 3: 1,042, 4: 517, 5–9: 880,
    10–99: 870, 100–499: 38, 500+: 3 (the budget reached); the zero
    bucket is mostly edits inside docstrings and comments, with some
    deletions that leave valid code. The 221-mutant sample agreed
    with ponyc on every verdict; every ponyc position was a
    hefermotor position on all 120 rejections, and the lowest
    positions agreed on 84 of 120, the other 36 all the opener
    record, T2's cost (an `end` or `(` inserted, or a truncation,
    leaving a construct unclosed: ponyc reports where it stopped,
    hefermotor there and at the opener). The checkout's `examples/`
    (117 files), `test/full-program-tests/` (310) and `tools/` (376)
    passed `--check` with one file reporting, `pony_compiler`'s
    `compile_errors_04`, which is broken on purpose. T1's working
    answer is taken as far as it has a consumer:
    `tools/corpus/extract_corpus.py` (from pony-lsp2, the
    fixture-package writing dropped, the C escapes decoded in one
    pass, comments outside string literals dropped before the scan,
    every `TEST_ERRORS` variant read) writes the unit-test programs
    of `test/libponyc/*.cc` as `sample-` cases into `build/corpus/`
    under `make corpus-cases PONYC_SRC=<checkout>`, never in CI, and
    the differential harness scores them against the ponyc on
    `PATH`; `pass_reach.py` is not quarried, since with the live
    ponyc as the oracle the pass each case reaches has no consumer
    before the semantic milestones. The 1,553 programs extracted from
    the pinned checkout (273 blocks skipped as not one program with
    one verdict) agreed with ponyc on every parse verdict; 28 are
    parse rejections (the suites' other rejections are `syntax.c`'s
    and later passes'), every ponyc position among them was a
    hefermotor position, and the lowest positions agreed on 27, the
    one exception again the opener record (`class \0a\ C`: ponyc
    stops at the lexer's refusal, hefermotor also records the
    annotations unterminated at `\`). `make corpus` takes
    a minute after the release builds (59 s): the sample's 221 ponyc
    runs are most of it, so `CORPUS_EVERY` sets its wall time;
    `run.sh` runs `--check` on one scheduler thread so the
    lines/s/core it prints is one core's rate; its `hefermotor check
    stdlib` was 0.48 s real in that run and 0.23–0.52 s over five
    more. Deviations from the sketch: a `--check` actor parses one
    tree per behaviour rather than its file and every mutant in one,
    so the garbage held between collections is one tree and not
    forty-nine; `--check` prints the mutation parameters as well as
    `--mutants`, since its summary is the one `make corpus` shows;
    the digest loop moved from the Makefile to
    `tools/syntax/token_digest.sh` so that `make corpus` and `make
    token-digest` run one loop; and the sketch's sample "has no
    marker and no README", which holds of the emitted cases, while
    the two committed ones carry a README like every other fixture.

14. **The views.** `view_items.pony` and `view_types.pony` as the
    design sketches them: `PackageUse`, `FfiDecl`, `FfiReturnArg`,
    `EntityDecl`, `FieldDecl`, `MethodDecl`, `ParamDecl`,
    `TypeParamDecl`; `TypeOf` over `NominalType`, `UnionType`,
    `IsectType`, `TupleType`, `ViewpointType`, `LambdaType`,
    `ThisType` and `CapType`, with `ValueArg` in `TypeArg`;
    `SyntaxTree.docstring`, `use_commands`, `entities` and
    `ffi_decls`; `_UsesOf` over `PackageUse`; `_Parts` with `unique`,
    `after`, `before`, `leaf`, `leaf_before`, `each` and `operands`,
    each accessor's docstring naming the rule it uses. The
    uniqueness each "the K child" accessor takes is data, one set of
    kinds per accessor in `_UniqueParts`, and `TreeCheck`'s `_Views`
    walk counts every set in one pass over the node's children; a
    field's `TkString` is unique only without `TkAssign`, since a
    string value is a `TkString` child too (found on the first
    `--check` run over the stdlib's mutants: a `"` inserted before a
    field's docstring), and the docstring rule after `=` is
    positional; a nominal type's name is unique only without a dot,
    for the same reason. The
    walk runs only when the structural rows found nothing, since it
    reads the tree through `children`, which is total only over a
    tree those rows accept. `ViewsNest` also requires the views a
    list accessor returns to be in source order without overlap,
    which is not by construction for the fold; through a tree the
    grammar builds it fires on nothing (its counterfactual is the
    checker's comparison inverted: 53 tests fail), and
    `PartsUnique`'s counterfactuals are hand-built fields with two
    name tokens and with two strings without a value, beside one with
    a string value then a docstring, which is silent. The infix fold
    collects a run's members and builds the `UnionType` or
    `IsectType` when the run closes, at the operator change or the
    end, with the closed run the first member of the next unless it
    has no member: the review found `(| & A |)` carrying an empty
    union whose span, the node's, reached past the intersection's,
    the one way `ViewsNest` fired through a sound tree; `(A | B & C |
    D)` folds as the docstring says and the inner runs' spans cover
    their members. An
    infix type reaches a field only inside parentheses, since ponyc's
    `type` is `atomtype [viewpoint]` and `infixtype` lives inside
    `groupedtype`, so the fold tests write `(A | B)`. Deviation from
    the sketch: `MethodDecl.docstring` follows ponyc's
    `sugar_docstring` as it runs after `fun_defaults`, rather than
    the rule its own lines state: `fun_defaults` appends `None` to
    the body of a `fun` whose return type is absent or a nominal
    named `None`, so `fun f() => "s"` has the docstring `"s"`
    (probed: ponyc's sugared AST carries it, for `(None)`,
    `builtin.None` and `None val` too, and `fun f(): U8 => "s"`, `be
    f() => "s"` and `new create() => "s"` do not), where the sketch
    said a body that is only a string has none;
    `MethodDecl.returns_none` is that condition, public because M2's
    body defaulting will need it. Measured: the walk adds 6 s of CPU
    to the stdlib's 22,320-mutant `--check` on one thread (14.4 s
    from 8.2 s; 0.3 ms per parse), and finds no violation over the
    stdlib,
    the checkout's examples, full-program tests and tools (60,864
    mutants). The walk over a type's members uses an explicit stack:
    a type nests as deep as the grammar's depth limit, and with the
    walk recursing the release parse tests overflowed the 3 MiB
    `StackNeed` sizes for the parser alone (CI's `make test-stack`;
    the debug build's frames fit). Five counterfactual mutations of
    the accessors and the rows each failed the test written for them;
    the review's eight
    more found the rows the tests now carry (two return type
    arguments, `None` in every spelling, `(|)`, `A iso!`, `->B`,
    `(A, )`, a field with no type, two broken lambda types, and the
    one-member union's class).

### The ponyc-bump procedure

Every claim about ponyc in these documents cites commit `6a0bfa80b`;
`parse/token_kind.pony` was generated from it, and the harnesses were
last run against it. Moving to a later commit is one change that does
all of the following, so that the pin is one commit throughout:

1. Update the commit named at the top of this file and in
   `docs/ponyc-divergences.md`, and re-check each cited path and line.
2. `make token-agreement PONYC_SRC=<checkout> PONYC_LIB=<its lib dir>`
   against the new ponyc on `PATH`: every stdlib file must agree. Then
   `make token-digest` and commit `tools/syntax/token_digest/`, which
   changes with the stdlib.
3. `make regen-token-kinds PONYC_SRC=<checkout>` and review the diff of
   `hefermotor/parse/token_kind.pony`. A kind added or removed changes
   the counts the token-kind tests assert; the tests still pass under a
   renamed kind, a changed fixed text, or an addition paired with a
   removal, so the reviewer of the diff must find those. `_lexer.pony`
   mirrors `lexer.c`'s scanning rules by hand, so the diff of `lexer.c`
   between the two commits is reviewed as well.
4. Run `make test`, `make determinism`, `make differential` and `make
   corpus` against the ponyc built from the new commit, and `make
   corpus-cases PONYC_SRC=<checkout>` for its unit-test programs; a
   differential case that changes class moves between `KNOWN_GAP` and
   the ordinary cases in the same change, with the divergence recorded
   in `docs/ponyc-divergences.md`.

## Rules and notes with no other home

- **The import allowlist is `tools/imports/deps.txt`**, checked by
  `tools/imports/check.sh` under `make lint-source`, which `make test`
  runs. A package that starts to need a stdlib package adds it to its line
  in the same change. The file also carries three directive lines: `!banned` (packages nothing may use), `!phase` (the
  packages and files where `digestof`, `MapIs`, `SetIs`, `HashIs` and `Pointer[` is rejected) and
  `!hash64-only` (files where `.hash()` is rejected), so that the check
  reads one file.
- **No map or set is iterated into bytes or into diagnostics without a
  sort.** `HashIs`, `MapIs` and `SetIs` hash by address, and two runs can produce identical bytes by luck.
- **`"group"` in the JSON document and `Group.index` are run-local
  ordinals.** The `groups` array carries each group's member directories,
  and the harnesses compare groups as sets of directories, never by
  ordinal.
- **The POSIX assumption lives in five places**: the default search roots
  (`/usr/local/lib`, `/opt/local/lib`), `MemoryFileSystem`'s lexical path
  normalisation, the port of `is_path_absolute` and `is_path_relative`
  (whose Windows branches at `package.c:1721, 1742, 1754` are not ported),
  the stdlib slot derived from the `ponyc` on `PATH`, and `_StackCheck`,
  which reads `getrlimit(RLIMIT_STACK)` and `pthread_attr_getstacksize`
  because the runtime sizes scheduler thread stacks from the soft limit
  (`src/libponyrt/platform/threads.c:185-208`); Windows gives every
  thread 1 MiB by default and is not handled.
- **`EACCES` from disk has no CI test.** `DiskFileSystem` maps it to
  `Denied`; CI runs as root, and git cannot store a mode-000 file, so the
  mapping is exercised only by hand. The same holds for a `.pony` entry
  that is a device or a pipe, which `DiskFileSystem.read` refuses with
  ponyc's "can't determine length of file" rather than asking the
  stdlib for a length it cannot give.
- **The stdlib slot is the first file named `ponyc` on `PATH`**, not
  the first executable one: `StdlibSlot` checks that the file exists
  and never that it runs, so a `ponyc` the shell would skip still
  decides the slot. The differential harness's sentinel is what
  catches a slot that differs from the `ponyc` that runs.
- **A package's display name is ponyc's qualified name, first reach
  wins, and nothing identifies a package by it.** ponyc loads
  dependencies depth-first (`scope.c:364-366`); discovery here is
  breadth-first, so the two can pick different names for a directory two
  locators reach.
- **Discovery is O(reachable bytes) on one core.** Its synchronous
  signature is what a parallel discovery would change, and
  `SourceFile`'s constructor-computed hash is what M5 would change to
  reuse an unchanged file without rehashing it.
- **`collections.Sort` is a dual-pivot quicksort that is quadratic on
  sorted input** (`packages/collections/sort.pony:49-79`); nothing in
  hefermotor calls it. `sort.MergeSort` is the one sort, and a new
  array whose size or order the checked tree controls is sorted with
  it.
- **What discovery may read**: anything `find_path` reaches, as ponyc
  does: absolute locators, the base directory for the root and
  `builtin`, the `pony_packages` walk to `/` before the search roots (so
  a world-writable ancestor such as `/tmp` can shadow a stdlib package
  for a checkout under it; ponyc parity, #3779 changed only the
  search-list order), the search roots. A checked tree's dependencies
  are trusted as compiling it would trust them (pony-lsp2
  `SEMANTIC_DESIGN.md:146-154`, Red's decision, with its trigger "revisit
  if it runs over source nobody chose to trust"). M5 inherits this and
  must re-apply the trigger; confinement, if ever wanted, is a policy
  inside `Locate` and `LocateTarget`, the only builders of `PackageDir`.
- **A relative `--path`, `PONYPATH` or `PATH` entry is taken under the
  base directory**, the process's working directory for the binary, as
  ponyc resolves a relative search path against its working directory
  (`package.c:363-372, 696-708`). `CheckArgs` joins it before the roots
  are built, so `SearchRoots` holds absolute directories only; a
  `--path` value is split on `:` as ponyc splits it. A base that is not
  absolute, which `Path.cwd()` gives when the working directory cannot
  be read, ends the run with exit 2.
- **An in-repo consumer takes the front door as a `Checker` parameter.**
  `command.Run` does; M5's server will. The umbrella is the only package
  that names `Check`.
