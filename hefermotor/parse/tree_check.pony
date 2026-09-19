use "collections"
use diag = "../diagnostics"

primitive OneRoot
  """
  Element 0 is an `NdModule` spanning every element.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "OneRoot"

primitive EofLast
  """
  The last element is a `TkEof` leaf at the file's size.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "EofLast"

primitive SubtreeSizes
  """
  An interior node's subtree size is one plus its children's, and a
  leaf's is one.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "SubtreeSizes"

primitive OffsetsMonotone
  """
  Offsets never decrease in pre-order.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "OffsetsMonotone"

primitive FirstLeafOffset
  """
  An interior node's offset is its first child's, or the next element's
  when it has no child.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "FirstLeafOffset"

primitive Reprint
  """
  The leaves tile the file: the first starts at 0, each starts where
  the one before it ended, and the last ends at the file's size.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "Reprint"

primitive ErrorLeafOnly
  """
  An `NdError` has leaf children only.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "ErrorLeafOnly"

primitive ErrorNonEmpty
  """
  An `NdError` has at least one child that is not trivia.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "ErrorNonEmpty"

primitive ErrorAtDiagnostic
  """
  An `NdError` starts where a diagnostic starts, or the file's
  `SyntaxLimit` is present.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "ErrorAtDiagnostic"

primitive ErrorParent
  """
  An `NdError`'s parent is the module, a member list, a sequence or a
  `use`, unless a `NestingTooDeep` record starts where it does.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "ErrorParent"

primitive ErrorNoEntity
  """
  No `NdError` holds an entity keyword.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "ErrorNoEntity"

primitive ErrorNoMemberStart
  """
  An `NdError` under a member list holds no field or method start.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "ErrorNoMemberStart"

primitive ErrorNoUseInSection
  """
  An `NdError` under the module that starts before the first entity
  holds no `use`.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "ErrorNoUseInSection"

primitive UsesFirst
  """
  No `NdUse` child of the module follows an `NdClassDef` child: a `use`
  after the first entity is an error item, never a command.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "UsesFirst"

primitive DiagnosticInFile
  """
  Every diagnostic's span ends at or before the file's size, and every
  diagnostic names the tree's file.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "DiagnosticInFile"

primitive DiagnosticsOrdered
  """
  The diagnostics are sorted under `DiagnosticOrder`.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "DiagnosticsOrdered"

primitive ViewsNest
  """
  Every view reached from `use_commands` and `entities`, recursively
  through members, parameters, type parameters, FFI declarations and
  the types `TypeOf` classifies from every declared type and type
  argument, has its span inside its parent view's span, and the views
  a list accessor returns are in source order without overlap. Checked
  only over a tree whose structural invariants hold, since the walk
  relies on them.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "ViewsNest"

primitive PartsUnique
  """
  On the same walk as `ViewsNest`, every accessor whose rule is "the K
  child" found at most one K child.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "PartsUnique"

type TreeInvariant is
  ( OneRoot
  | EofLast
  | SubtreeSizes
  | OffsetsMonotone
  | FirstLeafOffset
  | Reprint
  | ErrorLeafOnly
  | ErrorNonEmpty
  | ErrorAtDiagnostic
  | ErrorParent
  | ErrorNoEntity
  | ErrorNoMemberStart
  | ErrorNoUseInSection
  | UsesFirst
  | DiagnosticInFile
  | DiagnosticsOrdered
  | ViewsNest
  | PartsUnique )
  """
  What every tree this package builds keeps, with the diagnostics
  recorded for it.
  """

class val TreeViolation
  """
  An invariant a tree broke, at an element: the element's index, or 0
  for a fact about the whole tree, or the diagnostic's index for a
  diagnostic row. A test and tool artifact, never a diagnostic;
  `string` is the invariant's name and the index, labelled as an
  element or a diagnostic.
  """
  let invariant: TreeInvariant
  let index: USize

  new val create(invariant': TreeInvariant, index': USize) =>
    invariant = invariant'
    index = index'

  fun string(): String iso^ =>
    (recover String end)
      .> append(invariant.name())
      .> append(
        match invariant
        | DiagnosticInFile | DiagnosticsOrdered => " at diagnostic "
        else
          " at element "
        end)
      .> append(index.string())

primitive TreeCheck
  """
  Checks the invariants every tree this package builds keeps.
  """
  fun apply(tree: SyntaxTree, diagnostics: Array[diag.Diagnostic] val)
    : Array[TreeViolation] val
  =>
    """
    Every invariant `tree` and `diagnostics` break, and where; empty
    when they break none.
    """
    let out = Array[TreeViolation]
    let n = tree.size()
    let file_size = tree.file.content.size()
    _diagnostics(tree, diagnostics, out)
    let diagnostic_rows = out.size()
    if n == 0 then
      out.push(TreeViolation(OneRoot, 0))
      out.push(TreeViolation(EofLast, 0))
      return _frozen(out)
    end
    let starts = _DiagnosticStarts(tree, diagnostics)
    if (tree._size(0) != n) or (not (tree._kind(0) is NdModule)) then
      out.push(TreeViolation(OneRoot, 0))
    end
    if not ((tree._kind(n - 1) is TkEof) and
      (tree._offset(n - 1) == file_size))
    then
      out.push(TreeViolation(EofLast, n - 1))
    end
    // Open interior nodes as (index, end): `end` is the index just past
    // the subtree, and `seen` counts the elements its children's sizes
    // have accounted for.
    let open = Array[(USize, USize)]
    let seen = Array[USize]
    // Stacks of the open NdErrors and of the open interior nodes'
    // kinds.
    let errors = Array[_OpenError]
    let kinds = Array[NodeKind]
    var entity_seen = false
    var previous_offset: USize = 0
    var previous_finish: USize = 0
    var i: USize = 0
    while i < n do
      let offset = tree._offset(i)
      let size = tree._size(i)
      if offset < previous_offset then
        out.push(TreeViolation(OffsetsMonotone, i))
      end
      previous_offset = offset
      // Close every open node whose subtree ended before this element.
      while true do
        try
          (let parent, let stop) = open(open.size() - 1)?
          if stop > i then break end
          if seen(seen.size() - 1)? != (stop - parent - 1) then
            out.push(TreeViolation(SubtreeSizes, parent))
          end
          open.pop()?
          seen.pop()?
          if kinds.pop()? is NdError then
            try _close_error(errors.pop()?, out) else _Unreachable() end
          end
        else
          break
        end
      end
      // `counted == 0`: this element is the parent's first child.
      try
        (let parent, _) = open(open.size() - 1)?
        let counted = seen(seen.size() - 1)?
        if (counted == 0) and (tree._offset(parent) != offset) then
          out.push(TreeViolation(FirstLeafOffset, parent))
        end
        seen(seen.size() - 1)? = counted + size
      end
      match tree._kind(i)
      | let t: TokenKind =>
        if size != 1 then out.push(TreeViolation(SubtreeSizes, i)) end
        if previous_finish != offset then
          out.push(TreeViolation(Reprint, i))
        end
        previous_finish = tree._finish(i)
        try errors(errors.size() - 1)?.leaf(t) end
      | let k: NodeKind =>
        if size == 0 then out.push(TreeViolation(SubtreeSizes, i)) end
        try errors(errors.size() - 1)?.node() end
        if k is NdClassDef then entity_seen = true end
        if (k is NdUse) and entity_seen and
          (try kinds(kinds.size() - 1)? is NdModule else false end)
        then
          out.push(TreeViolation(UsesFirst, i))
        end
        if k is NdError then
          let parent = try kinds(kinds.size() - 1)? else NdModule end
          errors.push(_OpenError(i, parent, entity_seen))
          if not (starts.has(offset) or starts.limit) then
            out.push(TreeViolation(ErrorAtDiagnostic, i))
          end
          match parent
          | NdModule | NdMembers | NdSeq | NdUse => None
          else
            if not starts.nesting_at(offset) then
              out.push(TreeViolation(ErrorParent, i))
            end
          end
        end
        if size <= 1 then
          let next =
            if (i + 1) < n then tree._offset(i + 1) else file_size end
          if offset != next then
            out.push(TreeViolation(FirstLeafOffset, i))
          end
          if k is NdError then
            try _close_error(errors.pop()?, out) else _Unreachable() end
          end
        else
          open.push((i, i + size))
          seen.push(0)
          kinds.push(k)
        end
      end
      i = i + 1
    end
    while true do
      try
        (let parent, let stop) = open.pop()?
        if seen.pop()? != (stop - parent - 1) then
          out.push(TreeViolation(SubtreeSizes, parent))
        end
        if kinds.pop()? is NdError then
          try _close_error(errors.pop()?, out) else _Unreachable() end
        end
      else
        break
      end
    end
    if previous_finish != file_size then
      out.push(TreeViolation(Reprint, n - 1))
    end
    if out.size() == diagnostic_rows then _Views(tree, out) end
    _frozen(out)

  fun _frozen(out: Array[TreeViolation]): Array[TreeViolation] val =>
    let frozen = recover iso Array[TreeViolation](out.size()) end
    for v in out.values() do frozen.push(v) end
    consume frozen

  fun _close_error(e: _OpenError, out: Array[TreeViolation]) =>
    if e.has_node then out.push(TreeViolation(ErrorLeafOnly, e.index)) end
    if not e.has_significant then
      out.push(TreeViolation(ErrorNonEmpty, e.index))
    end
    if e.has_entity then out.push(TreeViolation(ErrorNoEntity, e.index)) end
    if (e.parent is NdMembers) and e.has_member_start then
      out.push(TreeViolation(ErrorNoMemberStart, e.index))
    end
    if (e.parent is NdModule) and (not e.after_entity) and e.has_use then
      out.push(TreeViolation(ErrorNoUseInSection, e.index))
    end

  fun _diagnostics(tree: SyntaxTree, diagnostics: Array[diag.Diagnostic] val,
    out: Array[TreeViolation])
  =>
    let size = tree.file.content.size()
    var previous: (diag.Diagnostic | None) = None
    for (i, d) in diagnostics.pairs() do
      match d.location
      | let s: diag.Span =>
        if (s.finish() > size) or (s.dir != tree.file.dir) or
          (s.name != tree.file.name)
        then
          out.push(TreeViolation(DiagnosticInFile, i))
        end
      | let f: diag.FileOnly =>
        if (f.dir != tree.file.dir) or (f.name != tree.file.name) then
          out.push(TreeViolation(DiagnosticInFile, i))
        end
      | diag.Nowhere => out.push(TreeViolation(DiagnosticInFile, i))
      end
      match previous
      | let p: diag.Diagnostic =>
        if diag.DiagnosticOrder.compare(p, d) is Greater then
          out.push(TreeViolation(DiagnosticsOrdered, i))
        end
      end
      previous = d
    end

primitive _Views
  """
  The walk `ViewsNest` and `PartsUnique` describe: every view built
  from the tree, each accessor called, each span checked against its
  parent view's, and each "the K child" rule checked for uniqueness.
  """
  fun apply(tree: SyntaxTree, out: Array[TreeViolation]) =>
    let root = tree.root().span()
    tree.docstring()
    let commands = tree.use_commands()
    let command_spans = recover iso Array[diag.Span](commands.size()) end
    for u in commands.values() do
      match u
      | let p: PackageUse => command_spans.push(p.span())
      | let d: FfiDecl => command_spans.push(d.span())
      end
    end
    _ordered(tree.root(), consume command_spans, out)
    let entity_spans = recover iso Array[diag.Span] end
    for e in tree.entities().values() do entity_spans.push(e.span()) end
    _ordered(tree.root(), consume entity_spans, out)
    for u in commands.values() do
      match u
      | let p: PackageUse =>
        _in(p.node(), p.span(), root, out)
        _unique(p.node(), _UniqueParts.package_use(), out)
        p.alias()
        p.locator()
        p.guard()
      | let d: FfiDecl =>
        _in(d.node(), d.span(), root, out)
        _unique(d.node(), _UniqueParts.ffi_decl(), out)
        _unique(d._body(), _UniqueParts.ffi_body(), out)
        d.alias()
        d.guard()
        d.symbol()
        d.has_ellipsis()
        d.is_partial()
        let arg_spans = recover iso Array[diag.Span] end
        for a in d.return_type_args().values() do arg_spans.push(a.span()) end
        _ordered(d.node(), consume arg_spans, out)
        _params(d.node(), d.params(), out)
        for a in d.return_type_args().values() do
          _in(d.node(), a.span(), d.span(), out)
          a.annotations()
          match a.type_arg()
          | let t: TypeExpr => _type(t, a.span(), out)
          | let v: ValueArg => _in(v.node(), v.span(), a.span(), out)
          end
        end
        for prm in d.params().values() do _param(prm, d.span(), out) end
      end
    end
    for e in tree.entities().values() do
      _in(e.node(), e.span(), root, out)
      _unique(e.node(), _UniqueParts.entity(), out)
      e.keyword()
      e.annotations()
      e.is_c_api()
      e.cap()
      e.name()
      e.docstring()
      _type_params(e.node(), e.type_params(), out)
      _type_params_of(e.type_params(), e.span(), out)
      match e.provides()
      | let t: TypeExpr => _type(t, e.span(), out)
      end
      let member_spans = recover iso Array[diag.Span] end
      for m in e.members().values() do
        match m
        | let f: FieldDecl => member_spans.push(f.span())
        | let md: MethodDecl => member_spans.push(md.span())
        end
      end
      _ordered(e.node(), consume member_spans, out)
      for m in e.members().values() do
        match m
        | let f: FieldDecl =>
          _in(f.node(), f.span(), e.span(), out)
          _unique(f.node(),
            if _Parts.has(f.node(), TkAssign) then _UniqueParts.field()
            else _UniqueParts.field_without_value()
            end, out)
          f.keyword()
          f.name()
          f.initialiser()
          f.docstring()
          match f.declared_type()
          | let t: TypeExpr => _type(t, f.span(), out)
          end
        | let md: MethodDecl =>
          _in(md.node(), md.span(), e.span(), out)
          _unique(md.node(), _UniqueParts.method(), out)
          md.keyword()
          md.annotations()
          md.cap()
          md.name()
          md.has_ellipsis()
          md.is_partial()
          md.docstring()
          md.body()
          _type_params(md.node(), md.type_params(), out)
          _params(md.node(), md.params(), out)
          _type_params_of(md.type_params(), md.span(), out)
          for prm in md.params().values() do _param(prm, md.span(), out) end
          match md.return_type()
          | let t: TypeExpr => _type(t, md.span(), out)
          end
        end
      end
    end

  fun _params(node: Node, ps: Array[ParamDecl] val,
    out: Array[TreeViolation])
  =>
    let spans = recover iso Array[diag.Span](ps.size()) end
    for p in ps.values() do spans.push(p.span()) end
    _ordered(node, consume spans, out)

  fun _type_params(node: Node, tps: Array[TypeParamDecl] val,
    out: Array[TreeViolation])
  =>
    let spans = recover iso Array[diag.Span](tps.size()) end
    for tp in tps.values() do spans.push(tp.span()) end
    _ordered(node, consume spans, out)

  fun _param(p: ParamDecl, parent: diag.Span, out: Array[TreeViolation]) =>
    _in(p.node(), p.span(), parent, out)
    _unique(p.node(), _UniqueParts.param(), out)
    p.name()
    p.annotations()
    p.default_value()
    match p.declared_type()
    | let t: TypeExpr => _type(t, p.span(), out)
    end

  fun _type_param(tp: TypeParamDecl, parent: diag.Span,
    work: Array[(TypeExpr, diag.Span)], out: Array[TreeViolation])
  =>
    """
    The type parameter's own parts; its types go onto `work`.
    """
    _in(tp.node(), tp.span(), parent, out)
    _unique(tp.node(), _UniqueParts.type_param(), out)
    tp.name()
    match tp.constraint()
    | let t: TypeExpr => work.push((t, tp.span()))
    end
    match tp.default()
    | let t: TypeExpr => work.push((t, tp.span()))
    | let v: ValueArg => _in(v.node(), v.span(), tp.span(), out)
    end

  fun _type_params_of(tps: Array[TypeParamDecl] val, parent: diag.Span,
    out: Array[TreeViolation])
  =>
    """
    The type parameters of an item, each with its types walked.
    """
    let work = Array[(TypeExpr, diag.Span)]
    for tp in tps.values() do _type_param(tp, parent, work, out) end
    while true do
      (let here, let above) = try work.pop()? else break end
      _one_type(here, above, work, out)
    end

  fun _type(t: TypeExpr, parent: diag.Span, out: Array[TreeViolation]) =>
    """
    The type views under `t`, walked with an explicit stack: a type
    nests as deep as the grammar's depth limit, and the walk's frames
    are not budgeted in `StackNeed`.
    """
    let work = Array[(TypeExpr, diag.Span)]
    work.push((t, parent))
    while true do
      (let here, let above) = try work.pop()? else break end
      _one_type(here, above, work, out)
    end

  fun _one_type(t: TypeExpr, parent: diag.Span,
    work: Array[(TypeExpr, diag.Span)], out: Array[TreeViolation])
  =>
    match \exhaustive\ t
    | let n: NominalType =>
      _in(n.node(), n.span(), parent, out)
      _unique(n.node(),
        if _Parts.has(n.node(), TkDot) then _UniqueParts.nominal()
        else _UniqueParts.nominal_without_package()
        end, out)
      n.package()
      n.name()
      n.cap()
      n.ephemeral()
      let arg_spans = recover iso Array[diag.Span] end
      for a in n.type_args().values() do
        match a
        | let m: TypeExpr => arg_spans.push(m.span())
        | let v: ValueArg => arg_spans.push(v.span())
        end
      end
      _ordered(n.node(), consume arg_spans, out)
      for a in n.type_args().values() do
        match a
        | let m: TypeExpr => work.push((m, n.span()))
        | let v: ValueArg => _in(v.node(), v.span(), n.span(), out)
        end
      end
    | let u: UnionType =>
      _in(u.node(), u.span(), parent, out)
      _ordered(u.node(), _type_spans(u.members()), out)
      for m in u.members().values() do work.push((m, u.span())) end
    | let i: IsectType =>
      _in(i.node(), i.span(), parent, out)
      _ordered(i.node(), _type_spans(i.members()), out)
      for m in i.members().values() do work.push((m, i.span())) end
    | let tu: TupleType =>
      _in(tu.node(), tu.span(), parent, out)
      _ordered(tu.node(), _type_spans(tu.members()), out)
      for m in tu.members().values() do work.push((m, tu.span())) end
    | let v: ViewpointType =>
      _in(v.node(), v.span(), parent, out)
      match v.left()
      | let l: TypeExpr => work.push((l, v.span()))
      end
      match v.right()
      | let r: TypeExpr => work.push((r, v.span()))
      end
    | let l: LambdaType =>
      _in(l.node(), l.span(), parent, out)
      _unique(l.node(), _UniqueParts.lambda(), out)
      l.is_bare()
      l.receiver_cap()
      l.name()
      l.is_partial()
      l.cap()
      l.ephemeral()
      _type_params(l.node(), l.type_params(), out)
      _ordered(l.node(), _type_spans(l.param_types()), out)
      for tp in l.type_params().values() do
        _type_param(tp, l.span(), work, out)
      end
      for m in l.param_types().values() do work.push((m, l.span())) end
      match l.return_type()
      | let r: TypeExpr => work.push((r, l.span()))
      end
    | let th: ThisType => _in(th.node(), th.span(), parent, out)
    | let c: CapType =>
      _in(c.node(), c.span(), parent, out)
      c.cap()
    end

  fun _in(node: Node, span: diag.Span, parent: diag.Span,
    out: Array[TreeViolation])
  =>
    """
    `span` lies inside `parent`, or `ViewsNest` is reported at `node`.
    """
    if (span.start < parent.start) or (span.finish() > parent.finish()) then
      out.push(TreeViolation(ViewsNest, node._index()))
    end

  fun _ordered(node: Node, spans: Array[diag.Span] val,
    out: Array[TreeViolation])
  =>
    """
    Each span starts at or after the one before it ends, or `ViewsNest`
    is reported at `node`.
    """
    var i: USize = 1
    while i < spans.size() do
      try
        if spans(i)?.start < spans(i - 1)?.finish() then
          out.push(TreeViolation(ViewsNest, node._index()))
          return
        end
      else
        _Unreachable()
      end
      i = i + 1
    end

  fun _type_spans(ts: Array[TypeExpr] val): Array[diag.Span] val =>
    let out = recover iso Array[diag.Span](ts.size()) end
    for t in ts.values() do out.push(t.span()) end
    consume out

  fun _unique(node: Node, parts: Array[Array[SyntaxKind] val] val,
    out: Array[TreeViolation])
  =>
    """
    `PartsUnique` is reported at `node` when any set in `parts` matches
    more than one child.
    """
    let counts = Array[USize].init(0, parts.size())
    for c in node.children() do
      let k = c.kind()
      for (i, kinds) in parts.pairs() do
        for kind in kinds.values() do
          if k is kind then
            try counts(i)? = counts(i)? + 1 else _Unreachable() end
          end
        end
      end
    end
    for n in counts.values() do
      if n > 1 then
        out.push(TreeViolation(PartsUnique, node._index()))
        return
      end
    end

class _OpenError
  """
  What an open `NdError`'s children have shown so far.
  """
  let index: USize
  let parent: NodeKind
  let after_entity: Bool
  var has_node: Bool = false
  var has_significant: Bool = false
  var has_entity: Bool = false
  var has_member_start: Bool = false
  var has_use: Bool = false

  new create(index': USize, parent': NodeKind, after_entity': Bool) =>
    index = index'
    parent = parent'
    after_entity = after_entity'

  fun ref node() =>
    has_node = true

  fun ref leaf(t: TokenKind) =>
    match t
    | TkWhitespace | TkLineComment | TkNestedComment => None
    | TkType | TkInterface | TkTrait | TkPrimitive | TkStruct | TkClass
    | TkActor =>
      has_significant = true
      has_entity = true
    | TkVar | TkLet | TkEmbed | TkFun | TkBe | TkNew =>
      has_significant = true
      has_member_start = true
    | TkUse =>
      has_significant = true
      has_use = true
    else
      has_significant = true
    end

class _DiagnosticStarts
  """
  Where the diagnostics start: the offsets of every span, whether the
  file's `SyntaxLimit` is present, and the offsets of the
  `NestingTooDeep` records.
  """
  let limit: Bool
  let _starts: Set[USize]
  let _nesting: Set[USize]

  new create(tree: SyntaxTree, diagnostics: Array[diag.Diagnostic] val) =>
    var limit' = false
    _starts = Set[USize]
    _nesting = Set[USize]
    for d in diagnostics.values() do
      match d.location
      | let s: diag.Span =>
        _starts.set(s.start)
        match d.cause
        | let _: NestingTooDeep => _nesting.set(s.start)
        end
      | let _: diag.FileOnly =>
        match d.cause
        | let _: SyntaxLimit => limit' = true
        end
      end
    end
    limit = limit'

  fun has(offset: USize): Bool =>
    _starts.contains(offset)

  fun nesting_at(offset: USize): Bool =>
    _nesting.contains(offset)
