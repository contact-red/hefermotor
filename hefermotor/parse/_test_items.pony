use "pony_test"

primitive \nodoc\ _ItemTests is TestList
  fun tag tests(test: PonyTest) =>
    test(_TestModuleShapes)
    test(_TestUseShapes)
    test(_TestUseFfiShapes)
    test(_TestEntityShapes)
    test(_TestFieldShapes)
    test(_TestMethodShapes)
    test(_TestStrayEnd)
    test(_TestUseInsideAnEntity)
    test(_TestObjectMembers)
    test(_TestFieldAfterMethod)
    test(_TestJunkBetweenUses)
    test(_TestFfiAnnotations)

primitive \nodoc\ _Skeleton
  """
  The tree as nested kind names with the trivia left out, so that an
  item's snapshot reads as its parts.
  """
  fun apply(tree: SyntaxTree val): String val =>
    _Shape(tree, false)

primitive \nodoc\ _Snapshot
  """
  Asserts a source's skeleton and reprint; that it parses clean when
  `clean`, and otherwise that `TreeCheck` finds nothing.
  """
  fun apply(h: TestHelper, src: String val, skeleton: String val,
    clean: Bool = true)
  =>
    let tree = _ParseText(src)
    h.assert_eq[String](skeleton, _Skeleton(tree), src)
    h.assert_eq[String](src, tree.reprint(), src + ": reprint")
    if clean then
      _Clean(h, tree, src)
    else
      for v in _Check(src).values() do h.fail(src + ": " + v.string()) end
    end

class \nodoc\ iso _TestModuleShapes is UnitTest
  fun name(): String => "parse/items: module"

  fun apply(h: TestHelper) =>
    """
    ponyc's `module`: an optional package docstring, use commands, then
    entities. `--astpackage` prints `(module:scope "Doc" (use ...)
    (class:scope ...))`; an empty file is a module with its end.
    """
    _Snapshot(h, "", "NdModule >TkEof")
    _Snapshot(h, "\"\"\"Doc\"\"\"\n", "NdModule >TkString >TkEof")
    _Snapshot(h, "\"\"\"Doc\"\"\"\nuse \"a\"\nclass C\n",
      "NdModule >TkString >NdUse >>TkUse >>TkString " +
      ">NdClassDef >>TkClass >>TkId >TkEof")
    // Junk before any item is the use section's, and the entity after
    // it is kept: ponyc reports `1:1: no code found` and stops.
    _Snapshot(h, "junk\nclass C\n",
      "NdModule >NdError >>TkId >NdClassDef >>TkClass >>TkId >TkEof",
      false)
    _Exactly(h, "junk\nclass C\n", [
      ("parse/expected", 0, "syntax error: expected use command or type, " +
        "interface, trait, primitive, class or actor definition, found " +
        "an identifier")
    ], "junk first")

class \nodoc\ iso _TestUseShapes is UnitTest
  fun name(): String => "parse/items: use"

  fun apply(h: TestHelper) =>
    """
    ponyc's `use`: `(use x "a" x)`, `(use (id c) "a" x)`, `(use x "a"
    (reference (id linux)))`. The error forms: `use = "a"` reports the
    specifier at the `=` (ponyc `1:5: expected specifier after use`),
    `use x "a"` the `=` at the string (`1:7: expected = after x`) with
    the string the command's error item, and `use` alone the specifier
    at the next command (`2:1: expected specifier after use`) with no
    error item, since the next token is already a command.
    """
    _Snapshot(h, "use \"a\"\n", "NdModule >NdUse >>TkUse >>TkString >TkEof")
    _Snapshot(h, "use c = \"a\"\n",
      "NdModule >NdUse >>TkUse >>NdUseName >>>TkId >>>TkAssign " +
      ">>TkString >TkEof")
    _Snapshot(h, "use \"a\" if linux\n",
      "NdModule >NdUse >>TkUse >>TkString >>TkIf >>NdRef >>>TkId >TkEof")
    _Snapshot(h, "use = \"a\"\n",
      "NdModule >NdUse >>TkUse >>NdError >>>TkAssign >>>TkString >TkEof",
      false)
    _Exactly(h, "use = \"a\"\n", [
      ("parse/expected", 4, "syntax error: expected specifier, found =")
    ], "no specifier")
    _Snapshot(h, "use x \"a\"\n",
      "NdModule >NdUse >>TkUse >>NdUseName >>>TkId >>NdError >>>TkString " +
      ">TkEof", false)
    _Snapshot(h, "use\nuse \"z\"\n",
      "NdModule >NdUse >>TkUse >NdUse >>TkUse >>TkString >TkEof", false)
    _Exactly(h, "use\nuse \"z\"\n", [
      ("parse/expected", 4, "syntax error: expected specifier, found use")
    ], "use alone")

class \nodoc\ iso _TestUseFfiShapes is UnitTest
  fun name(): String => "parse/items: use ffi"

  fun apply(h: TestHelper) =>
    """
    ponyc's `use_ffi`: `(ffidecl:scope (id f) (typeargs ...) (params
    (param (id x) (nominal ...) x) ...) x x)`, with `?` after the
    parameters and an annotation after a return type or a parameter;
    the name may be a string, the parameters an ellipsis alone. The
    error forms: no return type is reported at the `(` (ponyc `1:7:
    expected return type after f`), and a parameter with no type at
    the `)` (`1:13: expected mandatory type declaration on parameter
    after x`).
    """
    _Snapshot(h, "use @f[U8](x: U8, ...) ?\n",
      "NdModule >NdUse >>TkUse >>NdUseFFI >>>TkAt >>>TkId >>>NdTypeArgs " +
      ">>>>TkLsquare >>>>NdNominal >>>>>TkId >>>>TkRsquare >>>TkLparen " +
      ">>>NdParams >>>>NdParam >>>>>TkId >>>>>TkColon >>>>>NdNominal " +
      ">>>>>>TkId >>>>TkComma >>>>TkEllipsis >>>TkRparen >>>TkQuestion " +
      ">TkEof")
    _Snapshot(h, "use @f[P \\a\\](p: P \\b\\ = q)\n",
      "NdModule >NdUse >>TkUse >>NdUseFFI >>>TkAt >>>TkId >>>NdTypeArgs " +
      ">>>>TkLsquare >>>>NdNominal >>>>>TkId >>>>NdAnnotations " +
      ">>>>>TkBackslash >>>>>TkId >>>>>TkBackslash >>>>TkRsquare " +
      ">>>TkLparen >>>NdParams >>>>NdParam >>>>>TkId >>>>>TkColon " +
      ">>>>>NdNominal >>>>>>TkId >>>>>NdAnnotations >>>>>>TkBackslash " +
      ">>>>>>TkId >>>>>>TkBackslash >>>>>NdDefaultArg >>>>>>TkAssign " +
      ">>>>>>NdRef >>>>>>>TkId >>>TkRparen >TkEof")
    _Snapshot(h, "use @f[U8](...)\n",
      "NdModule >NdUse >>TkUse >>NdUseFFI >>>TkAt >>>TkId >>>NdTypeArgs " +
      ">>>>TkLsquare >>>>NdNominal >>>>>TkId >>>>TkRsquare >>>TkLparen " +
      ">>>NdParams >>>>TkEllipsis >>>TkRparen >TkEof")
    _Snapshot(h, "use @\"f\"[U8, U16]()\n",
      "NdModule >NdUse >>TkUse >>NdUseFFI >>>TkAt >>>TkString " +
      ">>>NdTypeArgs >>>>TkLsquare >>>>NdNominal >>>>>TkId >>>>TkComma " +
      ">>>>NdNominal >>>>>TkId >>>>TkRsquare >>>TkLparen >>>TkRparen " +
      ">TkEof")
    _Exactly(h, "use @f()\n", [
      ("parse/expected", 6, "syntax error: expected return type, found (")
    ], "no return type")
    _Exactly(h, "use @f[U8](x)\n", [
      ("parse/expected", 12, "syntax error: expected mandatory type " +
        "declaration on parameter, found )")
    ], "parameter without a type")

class \nodoc\ iso _TestEntityShapes is UnitTest
  fun name(): String => "parse/items: entity"

  fun apply(h: TestHelper) =>
    """
    ponyc's `class_def`: `(class:scope \\a\\ (id C) (typeparams ...) cap
    (provides ...) (members ...) @ "Doc")`, each part optional but the
    name, with the capability written before the name. An entity with
    nothing after its name has no member list. The error forms: no
    name is reported at what follows (ponyc `2:3: expected name after
    class`); junk after an entity's name is its member list's error
    item (`1:9: unexpected token ]`).
    """
    _Snapshot(h, "class C\n", "NdModule >NdClassDef >>TkClass >>TkId >TkEof")
    _Snapshot(h, "actor \\a\\ @ iso A[T] is B\n  \"\"\"Doc\"\"\"\n",
      "NdModule >NdClassDef >>TkActor >>NdAnnotations >>>TkBackslash " +
      ">>>TkId >>>TkBackslash >>TkAt >>TkIso >>TkId >>NdTypeParams " +
      ">>>TkLsquare >>>NdTypeParam >>>>TkId >>>TkRsquare >>NdProvides " +
      ">>>TkIs >>>NdNominal >>>>TkId >>TkString >TkEof")
    _Snapshot(h, "class\n  fun f() => 1\n",
      "NdModule >NdClassDef >>TkClass >>NdMembers >>>NdMethod >>>>TkFun " +
      ">>>>TkId >>>>TkLparen >>>>TkRparen >>>>TkDblarrow >>>>NdSeq " +
      ">>>>>TkInt >TkEof", false)
    _Exactly(h, "class\n  fun f() => 1\n", [
      ("parse/expected", 8, "syntax error: expected name, found fun")
    ], "no name")
    _Snapshot(h, "class C ]\n  fun f() => 1\n",
      "NdModule >NdClassDef >>TkClass >>TkId >>NdMembers >>>NdError " +
      ">>>>TkRsquare >>>NdMethod >>>>TkFun >>>>TkId >>>>TkLparen " +
      ">>>>TkRparen >>>>TkDblarrow >>>>NdSeq >>>>>TkInt >TkEof", false)
    _Exactly(h, "class C ]\n  fun f() => 1\n", [
      ("parse/expected", 8, "syntax error: expected field or method, " +
        "found ]")
    ], "junk after the name")

class \nodoc\ iso _TestFieldShapes is UnitTest
  fun name(): String => "parse/items: field"

  fun apply(h: TestHelper) =>
    """
    ponyc's `field`: `(flet (id x) (nominal ...) 1 "Doc")`, the value
    and the docstring optional; `var` and `embed` the same. The error
    form: no type is reported at what follows (ponyc `3:3: expected
    mandatory type declaration on field after x`).
    """
    _Snapshot(h, "class C\n  let x: U8\n",
      "NdModule >NdClassDef >>TkClass >>TkId >>NdMembers >>>NdField " +
      ">>>>TkLet >>>>TkId >>>>TkColon >>>>NdNominal >>>>>TkId >TkEof")
    _Snapshot(h, "class C\n  embed x: U8 = 1\n    \"\"\"Doc\"\"\"\n",
      "NdModule >NdClassDef >>TkClass >>TkId >>NdMembers >>>NdField " +
      ">>>>TkEmbed >>>>TkId >>>>TkColon >>>>NdNominal >>>>>TkId " +
      ">>>>TkAssign >>>>TkInt >>>>TkString >TkEof")
    _Exactly(h, "class C\n  var x\n  fun f() => 1\n", [
      ("parse/expected", 18, "syntax error: expected mandatory type " +
        "declaration on field, found fun")
    ], "no type")

class \nodoc\ iso _TestMethodShapes is UnitTest
  fun name(): String => "parse/items: method"

  fun apply(h: TestHelper) =>
    """
    ponyc's `method`: `(fun:scope \\a\\ cap (id f) (typeparams ...)
    (params ...) (nominal ...) ? (seq ...) "Doc")`, each part optional
    but the name and the parentheses; the capability slot takes `@`
    for a bare method. The error form: no name is
    reported at the `(` (ponyc `2:7: expected method name after fun`).
    """
    _Snapshot(h, "class C\n  fun f()\n",
      "NdModule >NdClassDef >>TkClass >>TkId >>NdMembers >>>NdMethod " +
      ">>>>TkFun >>>>TkId >>>>TkLparen >>>>TkRparen >TkEof")
    _Snapshot(h, "class C\n  fun @f()\n",
      "NdModule >NdClassDef >>TkClass >>TkId >>NdMembers >>>NdMethod " +
      ">>>>TkFun >>>>TkAt >>>>TkId >>>>TkLparen >>>>TkRparen >TkEof")
    _Snapshot(h, "class C\n  new \\a\\ ref f[T](x: T = 1): U8 ? =>\n" +
      "    \"\"\"Doc\"\"\"\n    2\n",
      "NdModule >NdClassDef >>TkClass >>TkId >>NdMembers >>>NdMethod " +
      ">>>>TkNew >>>>NdAnnotations >>>>>TkBackslash >>>>>TkId " +
      ">>>>>TkBackslash >>>>TkRef >>>>TkId >>>>NdTypeParams " +
      ">>>>>TkLsquare >>>>>NdTypeParam >>>>>>TkId >>>>>TkRsquare " +
      ">>>>TkLparen >>>>NdParams >>>>>NdParam >>>>>>TkId >>>>>>TkColon " +
      ">>>>>>NdNominal >>>>>>>TkId >>>>>>NdDefaultArg >>>>>>>TkAssign " +
      ">>>>>>>TkInt >>>>TkRparen >>>>TkColon >>>>NdNominal >>>>>TkId " +
      ">>>>TkQuestion >>>>TkDblarrow >>>>NdSeq >>>>>TkString >>>>>TkInt " +
      ">TkEof")
    _Exactly(h, "class C\n  fun ()\n", [
      ("parse/expected", 14, "syntax error: expected method name, found (")
    ], "no name")

class \nodoc\ iso _TestStrayEnd is UnitTest
  fun name(): String => "parse/items: a stray end costs one token"

  fun apply(h: TestHelper) =>
    """
    An `end` with nothing open, between two methods, is the member
    list's error item of one token, and both methods are members: ponyc
    reports `3:3: unexpected token end after type, interface, trait,
    primitive, class or actor definition` and skips the rest of the
    entity.
    """
    let src: String val = "class C\n  fun f() => 1\n  end\n  fun g() => 2\n"
    let tree = _ParseText(src)
    h.assert_eq[USize](2, _Find.count(tree, NdMethod))
    h.assert_eq[USize](1, _Find.count(tree, NdError))
    h.assert_eq[String]("end", _Find.text(h, tree, NdError))
    _Exactly(h, src, [
      ("parse/expected", 25, "syntax error: expected field or method, " +
        "found end")
    ], "stray end")

class \nodoc\ iso _TestUseInsideAnEntity is UnitTest
  fun name(): String => "parse/items: a use after an entity is an error item"

  fun apply(h: TestHelper) =>
    """
    A `use` between two members, after an entity's last member, or
    right after an entity's name is the member list's error item at
    the `use`, never a command, and the members after it are still the
    entity's: `class A\\nuse "b"\\n  fun g() => 1\\nclass B` keeps `g`
    as A's. ponyc reports the `use` at 3:3, 2:1 and 3:1 (`unexpected
    token use after type, interface, trait, primitive, class or actor
    definition`) and skips the rest of the entity.
    """
    let between: String val =
      "class C\n  fun f() => 1\n  use \"x\"\n  fun g() => 2\n"
    let tree = _ParseText(between)
    h.assert_eq[USize](2, _Find.count(tree, NdMethod))
    h.assert_eq[USize](1, _Find.count(tree, NdError))
    h.assert_eq[USize](0, _Find.count(tree, NdUse))
    h.assert_eq[String]("use \"x\"", _Find.text(h, tree, NdError))
    _Exactly(h, between, [
      ("parse/expected", 25, "syntax error: expected field or method, " +
        "found use")
    ], "between members")
    _Snapshot(h, "class A\nuse \"b\"\n  fun g() => 1\nclass B\n",
      "NdModule >NdClassDef >>TkClass >>TkId >>NdMembers >>>NdError " +
      ">>>>TkUse >>>>TkString >>>NdMethod >>>>TkFun >>>>TkId >>>>TkLparen " +
      ">>>>TkRparen >>>>TkDblarrow >>>>NdSeq >>>>>TkInt >NdClassDef " +
      ">>TkClass >>TkId >TkEof", false)
    _Exactly(h, "class A\n  fun g() => 1\nuse \"b\"\n", [
      ("parse/expected", 23, "syntax error: expected field or method, " +
        "found use")
    ], "after the last member")

class \nodoc\ iso _TestObjectMembers is UnitTest
  fun name(): String => "parse/items: an object literal's members"

  fun apply(h: TestHelper) =>
    """
    An object literal's member list stops at its `end`, and a stray
    token inside it is reported with the noun that names the `end`,
    where ponyc's sequence stops at the token and reports the literal
    unterminated at `object` (`2:14`). A bodiless method followed by a
    field, with no `end`, records the literal unterminated at `object`
    first and the field at its keyword, where ponyc's `Info:` frame
    points (`2:29`); with the `end` present, the field's record alone,
    where ponyc still reports the literal unterminated at `object`.
    """
    _Snapshot(h, "class C\n  fun f() => object fun g() => 1 end\n",
      "NdModule >NdClassDef >>TkClass >>TkId >>NdMembers >>>NdMethod " +
      ">>>>TkFun >>>>TkId >>>>TkLparen >>>>TkRparen >>>>TkDblarrow " +
      ">>>>NdSeq >>>>>NdObject >>>>>>TkObject >>>>>>NdMembers " +
      ">>>>>>>NdMethod >>>>>>>>TkFun >>>>>>>>TkId >>>>>>>>TkLparen " +
      ">>>>>>>>TkRparen >>>>>>>>TkDblarrow >>>>>>>>NdSeq >>>>>>>>>TkInt " +
      ">>>>>>TkEnd >TkEof")
    _Exactly(h, "class C\n  fun f() => object ] end\n", [
      ("parse/expected", 28, "syntax error: expected field, method or " +
        "end, found ]")
    ], "junk in an object")
    _Exactly(h, "class C\n  fun f() => object fun g() let x: U8 = 1 end\n",
      [("parse/expected", 36, "syntax error: expected method, found let")],
      "field after a method with an end")
    _Exactly(h, "class C\n  fun f() => object fun g() let x: U8 = 1\n", [
      ("parse/unterminated", 21,
        "syntax error: unterminated object literal")
      ("parse/expected", 36, "syntax error: expected method, found let")
    ], "field after a method with no end")

class \nodoc\ iso _TestFieldAfterMethod is UnitTest
  fun name(): String => "parse/items: a field after a method"

  fun apply(h: TestHelper) =>
    """
    Each field keyword at member level after a method is reported at
    the keyword and the field is kept: ponyc's `3:3: unexpected token
    var after type, interface, trait, primitive, class or actor
    definition`, after which it skips the rest of the entity. A `var`
    on the line after a method's body is a local of that body, on both
    sides.
    """
    let src: String val = "trait T\n  fun f()\n  var x: U8\n  var y: U8\n"
    let tree = _ParseText(src)
    h.assert_eq[USize](2, _Find.count(tree, NdField))
    h.assert_eq[USize](0, _Find.count(tree, NdError))
    _Exactly(h, src, [
      ("parse/expected", 20, "syntax error: expected method, found var")
      ("parse/expected", 32, "syntax error: expected method, found var")
    ], "fields after a method")
    let local: String val = "class C\n  fun f() =>\n    1\n    var x: U8\n"
    let body = _ParseText(local)
    h.assert_eq[USize](0, _Find.count(body, NdField))
    h.assert_eq[USize](1, _Find.count(body, NdLocal))
    _Clean(h, body, local)

class \nodoc\ iso _TestJunkBetweenUses is UnitTest
  fun name(): String => "parse/items: junk between use commands"

  fun apply(h: TestHelper) =>
    """
    `use "a"\\njunk\\nuse "b"\\nclass C` is a module with two commands,
    one error item holding the junk, and one diagnostic at it; ponyc's
    `2:1: syntax error: unexpected token junk after use command`, after
    which it reads `use "b"` too.
    """
    let src: String val = "use \"a\"\njunk\nuse \"b\"\nclass C\n"
    _Snapshot(h, src,
      "NdModule >NdUse >>TkUse >>TkString >NdError >>TkId >NdUse >>TkUse " +
      ">>TkString >NdClassDef >>TkClass >>TkId >TkEof", false)
    _Exactly(h, src, [
      ("parse/expected", 8, "syntax error: expected use command or type, " +
        "interface, trait, primitive, class or actor definition, found " +
        "an identifier")
    ], "junk between uses")

class \nodoc\ iso _TestFfiAnnotations is UnitTest
  fun name(): String => "parse/items: ffi annotations parse clean"

  fun apply(h: TestHelper) =>
    """
    Three of the `use @` lines of ponyc's `ffi-struct-by-value` test,
    verbatim, with an annotation after a return type and after
    parameters.
    """
    let src: String val =
      "use @point_sum[F64](p: Point \\by_value\\)\n" +
      "use @point_make[Point \\by_value\\](x: F64, y: F64)\n" +
      "use @rect_move[Rect \\by_value\\](r: Rect \\by_value\\, dx: I32, " +
      "dy: I32)\n" +
      "struct Point\n  var x: F64 = 0\n"
    _Clean(h, _ParseText(src), src)
