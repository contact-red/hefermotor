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
- **A `use` after a type definition is a syntax error, and the members
  after it are kept.** ponyc's module rule takes the package docstring,
  then `use` commands, then type definitions (`parser.c:1310-1319`), and
  a `use` after the first entity fails its `class_def` restart check at
  the keyword, after which ponyc skips to the next entity keyword and
  reads on. hefermotor reports at the same keyword and makes the
  command an error item of the enclosing entity's member list, never a
  command, so the members after it are still that entity's (`class
  A\nuse "b"\n  fun g() => 1` keeps `g` as A's member); `TreeCheck`'s
  `UsesFirst` pins that no command follows an entity.
- **Junk between `use` commands is reported and skipped on both
  sides.** Not a divergence, recorded here because the M1 design
  listed it as one: ponyc's `use` restart check reports the junk and
  skips to the next `use` or entity keyword (`parserapi.c:562-611`),
  and its `SEQ(use)` reads the command after it; hefermotor reports
  the junk at the same position, wraps it as the use section's error
  item, and reads on, so `use "a"\njunk\nuse "b"\nclass C` has two
  commands on both sides. The message text differs as the message
  entry says.
- **A field after a method is reported and parsed.** ponyc's `members`
  is fields then methods (`parser.c:1211-1216`). In an entity a field
  after a method fails the `class_def` restart check at its keyword;
  ponyc skips the rest of the entity and reads the next one, and
  hefermotor reports `expected method` at the same keyword and parses
  the field. In an object literal there is no restart check: ponyc's
  `members` stops at the field and the `TERMINATE` for `end` fails
  there, so ponyc reports the literal unterminated at `object` with
  the keyword as its `Info:` frame, where hefermotor reports the
  keyword and finds the `end`; the same family as "Junk inside a
  closed construct", and the fixture of that shape carries `KNOWN_GAP
  positions`.
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

- **The per-file budget.** 500 kept `parse/expected` and
  `parse/unterminated` records per file, then one `parse/limit` at the
  file; ponyc caps nothing. ponyc reports at most one parser error per
  restart region (`parser.c:1301-1302` and `:1221-1222`, the `use` and
  `class_def` `RESTART` sets), while hefermotor resyncs at members and
  statements too and can report at every one, so these two families are
  the ones it produces beyond ponyc's count. `parse/nesting` and `parse/lex` are
  never dropped.
- **Junk inside a closed construct is reported as the junk.** ponyc's
  sequence rule stops at a token that starts no expression, so the
  construct's `TERMINATE` fails there and ponyc reports the construct
  unterminated at its opener (`if true then 1 : 2 end` gives
  `unterminated if expression` at the `if`, with an `Info:` frame at
  the `:`). hefermotor's statement rule reports the `:`, the sequence
  rule takes it as an error node, and the `end` closes the `if`, so the
  report is one `parse/expected` at the junk and nothing at the `if`.
  The fixtures of this shape carry `KNOWN_GAP positions`.
- **A closer the parser does not reach is reported at the opener,
  beside whatever was reported inside.** `close` records
  `parse/unterminated` over the construct's opening token whenever the
  token in the closer's place is not the closer, as ponyc's `TERMINATE`
  does (`parserapi.c:91-99`, the primary error on the construct's own
  node), and with `before` where ponyc's `Info:` frame points. That
  covers a closer the source lacks and a closer the source has that
  the rules inside stopped short of: `{(,) => 1 }` has its `}`, but
  the parameter list fails at the `,`, nothing inside a lambda's header
  resynchronises, and `close` finds the `,`. ponyc reports one error
  per restart region and stops, so where that one error is inside the
  construct (`foo(1,` at the end of the file gives `expected argument
  after ,` only; `{(,) => 1 }` gives `expected ) after (` only),
  hefermotor also records the opener, and its sorted list starts at
  the opener where ponyc's line is the inner one. A third shape is a
  required token that itself opens what `close` closes: an FFI call
  `@S` at the end of a method body and the file gives ponyc `expected
  ( after S` only, and hefermotor that beside `unterminated ffi
  arguments` at the `@`, for an argument list that never began; every
  `close` site has the shape, since
  ponyc's rule macros return on the first failure and its `TERMINATE`
  never runs. T2 of Discussion #13 is the choice to make the opener's
  record conditional instead; its cost there lists the end-of-file
  shapes, and the closer-present and never-opened shapes belong on the
  same list.
- **Every refused token is reported; ponyc's parser stops at the
  first.** hefermotor records one `parse/lex` per refused token and
  scans on, where ponyc's parser returns at a `TK_LEX_ERROR`
  (`parserapi.c:428-429`, `:513-514`), so a byte-order mark is three
  records (`1:1`, `1:2`, `1:3`) where ponyc prints one at `1:1` and
  stops. A refused escape inside a literal is reported and carried on
  from on both sides. Every position ponyc reports is among
  hefermotor's, except after a `\` followed by a newline inside a
  literal: ponyc's `consume_chars` (`lexer.c:405-421`) counts a newline
  only as the first byte consumed, and `escape` consumes the `\` and
  the newline together, so every later line ponyc reports is one
  short. Messages are ponyc's lexer texts, with a source byte rendered
  as itself when printable ASCII and as `\xNN` otherwise where ponyc
  prints the byte raw (`Unrecognized character: \xef`). A refused
  numeric literal covers the bytes ponyc's lexer consumed before
  refusing it (`1__2` is a refused `1_` then an identifier `_2`),
  since ponyc's parser never sees what its lexer would scan next. A
  `\` as the source's last byte, inside a literal, is two records
  here, the escape and the unterminated literal; a ponyc built with
  assertions aborts on it (`consume_chars`), and one without reads
  past its buffer.
- **The unicode-range message names the escape only.** ponyc's
  `Escape sequence "%8s" exceeds unicode range (0x10FFFF)`
  (`lexer.c:796-797`) formats the rest of the source from the escape,
  so its message runs to the end of the file; hefermotor's names the
  eight-byte escape: `Escape sequence "\U110000" exceeds unicode range
  (0x10FFFF)`. The position agrees.
- **An expectation's message names the token found.** hefermotor
  renders "syntax error: expected WHAT, found TOKEN"; ponyc renders
  "syntax error: expected WHAT after LAST" (`parserapi.c:88`), and
  positions an expectation at the end of the file at the last token
  (`parserapi.c:33-37`), as hefermotor does. Both are positioned at the
  found token, so hefermotor names the token at the position it points
  to, except at the end of the file, where it names the end and points
  at the last token. WHAT is ponyc's rule description at every site,
  and the caller's description where ponyc's not-found propagation
  reports that (`parserapi.c:359-368`). At a resynchronisation site where ponyc's
  message is a restart check ("unexpected token X after ...",
  `parserapi.c:604`), WHAT names what hefermotor's rule expected:
  "field or method", or the module's "use command or type, interface,
  trait, primitive, class or actor definition". The "syntax error: "
  prefix is ponyc's for every parser error and no lexer error.

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
