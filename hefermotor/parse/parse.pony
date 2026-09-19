"""
# hefermotor/parse

The parser. `Parse` has two entry points: `uses_only` reads a file's
`use` section and returns its declarations, which discovery reads to
build the package graph, and `apply` runs the grammar over the whole
file into a `ParsedFile`, the tree and the diagnostics, and is the only
reporter of parse diagnostics. For every file, `apply(file).uses()`
and `uses_only(file)` are equal.
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
  One file after parsing: its tree, and what the parser reported,
  sorted under `DiagnosticOrder`. `file` is the tree's source; `uses`
  is the declarations of the tree's `use` section.
  """
  let tree: SyntaxTree
  let diagnostics: Array[diag.Diagnostic] val

  new val create(tree': SyntaxTree, diagnostics': Array[diag.Diagnostic] val)
  =>
    tree = tree'
    diagnostics = recover val
      sort.MergeSort[diag.Diagnostic](diagnostics'.clone())
    end

  fun file(): source.SourceFile =>
    """
    The source the tree covers.
    """
    tree.file

  fun uses(): Array[UseDecl] val =>
    """
    The declarations of the tree's `use` section, as `Parse.uses_only`
    gives them for the same file.
    """
    _UsesOf(tree)

primitive _UsesOf
  """
  The `UseDecl`s of a tree's `use` section: one per `PackageUse` in
  `use_commands` whose locator is present, with the locator decoded by
  `StringLiteralValue`, the alias's text, the guard's span, the
  command's span from the keyword through the guard or the literal,
  and the literal's span. A command that fails before its literal has
  no locator (the tokens after the fault are its error item) and an
  FFI declaration is not a `PackageUse`, so neither yields one; a
  command that fails in its guard yields one with what the guard's
  rule read.
  """
  fun apply(tree: SyntaxTree): Array[UseDecl] val =>
    let out = recover iso Array[UseDecl] end
    for command in tree.use_commands().values() do
      match command
      | let u: PackageUse =>
        match u.locator()
        | let l: Node => out.push(_one(tree.file, u, l))
        end
      end
    end
    consume out

  fun _one(file: source.SourceFile, u: PackageUse, literal: Node)
    : UseDecl
  =>
    let alias =
      match u.alias()
      | let a: Node => a.text()
      | None => None
      end
    let guard = u.guard()
    let guard_span =
      match guard
      | let g: Node => g.span()
      | None => None
      end
    let finish =
      match guard
      | let g: Node => g.finish()
      | None => literal.finish()
      end
    let start = u.node().offset()
    UseDecl(StringLiteralValue.of(literal), alias, guard_span,
      diag.Span(file.dir, file.name, start, finish - start), literal.span())

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
  `Parse(file).uses()` and `Parse.uses_only(file)` are equal element by
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
    _uses_only(file, _TokenStream(file.content))

  fun _uses_only(file: source.SourceFile, stream: _TokenStream ref)
    : Array[UseDecl] val
  =>
    """
    The prefix rule over `stream`, which is scanned only as far as the
    section extends: to the first entity keyword, or the end. The
    parser's records are discarded.
    """
    let p = _Parser(file, stream)
    _ModulePrefix(p)
    p.stop()
    (let prefix, _) = p.build()
    _UsesOf(prefix)

  fun apply(file: source.SourceFile): ParsedFile =>
    let p = _Parser(file, _TokenStream(file.content))
    _Module(p)
    (let whole, let diagnostics) = p.build()
    ParsedFile(whole, diagnostics)

  fun tree(file: source.SourceFile): SyntaxTree =>
    """
    The tree the grammar builds over the whole file.
    """
    apply(file).tree
