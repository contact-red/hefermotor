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
  | DiagnosticsOrdered )
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
