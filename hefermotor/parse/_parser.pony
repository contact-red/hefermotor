use diag = "../diagnostics"
use source = "../source"

primitive _MaxNesting
  """
  The deepest grammar recursion the parser will enter.

  The grammar recurses on the machine stack, a few frames per descent.
  What is counted is the recursion, not source nesting: the common
  expression shapes descend twice per source level, so parentheses meet
  the limit at about half this number. Refusing here keeps the refusal
  a diagnostic instead of a crash.
  """
  fun apply(): USize => 2500

class _Chain
  """
  One rule's pending chain wrappers: the mark they share, and the
  wrapper elements `close_chain` will lay down there.
  """
  let index: USize
  let from: USize
  embed wraps: Array[SyntaxElement] = Array[SyntaxElement]

  new create(index': USize, from': USize) =>
    index = index'
    from = from'

  fun ref record(k: NodeKind, size: USize) =>
    // The subtree covers the wrappers recorded before this one plus
    // itself, on top of the elements parsed since the mark.
    wraps.push((k, from.u32(), ((size - index) + wraps.size() + 1).u32()))

type _Opener is (USize, USize)
  """
  A construct's opening token, its byte offset and width, for `close`
  to position an unterminated record over. A tuple rather than an
  object because every call, group and control structure takes one.
  """

class _Parser
  """
  A cursor over the significant tokens of a source, and a builder for the
  tree that covers all of them, trivia included.

  No method on this class fails. Where the grammar expects something that is
  not there, `error_and_recover` records a diagnostic, wraps what it skipped
  in an `NdError` node, and parsing continues from a point the caller names.
  That is the whole difference from ponyc's parser, which returns no tree at
  all once an error has been reported.

  Trivia never reach the grammar. `start` flushes any pending whitespace and
  comments into the enclosing node before opening a new one, so trivia
  between two items belong to what contains them rather than to whichever
  item happens to follow.
  """
  let _file: source.SourceFile
  let _stream: _TokenStream ref
  var _elems: Array[SyntaxElement] iso = recover Array[SyntaxElement] end
    """
    Isolated rather than embedded so that `build` can hand it over with a
    destructive read instead of copying it. Every element is sendable -- a
    union of primitives and two integers -- so the array is still built with
    ordinary pushes.
    """
  embed _records: _Records
  embed _open: Array[USize] = Array[USize]
  var _last_significant: USize = 0
    """
    The byte offset of the last significant token emitted, where an
    expectation at the end of the file is positioned.
    """
  var _index: USize = 0
    """
    Index into the token stream, of the next unconsumed token.
    """
  var _offset: USize = 0
    """
    Byte offset of `_index`.
    """
  var _eof_emitted: Bool = false
  var _depth: USize = 0
    """
    Grammar recursion depth, counted by `descend`/`ascend`. Counted
    explicitly because the open-node stack cannot measure it: most
    rules wrap retroactively from a checkpoint and open nothing while
    they descend, and the machine stack grows regardless.
    """
  let _expr_start: Array[TokenKind] val = _TokenSets.expr_start()
    """
    The entry sets tested at every call, argument list and array are
    built once here rather than once per test.
    """
  let _case_pattern_start: Array[TokenKind] val =
    _TokenSets.case_pattern_start()
  let _type_start: Array[TokenKind] val = _TokenSets.type_start()

  new create(file: source.SourceFile, stream: _TokenStream ref) =>
    """
    A parser over `stream`, which must be the tokens of `file`'s
    content and is scanned only as far as the grammar reads.
    """
    _file = file
    _stream = stream
    _records = _Records(file)

  fun tag _is_trivia(k: TokenKind): Bool =>
    match k
    | TkWhitespace | TkLineComment | TkNestedComment => true
    else
      false
    end

  fun ref _peek(): (TokenKind, USize, USize) =>
    """
    The next significant token at or after the cursor: its kind, its
    index, and the byte offset it starts at. `TkEof` when there is none.
    """
    var i = _index
    var byte = _offset
    while true do
      (let k, let w) = _stream.token(i)
      if not _is_trivia(k) then return (k, i, byte) end
      byte = byte + w.usize()
      i = i + 1
    end
    (TkEof, i, byte)

  fun ref descend(): Bool =>
    """
    Enter one level of grammar recursion. Returns whether the limit is
    now exceeded.
    """
    _depth = _depth + 1
    _depth > _MaxNesting()

  fun ref too_deep(what: String val): Bool =>
    """
    Enter one level of grammar recursion; at the limit, refuse the
    region with a diagnostic naming `what` over the token here (at the
    end of the file, at the last significant token as `expected` is),
    resynchronise to the nearest closing token, item or method start,
    and leave the depth balanced. Returns whether it refused, and a
    guarded rule returns without parsing further when it did — its
    other exits still `ascend`.
    """
    if descend() then
      (let found, let index, let byte) = _peek()
      if found is TkEof then
        _records.record(NestingTooDeep(what, _MaxNesting()),
          _last_significant, 0)
      else
        _records.record(NestingTooDeep(what, _MaxNesting()), byte,
          _stream.token(index)._2.usize())
      end
      skip_to(_TokenSets.nesting_close())
      ascend()
      true
    else
      false
    end

  fun ref ascend() =>
    """
    Leave the level `descend` entered. Every `descend` is paired with one
    `ascend`, on the refusal path too.
    """
    _depth = _depth - 1

  fun ref current(): TokenKind =>
    """
    The kind of the next significant token, without consuming anything.
    """
    _peek()._1

  fun ref at(k: TokenKind): Bool =>
    current() is k

  fun ref at_any(kinds: Array[TokenKind] box): Bool =>
    let c = current()
    for k in kinds.values() do
      if c is k then return true end
    end
    false

  fun ref eof(): Bool =>
    current() is TkEof

  fun ref at_expr_start(): Bool =>
    """
    Whether the next significant token can start an expression.
    """
    at_any(_expr_start)

  fun ref at_case_pattern_start(): Bool =>
    """
    Whether the next significant token can start a case pattern.
    """
    at_any(_case_pattern_start)

  fun ref at_type_start(): Bool =>
    """
    Whether the next significant token can start a type.
    """
    at_any(_type_start)

  fun ref _emit(k: SyntaxKind, w: USize) =>
    """
    Push the token as a leaf, and record the lexer's refusals of it,
    which the stream lists by token index in cursor order.
    """
    while true do
      match _stream.next_failure()
      | (let index: USize, let failure: LexFailure, let from: USize,
        let length: USize) if index == _index =>
        _records.record(LexError(failure), from, length)
        _stream.take_failure()
      else
        break
      end
    end
    _elems.push((k, _offset.u32(), 1))
    _offset = _offset + w

  fun ref flush_trivia() =>
    """
    Emit the whitespace and comments before the next significant token,
    into whatever node is open now.

    A rule that parses a sequence calls this between elements, so that what
    separates them belongs to the sequence rather than to either side.
    """
    while true do
      (let k, let w) = _stream.token(_index)
      if not _is_trivia(k) then return end
      _emit(k, w.usize())
      _index = _index + 1
    end

  fun ref start(k: NodeKind) =>
    """
    Open a node. Pending trivia go to the enclosing node first, so a node
    begins at its first real token: `is Bar` and not ` is Bar`, and a
    declaration whose fold range would otherwise start on the blank line
    above it.

    Two things follow from that, and both are the caller's to respect. A
    node opened before nothing is consumed takes the trivia anyway, so a
    rule must not open one speculatively -- which is why an entity with no
    members has no member list rather than an empty one. And the root has
    nothing to be enclosed by, so leading trivia belongs inside it;
    flushing there would put elements before the root and leave the tree
    with two.
    """
    if _open.size() > 0 then
      flush_trivia()
    end
    _open.push(_elems.size())
    _elems.push((k, _offset.u32(), 0))

  fun ref finish() =>
    """
    Close the innermost open node, filling in the subtree size it turned
    out to have. A node ends at its last real token as it begins at its
    first: trivia a child rule flushed before consuming nothing go to
    the enclosing node, as siblings after this one, when there is an
    enclosing node; and a node that consumed nothing, opened after
    such trivia, moves before them, at their offset, so that the
    enclosing node can end at its last real token too.
    """
    try
      let index = _open.pop()?
      (let k, let offset, _) = _elems(index)?
      if _open.size() == 0 then
        _elems(index)? = (k, offset, (_elems.size() - index).u32())
        return
      end
      let last = _before_trailing_trivia(index + 1)
      if (last - index) == 1 then
        var first = index
        while (first > 0) and _is_trivia_element(first - 1) do
          first = first - 1
        end
        if first < index then
          let trivia_offset = _elems(first)?._2
          var j = index
          while j > first do
            _elems(j)? = _elems(j - 1)?
            j = j - 1
          end
          _elems(first)? = (k, trivia_offset, 1)
          return
        end
      end
      _elems(index)? = (k, offset, (last - index).u32())
    else
      _Unreachable()
    end

  fun ref _is_trivia_element(i: USize): Bool =>
    match (try _elems(i)?._1 else _Unreachable(); NdError end)
    | TkWhitespace | TkLineComment | TkNestedComment => true
    else
      false
    end

  fun ref _before_trailing_trivia(from: USize): USize =>
    """
    The index just past the last element at or after `from` that is not
    a trivia leaf; `from` when every element there is one.
    """
    var past = _elems.size()
    while (past > from) and _is_trivia_element(past - 1) do
      past = past - 1
    end
    past

  fun pos(): USize =>
    """
    How far the parser has read.

    Two reads with the same value mean the rule between them consumed
    nothing, which a loop must not go around again.
    """
    _index

  fun ref checkpoint(): (USize, USize) =>
    """
    Where a node would begin if one were opened now: the element index and
    the byte offset. Give it to `wrap_from` to put a node around everything
    parsed since.

    Flushes pending trivia first, as `start` does. Trivia belongs to the
    node being built, not to the one that may later be wrapped around this
    point: without the flush an infix operand begins at the space before
    it, and every extent taken from it is a character wide of the mark.
    """
    flush_trivia()
    (_elems.size(), _offset)

  fun ref wrap_from(mark: (USize, USize), k: NodeKind) =>
    """
    Put a node of kind `k` around every element added since `mark`,
    trailing trivia left outside as `finish` leaves them.

    An infix construct is not known to be one until its operator appears --
    `A` is a type and `A | B` is a union -- and a source-ordered tree cannot
    rebuild itself around the operator the way ponyc's `INFIX_BUILD` does.
    So a rule parses its left side, and wraps only if an operator follows.

    Safe against the open stack because every open node was opened before
    the mark, so inserting at it shifts none of their indices.

    Each call shifts every element after the mark, so a rule that wraps
    once per operator of an unbounded chain uses `chain` instead.
    """
    (let index, let from) = mark
    let past = _before_trailing_trivia(index)
    try
      _elems.insert(index, (k, from.u32(), ((past - index) + 1).u32()))?
    else
      _Unreachable()
    end

  fun ref chain(): _Chain =>
    """
    Like `checkpoint`, for a rule that wraps at one mark once per
    operator of an unbounded chain. `chain_wrap` records what
    `wrap_from` would have inserted, and `close_chain` lays every
    recorded wrapper down at the mark in one pass — the tail after the
    mark shifts once per chain instead of once per operator, which is
    what kept a long flat chain from costing the square of its length.
    """
    flush_trivia()
    _Chain(_elems.size(), _offset)

  fun ref chain_wrap(c: _Chain, k: NodeKind) =>
    """
    Record a wrapper of kind `k` around everything parsed since the
    chain's mark, trailing trivia left outside, to be laid down by
    `close_chain`.
    """
    c.record(k, _before_trailing_trivia(c.index))

  fun ref close_chain(c: _Chain) =>
    """
    Lay the chain's recorded wrappers down at its mark, outermost
    first, exactly as the same sequence of `wrap_from` calls would
    have. A chain with no recorded wrapper changes nothing.
    """
    let k = c.wraps.size()
    if k == 0 then
      return
    end
    // Grow by k, shift the tail up in one backward pass, and write the
    // wrappers into the gap in reverse record order: the last recorded
    // wrapper covers the whole chain, so it comes first in pre-order.
    let old_size = _elems.size()
    var i: USize = 0
    while i < k do
      _elems.push((NdError, 0, 0))
      i = i + 1
    end
    try
      var j = old_size
      while j > c.index do
        j = j - 1
        _elems(j + k)? = _elems(j)?
      end
      var w: USize = 0
      while w < k do
        _elems(c.index + w)? = c.wraps(k - 1 - w)?
        w = w + 1
      end
    else
      _Unreachable()
    end

  fun ref bump() =>
    """
    Emit the next significant token, and any trivia before it. At the
    end of the source the first call emits the `TkEof` and later calls
    emit nothing.
    """
    flush_trivia()
    (let k, let w) = _stream.token(_index)
    if k is TkEof then
      if _eof_emitted then return end
      _eof_emitted = true
    else
      _last_significant = _offset
    end
    _emit(k, w.usize())
    _index = _index + 1

  fun ref expect(k: TokenKind, what: String val): Bool =>
    """
    Emit the next significant token if it is `k`. Otherwise record that
    `what` was expected and emit nothing, leaving the cursor where it is so
    that the caller can decide how to recover.
    """
    if at(k) then
      bump()
      true
    else
      expected(what)
      false
    end

  fun ref open(): _Opener =>
    """
    The next significant token as the opener of a construct; a rule
    takes it before bumping the token, and gives it to `close`.
    """
    (let _, let index, let byte) = _peek()
    (byte, _stream.token(index)._2.usize())

  fun ref close(opener: _Opener, closer: TokenKind, what: String val) =>
    """
    Emit the next significant token if it is `closer`. Otherwise record
    `SyntaxUnterminated(what, before)` over the opener, with `before` at
    the token here (at the end of the file, at the last significant
    token), and emit nothing. This is ponyc's `TERMINATE`, and like it
    the record says only that the parser reached no closer: a closer
    later in the source that the rules inside the construct stopped
    short of is reported the same way. The record is made whatever was
    recorded inside, and is not noted for the dedupe, so a rule failing
    on the token here still records there.
    """
    if at(closer) then
      bump()
    else
      (let found, _, let byte) = _peek()
      let before = if found is TkEof then _last_significant else byte end
      (let offset, let width) = opener
      _records.record(SyntaxUnterminated(what, before), offset, width)
    end

  fun ref expect_any(kinds: Array[TokenKind] box, what: String val): Bool =>
    """
    Emit the next significant token if it is any of `kinds`.
    """
    if at_any(kinds) then
      bump()
      true
    else
      expected(what)
      false
    end

  fun ref expected(what: String val) =>
    """
    Record that `what` was expected here. Consumes nothing. Records
    nothing when the token here is a lexer refusal, whose own record
    says what is wrong, or when a rule before this one already failed
    on this token.
    """
    (let found, let index, let byte) = _peek()
    if found is TkLexError then return end
    if not _records.note_expected(index) then return end
    let position = if found is TkEof then _last_significant else byte end
    _records.record(SyntaxExpected(what, found), position, 0)

  fun ref error_and_recover(what: String val, resync: Array[TokenKind] box) =>
    """
    Record that `what` was expected here, then `skip_to(resync)`.

    This is ponyc's `RESTART`, which names the tokens a rule can resume at.
    ponyc uses it to keep reporting further errors; here it also bounds what
    an error costs, so that one bad item does not take the rest of the file
    with it.
    """
    expected(what)
    skip_to(resync)

  fun ref skip_to(resync: Array[TokenKind] box) =>
    """
    Wrap every token up to the next one in `resync` in an `NdError`
    node. Opens nothing when the current token is the end or is in
    `resync`: an `NdError` holds at least one token and none in
    `resync`. So a rule that calls this from a branch whose current
    token may be in `resync` must have consumed something before, or
    the loop around it spins.
    """
    if eof() or at_any(resync) then
      return
    end
    start(NdError)
    bump()
    while not (eof() or at_any(resync)) do
      bump()
    end
    finish()

  fun ref stop() =>
    """
    End the tree here, before the token the cursor is at: flush the
    pending trivia, then emit a `TkEof` at the stop offset, so that
    the leaves before it tile the prefix exactly. The `TkEof`'s own
    derived width runs to the file's end, so the tree is not one
    `SyntaxTree`'s docstring describes: it reads as the prefix only
    through the nodes before the `TkEof`.
    """
    flush_trivia()
    _elems.push((TkEof, _offset.u32(), 1))

  fun ref build(): (SyntaxTree val, Array[diag.Diagnostic] val) =>
    """
    Close anything still open, account for the trailing trivia, and hand
    back the tree and what was recorded, in emission order.
    """
    flush_trivia()
    while _open.size() > 0 do
      finish()
    end
    _elems.compact()
    let elems: Array[SyntaxElement] val =
      _elems = recover Array[SyntaxElement] end
    (SyntaxTree._create(_file, elems), _records.take())
