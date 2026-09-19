use diag = "../diagnostics"

// Views over the type grammar. `TypeOf` classifies a node; the views
// wrap one node each, except a union or intersection, which is a run
// of one operator inside an `NdInfixType`.

type TypeExpr is
  ( NominalType | UnionType | IsectType | TupleType | ViewpointType
  | LambdaType | ThisType | CapType )
  """
  A type, classified by its form; a part recovery left out is absent
  from the view. Grouping parentheses are transparent, as in ponyc,
  whose `groupedtype` prints inline. `TypeOf` gives `None` for a node
  that is not a type, for `()`, and for a grouping whose content it
  cannot classify.
  """

type TypeArg is (TypeExpr | ValueArg)
  """
  A type argument: a type, or a value argument.
  """

primitive TypeOf
  """
  Classifies a node as a type.
  """
  fun apply(n: Node): (TypeExpr | None) =>
    """
    `NdNominal` is a `NominalType`, `NdThisType` a `ThisType`, a
    capability or generic-capability leaf a `CapType`, `NdGroupedType`
    its one operand classified, `NdTupleType` a `TupleType`,
    `NdInfixType` the fold `UnionType` describes, `NdViewpoint` a
    `ViewpointType`, `NdLambdaType` or `NdBareLambdaType` a
    `LambdaType`; anything else is `None`.
    """
    match n.kind()
    | NdNominal => NominalType._create(n)
    | NdThisType => ThisType._create(n)
    | TkIso | TkTrn | TkRef | TkVal | TkBox | TkTag | TkCapRead | TkCapSend
    | TkCapShare | TkCapAlias | TkCapAny => CapType._create(n)
    | NdGroupedType =>
      let inner = _Parts.operands(n)
      if inner.size() == 1 then
        try apply(inner(0)?) else _Unreachable(); None end
      else
        None
      end
    | NdTupleType => TupleType._create(n)
    | NdInfixType => _InfixFold(n)
    | NdViewpoint => ViewpointType._create(n)
    | NdLambdaType | NdBareLambdaType => LambdaType._create(n)
    else
      None
    end

primitive _TypeArgOf
  """
  A type argument classified: an `NdValueFormalArg` is a `ValueArg`,
  anything else is what `TypeOf` gives.
  """
  fun apply(n: Node): (TypeArg | None) =>
    if n.kind() is NdValueFormalArg then ValueArg._create(n) else TypeOf(n) end

primitive _InfixFold
  """
  The fold of an `NdInfixType`'s significant children, `T op T op T
  ...`, read left to right: a run opens at the first operator and
  closes where the operator changes, and the closed run is the first
  member of the next unless it has no member.
  """
  fun apply(n: Node): (TypeExpr | None) =>
    var acc: (TypeExpr | None) = None
    var op: (TokenKind | None) = None
    var run = recover iso Array[TypeExpr] end
    var operand_expected = true
    for c in n.children() do
      if c.is_trivia() or (c.kind() is NdError) then continue end
      match c.kind()
      | let here: (TkPipe | TkIsecttype) =>
        if op isnt here then
          match op
          | let o: TokenKind =>
            let closed = _run(n, o, run = recover iso Array[TypeExpr] end)
            acc = if closed.members().size() > 0 then closed else None end
          end
          op = here
          match acc
          | let t: TypeExpr => run.push(t)
          end
        end
        operand_expected = true
      else
        if operand_expected then
          match op
          | None => acc = TypeOf(c)
          | let _: TokenKind =>
            match TypeOf(c)
            | let t: TypeExpr => run.push(t)
            end
          end
          operand_expected = false
        end
      end
    end
    match op
    | let o: TokenKind => _run(n, o, consume run)
    | None => acc
    end

  fun _run(n: Node, op: TokenKind, members: Array[TypeExpr] iso)
    : (UnionType | IsectType)
  =>
    if op is TkPipe then
      UnionType._create(n, consume members)
    else
      IsectType._create(n, consume members)
    end

class val NominalType
  """
  An `NdNominal`: `[package.]Name[type args][cap][^ or !]`.
  """
  let _node: Node

  new val _create(node': Node) =>
    _node = node'

  fun node(): Node =>
    """
    The node the view wraps.
    """
    _node

  fun span(): diag.Span =>
    """
    The node's span.
    """
    _node.span()

  fun package(): (Node | None) =>
    """
    The `TkId` before `TkDot`.
    """
    match _Parts.before(_node, TkDot)
    | let n: Node => if n.kind() is TkId then n else None end
    | None => None
    end

  fun name(): (Node | None) =>
    """
    The `TkId` after `TkDot`, else the `TkId` child.
    """
    if _Parts.has(_node, TkDot) then
      match _Parts.after(_node, TkDot)
      | let n: Node => if n.kind() is TkId then n else None end
      | None => None
      end
    else
      _Parts.unique(_node, TkId)
    end

  fun type_args(): Array[TypeArg] val =>
    """
    The `NdTypeArgs` child's arguments classified; one that cannot be
    classified is skipped.
    """
    _TypeArgsOf(_Parts.unique(_node, NdTypeArgs))

  fun cap(): (TokenKind | None) =>
    """
    The capability or generic-capability leaf child.
    """
    _Parts.leaf(_node, _TokenSets.any_cap())

  fun ephemeral(): (TokenKind | None) =>
    """
    `TkEphemeral` or `TkAliased`.
    """
    _Parts.leaf(_node, [TkEphemeral; TkAliased])

class val UnionType
  """
  A maximal run of `|` inside one `NdInfixType`, flat. The node's
  significant children are `T op T op T ...`, ponyc's flat `infixtype`
  over both operators; the fold opens a run at the first operator and
  closes it where the operator changes, so `A | B & C | D` is a union
  of `[A | B] & C` and `D`, whose first member is an intersection of
  the union `[A, B]` and `C`; ponyc's syntax pass rejects a mixed run.
  A grouped operand keeps the source's nesting: `A | (B | C)` is a
  union of `A` and a union of `B` and `C`; a consumer that needs a set
  flattens. An operand `TypeOf` cannot classify is skipped, so `A |` is
  a union of one, and a run that closes with no member is dropped, so
  `| & A` is an intersection of one. A run that is not the whole
  `NdInfixType` has no node of its own: `node()` is the `NdInfixType`,
  and `span()` runs from the first member's offset to the last
  member's finish, or is the node's span with no members.
  """
  let _node: Node
  let _members: Array[TypeExpr] val

  new val _create(node': Node, members': Array[TypeExpr] val) =>
    _node = node'
    _members = members'

  fun node(): Node =>
    """
    The `NdInfixType` the run sits in.
    """
    _node

  fun span(): diag.Span =>
    """
    From the first member's offset to the last member's finish; the
    node's span when there are no members.
    """
    _RunSpan(_node, _members)

  fun members(): Array[TypeExpr] val =>
    """
    The operands of the run, in order.
    """
    _members

class val IsectType
  """
  A maximal run of `&` inside one `NdInfixType`, as `UnionType` is for
  `|`.
  """
  let _node: Node
  let _members: Array[TypeExpr] val

  new val _create(node': Node, members': Array[TypeExpr] val) =>
    _node = node'
    _members = members'

  fun node(): Node =>
    """
    The `NdInfixType` the run sits in.
    """
    _node

  fun span(): diag.Span =>
    """
    From the first member's offset to the last member's finish; the
    node's span when there are no members.
    """
    _RunSpan(_node, _members)

  fun members(): Array[TypeExpr] val =>
    """
    The operands of the run, in order.
    """
    _members

class val TupleType
  """
  An `NdTupleType`.
  """
  let _node: Node

  new val _create(node': Node) =>
    _node = node'

  fun node(): Node =>
    """
    The node the view wraps.
    """
    _node

  fun span(): diag.Span =>
    """
    The node's span.
    """
    _node.span()

  fun members(): Array[TypeExpr] val =>
    """
    The elements classified; one that cannot be classified is skipped.
    """
    let out = recover iso Array[TypeExpr] end
    for c in _Parts.operands(_node).values() do
      match TypeOf(c)
      | let t: TypeExpr => out.push(t)
      end
    end
    consume out

class val ViewpointType
  """
  An `NdViewpoint`: `left->right`.
  """
  let _node: Node

  new val _create(node': Node) =>
    _node = node'

  fun node(): Node =>
    """
    The node the view wraps.
    """
    _node

  fun span(): diag.Span =>
    """
    The node's span.
    """
    _node.span()

  fun left(): (TypeExpr | None) =>
    """
    The child before `TkArrow`, classified.
    """
    match _Parts.before(_node, TkArrow)
    | let n: Node => TypeOf(n)
    | None => None
    end

  fun right(): (TypeExpr | None) =>
    """
    The child after `TkArrow`, classified; `A->B->C` nests right.
    """
    match _Parts.after(_node, TkArrow)
    | let n: Node => TypeOf(n)
    | None => None
    end

class val LambdaType
  """
  An `NdLambdaType` or `NdBareLambdaType`.
  """
  let _node: Node

  new val _create(node': Node) =>
    _node = node'

  fun node(): Node =>
    """
    The node the view wraps.
    """
    _node

  fun span(): diag.Span =>
    """
    The node's span.
    """
    _node.span()

  fun is_bare(): Bool =>
    """
    Whether the node is an `NdBareLambdaType`, `@{...}`.
    """
    _node.kind() is NdBareLambdaType

  fun receiver_cap(): (TokenKind | None) =>
    """
    The capability leaf before the `(`; when the `(` is missing,
    before any `)`, `:`, `?` or `}`, since a bare-capability return
    type is a leaf too.
    """
    _Parts.leaf_before(_node, _TokenSets.caps(),
      [TkLparen; TkLparenNew; TkRparen; TkColon; TkQuestion; TkRbrace])

  fun name(): (Node | None) =>
    """
    The `TkId` child.
    """
    _Parts.unique(_node, TkId)

  fun type_params(): Array[TypeParamDecl] val =>
    """
    The `NdTypeParam` children of the `NdTypeParams` child.
    """
    _TypeParamsOf(_Parts.unique(_node, NdTypeParams))

  fun param_types(): Array[TypeExpr] val =>
    """
    The `NdTypeList` child's types classified; one that cannot be
    classified is skipped.
    """
    let out = recover iso Array[TypeExpr] end
    match _Parts.unique(_node, NdTypeList)
    | let list: Node =>
      for c in _Parts.operands(list).values() do
        match TypeOf(c)
        | let t: TypeExpr => out.push(t)
        end
      end
    end
    consume out

  fun return_type(): (TypeExpr | None) =>
    """
    The child after `TkColon`, classified.
    """
    _TypeAfter(_node, TkColon)

  fun is_partial(): Bool =>
    """
    Whether the `TkQuestion` child is there.
    """
    _Parts.has(_node, TkQuestion)

  fun cap(): (TokenKind | None) =>
    """
    The capability or generic-capability leaf after the `}`.
    """
    var after_brace = false
    for c in _node.children() do
      if after_brace then
        for k in _TokenSets.any_cap().values() do
          if c.kind() is k then return k end
        end
      elseif c.kind() is TkRbrace then
        after_brace = true
      end
    end
    None

  fun ephemeral(): (TokenKind | None) =>
    """
    `TkEphemeral` or `TkAliased`.
    """
    _Parts.leaf(_node, [TkEphemeral; TkAliased])

class val ThisType
  """
  An `NdThisType`: `this` in type position.
  """
  let _node: Node

  new val _create(node': Node) =>
    _node = node'

  fun node(): Node =>
    """
    The node the view wraps.
    """
    _node

  fun span(): diag.Span =>
    """
    The node's span.
    """
    _node.span()

class val CapType
  """
  A bare capability in type position: a leaf with no node of its own.
  """
  let _node: Node

  new val _create(node': Node) =>
    _node = node'

  fun node(): Node =>
    """
    The node the view wraps.
    """
    _node

  fun span(): diag.Span =>
    """
    The node's span.
    """
    _node.span()

  fun cap(): TokenKind =>
    """
    The capability or generic capability.
    """
    match _node.kind()
    | let t: TokenKind => t
    else
      _Unreachable(); TkEof
    end

class val ValueArg
  """
  An `NdValueFormalArg`: a literal or `#` expression as a type
  argument; no accessor over its expression.
  """
  let _node: Node

  new val _create(node': Node) =>
    _node = node'

  fun node(): Node =>
    """
    The node the view wraps.
    """
    _node

  fun span(): diag.Span =>
    """
    The node's span.
    """
    _node.span()

primitive _TypeArgsOf
  fun apply(list: (Node | None)): Array[TypeArg] val =>
    let out = recover iso Array[TypeArg] end
    match list
    | let l: Node =>
      for c in _Parts.operands(l).values() do
        match _TypeArgOf(c)
        | let a: TypeArg => out.push(a)
        end
      end
    end
    consume out

primitive _RunSpan
  fun apply(node: Node, members: Array[TypeExpr] box): diag.Span =>
    try
      let first = members(0)?
      let last = members(members.size() - 1)?
      let start = first.span().start
      diag.Span(first.span().dir, first.span().name, start,
        last.span().finish() - start)
    else
      node.span()
    end
