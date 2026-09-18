use "pony_test"
use "pony_check"
use "collections"
use sort = "../sort"

actor \nodoc\ Main is TestList
  new create(env: Env) => PonyTest(env, this)
  new make() => None

  fun tag tests(test: PonyTest) =>
    _LineIndexTests.tests(test)
    test(_TestOrderKinds)
    test(_TestOrderByPathNotPair)
    test(_TestOrderFields)
    test(_TestOrderPrecedence)
    test(_TestDiagnosticString)
    test(_TestRenderSpan)
    test(_TestRenderMultiByteLine)
    test(_TestRenderTabs)
    test(_TestRenderFileOnlyAndNowhere)
    test(_TestRenderTwoFiles)
    test(_TestRenderLineEdges)
    test(_TestRenderUnknownFile)
    test(_TestRenderLongLineWindow)
    test(Property2UnitTest[(String, String), (String, String)](
      _PathOrderIsPathCompare))
    test(_TestPathOrderCases)
    test(Property1UnitTest[Array[Diagnostic]](_CanonicalSort))
    test(Property2UnitTest[Diagnostic, Diagnostic](_Antisymmetry))
    test(Property3UnitTest[Diagnostic, Diagnostic, Diagnostic](
      _Transitivity))
    test(Property1UnitTest[(Diagnostic, Diagnostic)](_NeighboursFollowView))
    test(Property2UnitTest[Diagnostic, Diagnostic](_PairsFollowView))

class \nodoc\ val _Cause is DiagnosticCause
  let _code: String
  let _message: String

  new val create(code': String, message': String) =>
    _code = code'
    _message = message'

  fun code(): String => _code
  fun message(): String => _message

class \nodoc\ _Sources is SourceLookup
  embed _files: Map[String, String] = _files.create()

  fun ref add(path: String, content: String) =>
    _files(path) = content

  fun content_of(path: String): (String | None) =>
    try _files(path)? else None end

class \nodoc\ iso _TestOrderKinds is UnitTest
  fun name(): String =>
    "diagnostics/order: kinds, and whole files differ by name"

  fun apply(h: TestHelper) =>
    let c = _Cause("x/c", "m")
    let nowhere = Diagnostic(c, Nowhere)
    let file = Diagnostic(c, FileOnly("/p", "a.pony"))
    let span = Diagnostic(c, Span("/p", "a.pony", 0, 1))
    h.assert_true(nowhere < file)
    h.assert_true(file < span)
    h.assert_true(nowhere < span)
    h.assert_false(span < file)
    h.assert_eq[Diagnostic](nowhere, Diagnostic(c, Nowhere))
    h.assert_true(file < Diagnostic(c, FileOnly("/p", "b.pony")))
    h.assert_ne[Diagnostic](file, Diagnostic(c, FileOnly("/p", "b.pony")))

class \nodoc\ iso _TestOrderByPathNotPair is UnitTest
  """
  When one package directory is a prefix of another, the joined path
  orders the two files the other way round from the directory-then-name
  pair, and the order uses the path.
  """
  fun name(): String => "diagnostics/order: by path, not by directory pair"

  fun apply(h: TestHelper) =>
    let c = _Cause("x/c", "m")
    let inner = Diagnostic(c, Span("/p/net/notifier", "y.pony", 0, 1))
    let outer = Diagnostic(c, Span("/p/net", "x.pony", 0, 1))
    h.assert_true("/p/net" < "/p/net/notifier")
    // 'n' < 'x', so by path the inner file sorts first.
    h.assert_true(inner < outer)
    h.assert_false(outer < inner)
    h.assert_true(Diagnostic(c, FileOnly("/p/net/notifier", "y.pony"))
      < Diagnostic(c, FileOnly("/p/net", "x.pony")))

class \nodoc\ iso _TestOrderFields is UnitTest
  fun name(): String =>
    "diagnostics/order: start, length, code, message, and finish"

  fun apply(h: TestHelper) =>
    let c = _Cause("x/c", "m")
    let at0 = Diagnostic(c, Span("/p", "a.pony", 0, 5))
    let at1 = Diagnostic(c, Span("/p", "a.pony", 1, 0))
    h.assert_true(at0 < at1)
    let short = Diagnostic(c, Span("/p", "a.pony", 0, 1))
    h.assert_true(short < at0)
    h.assert_eq[USize](5, Span("/p", "a.pony", 0, 5).finish())
    // `Span.eq` sees every field.
    let base = Span("/p", "a.pony", 0, 5)
    h.assert_true(base == Span("/p", "a.pony", 0, 5))
    h.assert_false(base == Span("/q", "a.pony", 0, 5))
    h.assert_false(base == Span("/p", "b.pony", 0, 5))
    h.assert_false(base == Span("/p", "a.pony", 1, 5))
    h.assert_false(base == Span("/p", "a.pony", 0, 6))
    let code_a = Diagnostic(_Cause("x/a", "z"), Span("/p", "a.pony", 0, 1))
    let code_b = Diagnostic(_Cause("x/b", "a"), Span("/p", "a.pony", 0, 1))
    h.assert_true(code_a < code_b)
    let msg_a = Diagnostic(_Cause("x/c", "a"), Span("/p", "a.pony", 0, 1))
    let msg_b = Diagnostic(_Cause("x/c", "b"), Span("/p", "a.pony", 0, 1))
    h.assert_true(msg_a < msg_b)
    h.assert_ne[Diagnostic](msg_a, msg_b)
    h.assert_eq[Diagnostic](msg_a,
      Diagnostic(_Cause("x/c", "a"), Span("/p", "a.pony", 0, 1)))

class \nodoc\ iso _TestOrderPrecedence is UnitTest
  """
  Each earlier key in the order decides before any later key is looked
  at: kind before path, path before start, location before code.
  """
  fun name(): String => "diagnostics/order: key precedence"

  fun apply(h: TestHelper) =>
    let c = _Cause("x/c", "m")
    h.assert_true(Diagnostic(c, FileOnly("/z", "z.pony"))
      < Diagnostic(c, Span("/a", "a.pony", 0, 0)))
    h.assert_true(Diagnostic(c, Span("/a", "a.pony", 5, 0))
      < Diagnostic(c, Span("/b", "b.pony", 0, 0)))
    h.assert_true(Diagnostic(_Cause("x/z", "m"), Span("/a", "a.pony", 0, 0))
      < Diagnostic(_Cause("x/a", "m"), Span("/a", "a.pony", 1, 0)))

class \nodoc\ iso _TestDiagnosticString is UnitTest
  fun name(): String => "diagnostics/string: one form per kind"

  fun apply(h: TestHelper) =>
    let c = _Cause("x/c", "m")
    h.assert_eq[String]("x/c: m at nowhere", Diagnostic(c, Nowhere).string())
    h.assert_eq[String]("x/c: m at /p/a.pony",
      Diagnostic(c, FileOnly("/p", "a.pony")).string())
    h.assert_eq[String]("x/c: m at /p/a.pony:7+2",
      Diagnostic(c, Span("/p", "a.pony", 7, 2)).string())

class \nodoc\ iso _TestRenderSpan is UnitTest
  fun name(): String => "diagnostics/render: a span, as ponyc prints it"

  fun apply(h: TestHelper) =>
    let sources: _Sources ref = _Sources
    sources.add("/pkgs/c/c.pony", "use \"a\"\nuse \"d\"\nuse \"missing\"\n")
    let render = RenderText(sources)
    let d = Diagnostic(
      _Cause("discover/use-not-found",
        "can't load package 'missing': couldn't locate this path"),
      Span("/pkgs/c", "c.pony", 16, 13))
    h.assert_eq[String](
      "Error:\n" +
      "/pkgs/c/c.pony:3:1: can't load package 'missing': couldn't locate " +
      "this path\n" +
      "use \"missing\"\n" +
      "^\n",
      render(d))
    h.assert_eq[String](
      "Error:\n/pkgs/c/c.pony:3:5: m\nuse \"missing\"\n    ^\n",
      render(Diagnostic(_Cause("x/c", "m"), Span("/pkgs/c", "c.pony", 20,
        9))))

class \nodoc\ iso _TestRenderMultiByteLine is UnitTest
  """
  The column is a byte count, as ponyc's is, so a two-byte character
  before the offset moves the column by two.
  """
  fun name(): String => "diagnostics/render: byte columns"

  fun apply(h: TestHelper) =>
    let sources: _Sources ref = _Sources
    sources.add("/p/a.pony", "let café = 1\n")
    let render = RenderText(sources)
    // "let caf" is 7 bytes and "é" is 2, so "=" is at byte 10.
    h.assert_eq[String](
      "Error:\n/p/a.pony:1:11: m\nlet café = 1\n          ^\n",
      render(Diagnostic(_Cause("x/c", "m"), Span("/p", "a.pony", 10, 1))))

class \nodoc\ iso _TestRenderTabs is UnitTest
  fun name(): String => "diagnostics/render: tabs in the padding"

  fun apply(h: TestHelper) =>
    let sources: _Sources ref = _Sources
    sources.add("/p/a.pony", "\tlet x = 1\n")
    let render = RenderText(sources)
    h.assert_eq[String](
      "Error:\n/p/a.pony:1:6: m\n\tlet x = 1\n\t    ^\n",
      render(Diagnostic(_Cause("x/c", "m"), Span("/p", "a.pony", 5, 1))))

class \nodoc\ iso _TestRenderFileOnlyAndNowhere is UnitTest
  fun name(): String => "diagnostics/render: file-only and nowhere"

  fun apply(h: TestHelper) =>
    let sources: _Sources ref = _Sources
    let render = RenderText(sources)
    h.assert_eq[String]("Error:\n/p/a.pony: couldn't open file\n",
      render(Diagnostic(_Cause("x/c", "couldn't open file"),
        FileOnly("/p", "a.pony"))))
    h.assert_eq[String]("Error:\nno root\n",
      render(Diagnostic(_Cause("x/c", "no root"), Nowhere)))

class \nodoc\ iso _TestRenderTwoFiles is UnitTest
  fun name(): String => "diagnostics/render: two files through one renderer"

  fun apply(h: TestHelper) =>
    let sources: _Sources ref = _Sources
    sources.add("/p/a.pony", "one\n")
    sources.add("/q/a.pony", "\ntwo\n")
    let render = RenderText(sources)
    h.assert_eq[String]("Error:\n/p/a.pony:1:1: m\none\n^\n",
      render(Diagnostic(_Cause("x/c", "m"), Span("/p", "a.pony", 0, 1))))
    h.assert_eq[String]("Error:\n/q/a.pony:2:1: m\ntwo\n^\n",
      render(Diagnostic(_Cause("x/c", "m"), Span("/q", "a.pony", 1, 1))))

class \nodoc\ iso _TestRenderLineEdges is UnitTest
  fun name(): String => "diagnostics/render: an empty line and a CRLF line"

  fun apply(h: TestHelper) =>
    let sources: _Sources ref = _Sources
    sources.add("/p/a.pony", "ab\r\n\ncd")
    let render = RenderText(sources)
    h.assert_eq[String]("Error:\n/p/a.pony:2:1: m\n\n^\n",
      render(Diagnostic(_Cause("x/c", "m"), Span("/p", "a.pony", 4, 0))))
    // The range starts on the CRLF line's newline, past its content.
    h.assert_eq[String]("Error:\n/p/a.pony:1:4: m\nab\n   ^\n",
      render(Diagnostic(_Cause("x/c", "m"), Span("/p", "a.pony", 3, 1))))

class \nodoc\ iso _TestRenderLongLineWindow is UnitTest
  """
  A line longer than the window is cut to the window around the caret
  with `...` at each cut edge, and the caret is padded over what is
  printed; a line within the window is printed whole.
  """
  fun name(): String => "diagnostics/render: a long line is windowed"

  fun apply(h: TestHelper) ? =>
    let width = _Window.width()
    // A line of digits, so a byte's column is readable from the text.
    let line = recover val
      let s = String(600)
      for i in Range(0, 600) do s.push('0' + (i % 10).u8()) end
      s
    end
    let short: String = line.substring(0, width.isize())
    // Within the window: untouched.
    (let t0, let c0) = _Window(short, 0)
    h.assert_eq[String](short, t0)
    h.assert_eq[USize](0, c0)
    (let t1, let c1) = _Window(short, width - 1)
    h.assert_eq[String](short, t1)
    h.assert_eq[USize](width - 1, c1)
    // Caret at 0: the head of the line, cut at the far edge only.
    (let t2, let c2) = _Window(line, 0)
    h.assert_eq[String](line.substring(0, width.isize()) + "...", t2)
    h.assert_eq[USize](0, c2)
    // Caret at the line's end: the tail, cut at the near edge only.
    (let t3, let c3) = _Window(line, 599)
    h.assert_eq[String]("..." + line.substring(400), t3)
    h.assert_eq[USize](3 + 199, c3)
    h.assert_eq[U8]('9', t3(c3)?)
    // At the first edge: no near cut yet.
    (let t4, let c4) = _Window(line, width / 2)
    h.assert_eq[String](line.substring(0, width.isize()) + "...", t4)
    h.assert_eq[USize](width / 2, c4)
    // Just past it: the window slides by one and both edges are cut.
    (let t5, let c5) = _Window(line, (width / 2) + 1)
    h.assert_eq[String]("..." + line.substring(1, (width + 1).isize()) +
      "...", t5)
    h.assert_eq[USize](3 + (width / 2), c5)
    h.assert_eq[U8]('1', t5(c5)?)
    // Just inside the far edge: the last window, both edges cut still.
    (let t6, let c6) = _Window(line, 600 - (width / 2) - 1)
    h.assert_eq[String]("..." + line.substring(399, 599) + "...", t6)
    h.assert_eq[U8]('9', t6(c6)?)
    // Just outside it: the tail with no far cut.
    (let t7, let c7) = _Window(line, 600 - (width / 2))
    h.assert_eq[String]("..." + line.substring(400), t7)
    h.assert_eq[U8]('0', t7(c7)?)
    // Through the renderer, with a multibyte character before the caret:
    // columns are bytes, so the caret still lands on its byte.
    let sources: _Sources ref = _Sources
    let text: String = "\u00E9" + line
    sources.add("/p/a.pony", text)
    let render = RenderText(sources)
    let at: USize = 2 + 599
    let rendered: String = render(Diagnostic(_Cause("x/c", "m"),
      Span("/p", "a.pony", at, 1)))
    h.assert_true(rendered.contains("\n..." + line.substring(400) + "\n"))
    let caret_line: String = rendered.substring(
      rendered.rfind("\n", -2)? + 1)
    // 3 for the cut marker, 199 for the bytes before the caret.
    h.assert_eq[String](
      recover val String.>concat(Array[U8].init(' ', 3 + 199).values())
        .>append("^\n") end,
      caret_line)
    // A tab inside the window is copied into the padding at its place
    // in the shown slice: byte 250 of a 300-byte line is byte 153 of the
    // slice, which starts at 100 behind the cut marker.
    let tabbed = recover val
      let t = String(300)
      for i in Range(0, 300) do t.push(if i == 250 then '\t' else 'a' end) end
      t
    end
    sources.add("/p/t.pony", tabbed)
    let with_tab: String = render(Diagnostic(_Cause("x/c", "m"),
      Span("/p", "t.pony", 260, 1)))
    let tab_caret: String = with_tab.substring(with_tab.rfind("\n", -2)? + 1)
    h.assert_eq[USize](3 + 160 + 2, tab_caret.size())
    h.assert_eq[U8]('\t', tab_caret(153)?)
    h.assert_eq[U8](' ', tab_caret(152)?)
    h.assert_eq[U8]('^', tab_caret(163)?)

class \nodoc\ iso _TestPathOrderCases is UnitTest
  """
  The cases `_PathOrderIsPathCompare` rarely draws: one joined path split
  two ways,
  a directory that is a prefix of another, an empty directory or name,
  and the same two objects on both sides.
  """
  fun name(): String => "diagnostics/order: path order cases"

  fun apply(h: TestHelper) =>
    h.assert_true(_PathOrder("/a", "b/c", "/a/b", "c") is Equal)
    h.assert_true(_PathOrder("/a/b", "c", "/a", "b/c") is Equal)
    h.assert_true(_PathOrder("/p/net/notifier", "y.pony", "/p/net", "x.pony")
      is Less)
    h.assert_true(_PathOrder("/p/net", "x.pony", "/p/net/notifier", "y.pony")
      is Greater)
    h.assert_true(_PathOrder("", "a", "", "b") is Less)
    h.assert_true(_PathOrder("/a", "", "/a", "b") is Less)
    h.assert_true(_PathOrder("/a", "b", "/a/b", "") is Less)
    let dir: String = "/same".clone()
    let file: String = "x.pony".clone()
    h.assert_true(_PathOrder(dir, file, dir, file) is Equal)
    h.assert_true(_PathOrder(dir, file, "/same".clone(), "x.pony".clone())
      is Equal)

class \nodoc\ val _PathOrderIsPathCompare is Property2[(String, String),
  (String, String)]
  """
  `_PathOrder` over two directory-and-name pairs is `String.compare`
  over their joined paths. The alphabet is two letters and `/`, so equal
  directories and directory prefixes are common.
  """
  fun name(): String => "diagnostics/order: path order is path compare"

  fun gen1(): Generator[(String, String)] => _gen()

  fun gen2(): Generator[(String, String)] => _gen()

  fun _gen(): Generator[(String, String)] =>
    let part = Generators.ascii(where from = 0, to = 4)
      .map[String]({(s: String): String =>
        let out = recover iso String end
        for b in s.values() do
          out.push(match b % 3 | 0 => 'a' | 1 => 'b' else '/' end)
        end
        consume out
      })
    Generators.zip2[String, String](part, part)

  fun property2(a: (String, String), b: (String, String), h: PropertyHelper)
  =>
    let expected = (a._1 + "/" + a._2).compare(b._1 + "/" + b._2)
    let got = _PathOrder(a._1, a._2, b._1, b._2)
    h.assert_true(expected is got, (a._1 + "/" + a._2) + " vs " +
      (b._1 + "/" + b._2))

class \nodoc\ iso _TestRenderUnknownFile is UnitTest
  fun name(): String => "diagnostics/render: a span in a file with no text"

  fun apply(h: TestHelper) =>
    let sources: _Sources ref = _Sources
    let render = RenderText(sources)
    h.assert_eq[String]("Error:\n/p/a.pony: m\n",
      render(Diagnostic(_Cause("x/c", "m"), Span("/p", "a.pony", 3, 1))))

primitive \nodoc\ _Flip
  """
  The other member of a two-element alphabet.
  """
  fun apply(v: String, pair: Array[String] val): String =>
    try
      if v == pair(0)? then pair(1)? else pair(0)? end
    else
      v
    end

primitive \nodoc\ _Gen
  """
  Diagnostics drawn from small alphabets, so that every key in the order
  is reached: two directories, two names, two starts, two lengths, two
  codes, two messages, all three location kinds. `neighbour` draws a
  diagnostic and a second that is the same or differs in exactly one
  field, so a comparator that ignored any one field returns `Equal` for
  some pair whose views differ.
  """
  fun dirs(): Array[String] val => ["/p/a"; "/p/a/b"]
  fun names(): Array[String] val => ["x.pony"; "y.pony"]
  fun codes(): Array[String] val => ["l/a"; "l/b"]
  fun messages(): Array[String] val => ["m"; "n"]

  fun diagnostic(): Generator[Diagnostic] =>
    let dirs' = dirs()
    let names' = names()
    let codes' = codes()
    let messages' = messages()
    let cause = Generators.map2[String, String, DiagnosticCause](
      Generators.one_of[String](codes'),
      Generators.one_of[String](messages'), {(c, m) => _Cause(c, m)})
    let span = Generators.map4[String, String, USize, USize, Location](
      Generators.one_of[String](dirs'), Generators.one_of[String](names'),
      Generators.usize(0, 1), Generators.usize(0, 1),
      {(d, n, s, l) => Span(d, n, s, l)})
    let file = Generators.map2[String, String, Location](
      Generators.one_of[String](dirs'), Generators.one_of[String](names'),
      {(d, n) => FileOnly(d, n)})
    let nowhere = Generators.unit[Location](Nowhere)
    let location = Generators.frequency[Location]([
      (4, span); (2, file); (1, nowhere)])
    Generators.map2[DiagnosticCause, Location, Diagnostic](cause, location,
      {(c, l) => Diagnostic(c, l)})

  fun neighbour(): Generator[(Diagnostic, Diagnostic)] =>
    """
    A diagnostic and a second that is the same or differs in exactly one
    of: directory, name, start, length, code, message. A `Nowhere`
    location becomes a whole file instead.
    """
    Generators.map2[Diagnostic, USize, (Diagnostic, Diagnostic)](
      diagnostic(), Generators.usize(0, 6),
      {(d, which) =>
        let c = d.cause
        let other =
          match which
          | 0 => d
          | 1 => Diagnostic(_Cause(_Flip(c.code(), _Gen.codes()),
            c.message()), d.location)
          | 2 =>
            Diagnostic(_Cause(c.code(), _Flip(c.message(), _Gen.messages())),
              d.location)
          else
            match d.location
            | Nowhere =>
              Diagnostic(c, FileOnly(_Flip("", _Gen.dirs()),
                _Flip("", _Gen.names())))
            | let f: FileOnly =>
              if which == 3 then
                Diagnostic(c, FileOnly(_Flip(f.dir, _Gen.dirs()),
                  f.name))
              else
                Diagnostic(c, FileOnly(f.dir,
                  _Flip(f.name, _Gen.names())))
              end
            | let sp: Span =>
              match which
              | 3 => Diagnostic(c, Span(_Flip(sp.dir, _Gen.dirs()),
                sp.name, sp.start, sp.length))
              | 4 => Diagnostic(c, Span(sp.dir,
                _Flip(sp.name, _Gen.names()), sp.start, sp.length))
              | 5 => Diagnostic(c, Span(sp.dir, sp.name, 1 - sp.start,
                sp.length))
              else
                Diagnostic(c, Span(sp.dir, sp.name, sp.start,
                  1 - sp.length))
              end
            end
          end
        (d, other)
      })

  fun view(d: Diagnostic): (USize, String, USize, USize, String, String)
  =>
    """
    The keys of the documented order as a tuple: kind, path, start,
    length, code, message. `compare_views` orders two of them field by
    field, so the tuple order is an oracle for `DiagnosticOrder` that
    shares none of its code.
    """
    match \exhaustive\ d.location
    | Nowhere => (0, "", 0, 0, d.cause.code(), d.cause.message())
    | let f: FileOnly =>
      (1, f.path(), 0, 0, d.cause.code(), d.cause.message())
    | let s: Span =>
      (2, s.path(), s.start, s.length, d.cause.code(), d.cause.message())
    end

  fun compare_views(a: Diagnostic, b: Diagnostic): Compare =>
    (let ka, let pa, let sa, let la, let ca, let ma) = view(a)
    (let kb, let pb, let sb, let lb, let cb, let mb) = view(b)
    if ka != kb then return if ka < kb then Less else Greater end end
    if pa != pb then return if pa < pb then Less else Greater end end
    if sa != sb then return if sa < sb then Less else Greater end end
    if la != lb then return if la < lb then Less else Greater end end
    if ca != cb then return if ca < cb then Less else Greater end end
    if ma != mb then return if ma < mb then Less else Greater end end
    Equal

class \nodoc\ iso _CanonicalSort is Property1[Array[Diagnostic]]
  """
  A list and its reverse sort to lists equal element by element.
  """
  fun name(): String => "diagnostics/order: canonical sort"

  fun gen(): Generator[Array[Diagnostic]] =>
    Generators.array_of[Diagnostic](_Gen.diagnostic(), 0, 12)

  fun property(sample: Array[Diagnostic], h: PropertyHelper) =>
    let a = sample.clone()
    let b = sample.clone()
    b.reverse_in_place()
    sort.MergeSort[Diagnostic](a)
    sort.MergeSort[Diagnostic](b)
    h.assert_eq[USize](a.size(), b.size())
    var i: USize = 0
    while i < a.size() do
      try
        h.assert_true(_Gen.compare_views(a(i)?, b(i)?) is Equal,
          "index " + i.string())
      else
        h.fail("index " + i.string())
      end
      i = i + 1
    end

class \nodoc\ iso _Antisymmetry is Property2[Diagnostic, Diagnostic]
  fun name(): String => "diagnostics/order: antisymmetry"

  fun gen1(): Generator[Diagnostic] => _Gen.diagnostic()
  fun gen2(): Generator[Diagnostic] => _Gen.diagnostic()

  fun property2(a: Diagnostic, b: Diagnostic, h: PropertyHelper) =>
    match DiagnosticOrder.compare(a, b)
    | Less => h.assert_true(DiagnosticOrder.compare(b, a) is Greater)
    | Greater => h.assert_true(DiagnosticOrder.compare(b, a) is Less)
    | Equal => h.assert_true(DiagnosticOrder.compare(b, a) is Equal)
    end

class \nodoc\ iso _Transitivity
  is Property3[Diagnostic, Diagnostic, Diagnostic]
  fun name(): String => "diagnostics/order: transitivity"

  fun gen1(): Generator[Diagnostic] => _Gen.diagnostic()
  fun gen2(): Generator[Diagnostic] => _Gen.diagnostic()
  fun gen3(): Generator[Diagnostic] => _Gen.diagnostic()

  fun property3(a: Diagnostic, b: Diagnostic, c: Diagnostic,
    h: PropertyHelper)
  =>
    if (a <= b) and (b <= c) then h.assert_true(a <= c) end
    if (a < b) and (b < c) then h.assert_true(a < c) end

class \nodoc\ iso _NeighboursFollowView
  is Property1[(Diagnostic, Diagnostic)]
  """
  Over pairs that differ in at most one field, `DiagnosticOrder` agrees
  with the view's order, so a comparator that ignored any one field
  would return `Equal` for two diagnostics whose views differ.
  """
  fun name(): String => "diagnostics/order: neighbours follow the view"

  fun gen(): Generator[(Diagnostic, Diagnostic)] => _Gen.neighbour()

  fun property(sample: (Diagnostic, Diagnostic), h: PropertyHelper) =>
    (let a, let b) = sample
    h.assert_true(DiagnosticOrder.compare(a, b) is _Gen.compare_views(a, b))

class \nodoc\ iso _PairsFollowView is Property2[Diagnostic, Diagnostic]
  """
  Over independent pairs, `DiagnosticOrder` agrees with the view's order,
  so the documented precedence of the keys holds, not only their set.
  """
  fun name(): String => "diagnostics/order: pairs follow the view"

  fun gen1(): Generator[Diagnostic] => _Gen.diagnostic()
  fun gen2(): Generator[Diagnostic] => _Gen.diagnostic()

  fun property2(a: Diagnostic, b: Diagnostic, h: PropertyHelper) =>
    h.assert_true(DiagnosticOrder.compare(a, b) is _Gen.compare_views(a, b))

primitive \nodoc\ _LineIndexTests is TestList
  fun tag tests(test: PonyTest) =>
    test(_TestEmptySourceHasOneLine)
    test(_TestLinesAndColumns)
    test(_TestLineEndsBeforeNewline)
    test(_TestPositionPastTheEnd)

class \nodoc\ iso _TestEmptySourceHasOneLine is UnitTest
  fun name(): String => "diagnostics/line index: an empty source has one line"

  fun apply(h: TestHelper) =>
    let index = LineIndex("")
    h.assert_eq[USize](1, index.line_count())
    (let line, let column) = index.position(0)
    h.assert_eq[USize](0, line)
    h.assert_eq[USize](0, column)

class \nodoc\ iso _TestLinesAndColumns is UnitTest
  fun name(): String => "diagnostics/line index: lines and byte columns"

  fun apply(h: TestHelper) =>
    let index = LineIndex("ab\ncd\n")
    h.assert_eq[USize](3, index.line_count(),
      "a trailing newline leaves an empty last line")
    _At(h, index, 0, 0, 0)
    _At(h, index, 1, 0, 1)
    _At(h, index, 2, 0, 2)
    _At(h, index, 3, 1, 0)
    _At(h, index, 5, 1, 2)
    _At(h, index, 6, 2, 0)
    // A column is a byte count, so a two-byte character counts twice.
    _At(h, LineIndex("caf\u00e9 x"), 6, 0, 6)

class \nodoc\ iso _TestLineEndsBeforeNewline is UnitTest
  fun name(): String =>
    "diagnostics/line index: a line ends before its newline"

  fun apply(h: TestHelper) =>
    let lf = LineIndex("ab\ncd\n")
    h.assert_eq[USize](2, lf.line_end(0))
    h.assert_eq[USize](5, lf.line_end(1))
    h.assert_eq[USize](6, lf.line_end(2))
    let crlf = LineIndex("ab\r\ncd\r\n")
    h.assert_eq[USize](2, crlf.line_end(0))
    h.assert_eq[USize](6, crlf.line_end(1))
    h.assert_eq[USize](8, LineIndex("ab\ncd\nef").line_end(2))

class \nodoc\ iso _TestPositionPastTheEnd is UnitTest
  fun name(): String => "diagnostics/line index: an offset past the end"

  fun apply(h: TestHelper) =>
    (let line, let column) = LineIndex("ab\ncd").position(9999)
    h.assert_eq[USize](1, line)
    h.assert_eq[USize](2, column)
    (let line', let column') = LineIndex("ab\ncd\n").position(9999)
    h.assert_eq[USize](2, line')
    h.assert_eq[USize](0, column')
    h.assert_eq[USize](2, LineIndex("ab").line_start(99))

primitive \nodoc\ _At
  fun apply(h: TestHelper, index: LineIndex, byte: USize, line: USize,
    column: USize)
  =>
    (let l, let c) = index.position(byte)
    h.assert_eq[USize](line, l, "line at byte " + byte.string())
    h.assert_eq[USize](column, c, "column at byte " + byte.string())
