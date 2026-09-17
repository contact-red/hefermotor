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
| Diagnostic ordering | one sort in `_ReadySet.report()` under `DiagnosticOrder`, a total order over what a renderer sees; the stdlib `Sort` is quadratic on sorted input and is replaced at M3's first heavy emitter |
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
identity inside a tree. The stdlib `Sort` is replaced at the first
heavy emitter. The actor-per-task versus bounded-pool question is
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
- **The POSIX assumption lives in four places**: the default search roots
  (`/usr/local/lib`, `/opt/local/lib`), `MemoryFileSystem`'s lexical path
  normalisation, the port of `is_path_absolute` and `is_path_relative`
  (whose Windows branches at `package.c:1721, 1742, 1754` are not ported),
  and the stdlib slot derived from the `ponyc` on `PATH`.
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
  sorted input** (`packages/collections/sort.pony:49-79`), and
  `_ReadySet.report()` sorts diagnostics that arrive nearly sorted. The
  bound is fine at M0's volumes; revisit at M3 when a corpus run can
  produce enough diagnostics to matter.
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
