// Pony's type grammar, ported rule for rule from ponyc's parser.c.
//
// The one systematic departure: ponyc's INFIX_BUILD rebuilds the tree around
// an operator, making `A | B` a union node with two children. This tree is
// source-ordered, so the operator stays between its operands and the rule
// wraps them instead. See `_Parser.wrap_from`.

primitive _TypeRule
  """
  ponyc's `type`: an atom, optionally followed by a viewpoint. `what`
  is the site's noun, which a missing type is reported as.
  """
  fun apply(p: _Parser ref, what: String val) =>
    if p.too_deep("type") then
      return
    end
    let mark = p.checkpoint()
    _AtomType(p, what)
    if p.at(TkArrow) then
      p.bump()
      _TypeRule(p, "viewpoint")
      p.wrap_from(mark, NdViewpoint)
    end
    p.ascend()

primitive _InfixType
  """
  ponyc's `infixtype`: types joined by `|` or `&`.
  """
  fun apply(p: _Parser ref, what: String val) =>
    let mark = p.checkpoint()
    _TypeRule(p, what)
    var joined = false
    while p.at(TkPipe) or p.at(TkIsecttype) do
      joined = true
      p.bump()
      _TypeRule(p, "type")
    end
    if joined then
      p.wrap_from(mark, NdInfixType)
    end

primitive _AtomType
  """
  ponyc's `atomtype`: `this`, a capability, a parenthesised type, a named
  type, or a lambda type.
  """
  fun apply(p: _Parser ref, what: String val) =>
    if p.at(TkThis) then
      p.start(NdThisType)
      p.bump()
      p.finish()
    elseif p.at_any(_TokenSets.any_cap()) then
      p.bump()
    elseif p.at_any(_TokenSets.lparen()) then
      _GroupedType(p)
    elseif p.at(TkId) then
      _Nominal(p)
    elseif p.at(TkLbrace) then
      _LambdaType(p, NdLambdaType)
    elseif p.at(TkAtLbrace) then
      _LambdaType(p, NdBareLambdaType)
    else
      p.expected(what)
    end

primitive _Nominal
  """
  ponyc's `nominal`: `[package.]Name[typeargs][cap][^ or !]`.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdNominal)
    p.bump()
    if p.at(TkDot) then
      p.bump()
      p.expect(TkId, "name")
    end
    if p.at(TkLsquare) then
      _TypeArgs(p)
    end
    if p.at_any(_TokenSets.any_cap()) then
      p.bump()
    end
    if p.at(TkEphemeral) or p.at(TkAliased) then
      p.bump()
    end
    p.finish()

primitive _GroupedType
  """
  ponyc's `groupedtype`: `(infixtype[, infixtype]*)`.

  A comma makes it a tuple, which is not known until the comma appears.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdGroupedType)
    p.bump()
    let mark = p.checkpoint()
    _InfixType(p, "type")
    var tuple = false
    while p.at(TkComma) do
      tuple = true
      p.bump()
      _InfixType(p, "type")
    end
    if tuple then
      p.wrap_from(mark, NdTupleType)
    end
    p.expect(TkRparen, ")")
    p.finish()

primitive _LambdaType
  """
  ponyc's `lambdatype` and `barelambdatype`, which differ only in whether
  they open with `{` or `@{`.
  """
  fun apply(p: _Parser ref, kind: NodeKind) =>
    p.start(kind)
    p.bump()
    if p.at_any(_TokenSets.caps()) then
      p.bump()
    end
    if p.at(TkId) then
      p.bump()
    end
    if p.at_any(_TokenSets.lsquare()) then
      _TypeParams(p)
    end
    p.expect_any(_TokenSets.lparen(), "(")
    // ponyc's `OPT RULE("parameters", typelist)`: entered only where a
    // type can start.
    if p.at_type_start() then
      _TypeList(p)
    end
    p.expect(TkRparen, ")")
    if p.at(TkColon) then
      p.bump()
      _TypeRule(p, "return type")
    end
    if p.at(TkQuestion) then
      p.bump()
    end
    p.expect(TkRbrace, "}")
    if p.at_any(_TokenSets.any_cap()) then
      p.bump()
    end
    if p.at(TkEphemeral) or p.at(TkAliased) then
      p.bump()
    end
    p.finish()

primitive _TypeList
  """
  ponyc's `typelist`: the parameter types of a lambda type.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdTypeList)
    _TypeRule(p, "parameter type")
    while p.at(TkComma) do
      p.bump()
      _TypeRule(p, "parameter type")
    end
    p.finish()

primitive _TypeArgs
  """
  ponyc's `typeargs`: `[typearg[, typearg]*]` at a use site.

  Only `[` opens one, never the newline form: a `[` on a new line starts an
  array literal, not type arguments.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdTypeArgs)
    let opener = p.open()
    p.bump()
    _TypeArg(p, "type argument")
    while p.at(TkComma) do
      p.bump()
      _TypeArg(p, "type argument")
    end
    p.close(opener, TkRsquare, "type arguments")
    p.finish()

primitive _TypeArg
  """
  ponyc's `typearg`: a type, a literal, or a `#`-prefixed constant.
  """
  fun apply(p: _Parser ref, what: String val) =>
    if p.at_any(_TokenSets.literals()) then
      p.start(NdValueFormalArg)
      p.bump()
      p.finish()
    elseif p.at(TkConstant) then
      p.start(NdValueFormalArg)
      _ConstExpr(p)
      p.finish()
    else
      _TypeRule(p, what)
    end

primitive _TypeParams
  """
  ponyc's `typeparams`: `[typeparam[, typeparam]*]` on a declaration.

  Both forms of `[` open one, because a declaration's type parameters can
  begin a line.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdTypeParams)
    let opener = p.open()
    p.bump()
    _TypeParam(p)
    while p.at(TkComma) do
      p.bump()
      _TypeParam(p)
    end
    p.close(opener, TkRsquare, "type parameters")
    p.finish()

primitive _TypeParam
  """
  ponyc's `typeparam`: a name, an optional constraint, an optional
  default. A missing name is reported as the list's "type parameter",
  as ponyc's not-found propagation reports it.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdTypeParam)
    p.expect(TkId, "type parameter")
    if p.at(TkColon) then
      p.bump()
      _TypeRule(p, "type constraint")
    end
    if p.at(TkAssign) then
      p.bump()
      _TypeArg(p, "default type argument")
    end
    p.finish()
