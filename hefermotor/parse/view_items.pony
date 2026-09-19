use diag = "../diagnostics"

// Views over the item grammar: use commands, entities, members,
// parameters and type parameters. Each wraps one node of the right kind
// (an FFI declaration reads two), built only by the tree or another
// view, so the kind is right by construction. Every part the grammar
// makes optional, or that recovery can leave out, is optional. The
// part-finding rule is stated per accessor: "the K child" is the unique
// direct child of kind K (`_Parts.unique`; `None` when there are
// several, which `TreeCheck`'s `PartsUnique` row reports), "after T" the first
// significant direct child following the delimiter T, "before T" the
// last one preceding it. On a broken part an accessor returns what it
// finds among the parts that are there.

type UseCommand is (PackageUse | FfiDecl)
  """
  A `use` command: of a package, or an FFI declaration.
  """

type MemberDecl is (FieldDecl | MethodDecl)
  """
  A member of an entity or an object literal.
  """

primitive _Parts
  """
  The part-finding rules, over a node's significant direct children:
  trivia and `NdError` are never a part.
  """
  fun unique(node: Node, k: SyntaxKind): (Node | None) =>
    """
    The one direct child of kind `k`; `None` for none or several.
    """
    var found: (Node | None) = None
    for c in node.children() do
      if c.kind() is k then
        if found isnt None then return None end
        found = c
      end
    end
    found

  fun after(node: Node, delimiter: TokenKind): (Node | None) =>
    """
    The first significant direct child after the first `delimiter`
    leaf; `None` without the delimiter or with nothing after it.
    """
    var seen = false
    for c in node.children() do
      if seen then
        if _significant(c) then return c end
      elseif c.kind() is delimiter then
        seen = true
      end
    end
    None

  fun before(node: Node, delimiter: TokenKind): (Node | None) =>
    """
    The last significant direct child before the first `delimiter`
    leaf; `None` without the delimiter or with nothing before it.
    """
    var last: (Node | None) = None
    for c in node.children() do
      if c.kind() is delimiter then return last end
      if _significant(c) then last = c end
    end
    None

  fun first(node: Node): (Node | None) =>
    """
    The first significant direct child.
    """
    for c in node.children() do
      if _significant(c) then return c end
    end
    None

  fun leaf(node: Node, kinds: Array[TokenKind] val): (TokenKind | None) =>
    """
    The kind of the first direct leaf whose kind is one of `kinds`.
    """
    for c in node.children() do
      for k in kinds.values() do
        if c.kind() is k then return k end
      end
    end
    None

  fun leaf_before(node: Node, kinds: Array[TokenKind] val,
    delimiters: Array[TokenKind] val): (TokenKind | None)
  =>
    """
    The kind of the first direct leaf whose kind is one of `kinds`,
    before any leaf whose kind is one of `delimiters`.
    """
    for c in node.children() do
      for d in delimiters.values() do
        if c.kind() is d then return None end
      end
      for k in kinds.values() do
        if c.kind() is k then return k end
      end
    end
    None

  fun has(node: Node, k: TokenKind): Bool =>
    """
    Whether a direct leaf of kind `k` exists.
    """
    node.child(k) isnt None

  fun each(node: Node, k: NodeKind): Array[Node] val =>
    """
    Every direct child of kind `k`, in order.
    """
    let out = recover iso Array[Node] end
    for c in node.children() do
      if c.kind() is k then out.push(c) end
    end
    consume out

  fun operands(node: Node): Array[Node] val =>
    """
    The significant direct children that are not punctuation: not a
    bracket, a comma or an annotation group.
    """
    let out = recover iso Array[Node] end
    for c in node.children() do
      match c.kind()
      | TkLparen | TkLparenNew | TkRparen | TkLsquare | TkLsquareNew
      | TkRsquare | TkComma | NdAnnotations => None
      else
        if _significant(c) then out.push(c) end
      end
    end
    consume out

  fun _significant(c: Node): Bool =>
    (not c.is_trivia()) and (c.kind() isnt NdError)

primitive _UniqueParts
  """
  The kinds a view's "the K child" accessors take as unique, one set
  per accessor, for `PartsUnique`.
  """
  fun package_use(): Array[Array[SyntaxKind] val] val =>
    """
    `NdUseFFI` is here because a `use` with two of them is read as a
    `PackageUse`: the tree's rule is "the `NdUseFFI` child".
    """
    [[NdUseName]; [NdUseFFI]]

  fun ffi_decl(): Array[Array[SyntaxKind] val] val =>
    [[NdUseName]]

  fun ffi_body(): Array[Array[SyntaxKind] val] val =>
    [[NdTypeArgs]; [NdParams]; [TkQuestion]]

  fun entity(): Array[Array[SyntaxKind] val] val =>
    [ [NdAnnotations]; [TkAt]; [TkIso; TkTrn; TkRef; TkVal; TkBox; TkTag]
      [TkId]; [NdTypeParams]; [NdProvides]; [TkString]; [NdMembers] ]

  fun field(): Array[Array[SyntaxKind] val] val =>
    [[TkId]]

  fun field_without_value(): Array[Array[SyntaxKind] val] val =>
    """
    Without `TkAssign` the docstring is the `TkString` child; with it
    a string value is a `TkString` child too, and the docstring rule
    is positional.
    """
    [[TkId]; [TkString]]

  fun method(): Array[Array[SyntaxKind] val] val =>
    [ [NdAnnotations]; [TkId]; [NdTypeParams]; [NdParams]; [TkQuestion]
      [TkString]; [NdSeq] ]

  fun param(): Array[Array[SyntaxKind] val] val =>
    [[TkId]; [NdAnnotations]; [NdDefaultArg]]

  fun type_param(): Array[Array[SyntaxKind] val] val =>
    [[TkId]]

  fun nominal(): Array[Array[SyntaxKind] val] val =>
    """
    A nominal type with a dot has two `TkId` children by design, so
    the name's uniqueness is `nominal_without_package`'s.
    """
    [ [NdTypeArgs]
      [ TkIso; TkTrn; TkRef; TkVal; TkBox; TkTag; TkCapRead; TkCapSend
        TkCapShare; TkCapAlias; TkCapAny ]
      [TkEphemeral; TkAliased] ]

  fun nominal_without_package(): Array[Array[SyntaxKind] val] val =>
    [ [TkId]; [NdTypeArgs]
      [ TkIso; TkTrn; TkRef; TkVal; TkBox; TkTag; TkCapRead; TkCapSend
        TkCapShare; TkCapAlias; TkCapAny ]
      [TkEphemeral; TkAliased] ]

  fun lambda(): Array[Array[SyntaxKind] val] val =>
    [ [TkId]; [NdTypeParams]; [NdTypeList]; [TkQuestion]
      [TkEphemeral; TkAliased] ]

class val PackageUse
  """
  A `use` of a package: an `NdUse` whose specifier is not an FFI
  declaration.
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

  fun alias(): (Node | None) =>
    """
    The `TkId` inside the `NdUseName` child.
    """
    match _Parts.unique(_node, NdUseName)
    | let n: Node => n.child(TkId)
    | None => None
    end

  fun locator(): (Node | None) =>
    """
    The first `TkString` child, since a guard may be a bare string and
    follows the locator; `None` when recovery left none.
    """
    _node.child(TkString)

  fun guard(): (Node | None) =>
    """
    The child after `TkIf`.
    """
    _Parts.after(_node, TkIf)

class val FfiDecl
  """
  A `use @` declaration: `node`, `span`, `alias` and `guard` read the
  `NdUse`; every other accessor reads its `NdUseFFI` child.
  """
  let _node: Node
  let _ffi: Node

  new val _create(node': Node, ffi': Node) =>
    _node = node'
    _ffi = ffi'

  fun node(): Node =>
    """
    The `NdUse`: the whole declaration.
    """
    _node

  fun _body(): Node =>
    """
    The `NdUseFFI` child.
    """
    _ffi

  fun span(): diag.Span =>
    """
    The whole declaration's span.
    """
    _node.span()

  fun alias(): (Node | None) =>
    """
    The `TkId` inside the `NdUseName` child.
    """
    match _Parts.unique(_node, NdUseName)
    | let n: Node => n.child(TkId)
    | None => None
    end

  fun guard(): (Node | None) =>
    """
    The child after `TkIf`.
    """
    _Parts.after(_node, TkIf)

  fun name(): (Node | None) =>
    """
    The `TkId` or `TkString` leaf after `TkAt`.
    """
    match _Parts.after(_ffi, TkAt)
    | let n: Node =>
      match n.kind()
      | TkId | TkString => n
      else
        None
      end
    | None => None
    end

  fun symbol(): (String | None) =>
    """
    The name's text, a string literal decoded.
    """
    match name()
    | let n: Node =>
      if n.kind() is TkString then StringLiteralValue.of(n) else n.text() end
    | None => None
    end

  fun return_type_args(): Array[FfiReturnArg] val =>
    """
    The `NdTypeArgs` child's arguments, each with the annotation group
    after it; ponyc's syntax pass allows one argument.
    """
    let out = recover iso Array[FfiReturnArg] end
    match _Parts.unique(_ffi, NdTypeArgs)
    | let args: Node =>
      var arg: (Node | None) = None
      var annotations: (Node | None) = None
      for c in args.children() do
        match c.kind()
        | TkLsquare | TkLsquareNew | TkRsquare | TkWhitespace
        | TkLineComment | TkNestedComment | NdError => None
        | NdAnnotations => if arg isnt None then annotations = c end
        | TkComma =>
          match arg
          | let a: Node => out.push(FfiReturnArg._create(a, annotations))
          end
          arg = None
          annotations = None
        else
          arg = c
        end
      end
      match arg
      | let a: Node => out.push(FfiReturnArg._create(a, annotations))
      end
    end
    consume out

  fun params(): Array[ParamDecl] val =>
    """
    The `NdParam` children of the `NdParams` child; empty for `()` and
    for a missing `(`.
    """
    _ParamsOf(_Parts.unique(_ffi, NdParams))

  fun has_ellipsis(): Bool =>
    """
    Whether a `TkEllipsis` leaf sits inside the `NdParams` child.
    """
    _HasEllipsis(_Parts.unique(_ffi, NdParams))

  fun is_partial(): Bool =>
    """
    Whether the `TkQuestion` child is there.
    """
    _Parts.has(_ffi, TkQuestion)

class val FfiReturnArg
  """
  One return type argument of an FFI declaration, with the annotation
  group ponyc's `ffi_ret_typearg` allows after it; ponyc prints the
  annotation inside the nominal.
  """
  let _node: Node
  let _annotations: (Node | None)

  new val _create(node': Node, annotations': (Node | None)) =>
    _node = node'
    _annotations = annotations'

  fun span(): diag.Span =>
    """
    From the argument's start through its annotation group.
    """
    match _annotations
    | let a: Node =>
      diag.Span(_node.span().dir, _node.span().name, _node.offset(),
        a.finish() - _node.offset())
    | None => _node.span()
    end

  fun type_arg(): (TypeArg | None) =>
    """
    The argument classified.
    """
    _TypeArgOf(_node)

  fun annotations(): (Node | None) =>
    """
    The `NdAnnotations` sibling after the argument.
    """
    _annotations

class val EntityDecl
  """
  An `NdClassDef`: a type alias, interface, trait, primitive, struct,
  class or actor.
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

  fun keyword(): TokenKind =>
    """
    The entity keyword, the first token.
    """
    _FirstToken(_node)

  fun annotations(): (Node | None) =>
    """
    The `NdAnnotations` child.
    """
    _Parts.unique(_node, NdAnnotations)

  fun is_c_api(): Bool =>
    """
    Whether the `TkAt` child is there.
    """
    _Parts.has(_node, TkAt)

  fun cap(): (TokenKind | None) =>
    """
    The capability leaf child; the provides type is inside
    `NdProvides`, so there is at most one.
    """
    _Parts.leaf(_node, _TokenSets.caps())

  fun name(): (Node | None) =>
    """
    The `TkId` child; annotation names are inside `NdAnnotations`.
    """
    _Parts.unique(_node, TkId)

  fun type_params(): Array[TypeParamDecl] val =>
    """
    The `NdTypeParam` children of the `NdTypeParams` child.
    """
    _TypeParamsOf(_Parts.unique(_node, NdTypeParams))

  fun provides(): (TypeExpr | None) =>
    """
    The `NdProvides` child's type, after its `TkIs`, classified.
    """
    match _Parts.unique(_node, NdProvides)
    | let p: Node =>
      match _Parts.after(p, TkIs)
      | let t: Node => TypeOf(t)
      | None => None
      end
    | None => None
    end

  fun docstring(): (Node | None) =>
    """
    The `TkString` child; an entity has no other string position.
    """
    _Parts.unique(_node, TkString)

  fun members(): Array[MemberDecl] val =>
    """
    The `NdField` and `NdMethod` children of the `NdMembers` child, in
    order, `NdError` children skipped.
    """
    let out = recover iso Array[MemberDecl] end
    match _Parts.unique(_node, NdMembers)
    | let list: Node =>
      for c in list.children() do
        match c.kind()
        | NdField => out.push(FieldDecl._create(c))
        | NdMethod => out.push(MethodDecl._create(c))
        end
      end
    end
    consume out

class val FieldDecl
  """
  An `NdField`.
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

  fun keyword(): TokenKind =>
    """
    `TkVar`, `TkLet` or `TkEmbed`, the first token.
    """
    _FirstToken(_node)

  fun name(): (Node | None) =>
    """
    The `TkId` child; an initialiser's identifier is inside an `NdRef`.
    """
    _Parts.unique(_node, TkId)

  fun declared_type(): (TypeExpr | None) =>
    """
    The child after `TkColon`, classified.
    """
    _TypeAfter(_node, TkColon)

  fun initialiser(): (Node | None) =>
    """
    The child after `TkAssign`.
    """
    _Parts.after(_node, TkAssign)

  fun docstring(): (Node | None) =>
    """
    After `TkAssign`, the second significant child when it is a
    `TkString`; without `TkAssign`, the `TkString` child.
    """
    if _Parts.has(_node, TkAssign) then
      var after_assign = false
      var seen: USize = 0
      for c in _node.children() do
        if after_assign then
          if c.is_trivia() or (c.kind() is NdError) then continue end
          seen = seen + 1
          if seen == 2 then
            return if c.kind() is TkString then c else None end
          end
        elseif c.kind() is TkAssign then
          after_assign = true
        end
      end
      None
    else
      _Parts.unique(_node, TkString)
    end

class val MethodDecl
  """
  An `NdMethod`: a function, behaviour or constructor.
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

  fun keyword(): TokenKind =>
    """
    `TkFun`, `TkBe` or `TkNew`, the first token.
    """
    _FirstToken(_node)

  fun annotations(): (Node | None) =>
    """
    The `NdAnnotations` child.
    """
    _Parts.unique(_node, NdAnnotations)

  fun cap(): (TokenKind | None) =>
    """
    The capability or `TkAt` leaf child before any `TkColon`: a
    bare-capability return type sits after the colon, and the name may
    be missing.
    """
    _Parts.leaf_before(_node, _TokenSets.caps_or_at(), [TkColon])

  fun name(): (Node | None) =>
    """
    The `TkId` child; parameters are inside `NdParams` and the body
    inside `NdSeq`.
    """
    _Parts.unique(_node, TkId)

  fun type_params(): Array[TypeParamDecl] val =>
    """
    The `NdTypeParam` children of the `NdTypeParams` child.
    """
    _TypeParamsOf(_Parts.unique(_node, NdTypeParams))

  fun params(): Array[ParamDecl] val =>
    """
    The `NdParam` children of the `NdParams` child; empty for `()` and
    for a missing `(`.
    """
    _ParamsOf(_Parts.unique(_node, NdParams))

  fun has_ellipsis(): Bool =>
    """
    Whether a `TkEllipsis` leaf sits inside the `NdParams` child.
    """
    _HasEllipsis(_Parts.unique(_node, NdParams))

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

  fun docstring(): (Node | None) =>
    """
    The `TkString` child, the string before `=>`; else the body's first
    significant child when it is a `TkString` leaf and, for a method
    that is not `returns_none`, a later significant child other than
    `TkSemi` exists anywhere in the body. This is ponyc's
    `sugar_docstring` rule: it takes a leading string literal with a
    sibling, and `fun_defaults` has appended `None` to the body of a
    `fun` whose return type is `None` or absent just before it runs,
    so `fun f() => "s"` has the docstring `"s"`, `fun f(): U8 => "s"`
    and `be f() => "s"` have none, and `fun f(): U8 => "s"; 2` has it.
    """
    match _Parts.unique(_node, TkString)
    | let s: Node => return s
    end
    match body()
    | let b: Node =>
      var first: (Node | None) = None
      for c in b.children() do
        if c.is_trivia() or (c.kind() is NdError) then continue end
        match first
        | None =>
          if c.kind() is TkString then first = c else return None end
          if returns_none() then return first end
        | let s: Node =>
          if c.kind() isnt TkSemi then return s end
        end
      end
      None
    | None => None
    end

  fun returns_none(): Bool =>
    """
    Whether this is a `fun` whose return type is absent or a nominal
    type named `None`, the methods ponyc's `fun_defaults` appends
    `None` to the body of.
    """
    if keyword() isnt TkFun then return false end
    match return_type()
    | None => true
    | let n: NominalType =>
      match n.name()
      | let id: Node => id.text() == "None"
      | None => false
      end
    else
      false
    end

  fun body(): (Node | None) =>
    """
    The `NdSeq` child.
    """
    _Parts.unique(_node, NdSeq)

class val ParamDecl
  """
  An `NdParam` of a method or an FFI declaration.
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

  fun name(): (Node | None) =>
    """
    The `TkId` child.
    """
    _Parts.unique(_node, TkId)

  fun declared_type(): (TypeExpr | None) =>
    """
    The child after `TkColon`, classified.
    """
    _TypeAfter(_node, TkColon)

  fun annotations(): (Node | None) =>
    """
    The `NdAnnotations` child, which only an FFI parameter has.
    """
    _Parts.unique(_node, NdAnnotations)

  fun default_value(): (Node | None) =>
    """
    The `NdDefaultArg` child.
    """
    _Parts.unique(_node, NdDefaultArg)

class val TypeParamDecl
  """
  An `NdTypeParam`.
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

  fun name(): (Node | None) =>
    """
    The `TkId` child.
    """
    _Parts.unique(_node, TkId)

  fun constraint(): (TypeExpr | None) =>
    """
    The child after `TkColon`, classified.
    """
    _TypeAfter(_node, TkColon)

  fun default(): (TypeArg | None) =>
    """
    The child after `TkAssign`, classified.
    """
    match _Parts.after(_node, TkAssign)
    | let n: Node => _TypeArgOf(n)
    | None => None
    end

primitive _FirstToken
  """
  The kind of a node's first token, for the nodes the grammar opens
  with a keyword it has already matched.
  """
  fun apply(node: Node): TokenKind =>
    match node.first_token()
    | let t: TokenKind => t
    | None => _Unreachable(); TkEof
    end

primitive _TypeAfter
  fun apply(node: Node, delimiter: TokenKind): (TypeExpr | None) =>
    match _Parts.after(node, delimiter)
    | let n: Node => TypeOf(n)
    | None => None
    end

primitive _ParamsOf
  fun apply(list: (Node | None)): Array[ParamDecl] val =>
    let out = recover iso Array[ParamDecl] end
    match list
    | let l: Node =>
      for c in _Parts.each(l, NdParam).values() do
        out.push(ParamDecl._create(c))
      end
    end
    consume out

primitive _HasEllipsis
  fun apply(list: (Node | None)): Bool =>
    match list
    | let l: Node => _Parts.has(l, TkEllipsis)
    | None => false
    end

primitive _TypeParamsOf
  fun apply(list: (Node | None)): Array[TypeParamDecl] val =>
    let out = recover iso Array[TypeParamDecl] end
    match list
    | let l: Node =>
      for c in _Parts.each(l, NdTypeParam).values() do
        out.push(TypeParamDecl._create(c))
      end
    end
    consume out
