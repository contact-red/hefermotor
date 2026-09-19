"""
# hefermotor/parse

The parser. `Parse` has two entry points: `uses_only` reads a file's
`use` section and returns its declarations, which discovery reads to
build the package graph, and `apply` runs the grammar over the whole
file and is the only reporter of parse diagnostics.
"""
use diag = "../diagnostics"
use sort = "../sort"
use source = "../source"

class val UseDecl is Equatable[UseDecl]
  """
  One package or directive `use` as written: the decoded locator including
  any scheme prefix, the alias if any, the span of the guard expression if
  one follows `if`, the span of the whole declaration from the `use`
  keyword through the guard or the literal, and the span of the locator's
  string literal including its quotes. FFI declarations (`use @name`) are
  not `UseDecl`s. `eq` is over all five fields.
  """
  let locator: String
  let alias: (String | None)
  let guard: (diag.Span | None)
  let span: diag.Span
  let locator_span: diag.Span

  new val create(
    locator': String,
    alias': (String | None),
    guard': (diag.Span | None),
    span': diag.Span,
    locator_span': diag.Span)
  =>
    locator = locator'
    alias = alias'
    guard = guard'
    span = span'
    locator_span = locator_span'

  fun eq(that: UseDecl box): Bool =>
    (locator == that.locator) and _same_alias(that) and _same_guard(that)
      and (span == that.span) and (locator_span == that.locator_span)

  fun _same_alias(that: UseDecl box): Bool =>
    match (alias, that.alias)
    | (None, None) => true
    | (let a: String, let b: String) => a == b
    else
      false
    end

  fun _same_guard(that: UseDecl box): Bool =>
    match (guard, that.guard)
    | (None, None) => true
    | (let a: diag.Span, let b: diag.Span) => a == b
    else
      false
    end

class val ParsedFile
  """
  One file after parsing: the source it came from, its `use` section's
  declarations, and what the parser reported, sorted under
  `DiagnosticOrder`.
  """
  let file: source.SourceFile
  let uses: Array[UseDecl] val
  let diagnostics: Array[diag.Diagnostic] val

  new val create(
    file': source.SourceFile,
    uses': Array[UseDecl] val,
    diagnostics': Array[diag.Diagnostic] val)
  =>
    file = file'
    uses = uses'
    diagnostics = recover val
      sort.MergeSort[diag.Diagnostic](diagnostics'.clone())
    end

primitive StackNeed
  """
  The scheduler thread stack, in bytes, within which the parser refuses
  a region at its depth limit rather than overflows, whatever the
  nesting: 3 MiB.
  """
  fun apply(): USize => 3 * 1024 * 1024

primitive Parse
  """
  `uses_only` reads the module's `use` section, stops at the first type
  declaration, and reports nothing. `apply` runs the grammar over the
  whole file and is the only reporter of parse diagnostics. For every file,
  `Parse(file).uses` and `Parse.uses_only(file)` are equal element by
  element.

  What `uses` holds, for any file: every `use` the module's `use` section
  accepts, in source order, duplicates kept; `locator` is the literal's
  content with its escapes decoded; `span` runs from the `use` keyword
  through the end of the guard, or of the string literal when there is
  no guard; `locator_span` covers the string literal including its
  quotes; `guard` is the guard expression's span, or `None`; `use @`
  declarations are excluded; a `use` after the first type declaration is
  not in `uses`; well-formed input produces no diagnostics.
  """
  fun uses_only(file: source.SourceFile): Array[UseDecl] val =>
    _UseScanner(file).run()

  fun apply(file: source.SourceFile): ParsedFile =>
    (_, let diagnostics) = _ParseModule(file)
    ParsedFile(file, uses_only(file), diagnostics)

  fun tree(file: source.SourceFile): SyntaxTree =>
    """
    The tree the grammar builds over the whole file.
    """
    _ParseModule(file)._1
