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

primitive _Module
  """
  ponyc's `module`: an optional package docstring, then use commands and
  entity declarations, to the end of the source.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdModule)

    if p.at(TkString) then
      p.bump()
    end

    while not p.eof() do
      if p.at(TkUse) then
        _Use(p)
      elseif p.at_any(_TokenSets.entities()) then
        _ClassDef(p)
      else
        p.error_and_recover(
          "use command or type, interface, trait, primitive, class or " +
            "actor definition",
          _TokenSets.top_level())
      end
    end

    // ponyc's module ends with SKIP(TK_EOF). Emitting it matters here for a
    // second reason: `bump` flushes pending trivia first, so this is what
    // puts a trailing newline inside the module rather than after it.
    p.bump()
    p.finish()

primitive _Use
  """
  ponyc's `use`: `use [name =] (uri | ffi) [if condition]`.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdUse)
    p.bump()

    // ponyc's `use_name` is optional on its first token only: once an
    // identifier is there, the `=` is required, and without it ponyc
    // fails the use and resumes at the next top-level keyword, which
    // the section loop takes.
    if p.at(TkId) then
      p.start(NdUseName)
      p.bump()
      let assigned = p.expect(TkAssign, "=")
      p.finish()
      if (not assigned) and
        (p.eof() or p.at_any(_TokenSets.top_level()))
      then
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
  ponyc's `use_ffi`: `@name[ReturnType](params) [?]`.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdUseFFI)
    p.bump()
    p.expect_any([TkId; TkString], "ffi name")
    if p.at(TkLsquare) then
      _TypeArgs(p)
    else
      p.expected("return type")
    end
    p.expect_any(_TokenSets.lparen(), "(")
    if p.at(TkId) or p.at(TkEllipsis) then
      _Params(p)
    end
    p.expect(TkRparen, ")")
    if p.at(TkQuestion) then
      p.bump()
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
    // fold range a line too long.
    if not (p.eof() or p.at_any(_TokenSets.top_level())) then
      _Members(p)
    end

    p.finish()

primitive _Annotations
  """
  ponyc's `annotations`: `\\name[, name]*\\`.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdAnnotations)
    p.bump()
    p.expect(TkId, "annotation")
    while p.at(TkComma) do
      p.bump()
      p.expect(TkId, "annotation")
    end
    p.expect(TkBackslash, "\\")
    p.finish()

primitive _Members
  """
  The fields and methods of an entity, to the start of the next item.

  ponyc requires every field to precede every method and rejects a source
  where one does not. This accepts them in any order and leaves the
  ordering rule to whatever checks the tree.
  """
  fun apply(p: _Parser ref) =>
    p.start(NdMembers)
    while not (p.eof() or p.at(TkEnd) or p.at_any(_TokenSets.top_level())) do
      if p.at_any(_TokenSets.field_start()) then
        _Field(p)
      elseif p.at_any(_TokenSets.method_start()) then
        _Method(p)
      else
        p.error_and_recover(
          "field or method", _TokenSets.member_or_top_level())
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
