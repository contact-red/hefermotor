# Where hefermotor and ponyc differ

hefermotor implements Pony as ponyc defines it. Where the two disagree, or
where ponyc's behaviour in a corner is not what its documentation says, the
fact is recorded here with the ponyc source it rests on. A fact marked
"pinned in pony-lsp2" was verified against ponyc 0.69.1 by a probe in that
project; re-probe it against the current ponyc before relying on it here.
Every other entry cites ponyc at commit `6a0bfa80b`.

## Recorded in this project

- **`builtin/` in the base directory shadows every search root.** ponyc
  locates the compile target and `builtin` with no using package
  (`src/libponyc/pkg/package.c:462-464`), tries the locator relative to the
  current directory first (472), skips the `pony_packages` walks (486) and
  then tries the search paths (507-515). hefermotor's `LocateTarget` does
  the same relative to its explicit base directory. Parity, recorded
  because it is surprising: `cd` into a directory holding a stray
  `builtin/` and every verdict changes, on both sides.
- **The `pony_packages` walk starts at the parent.** `try_package_path`
  resolves `base/..` before its first attempt (`package.c:417-440`), so
  `<package>/pony_packages/<locator>` is never tried and
  `<parent>/pony_packages/<locator>` is the first candidate. A port that
  starts at the package itself accepts a program ponyc rejects.
- **A `builtin` that is located but cannot be loaded stops the run.**
  ponyc rejects it with exit 255 as it rejects any bad input. hefermotor
  reports `BuiltinNotLoaded` and exits 2, because the user fixes `--path`,
  not their code, and the differential harness against ponyc (task 10 in
  discussion #1) aborts rather than scoring the case.
- **`runtimestats` and `runtimestatsmessages` come from `-D`.** In ponyc
  they are constants of the compiler's own build
  (`src/libponyc/pkg/platformfuns.c:116-136`) and are matched before user
  flags (`src/libponyc/pkg/ifdef.c:152-158`), so `-Druntimestats` does not
  set them. hefermotor has no compiler build to read and evaluates both
  names from the defines it is given.
- **A file or a denied directory at a candidate does not stop a locate.**
  `try_path` returns NULL for a file, a realpath failure and a stat failure
  alike (`package.c:364-390`), and `find_path` continues to the next
  candidate. A locator that reaches a file at one candidate and a directory
  at a later one resolves to the directory; "must refer to a directory" is
  only added to the final error (1077-1079). hefermotor does the same.
- **An unresolvable `use` is reported at the `use` keyword.** ponyc's
  "can't load package" error is positioned at the `TK_USE` node
  (`src/libponyc/pass/scope.c:87`), whose position is the keyword
  (`src/libponyc/ast/parser.c:1303`). The guard-not-allowed and
  alias-not-allowed errors are positioned at the alias node
  (`src/libponyc/pkg/use.c:126-136`); hefermotor reports both over the
  whole `use` declaration, starting at the keyword. An unknown scheme is
  reported at the locator string on both sides (`use.c:106-108`). ponyc
  emits "couldn't locate this path" as a file-level error with no
  position (`package.c:1075`) and then "can't load package" at the `use`;
  hefermotor emits one diagnostic, `CantLoadPackage`, over the whole
  `use` declaration.
- **A `use` after a type definition is a syntax error.** ponyc's module
  rule takes the package docstring, then `use` commands, then type
  definitions (`parser.c:1310-1319`). The parser quarried from pony-lsp2
  accepts a `use` after a type silently (`_Module` in its `grammar.pony`);
  M1 changes that rule.
- **Package display names can differ from ponyc's.** ponyc names a package
  by the locator that first reached it and loads dependencies depth-first
  from the scope pass (`scope.c:364-366`); hefermotor discovers
  breadth-first, so when two locators reach one directory the first-reach
  name can differ. The name is display only; nothing identifies a package
  by it.
- **An unreadable file fails its package, and every `use` of a failed
  directory is reported.** ponyc reports `can't open file <path>`
  (`source.c:17`, `package.c:150-156`), reads the other files (310-314),
  then fails the package load (1186-1192), so a dependent's `use` gets
  "can't load package". ponyc registers a package before any failure
  that follows locating its directory, so a second `use` of a directory
  that failed for any reason (an unreadable file, no source files) gets
  the registered package back with no second error (1155-1157).
  hefermotor reports the file, fails the package and reports each `use`
  of a failed directory with the reason.
- **Grammar recursion is bounded.** ponyc's parser is recursive descent
  (`src/libponyc/ast/parserapi.h:16-19`) with no depth check in
  `parserapi.c`, so a source nested deeply enough overflows its stack.
  hefermotor
  refuses a region past 2500 descents of the grammar with a diagnostic
  at the token that would have opened it, skips to the nearest closing
  token, item or member start, and parses on; the limit needs
  `parse.StackNeed()` (3 MiB) of scheduler thread stack, below which
  `hefermotor check` exits 2 before reading anything.

## Pinned in pony-lsp2

Each of these was pinned by a probe against ponyc 0.69.1 in pony-lsp2 and
is carried here as a starting point for M2. Re-probe before relying on it.

- **Case folding.** When ponyc checks two names for a clash it folds
  each first (`name_without_case`, `src/libponyc/ast/symtab.c:36-51`):
  a name whose first letter after an optional `$` and an optional `_` is
  uppercase (`is_name_type`, `src/libponyc/ast/id.c:187-196`) is
  compared in upper case, any other name in lower case; underscores are
  kept. A checker that folds the same way finds every clash ponyc finds.
- **Scope shapes.** Every grammar rule in ponyc's `SCOPE()` set opens a
  scope; call arguments, array elements, conditions and iterators are
  scope-free `rawseq` positions; a `with`-element initialiser's local
  ends where the sugar moves it, beside the `with`; two elements'
  initialisers declaring one name are not compared.
- **Which declaration is reported first after desugaring.** An object
  literal's fields and a lambda's captures are prepended, methods and
  the synthesized `create` are appended, `with` prepends one local per
  element with each element's ids in written order, and the first insert
  of a folded name wins.
- **Parameter-name legality.** `check_id_param` is reachable only through
  `check_method`, so an FFI declaration's parameters are unchecked. For a
  lambda, ponyc substitutes a `_` parameter from an antecedent type before
  the check runs, so a typed `_` with no antecedent is rejected.
- **Import clash.** The scope chain is earlier opens, the package's own
  entities, then importable `builtin` names; ponyc stops the compile at the
  first clashing `use`.
- **Invalid provides.** Nominal and intersection rules apply to entities and
  object literals; qualified names and enclosing type parameters in a
  provides clause were accepted without a check by pony-lsp2's checker.
- **Diagnostic staging.** ponyc's traversal of a pass can stop at its
  first error; a checker that reports every error a pass would find
  reports more than ponyc does on the same input.
- **Shapes ponyc rejects that pony-lsp2's checker accepted.** A repeated
  import of one directory; a typed `_` lambda parameter with no antecedent;
  an alias in a provides clause resolving to a class; a type parameter
  shadowing a later entity; one `with` name declared in two elements'
  initialisers.
- **CRLF source lines.** ponyc echoes the `\r` of a CRLF source line in its
  error rendering; pony-lsp2's renderer stripped it; that project had
  not decided whether to keep the `\r`.
