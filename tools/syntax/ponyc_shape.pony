use parse = "../../hefermotor/parse"

primitive _PonycShape
  """
  A file's items and types in the shape `ponyc --pass=parse
  --astpackage` prints a module in, read through the views, so that
  `tools/syntax/agree.py` can compare the two after normalising both.
  The module starts with a sentinel line `;; <file name>` and is one
  S-expression: `(module DOC? USE* ENTITY*)`, an absent part printed
  as `x` except the package docstring, which prints nothing, a string
  as its decoded value with `"`, `\` and NUL escaped
  as ponyc's `token_print_escaped` does and every other byte raw. An
  expression slot (a use guard, a field value, a default argument, a
  method body) prints the presence marker `(seq ...)`, or
  `(seq "<text>" ...)` for a body whose first expression is a string
  literal with something after it and whose docstring slot is empty,
  since that is the string ponyc's `sugar_docstring` moves; `<text>`
  is the literal's value through `StringLiteralValue`. A value type
  argument prints `value`, or `(value \annotation ...\)` with an
  annotation group. An empty member list prints `members`, as ponyc
  prints it.
  """
  fun apply(tree: parse.SyntaxTree): String val =>
    recover val
      let out = String
      out.append(";; " + tree.file.name + "\n(module")
      // ponyc prints no slot for an absent package docstring.
      match tree.docstring()
      | let d: parse.Node => _string(out, d)
      end
      for u in tree.use_commands().values() do
        match u
        | let l: parse.PackageUse => _use(out, l)
        | let d: parse.FfiDecl => _ffi(out, d)
        end
      end
      for e in tree.entities().values() do _entity(out, e) end
      out.append(")\n")
      out
    end

  fun _use(out: String ref, u: parse.PackageUse) =>
    out.append(" (use")
    _id(out, u.alias())
    _opt_string(out, u.locator())
    _marker(out, u.guard())
    out.append(")")

  fun _ffi(out: String ref, d: parse.FfiDecl) =>
    out.append(" (use")
    _id(out, d.alias())
    out.append(" (ffidecl")
    match d.name()
    | let n: parse.Node =>
      if n.kind() is parse.TkString then _string(out, n) else _id(out, n) end
    | None => out.append(" x")
    end
    out.append(" (typeargs")
    for r in d.return_type_args().values() do
      _type_arg(out, r.type_arg(), r.annotations())
    end
    out.append(")")
    _params(out, d.params(), d.has_ellipsis())
    // ponyc's named-arguments slot, then the partial marker.
    out.append(" x")
    out.append(if d.is_partial() then " ?" else " x" end)
    out.append(")")
    _marker(out, d.guard())
    out.append(")")

  fun _entity(out: String ref, e: parse.EntityDecl) =>
    out.append(" (" + _Fixed(e.keyword()))
    _annotations(out, e.annotations())
    _id(out, e.name())
    _type_params(out, e.type_params())
    _opt_token(out, e.cap())
    match e.provides()
    | let t: parse.TypeExpr =>
      out.append(" (provides")
      _type(out, t)
      out.append(")")
    | None => out.append(" x")
    end
    let members = e.members()
    if members.size() == 0 then
      out.append(" members")
    else
      out.append(" (members")
      for m in members.values() do
        match m
        | let f: parse.FieldDecl => _field(out, f)
        | let md: parse.MethodDecl => _method(out, md)
        end
      end
      out.append(")")
    end
    out.append(if e.is_c_api() then " @" else " x" end)
    _opt_string(out, e.docstring())
    out.append(")")

  fun _field(out: String ref, f: parse.FieldDecl) =>
    out.append(
      match f.keyword()
      | parse.TkVar => " (fvar"
      | parse.TkLet => " (flet"
      else
        " (embed"
      end)
    _id(out, f.name())
    _type(out, f.declared_type())
    _marker(out, f.initialiser())
    _opt_string(out, f.docstring())
    out.append(")")

  fun _method(out: String ref, m: parse.MethodDecl) =>
    out.append(" (" + _Fixed(m.keyword()))
    _annotations(out, m.annotations())
    _opt_token(out, m.cap())
    _id(out, m.name())
    _type_params(out, m.type_params())
    _params(out, m.params(), m.has_ellipsis())
    _type(out, m.return_type())
    out.append(if m.is_partial() then " ?" else " x" end)
    // The string before `=>` is what ponyc's parse pass puts in the
    // docstring slot; the body's leading string is the marker's.
    let slot = m.node().child(parse.TkString)
    _body(out, m.body(), slot)
    _opt_string(out, slot)
    out.append(")")

  fun _body(out: String ref, body: (parse.Node | None),
    slot: (parse.Node | None))
  =>
    match body
    | let b: parse.Node =>
      var first: (parse.Node | None) = None
      var continues = false
      for c in b.children() do
        if c.is_trivia() or (c.kind() is parse.NdError) then continue end
        match first
        | None =>
          if c.kind() is parse.TkString then first = c else break end
        | let _: parse.Node =>
          continues = true
          break
        end
      end
      match first
      | let s: parse.Node if continues and (slot is None) =>
        out.append(" (seq")
        _string(out, s)
        out.append(" ...)")
      else
        out.append(" (seq ...)")
      end
    | None => out.append(" x")
    end

  fun _params(out: String ref, params: Array[parse.ParamDecl] val,
    ellipsis: Bool)
  =>
    if (params.size() == 0) and (not ellipsis) then
      out.append(" x")
      return
    end
    out.append(" (params")
    for p in params.values() do
      out.append(" (param")
      _annotations(out, p.annotations())
      _id(out, p.name())
      _type(out, p.declared_type())
      _marker(out, p.default_value())
      out.append(")")
    end
    if ellipsis then out.append(" ...") end
    out.append(")")

  fun _type_params(out: String ref, tps: Array[parse.TypeParamDecl] val) =>
    if tps.size() == 0 then
      out.append(" x")
      return
    end
    out.append(" (typeparams")
    for tp in tps.values() do
      out.append(" (typeparam")
      _id(out, tp.name())
      _type(out, tp.constraint())
      _type_arg(out, tp.default(), None)
      out.append(")")
    end
    out.append(")")

  fun _type(out: String ref, t: (parse.TypeExpr | None),
    annotations: (parse.Node | None) = None)
  =>
    """
    ponyc prints an FFI return type argument's annotation group inside
    the type, after its head; a childless `thistype` or capability
    becomes a node to hold it.
    """
    match t
    | None => out.append(" x")
    | let n: parse.NominalType => _nominal(out, n, annotations)
    | let u: parse.UnionType =>
      _pairs(out, "uniontype", u.members(), annotations)
    | let i: parse.IsectType => _pairs(out, "&", i.members(), annotations)
    | let tu: parse.TupleType =>
      out.append(" (tupletype")
      _annotations(out, annotations)
      for m in tu.members().values() do _type(out, m) end
      out.append(")")
    | let v: parse.ViewpointType =>
      out.append(" (->")
      _annotations(out, annotations)
      _type(out, v.left())
      _type(out, v.right())
      out.append(")")
    | let _: parse.ThisType => _atom(out, "thistype", annotations)
    | let c: parse.CapType => _atom(out, _Fixed(c.cap()), annotations)
    | let l: parse.LambdaType => _lambda(out, l, annotations)
    end

  fun _atom(out: String ref, text: String, annotations: (parse.Node | None))
  =>
    match annotations
    | None => out.append(" " + text)
    | let a: parse.Node =>
      out.append(" (" + text)
      _annotations(out, a)
      out.append(")")
    end

  fun _nominal(out: String ref, n: parse.NominalType,
    annotations: (parse.Node | None))
  =>
    out.append(" (nominal")
    _annotations(out, annotations)
    _id(out, n.package())
    _id(out, n.name())
    let args = n.type_args()
    if args.size() == 0 then
      out.append(" x")
    else
      out.append(" (typeargs")
      for a in args.values() do _type_arg(out, a, None) end
      out.append(")")
    end
    _opt_token(out, n.cap())
    _opt_token(out, n.ephemeral())
    out.append(")")

  fun _type_arg(out: String ref, a: (parse.TypeArg | None),
    annotations: (parse.Node | None))
  =>
    """
    A type argument with the annotation group an FFI return type
    argument may carry.
    """
    match a
    | None => out.append(" x")
    | let _: parse.ValueArg => _atom(out, "value", annotations)
    | let t: parse.TypeExpr => _type(out, t, annotations)
    end

  fun _pairs(out: String ref, head: String,
    members: Array[parse.TypeExpr] val, annotations: (parse.Node | None))
  =>
    """
    A flat run printed as ponyc's left-nested pairs: `A | B | C` is
    `(uniontype (uniontype A B) C)`, an annotation group after the
    outermost head. A grouped inner run is a member and prints as its
    own pair, which is what ponyc prints for `A | (B | C)`. A run of
    one member prints as `(head A)`, a shape ponyc never prints, so
    that a lost operand shows.
    """
    var i: USize = 1
    while i < members.size() do
      out.append(" (" + head)
      if i == 1 then _annotations(out, annotations) end
      i = i + 1
    end
    if members.size() < 2 then
      out.append(" (" + head)
      _annotations(out, annotations)
    end
    try _type(out, members(0)?) end
    i = 1
    while i < members.size() do
      try _type(out, members(i)?) end
      out.append(")")
      i = i + 1
    end
    if members.size() < 2 then out.append(")") end

  fun _lambda(out: String ref, l: parse.LambdaType,
    annotations: (parse.Node | None))
  =>
    out.append(if l.is_bare() then " (barelambdatype" else " (lambdatype" end)
    _annotations(out, annotations)
    _opt_token(out, l.receiver_cap())
    _id(out, l.name())
    _type_params(out, l.type_params())
    let types = l.param_types()
    if types.size() == 0 then
      out.append(" x")
    else
      out.append(" (params")
      for t in types.values() do _type(out, t) end
      out.append(")")
    end
    _type(out, l.return_type())
    out.append(if l.is_partial() then " ?" else " x" end)
    _opt_token(out, l.cap())
    _opt_token(out, l.ephemeral())
    out.append(")")

  fun _annotations(out: String ref, group: (parse.Node | None)) =>
    match group
    | let g: parse.Node =>
      out.append(" \\annotation")
      for c in g.children() do
        if c.kind() is parse.TkId then out.append(" (id " + c.text() + ")") end
      end
      out.append("\\")
    | None => None
    end

  fun _id(out: String ref, n: (parse.Node | None)) =>
    match n
    | let node: parse.Node => out.append(" (id " + node.text() + ")")
    | None => out.append(" x")
    end

  fun _opt_token(out: String ref, t: (parse.TokenKind | None)) =>
    match t
    | let k: parse.TokenKind => out.append(" " + _Fixed(k))
    | None => out.append(" x")
    end

  fun _opt_string(out: String ref, n: (parse.Node | None)) =>
    match n
    | let node: parse.Node => _string(out, node)
    | None => out.append(" x")
    end

  fun _string(out: String ref, n: parse.Node) =>
    out.append(" \"")
    for b in parse.StringLiteralValue.of(n).values() do
      match b
      | '"' => out.append("\\\"")
      | '\\' => out.append("\\\\")
      | 0 => out.append("\\0")
      else
        out.push(b)
      end
    end
    out.push('"')

  fun _marker(out: String ref, n: (parse.Node | None)) =>
    out.append(if n is None then " x" else " (seq ...)" end)

primitive _Fixed
  """
  A token kind's fixed text, for the kinds ponyc prints as themselves.
  """
  fun apply(k: parse.TokenKind): String =>
    match k.text()
    | let t: String => t
    | None => _Unreachable(); ""
    end
