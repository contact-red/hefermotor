// The control structures of Pony's expression grammar, and the atoms.

primitive _Cond
  """
  ponyc's `cond`: `if condition then ... [elseif ...] [else ...] end`.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdIf)
    let opener = p.open()
    p.bump()
    _Annotated(p)
    _RawSeq(p, "condition expression")
    p.expect(TkThen, "then")
    _RawSeq(p, "then value")
    _ElseTail(p, TkIf)
    p.close(opener, TkEnd, "if expression")
    p.finish()

primitive _IfDef
  """
  ponyc's `ifdef`: the same shape over build flags.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdIfDef)
    let opener = p.open()
    p.bump()
    _Annotated(p)
    _Infix(p, _ExprNormal, "condition expression")
    p.expect(TkThen, "then")
    _RawSeq(p, "then value")
    _ElseTail(p, TkIfdef)
    p.close(opener, TkEnd, "ifdef expression")
    p.finish()

primitive _ElseTail
  """
  The `elseif ... then ...` chain and `else ...` that close a conditional.

  ponyc writes the chain as a rule that recurses into itself; the shape is
  the same either way, and a loop keeps the tree flat rather than nesting
  one `elseif` inside the last.
  """
  fun apply(p: _Parser ref, chain_kind: TokenKind) =>
    while p.at(TkElseif) do
      p.start(if chain_kind is TkIfdef then NdIfDef else NdIf end)
      p.bump()
      _Annotated(p)
      if chain_kind is TkIfdef then
        _Infix(p, _ExprNormal, "condition expression")
      else
        _RawSeq(p, "condition expression")
      end
      p.expect(TkThen, "then")
      _RawSeq(p, "then value")
      p.finish()
    end
    _ElseClause(p, "else value")

primitive _ElseClause
  """
  The `else ...` that may close a control structure; `what` is ponyc's
  noun for the missing body at the site.
  """
  fun apply(p: _Parser ref, what: String val) =>
    if p.at(TkElse) then
      p.start(NdElse)
      p.bump()
      _Annotated(p)
      _RawSeq(p, what)
      p.finish()
    end

primitive _IfTypeSet
  """
  ponyc's `iftypeset`: `iftype T <: U then ... [elseif ...] [else ...] end`.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdIfTypeSet)
    let opener = p.open()
    p.bump()
    _Annotated(p)
    _IfTypeClause(p)
    while p.at(TkElseif) do
      p.bump()
      _Annotated(p)
      _IfTypeClause(p)
    end
    _ElseClause(p, "else value")
    p.close(opener, TkEnd, "iftype expression")
    p.finish()

primitive _IfTypeClause
  fun apply(p: _Parser ref) =>
    p.start(NdIfType)
    _TypeRule(p, "iftype clause")
    p.expect(TkSubtype, "<:")
    _TypeRule(p, "type")
    p.expect(TkThen, "then")
    _RawSeq(p, "then value")
    p.finish()

primitive _Match
  """
  ponyc's `match`: a subject, cases, and an optional else.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdMatch)
    let opener = p.open()
    p.bump()
    _Annotated(p)
    _RawSeq(p, "match expression")
    p.start(NdCases)
    while p.at(TkPipe) do
      _Case(p)
    end
    p.finish()
    _ElseClause(p, "else clause")
    p.close(opener, TkEnd, "match expression")
    p.finish()

primitive _Case
  """
  ponyc's `caseexpr`: `| pattern [if guard] [=> body]`.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdCase)
    p.bump()
    _Annotated(p)
    // ponyc's `OPT RULE("case pattern", casepattern)`: entered only
    // where a case pattern can start, which an `if` cannot.
    if p.at_case_pattern_start() then
      _Pattern(p, _ExprCase, "value")
    end
    if p.at(TkIf) then
      p.start(NdGuard)
      p.bump()
      _RawSeq(p, "guard expression")
      p.finish()
    end
    if p.at(TkDblarrow) then
      p.bump()
      _RawSeq(p, "case body")
    end
    p.finish()

primitive _While
  fun apply(p: _Parser ref) =>
    p.start(NdWhile)
    let opener = p.open()
    p.bump()
    _Annotated(p)
    _RawSeq(p, "condition expression")
    p.expect(TkDo, "do")
    _RawSeq(p, "while body")
    _ElseClause(p, "else clause")
    p.close(opener, TkEnd, "while loop")
    p.finish()

primitive _Repeat
  fun apply(p: _Parser ref) =>
    p.start(NdRepeat)
    let opener = p.open()
    p.bump()
    _Annotated(p)
    _RawSeq(p, "repeat body")
    p.expect(TkUntil, "until")
    _Annotated(p)
    _RawSeq(p, "condition expression")
    _ElseClause(p, "else clause")
    p.close(opener, TkEnd, "repeat loop")
    p.finish()

primitive _For
  fun apply(p: _Parser ref) =>
    p.start(NdFor)
    let opener = p.open()
    p.bump()
    _Annotated(p)
    _IdSeq(p, "iterator name")
    p.expect(TkIn, "in")
    _RawSeq(p, "iterator")
    p.expect(TkDo, "do")
    _RawSeq(p, "for body")
    _ElseClause(p, "else clause")
    p.close(opener, TkEnd, "for loop")
    p.finish()

primitive _With
  fun apply(p: _Parser ref) =>
    p.start(NdWith)
    let opener = p.open()
    p.bump()
    _Annotated(p)
    _WithElem(p)
    while p.at(TkComma) do
      p.bump()
      _WithElem(p)
    end
    p.expect(TkDo, "do")
    _RawSeq(p, "with body")
    p.close(opener, TkEnd, "with expression")
    p.finish()

primitive _WithElem
  fun apply(p: _Parser ref) =>
    p.start(NdWithElem)
    _IdSeq(p, "with expression")
    p.expect(TkAssign, "=")
    _RawSeq(p, "initialiser")
    p.finish()

primitive _IdSeq
  """
  ponyc's `idseq`: the names a `for` or a `with` binds, one or a tuple.
  """
  fun apply(p: _Parser ref, what: String val) =>
    // Recurses through _IdSeqName without passing the sequence or term
    // rules, so it carries its own descent.
    if p.too_deep("expression") then
      return
    end
    p.start(NdIdSeq)
    if p.at_any(_TokenSets.lparen()) then
      p.bump()
      _IdSeqName(p, "variable name")
      while p.at(TkComma) do
        p.bump()
        _IdSeqName(p, "variable name")
      end
      p.expect(TkRparen, ")")
    else
      _IdSeqName(p, what)
    end
    p.finish()
    p.ascend()

primitive _IdSeqName
  fun apply(p: _Parser ref, what: String val) =>
    if p.at_any(_TokenSets.lparen()) then
      _IdSeq(p, "variable name")
    else
      p.expect(TkId, what)
    end

primitive _Try
  fun apply(p: _Parser ref) =>
    p.start(NdTry)
    let opener = p.open()
    p.bump()
    _Annotated(p)
    _RawSeq(p, "try body")
    _ElseClause(p, "try else body")
    if p.at(TkThen) then
      p.start(NdThen)
      p.bump()
      _Annotated(p)
      _RawSeq(p, "try then body")
      p.finish()
    end
    p.close(opener, TkEnd, "try expression")
    p.finish()

primitive _Recover
  fun apply(p: _Parser ref) =>
    p.start(NdRecover)
    let opener = p.open()
    p.bump()
    _Annotated(p)
    if p.at_any(_TokenSets.caps()) then
      p.bump()
    end
    _RawSeq(p, "recover body")
    p.close(opener, TkEnd, "recover expression")
    p.finish()

primitive _Consume
  fun apply(p: _Parser ref) =>
    p.start(NdConsume)
    p.bump()
    if p.at_any(_TokenSets.caps()) then
      p.bump()
    end
    _Term(p, _ExprNormal, "expression")
    p.finish()

primitive _Annotated
  """
  The `\\annotation\\` that may follow a control keyword, an FFI
  return type argument or an FFI parameter.
  """
  fun apply(p: _Parser ref) =>
    if p.at(TkBackslash) then
      _Annotations(p)
    end
