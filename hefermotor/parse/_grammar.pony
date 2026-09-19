use diag = "../diagnostics"
use source = "../source"

// Pony's item grammar, ported rule for rule from ponyc's parser.c: module,
// use, entity declarations, members, methods, fields and parameters.
//
// Method bodies, field values, default arguments and use conditions are
// expressions, and `expr_grammar.pony` has those rules.

primitive _ParseModule
  """
  Parse a file into a tree, with what the parser recorded.

  Never fails, whatever the input. What cannot be interpreted becomes an
  `NdError` node bounded by the next item, and parsing continues.
  """
  fun apply(file: source.SourceFile)
    : (SyntaxTree val, Array[diag.Diagnostic] val)
  =>
    let p = _Parser(file)
    _Module(p)
    p.build()

primitive _What
  """
  The two nouns hefermotor reports at the module's recovery sites,
  each taken from ponyc's `module` descriptions.
  """
  fun use_section(): String val =>
    """
    ponyc's two `SEQ` descriptions in `module`, since the section
    accepts either.
    """
    "use command or type, interface, trait, primitive, class or actor " +
      "definition"

  fun module(): String val =>
    """
    ponyc's `SKIP` description at the end of `module`.
    """
    "type, interface, trait, primitive, class, actor, member or method"

primitive _Module
  """
  ponyc's `module`: the package docstring and use section
  (`_ModulePrefix`), then entity declarations to the end of the
  source.
  """
  fun apply(p: _Parser ref) =>
    _ModulePrefix(p)
    while not p.eof() do
      if p.at_any(_TokenSets.entities()) then
        _ClassDef(p)
      else
        // Unreachable while the use section and every member list
        // leave the cursor at an entity keyword or the end; kept so
        // that the loop cannot spin if one of them changes.
        p.error_and_recover(_What.module(), _TokenSets.entities())
      end
    end
    // ponyc's module ends with SKIP(TK_EOF). Emitting it matters here for a
    // second reason: `bump` flushes pending trivia first, so this is what
    // puts a trailing newline inside the module rather than after it.
    p.bump()
    p.finish()

primitive _ModulePrefix
  """
  The part of a module before its first entity: the package docstring
  and the use section. Opens the module and leaves it open, so that a
  caller can stop after the prefix or go on to the entities.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdModule)
    if p.at(TkString) then
      p.bump()
    end
    _UseSection(p)

primitive _UseSection
  """
  ponyc's `{use}`, ending only at an entity keyword or the end of the
  source: anything else that is not `use` is reported and skipped
  here, as ponyc's `use` restart check reports and skips it.
  """
  fun apply(p: _Parser ref) =>
    while not (p.eof() or p.at_any(_TokenSets.entities())) do
      if p.at(TkUse) then
        _Use(p)
      else
        p.error_and_recover(_What.use_section(), _TokenSets.top_level())
      end
    end

primitive _Use
  """
  ponyc's `use`: `use [name =] (uri | ffi) [if condition]`. Commits after
  the name, as ponyc's `use_name` does: once an identifier is there the
  `=` is required, and without it the rest of the command up to the
  next top-level keyword is an error item of the `use`, so a malformed
  command yields no locator rather than taking the next string as one.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdUse)
    p.bump()

    if p.at(TkId) then
      p.start(NdUseName)
      p.bump()
      let assigned = p.expect(TkAssign, "=")
      p.finish()
      if not assigned then
        // `expect` recorded the expectation; `skip_to` opens no error
        // node when the next token is already a top-level keyword.
        p.skip_to(_TokenSets.top_level())
        p.finish()
        return
      end
    end

    if p.at(TkString) then
      p.bump()
    elseif p.at(TkAt) then
      _UseFFI(p)
    else
      p.error_and_recover("specifier", _TokenSets.top_level())
    end

    if p.at(TkIf) then
      p.bump()
      _Infix(p, _ExprNormal, "use condition")
    end

    p.finish()

primitive _UseFFI
  """
  ponyc's `use_ffi`: `@name[ReturnType](params) [?]`, where the return
  type arguments and the parameters each take an annotation after
  them, which `_TypeArgs` and `_Params` do not accept.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdUseFFI)
    p.bump()
    p.expect_any([TkId; TkString], "ffi name")
    if p.at(TkLsquare) then
      _FfiRetTypeArgs(p)
    else
      p.expected("return type")
    end
    p.expect_any(_TokenSets.lparen(), "(")
    // ponyc's `OPT RULE("ffi parameters", ffi_params)`: entered only
    // where a parameter can start.
    if p.at(TkId) or p.at(TkEllipsis) then
      _FfiParams(p)
    end
    p.expect(TkRparen, ")")
    if p.at(TkQuestion) then
      p.bump()
    end
    p.finish()

primitive _FfiRetTypeArgs
  """
  ponyc's `ffi_ret_typeargs`: `[T[, T]*]` with an optional annotation
  after each type argument.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdTypeArgs)
    let opener = p.open()
    p.bump()
    _TypeArg(p, "type argument")
    _Annotated(p)
    while p.at(TkComma) do
      p.bump()
      _TypeArg(p, "type argument")
      _Annotated(p)
    end
    p.close(opener, TkRsquare, "type arguments")
    p.finish()

primitive _FfiParams
  """
  ponyc's `ffi_params`: `ffi_param[, ffi_param]*`, where a param may be
  `...`.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdParams)
    _FfiParam(p)
    while p.at(TkComma) do
      p.bump()
      _FfiParam(p)
    end
    p.finish()

primitive _FfiParam
  """
  ponyc's `ffi_param`: `name: Type [annotation] [= default]`, or an
  ellipsis.
  """
  fun apply(p: _Parser ref) =>
    if p.at(TkEllipsis) then
      p.bump()
      return
    end
    p.start(NdParam)
    p.expect(TkId, "parameter")
    p.expect(TkColon, "mandatory type declaration on parameter")
    _TypeRule(p, "parameter type")
    _Annotated(p)
    if p.at(TkAssign) then
      _DefaultArg(p)
    end
    p.finish()

primitive _ClassDef
  """
  ponyc's `class_def`: an entity keyword, then its name, type parameters,
  provides list, docstring and members.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdClassDef)
    p.bump()

    if p.at(TkBackslash) then
      _Annotations(p)
    end
    if p.at(TkAt) then
      p.bump()
    end
    if p.at_any(_TokenSets.caps()) then
      p.bump()
    end

    p.expect(TkId, "name")

    if p.at_any(_TokenSets.lsquare()) then
      _TypeParams(p)
    end

    if p.at(TkIs) then
      p.start(NdProvides)
      p.bump()
      _TypeRule(p, "provided type")
      p.finish()
    end

    if p.at(TkString) then
      p.bump()
    end

    // Only when there is something to put in it. A node opened before
    // anything is consumed takes the trivia that precede it, which would
    // put the blank line after a member-less entity inside it and make its
    // fold range a line too long. A `use` here is the list's first
    // error item, not a top-level item, so the members after it are
    // still this entity's.
    if not (p.eof() or p.at_any(_TokenSets.entities())) then
      _Members(p, _InEntity)
    end

    p.finish()

primitive _Annotations
  """
  ponyc's `annotations`: `\\name[, name]*\\`.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdAnnotations)
    let opener = p.open()
    p.bump()
    p.expect(TkId, "annotation")
    while p.at(TkComma) do
      p.bump()
      p.expect(TkId, "annotation")
    end
    p.close(opener, TkBackslash, "annotations")
    p.finish()

primitive _InEntity
  """
  A member list under an entity: it ends at the next entity or the end
  of the source, and takes a stray `end` or `use` as an error item.
  """
  fun ends_at(): Array[TokenKind] val => _TokenSets.entities()
  fun resync(): Array[TokenKind] val => _TokenSets.member_or_entity()
  fun what(): String val => "field or method"

primitive _InObject
  """
  A member list in an object literal: it ends at the literal's `end`
  as well as at the next entity or the end of the source.
  """
  fun ends_at(): Array[TokenKind] val => _TokenSets.entities_or_end()
  fun resync(): Array[TokenKind] val => _TokenSets.member_or_entity_or_end()
  fun what(): String val => "field, method or end"

type _MembersContext is (_InEntity | _InObject)

primitive _Members
  """
  ponyc's `members`: the fields and then the methods of an entity or an
  object literal, to where `ctx` says the list ends. A field after a
  method is reported at its keyword, where ponyc's restart check
  reports it in an entity, and parsed as a field.
  """
  fun apply(p: _Parser ref, ctx: _MembersContext) =>
    p.start(NdMembers)
    var method_seen = false
    while not (p.eof() or p.at_any(ctx.ends_at())) do
      if p.at_any(_TokenSets.field_start()) then
        if method_seen then
          p.expected("method")
        end
        _Field(p)
      elseif p.at_any(_TokenSets.method_start()) then
        method_seen = true
        _Method(p)
      else
        p.error_and_recover(ctx.what(), ctx.resync())
      end
    end
    p.finish()

primitive _Field
  """
  ponyc's `field`: `(var | let | embed) name: Type [= value] [docstring]`.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdField)
    p.bump()
    p.expect(TkId, "field name")
    p.expect(TkColon, "mandatory type declaration on field")
    _TypeRule(p, "field type")
    if p.at(TkAssign) then
      p.bump()
      _Infix(p, _ExprNormal, "field value")
    end
    if p.at(TkString) then
      p.bump()
    end
    p.finish()

primitive _Method
  """
  ponyc's `method`: `(fun | be | new) [cap] name [typeparams](params)
  [: Type] [?] [docstring] [=> body]`.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdMethod)
    p.bump()

    if p.at(TkBackslash) then
      _Annotations(p)
    end
    if p.at_any(_TokenSets.caps()) or p.at(TkAt) then
      p.bump()
    end

    p.expect(TkId, "method name")

    if p.at_any(_TokenSets.lsquare()) then
      _TypeParams(p)
    end

    p.expect_any(_TokenSets.lparen(), "(")
    // ponyc's `OPT RULE("parameters", params)`: entered only where a
    // parameter can start.
    if p.at(TkId) or p.at(TkEllipsis) then
      _Params(p)
    end
    p.expect(TkRparen, ")")

    if p.at(TkColon) then
      p.bump()
      _TypeRule(p, "return type")
    end
    if p.at(TkQuestion) then
      p.bump()
    end
    if p.at(TkString) then
      p.bump()
    end
    if p.at(TkDblarrow) then
      p.bump()
      _RawSeq(p, "method body")
    end

    p.finish()

primitive _Params
  """
  ponyc's `params`: `param[, param]*`, where a param may be `...`.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdParams)
    _Param(p)
    while p.at(TkComma) do
      p.bump()
      _Param(p)
    end
    p.finish()

primitive _Param
  """
  ponyc's `param`: `name: Type [= default]`, or an ellipsis.
  """
  fun apply(p: _Parser ref) =>
    if p.at(TkEllipsis) then
      p.bump()
      return
    end

    p.start(NdParam)
    p.expect(TkId, "parameter")
    p.expect(TkColon, "mandatory type declaration on parameter")
    _TypeRule(p, "parameter type")
    if p.at(TkAssign) then
      _DefaultArg(p)
    end
    p.finish()
