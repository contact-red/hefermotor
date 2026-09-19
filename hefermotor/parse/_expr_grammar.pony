// Pony's expression grammar, ported rule for rule from ponyc's parser.c.
//
// Two systematic departures, both because this builds a source-ordered tree
// rather than an AST for later passes. INFIX_BUILD rebuilds the tree around
// an operator; here the operator stays between its operands and the rule
// wraps them, with `_Parser.wrap_from`. REORDER puts a rule's children in the
// order a later pass wants; here they stay in the order they were written.
//
// ponyc's `test_*` rules are omitted. They exist for `$`-prefixed symbols
// that only its own test suite uses, and are enabled by a flag this parser
// does not offer.

primitive _RawSeq
  """
  ponyc's `rawseq`: one or more expressions, separated by semicolons or by
  nothing at all. `what` is the site's noun, which a missing first
  expression is reported as; after a `;` the noun is ponyc's "value".
  """
  fun apply(p: _Parser ref, what: String val) =>
    if p.too_deep("expression") then
      return
    end
    p.start(NdSeq)
    // ponyc's sequence stops after a jump; what follows one is the
    // enclosing rule's to take.
    var jumped = _Statement(p, _ExprNormal, what)
    while (not jumped) and (not _SeqEnd(p.current())) do
      let before = p.pos()
      if p.at(TkSemi) then
        p.bump()
        if _SeqEnd(p.current()) then
          p.expected("value")
          break
        end
        jumped = _Statement(p, _ExprNormal, "value")
      else
        // No semicolon, so this begins a statement, and only the newline
        // forms of `(`, `[` and `-` may open one.
        jumped = _Statement(p, _ExprStatement, "value")
      end
      if p.pos() == before then
        // The token here starts no expression and ends no sequence, so
        // nothing was consumed and going around again would spin. The rule
        // that failed has already said what it expected; take the token as
        // an error and carry on, so that no input can hang the parser.
        p.start(NdError)
        p.bump()
        p.finish()
      end
    end
    p.finish()
    p.ascend()

primitive _SeqEnd
  """
  Whether a token ends a sequence of expressions rather than starting
  another one.

  Not `var`, `let` or `embed`: those begin a local declaration, which is an
  expression. `fun`, `be` and `new` do end one, and cannot appear inside an
  expression except within an `object` literal, which is consumed to its
  `end` before this is asked.
  """
  fun apply(kind: TokenKind): Bool =>
    match kind
    | TkEnd | TkElse | TkElseif | TkThen | TkDo | TkUntil | TkPipe
    | TkRparen | TkRsquare | TkRbrace | TkComma | TkWhere | TkDblarrow
    | TkEof
    | TkFun | TkBe | TkNew
    | TkUse | TkType | TkInterface | TkTrait
    | TkPrimitive | TkStruct | TkClass | TkActor => true
    else
      false
    end

primitive _Statement
  """
  ponyc's `assignment` or `jump`, whichever the next token begins;
  returns whether it was a jump.
  """
  fun apply(p: _Parser ref, mode: _ExprMode, what: String val): Bool =>
    if _IsJump(p.current()) then
      _Jump(p)
      true
    else
      _Assignment(p, mode, what)
      false
    end

primitive _IsJump
  fun apply(kind: TokenKind): Bool =>
    match kind
    | TkReturn | TkBreak | TkContinue | TkError
    | TkCompileIntrinsic | TkCompileError => true
    else
      false
    end

primitive _Jump
  """
  ponyc's `jump`: a control transfer and, for some of them, a value.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdJump)
    p.bump()
    // ponyc's `OPT RULE("return value", rawseq)`: entered only where an
    // expression can start.
    if p.at_expr_start() then
      _RawSeq(p, "return value")
    end
    p.finish()

primitive _Assignment
  """
  ponyc's `assignment`: an infix expression, optionally assigned to.
  """
  fun apply(p: _Parser ref, mode: _ExprMode, what: String val) =>
    let mark = p.checkpoint()
    _Infix(p, mode, what)
    if p.at(TkAssign) then
      // The recursion on the right of `=` runs after _Infix has
      // already returned, so this branch carries its own descent —
      // at the entry it would also count every plain statement.
      if p.too_deep("expression") then
        return
      end
      p.bump()
      _Assignment(p, _ExprNormal, "assign rhs")
      p.wrap_from(mark, NdAssign)
      p.ascend()
    end

primitive _Infix
  """
  ponyc's `infix`: terms joined by binary operators, `is`, `isnt` or `as`.

  Pony gives infix operators no precedence -- the parentheses are the
  precedence -- so each operator simply takes everything to its left,
  nesting `a + b + c` to the left as ponyc's INFIX_BUILD does.
  """
  fun apply(p: _Parser ref, mode: _ExprMode, what: String val) =>
    let mark = p.chain()
    _Term(p, mode, what)
    var going = true
    while going do
      if p.at(TkAs) then
        p.bump()
        _TypeRule(p, "type")
        p.chain_wrap(mark, NdAsOp)
      elseif p.at(TkIs) or p.at(TkIsnt) or _IsBinOp(p.current()) then
        p.bump()
        // A partial operator: `a +? b`.
        if p.at(TkQuestion) then
          p.bump()
        end
        _Term(p, _ExprNormal, "value")
        p.chain_wrap(mark, NdBinOp)
      else
        going = false
      end
    end
    p.close_chain(mark)

primitive _IsBinOp
  fun apply(kind: TokenKind): Bool =>
    match kind
    | TkAnd | TkOr | TkXor
    | TkPlus | TkMinus | TkMultiply | TkDivide | TkRem | TkMod
    | TkPlusTilde | TkMinusTilde | TkMultiplyTilde | TkDivideTilde
    | TkRemTilde | TkModTilde
    | TkLshift | TkRshift | TkLshiftTilde | TkRshiftTilde
    | TkEq | TkNe | TkLt | TkLe | TkGe | TkGt
    | TkEqTilde | TkNeTilde | TkLtTilde | TkLeTilde | TkGeTilde
    | TkGtTilde => true
    else
      false
    end

primitive _Term
  """
  ponyc's `term`: a control structure, a `consume`, or a pattern.
  """
  fun apply(p: _Parser ref, mode: _ExprMode, what: String val) =>
    // Every expression-level descent passes through this rule, control
    // structures in condition position included, so the depth guard
    // here covers what the guard in the sequence rule cannot: nesting
    // that never opens a new sequence.
    if p.too_deep("expression") then
      return
    end
    let kind = p.current()
    match kind
    | TkIf => _Cond(p)
    | TkIfdef => _IfDef(p)
    | TkIftypeSet => _IfTypeSet(p)
    | TkMatch => _Match(p)
    | TkWhile => _While(p)
    | TkRepeat => _Repeat(p)
    | TkFor => _For(p)
    | TkWith => _With(p)
    | TkTry => _Try(p)
    | TkRecover => _Recover(p)
    | TkConsume => _Consume(p)
    | TkConstant => _ConstExpr(p)
    else
      _Pattern(p, mode, what)
    end
    p.ascend()

primitive _Pattern
  """
  ponyc's `pattern`: a local declaration, or an expression.
  """
  fun apply(p: _Parser ref, mode: _ExprMode, what: String val) =>
    match p.current()
    | TkVar | TkLet | TkEmbed | TkMatchCapture => _Local(p)
    else
      _ParamPattern(p, mode, what)
    end

primitive _Local
  """
  ponyc's `local`: `var`, `let`, `embed` or a match capture, and its name.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdLocal)
    p.bump()
    p.expect(TkId, "variable name")
    if p.at(TkColon) then
      p.bump()
      _TypeRule(p, "variable type")
    end
    p.finish()

primitive _ParamPattern
  """
  ponyc's `parampattern`: a prefix operator applied to one, or a postfix
  expression.
  """
  fun apply(p: _Parser ref, mode: _ExprMode, what: String val) =>
    if _IsPrefixOp(p.current(), mode) then
      // A prefix chain recurses here without passing the sequence rule
      // or `_Term`, so it carries its own descent.
      if p.too_deep("expression") then
        return
      end
      p.start(NdUnaryOp)
      p.bump()
      // After the operator the newline forms no longer matter, but a
      // case pattern stays one: ponyc's `caseprefix` recurses through
      // `caseparampattern`, so `| -if` is still a missing expression.
      _ParamPattern(p,
        if mode is _ExprCase then _ExprCase else _ExprNormal end,
        "expression")
      p.finish()
      p.ascend()
    else
      _Postfix(p, mode, what)
    end

primitive _IsPrefixOp
  """
  Whether a token is a prefix operator here.

  A statement may open with the newline form of `-` and not the ordinary
  one, which is what stops `a\n-b` reading as a subtraction.
  """
  fun apply(kind: TokenKind, mode: _ExprMode): Bool =>
    match kind
    | TkNot | TkAddress | TkDigestof
    | TkMinusNew | TkMinusTildeNew => true
    | TkMinus | TkMinusTilde => not (mode is _ExprStatement)
    else
      false
    end

primitive _Postfix
  """
  ponyc's `postfix`: an atom, then any number of `.`, `~`, `.>`, type
  arguments and calls applied to it.
  """
  fun apply(p: _Parser ref, mode: _ExprMode, what: String val) =>
    let mark = p.chain()
    _Atom(p, mode, what)

    // Each operator wraps everything so far, so `x.y.z(k)` nests to the
    // left as ponyc's INFIX_BUILD does: the receiver of `.z` is `x.y`, and
    // the receiver of the call is `x.y.z`. That nesting is what lets a
    // question about `.y` be answered without re-parsing the chain.
    var going = true
    while going do
      if p.at(TkDot) or p.at(TkTilde) or p.at(TkChain) then
        let kind =
          if p.at(TkDot) then NdDot
          elseif p.at(TkTilde) then NdTilde
          else NdChain
          end
        p.bump()
        p.expect(TkId,
          if kind is NdDot then "member name" else "method name" end)
        p.chain_wrap(mark, kind)
      elseif p.at(TkLsquare) then
        _TypeArgs(p)
        p.chain_wrap(mark, NdQualify)
      elseif p.at(TkLparen) then
        _Call(p)
        p.chain_wrap(mark, NdCall)
      else
        going = false
      end
    end
    p.close_chain(mark)

primitive _Call
  """
  ponyc's `call`: the argument list of a call.

  Only `(` and never its newline form: a parenthesis that begins a line
  begins a statement.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdArgs)
    p.bump()
    if p.at_expr_start() then
      _Positional(p)
    end
    if p.at(TkWhere) then
      _NamedArgs(p)
    end
    p.expect(TkRparen, ")")
    p.finish()
    if p.at(TkQuestion) then
      p.bump()
    end

primitive _Positional
  """
  ponyc's `positional`: the comma-separated arguments of a call, entered
  only on a token that starts an expression, as ponyc's optional rule
  is.
  """
  fun apply(p: _Parser ref) =>
    _RawSeq(p, "argument")
    while p.at(TkComma) do
      p.bump()
      _RawSeq(p, "argument")
    end

primitive _NamedArgs
  """
  ponyc's `named`: the `where name = value` arguments of a call.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdNamedArgs)
    p.bump()
    _NamedArg(p)
    while p.at(TkComma) do
      p.bump()
      _NamedArg(p)
    end
    p.finish()

primitive _NamedArg
  fun apply(p: _Parser ref) =>
    p.start(NdNamedArg)
    p.expect(TkId, "named argument")
    p.expect(TkAssign, "=")
    _RawSeq(p, "argument value")
    p.finish()

primitive _ConstExpr
  """
  ponyc's `const_expr`: a `#` and the expression it makes constant.
  """
  fun apply(p: _Parser ref) =>
    // Reached from a type argument without passing the sequence or
    // term rules, so it carries its own descent.
    if p.too_deep("expression") then
      return
    end
    p.start(NdConstExpr)
    p.bump()
    _Postfix(p, _ExprNormal, "formal argument value")
    p.finish()
    p.ascend()
