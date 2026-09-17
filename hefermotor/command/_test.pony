use "collections"
use "json"
use "pony_test"
use "promises"
use diag = "../diagnostics"
use discover = "../discover"
use export = "../export"
use parse = "../parse"
use schedule = "../schedule"
use source = "../source"

actor \nodoc\ Main is TestList
  new create(env: Env) => PonyTest(env, this)
  new make() => None

  fun tag tests(test: PonyTest) =>
    test(_TestCheckArgs)
    test(_TestSearchRootOrder)
    test(_TestStdlibSlot)
    test(_TestJsonString)
    test(_TestRunJsonOnStdoutExit1)
    test(_TestRunCleanExit0)
    test(_TestRunTextOnStderr)
    test(_TestRunDefaultTargetIsBase)
    test(_TestRunUsageErrorExit2)
    test(_TestRunHelpExit0)
    test(_TestRunRelativeBaseExit2)
    test(_TestRunBuiltinNotFoundExit2)
    test(_TestRunBuiltinNotLoadedExit2)
    test(_TestRunInternalErrorExit70)
    test(_TestRunRejectedReportLeaves70)
    test(_TestRunJsonEscapes)
    test(_TestRunStdlibSlotFirst)
    test(_TestRunReversedFixtureIsIdentical)

actor \nodoc\ _Capture is OutStream
  """
  An `OutStream` that keeps what was printed and hands it over on
  request. `contents` is sent in reaction to the run's fulfilment, which
  follows its last print, so causal delivery puts it after every print.
  """
  embed _prints: Array[String] = _prints.create()

  be print(data: ByteSeq) => _prints.push(_Text(data) + "\n")
  be write(data: ByteSeq) => _prints.push(_Text(data))
  be printv(data: ByteSeqIter) =>
    for d in data.values() do _prints.push(_Text(d) + "\n") end

  be writev(data: ByteSeqIter) =>
    for d in data.values() do _prints.push(_Text(d)) end
  be flush() => None

  be contents(p: Promise[Array[String] val]) =>
    // One entry per print or write call.
    let copy = recover iso Array[String] end
    for s in _prints.values() do copy.push(s) end
    p(consume copy)

primitive \nodoc\ _Text
  fun apply(data: ByteSeq): String =>
    match data
    | let s: String => s
    | let a: Array[U8] val => String.from_array(a)
    end

actor \nodoc\ _ExitCodes
  """
  Every code `env.exitcode` was called with, in call order.
  """
  embed _codes: Array[I32] = _codes.create()

  be push(code: I32) => _codes.push(code)

  be contents(p: Promise[Array[I32] val]) =>
    let copy = recover iso Array[I32] end
    for c in _codes.values() do copy.push(c) end
    p(consume copy)

primitive \nodoc\ _TestEnv
  fun apply(h: TestHelper, args: Array[String] val, out: OutStream,
    err: OutStream, codes: _ExitCodes,
    vars: Array[String] val = recover val Array[String] end)
    : Env
  =>
    Env.create(h.env.root, h.env.input, out, err, args, vars,
      {(code: I32) => codes.push(code) })

primitive \nodoc\ _Fixture
  """
  `builtin`; `a` and `b` use each other; `c` uses `a`, `d` and a
  missing package; `d` uses nothing. The base directory the tests pass
  is `/work`.
  """
  fun fs(): discover.MemoryFileSystem ref =>
    let mem: discover.MemoryFileSystem ref = discover.MemoryFileSystem
    mem.file("/pkgs/builtin/builtin.pony", "primitive None\n")
    mem.file("/pkgs/a/a.pony", "use \"b\"\n")
    mem.file("/pkgs/b/b.pony", "use \"a\"\n")
    mem.file("/pkgs/c/c.pony", "use \"a\"\nuse \"d\"\nuse \"missing\"\n")
    mem.file("/pkgs/d/d.pony", "primitive D\n")
    mem.dir("/work")
    mem

  fun reversed(): discover.MemoryFileSystem ref =>
    """
    The same files, added in the opposite order.
    """
    let mem: discover.MemoryFileSystem ref = discover.MemoryFileSystem
    mem.dir("/work")
    mem.file("/pkgs/d/d.pony", "primitive D\n")
    mem.file("/pkgs/c/c.pony", "use \"a\"\nuse \"d\"\nuse \"missing\"\n")
    mem.file("/pkgs/b/b.pony", "use \"a\"\n")
    mem.file("/pkgs/a/a.pony", "use \"b\"\n")
    mem.file("/pkgs/builtin/builtin.pony", "primitive None\n")
    mem

primitive \nodoc\ _NoParse
  fun apply(file: source.SourceFile): parse.ParsedFile =>
    parse.ParsedFile(file, recover val Array[parse.UseDecl] end,
      recover val Array[diag.Diagnostic] end)

primitive \nodoc\ _StubAnalysis
  fun apply(
    members: Array[discover.ParsedPackage] val,
    deps: export.DepExports,
    config: source.BuildConfig)
    : export.GroupResult
  =>
    let exports = recover iso Array[export.PackageExport] end
    for m in members.values() do
      exports.push(export.PackageExport(m.package.dir,
        export.ExportData.stub(m.package.source_hash)))
    end
    export.GroupResult(consume exports,
      recover val Array[diag.Diagnostic] end)

primitive \nodoc\ _StubChecker
  """
  The real scheduler over stub phases.
  """
  fun apply(program: discover.Program, config: source.BuildConfig)
    : Promise[schedule.Report]
  =>
    schedule.Schedule(program, config, _NoParse, _StubAnalysis)

primitive \nodoc\ _RejectingChecker
  """
  A checker whose promise is rejected at once, which `Schedule`'s
  contract rules out, so only the command's preset exit code stands.
  """
  fun apply(program: discover.Program, config: source.BuildConfig)
    : Promise[schedule.Report]
  =>
    let p = Promise[schedule.Report]
    p.reject()
    p

class \nodoc\ val _Cause is diag.DiagnosticCause
  let _code: String
  let _message: String

  new val create(code': String, message': String) =>
    _code = code'
    _message = message'

  fun code(): String => _code

  fun message(): String => _message

class \nodoc\ val _ReportingChecker
  """
  A checker whose report holds the given diagnostics and no export.
  """
  let _diagnostics: Array[diag.Diagnostic] val

  new val create(diagnostics: Array[diag.Diagnostic] val) =>
    _diagnostics = diagnostics

  fun apply(program: discover.Program, config: source.BuildConfig)
    : Promise[schedule.Report]
  =>
    let p = Promise[schedule.Report]
    p(schedule.Report(_diagnostics,
      recover val Array[export.PackageExport] end))
    p

primitive \nodoc\ _Json
  """
  The document parsed back by the stdlib `json` package.
  """
  fun apply(h: TestHelper, document: String): JSONObject ? =>
    match JSONParser.parse(document)
    | let o: JSONObject => o
    | let v: JSONValue =>
      h.fail("the document is not an object")
      error
    | let e: JSONParseError =>
      h.fail("the document does not parse: " + e.message + " at " +
        e.offset.string())
      error
    end

  fun strings(value: JSONValue): Array[String] ? =>
    let out = Array[String]
    let arr = value as JSONArray
    for i in Range(0, arr.size()) do out.push(arr(i)? as String) end
    out

primitive \nodoc\ _AssertJsonShape
  """
  Asserts the keys are exactly `format`, `export_digest`, `packages`,
  `groups` and `diagnostics`, `format` is 1, and every `packages` entry
  has `dir`, `name`, `group` and `export_hash`.
  """
  fun apply(h: TestHelper, document: String) ? =>
    let doc = _Json(h, document)?
    h.assert_eq[USize](5, doc.size())
    for key in ["format"; "export_digest"; "packages"; "groups"
      "diagnostics"].values()
    do
      h.assert_true(doc.contains(key), key)
    end
    h.assert_eq[I64](1, doc("format")? as I64)
    h.assert_eq[USize](16, (doc("export_digest")? as String).size())
    let packages = doc("packages")? as JSONArray
    for i in Range(0, packages.size()) do
      let p = packages(i)? as JSONObject
      h.assert_eq[USize](4, p.size())
      p("dir")? as String
      p("name")? as String
      p("group")? as I64
      match p("export_hash")?
      | let s: String => h.assert_eq[USize](16, s.size())
      | None => None
      else
        h.fail("export_hash is a hash or null")
      end
    end
    doc("groups")? as JSONArray
    doc("diagnostics")? as JSONArray

primitive \nodoc\ _AssertFixtureJson
  """
  Beyond the shape: the groups, as sets of directory sets, are the
  fixture's four; `packages[].dir` are its five; the one diagnostic is
  `discover/use-not-found` at `/pkgs/c/c.pony`, start 16, length 13.
  """
  fun apply(h: TestHelper, document: String) ? =>
    let doc = _Json(h, document)?
    let groups = Set[String]
    let arr = doc("groups")? as JSONArray
    for i in Range(0, arr.size()) do
      let members = _Json.strings(arr(i)?)?
      Sort[Array[String], String](members)
      groups.set("|".join(members.values()))
    end
    h.assert_eq[USize](4, groups.size())
    for g in ["/pkgs/builtin"; "/pkgs/a|/pkgs/b"; "/pkgs/d"; "/pkgs/c"]
      .values()
    do
      h.assert_true(groups.contains(g), g)
    end
    let dirs = Array[String]
    let packages = doc("packages")? as JSONArray
    for i in Range(0, packages.size()) do
      dirs.push((packages(i)? as JSONObject)("dir")? as String)
    end
    h.assert_array_eq[String](
      ["/pkgs/a"; "/pkgs/b"; "/pkgs/builtin"; "/pkgs/c"; "/pkgs/d"], dirs)
    let diagnostics = doc("diagnostics")? as JSONArray
    h.assert_eq[USize](1, diagnostics.size())
    let d = diagnostics(0)? as JSONObject
    h.assert_eq[String]("discover/use-not-found", d("code")? as String)
    h.assert_eq[String](
      "can't load package 'missing': couldn't locate this path",
      d("message")? as String)
    let at = d("location")? as JSONObject
    h.assert_eq[String]("/pkgs/c/c.pony", at("file")? as String)
    h.assert_eq[I64](16, at("start")? as I64)
    h.assert_eq[I64](13, at("length")? as I64)

class \nodoc\ iso _TestCheckArgs is UnitTest
  fun name(): String => "command/check args"

  fun apply(h: TestHelper) =>
    let none = recover val Array[String] end
    match CheckArgs(["hefermotor"; "check"], none, None, "/work")
    | let c: CheckCommand =>
      h.assert_eq[String](".", c.target)
      h.assert_false(c.json)
      h.assert_array_eq[String](["/usr/local/lib"; "/opt/local/lib"],
        c.search_roots.dirs)
    else
      h.fail("check with no arguments")
    end
    match CheckArgs(["hefermotor"; "check"; "/p/x"; "--json"], none, None,
      "/work")
    | let c: CheckCommand =>
      h.assert_eq[String]("/p/x", c.target)
      h.assert_true(c.json)
    else
      h.fail("check with a target and --json")
    end
    match CheckArgs(["hefermotor"; "frob"], none, None, "/work")
    | let u: UsageError => h.assert_true(u.string().contains("frob"))
    else
      h.fail("an unknown command")
    end
    match CheckArgs(["hefermotor"; "check"; "--nope"], none, None, "/work")
    | let u: UsageError => h.assert_true(u.string().contains("usage:"))
    else
      h.fail("an unknown option")
    end
    match CheckArgs(["hefermotor"; "check"; "a"; "b"], none, None, "/work")
    | let u: UsageError => None
    else
      h.fail("two targets")
    end
    match CheckArgs(["hefermotor"], none, None, "/work")
    | let u: UsageError => None
    else
      h.fail("no command")
    end
    match CheckArgs(["hefermotor"; "help"], none, None, "/work")
    | let help: HelpRequested => h.assert_true(help.text.contains("check"))
    else
      h.fail("help")
    end
    match CheckArgs(["hefermotor"; "check"; "--help"], none, None, "/work")
    | let help: HelpRequested => None
    else
      h.fail("check --help")
    end

class \nodoc\ iso _TestSearchRootOrder is UnitTest
  """
  The stdlib slot, then each `--path` in order, then `PONYPATH`, then
  the POSIX defaults; a relative entry is taken under the base.
  """
  fun name(): String => "command/search roots in order"

  fun apply(h: TestHelper) =>
    match CheckArgs(
      ["hefermotor"; "check"; "--path=/one:"; "--path=two:/five"; "--path="],
      ["HOME=/h"; "PONYPATH=/three:four"; "PATH=/bin"], "/std", "/work")
    | let c: CheckCommand =>
      h.assert_array_eq[String]([
        "/std"; "/one"; "/work/two"; "/five"; "/three"; "/work/four"
        "/usr/local/lib"; "/opt/local/lib"], c.search_roots.dirs)
    else
      h.fail("roots")
    end
    match CheckArgs(["hefermotor"; "check"], ["PONYPATH="], None, "/work")
    | let c: CheckCommand =>
      h.assert_array_eq[String](["/usr/local/lib"; "/opt/local/lib"],
        c.search_roots.dirs)
    else
      h.fail("empty PONYPATH")
    end

class \nodoc\ iso _TestStdlibSlot is UnitTest
  """
  The packages directory beside the first `ponyc` on `PATH`, through a
  link, or none.
  """
  fun name(): String => "command/the stdlib slot beside ponyc"

  fun apply(h: TestHelper) ? =>
    let fs: discover.MemoryFileSystem ref = discover.MemoryFileSystem
    fs.file("/opt/pony/v1/bin/ponyc", "")
    fs.dir("/opt/pony/v1/packages/builtin")
    fs.link("/opt/pony/bin/ponyc", "/opt/pony/v1/bin/ponyc")
    fs.dir("/usr/bin")
    fs.dir("/nopkg/bin")
    fs.file("/nopkg/bin/ponyc", "")
    fs.dir("/dirponyc/bin/ponyc")
    h.assert_eq[String]("/opt/pony/v1/packages",
      StdlibSlot(fs, ["PATH=/usr/bin:/opt/pony/bin:/nopkg/bin"], "/w")
        as String)
    h.assert_eq[String]("/opt/pony/v1/packages",
      StdlibSlot(fs, ["PATH=/opt/pony/v1/bin"], "/w") as String)
    // A build tree keeps the binary two levels below the packages.
    fs.file("/src/ponyc/build/debug/ponyc", "")
    fs.dir("/src/ponyc/packages/builtin")
    h.assert_eq[String]("/src/ponyc/packages",
      StdlibSlot(fs, ["PATH=/src/ponyc/build/debug"], "/w") as String)
    // A relative or empty entry is taken under the base.
    h.assert_eq[String]("/opt/pony/v1/packages",
      StdlibSlot(fs, ["PATH=v1/bin"], "/opt/pony") as String)
    h.assert_eq[String]("/opt/pony/v1/packages",
      StdlibSlot(fs, ["PATH=:/usr/bin"], "/opt/pony/v1/bin") as String)
    // Only the first ponyc on PATH counts, even when no packages
    // directory is beside it.
    h.assert_true(StdlibSlot(fs, ["PATH=/nopkg/bin:/opt/pony/bin"], "/w")
      is None)
    h.assert_true(StdlibSlot(fs, ["PATH=/usr/bin"], "/w") is None)
    h.assert_true(StdlibSlot(fs, ["PATH=/dirponyc/bin"], "/w") is None)
    h.assert_true(StdlibSlot(fs, ["PATH=relative/bin"], "/w") is None)
    h.assert_true(StdlibSlot(fs, ["HOME=/h"], "/w") is None)
    h.assert_true(StdlibSlot(fs, [], "/w") is None)

primitive \nodoc\ _Bytes
  """
  A string holding exactly these bytes. A `\x` escape in a Pony string
  literal is a code point, encoded as UTF-8, so an invalid byte sequence
  can only be built from the bytes.
  """
  fun apply(bytes: Array[U8] val): String => String.from_array(bytes)

class \nodoc\ iso _TestJsonString is UnitTest
  fun name(): String => "command/json strings are escaped and valid"

  fun apply(h: TestHelper) ? =>
    h.assert_eq[String]("\"plain\"", _JsonString("plain"))
    h.assert_eq[String]("\"a\\\"b\\\\c\"", _JsonString("a\"b\\c"))
    h.assert_eq[String]("\"\\n\\r\\t\\u0001\\u001f\"",
      _JsonString("\n\r\t\x01\x1f"))
    // Well-formed sequences of two, three and four bytes pass through.
    let utf8 = "caf\u00E9 \u20AC \U01F600"
    h.assert_eq[String]("\"" + utf8 + "\"", _JsonString(utf8))
    // Invalid sequences become U+FFFD, one per bad byte: a lone
    // continuation byte, a truncated lead, an overlong encoding, a
    // surrogate, and a code point past U+10FFFF.
    let bad = "\uFFFD"
    h.assert_eq[String]("\"x" + bad + "y\"",
      _JsonString(_Bytes(['x'; 0x80; 'y'])))
    h.assert_eq[String]("\"" + bad + "\"", _JsonString(_Bytes([0xC3])))
    h.assert_eq[String]("\"" + bad + bad + "\"",
      _JsonString(_Bytes([0xC0; 0x80])))
    h.assert_eq[String]("\"" + bad + bad + bad + "\"",
      _JsonString(_Bytes([0xED; 0xA0; 0x80])))
    h.assert_eq[String]("\"" + bad + bad + bad + bad + "\"",
      _JsonString(_Bytes([0xF4; 0x90; 0x80; 0x80])))
    // A truncated lead followed by ASCII loses only the lead.
    h.assert_eq[String]("\"" + bad + "a\"", _JsonString(_Bytes([0xE2; 'a'])))
    // The stdlib parser reads each back.
    for text in ["a\"b\\c"; "\n\x01"; utf8; _Bytes(['x'; 0x80; 'y'])
      _Bytes([0xC3])].values()
    do
      match JSONParser.parse("[" + _JsonString(text) + "]")
      | let a: JSONArray => a(0)? as String
      else
        h.fail("does not parse back: " + _JsonString(text))
      end
    end
    h.assert_eq[String]("a\"b\\c",
      JSONParser.parse(_JsonString("a\"b\\c")) as String)
    h.assert_eq[String]("x" + bad + "y",
      JSONParser.parse(_JsonString(_Bytes(['x'; 0x80; 'y']))) as String)

primitive \nodoc\ _Ended
  """
  Runs `Run` and hands the ended code, the prints on out and err, and
  the exit codes to `after`.
  """
  fun apply(h: TestHelper, args: Array[String] val,
    fs: discover.MemoryFileSystem ref, check: Checker,
    after: {(I32, Array[String] val, Array[String] val, Array[I32] val)} val,
    vars: Array[String] val = recover val Array[String] end)
  =>
    let out = _Capture
    let err = _Capture
    let codes = _ExitCodes
    let env = _TestEnv(h, args, out, err, codes, vars)
    h.long_test(2_000_000_000)
    Run(env, fs, "/work", check)
      .next[None]({(ended: I32)(h, out, err, codes, after) =>
        out.contents(Promise[Array[String] val].>next[None](
          {(prints: Array[String] val)(h, err, codes, after, ended) =>
            err.contents(Promise[Array[String] val].>next[None](
              {(errors: Array[String] val)(h, codes, after, ended, prints)
              =>
                codes.contents(Promise[Array[I32] val].>next[None](
                  {(seen: Array[I32] val)(h, after, ended, prints, errors)
                  =>
                    after(ended, prints, errors, seen)
                    h.complete(true)
                  }))
              }))
          }))
      })

class \nodoc\ iso _TestRunJsonOnStdoutExit1 is UnitTest
  fun name(): String => "command/--json prints one document, exits 1"

  fun apply(h: TestHelper) =>
    _Ended(h, ["hefermotor"; "check"; "/pkgs/c"; "--path=/pkgs"; "--json"],
      _Fixture.fs(), _StubChecker,
      {(ended, out, err, codes)(h) =>
        h.assert_eq[I32](1, ended)
        h.assert_eq[USize](1, out.size())
        h.assert_eq[USize](0, err.size())
        try
          // One document, its keys in the emitter's order.
          h.assert_true(out(0)?.at("{\"format\":1,\"export_digest\":\""))
          h.assert_true(out(0)?.contains("\"}],\"groups\":[[\""))
          h.assert_true(out(0)?.contains("]],\"diagnostics\":[{\"code\""))
          h.assert_true(out(0)?.at("}]}\n", -4))
          _AssertJsonShape(h, out(0)?)?
          _AssertFixtureJson(h, out(0)?)?
        else
          h.fail("the document")
        end
        // 70 was set before scheduling, then overwritten once.
        h.assert_array_eq[I32]([70; 1], codes)
      })

class \nodoc\ iso _TestRunCleanExit0 is UnitTest
  fun name(): String => "command/nothing to report exits 0"

  fun apply(h: TestHelper) =>
    _Ended(h, ["hefermotor"; "check"; "/pkgs/d"; "--path=/pkgs"],
      _Fixture.fs(), _StubChecker,
      {(ended, out, err, codes)(h) =>
        h.assert_eq[I32](0, ended)
        h.assert_eq[USize](0, out.size())
        h.assert_eq[USize](0, err.size())
        h.assert_array_eq[I32]([70; 0], codes)
      })

class \nodoc\ iso _TestRunTextOnStderr is UnitTest
  """
  Text mode writes one rendering per diagnostic to stderr in ponyc's
  shape, nothing to stdout.
  """
  fun name(): String => "command/text goes to stderr in ponyc's shape"

  fun apply(h: TestHelper) =>
    _Ended(h, ["hefermotor"; "check"; "/pkgs/c"; "--path=/pkgs"],
      _Fixture.fs(), _StubChecker,
      {(ended, out, err, codes)(h) =>
        h.assert_eq[I32](1, ended)
        h.assert_eq[USize](0, out.size())
        h.assert_eq[USize](1, err.size())
        try
          h.assert_eq[String](
            "Error:\n/pkgs/c/c.pony:3:1: can't load package 'missing': " +
            "couldn't locate this path\nuse \"missing\"\n^\n", err(0)?)
        end
      })

class \nodoc\ iso _TestRunDefaultTargetIsBase is UnitTest
  fun name(): String => "command/no target checks the base directory"

  fun apply(h: TestHelper) =>
    let fs = _Fixture.fs()
    fs.file("/work/w.pony", "use \"d\"\n")
    _Ended(h, ["hefermotor"; "check"; "--path=/pkgs"; "--json"], fs,
      _StubChecker,
      {(ended, out, err, codes)(h) =>
        h.assert_eq[I32](0, ended)
        try
          let doc = _Json(h, out(0)?)?
          let dirs = Array[String]
          let packages = doc("packages")? as JSONArray
          for i in Range(0, packages.size()) do
            dirs.push((packages(i)? as JSONObject)("dir")? as String)
          end
          h.assert_array_eq[String](["/pkgs/builtin"; "/pkgs/d"; "/work"],
            dirs)
        else
          h.fail("the document")
        end
      })

class \nodoc\ iso _TestRunUsageErrorExit2 is UnitTest
  fun name(): String => "command/an unknown command exits 2"

  fun apply(h: TestHelper) =>
    _Ended(h, ["hefermotor"; "frob"], _Fixture.fs(), _StubChecker,
      {(ended, out, err, codes)(h) =>
        h.assert_eq[I32](2, ended)
        h.assert_eq[USize](1, err.size())
        try h.assert_true(err(0)?.contains("usage:")) end
        h.assert_array_eq[I32]([2], codes)
      })

class \nodoc\ iso _TestRunHelpExit0 is UnitTest
  fun name(): String => "command/help prints to stdout, exits 0"

  fun apply(h: TestHelper) =>
    _Ended(h, ["hefermotor"; "help"], _Fixture.fs(), _StubChecker,
      {(ended, out, err, codes)(h) =>
        h.assert_eq[I32](0, ended)
        h.assert_eq[USize](1, out.size())
        try h.assert_true(out(0)?.contains("check")) end
        h.assert_array_eq[I32]([0], codes)
      })

class \nodoc\ iso _TestRunRelativeBaseExit2 is UnitTest
  """
  A base directory that is not absolute, which the binary gets when the
  working directory cannot be read, cannot start a run.
  """
  fun name(): String => "command/a relative base exits 2"

  fun apply(h: TestHelper) =>
    let codes = _ExitCodes
    let err = _Capture
    let env = _TestEnv(h, ["hefermotor"; "check"; "--path=/pkgs"],
      _Capture, err, codes)
    h.long_test(2_000_000_000)
    Run(env, _Fixture.fs(), ".", _StubChecker)
      .next[None]({(ended: I32)(h, err) =>
        h.assert_eq[I32](2, ended)
        err.contents(Promise[Array[String] val].>next[None](
          {(errors: Array[String] val)(h) =>
            h.assert_eq[USize](1, errors.size())
            try h.assert_true(errors(0)?.contains("not absolute")) end
            h.complete(true)
          }))
      })

class \nodoc\ iso _TestRunBuiltinNotFoundExit2 is UnitTest
  fun name(): String => "command/no builtin anywhere exits 2"

  fun apply(h: TestHelper) =>
    _Ended(h, ["hefermotor"; "check"; "/pkgs/c"; "--path=/nowhere"],
      _Fixture.fs(), _StubChecker,
      {(ended, out, err, codes)(h) =>
        h.assert_eq[I32](2, ended)
        h.assert_eq[USize](1, err.size())
        try h.assert_true(err(0)?.contains("no 'builtin' package")) end
        h.assert_array_eq[I32]([2], codes)
      })

class \nodoc\ iso _TestRunBuiltinNotLoadedExit2 is UnitTest
  fun name(): String => "command/an empty builtin exits 2"

  fun apply(h: TestHelper) =>
    let fs: discover.MemoryFileSystem ref = discover.MemoryFileSystem
    fs.dir("/pkgs/builtin")
    fs.file("/pkgs/d/d.pony", "")
    fs.dir("/work")
    _Ended(h, ["hefermotor"; "check"; "/pkgs/d"; "--path=/pkgs"], fs,
      _StubChecker,
      {(ended, out, err, codes)(h) =>
        h.assert_eq[I32](2, ended)
        h.assert_eq[USize](1, err.size())
        try
          h.assert_true(err(0)?.contains("/pkgs/builtin"))
          h.assert_true(err(0)?.contains("no Pony source files"))
        end
        h.assert_array_eq[I32]([2], codes)
      })

class \nodoc\ iso _TestRunInternalErrorExit70 is UnitTest
  fun name(): String => "command/an internal error exits 70"

  fun apply(h: TestHelper) =>
    _Ended(h, ["hefermotor"; "check"; "/pkgs/d"; "--path=/pkgs"],
      _Fixture.fs(),
      _ReportingChecker([
        diag.Diagnostic(_Cause("internal/test", "broke"), diag.Nowhere)]),
      {(ended, out, err, codes)(h) =>
        h.assert_eq[I32](70, ended)
        h.assert_array_eq[I32]([70; 70], codes)
        h.assert_eq[USize](1, err.size())
      })

class \nodoc\ iso _TestRunRejectedReportLeaves70 is UnitTest
  fun name(): String => "command/a rejected report leaves exit 70"

  fun apply(h: TestHelper) =>
    let codes = _ExitCodes
    let env = _TestEnv(h,
      ["hefermotor"; "check"; "/pkgs/d"; "--path=/pkgs"],
      _Capture, _Capture, codes)
    h.long_test(2_000_000_000)
    Run(env, _Fixture.fs(), "/work", _RejectingChecker)
      .next[None](
        {(ended: I32) => h.fail("a rejected report must not fulfil") },
        {()(h, codes) =>
          codes.contents(Promise[Array[I32] val].>next[None](
            {(seen: Array[I32] val)(h) =>
              // The preset, and nothing after it.
              h.assert_array_eq[I32]([70], seen)
              h.complete(true)
            }))
        })

class \nodoc\ iso _TestRunJsonEscapes is UnitTest
  """
  A message holding a double quote, a backslash, a newline, a control
  byte and an invalid UTF-8 sequence comes back from the stdlib parser
  by value, the control byte intact and the bad byte as U+FFFD.
  """
  fun name(): String => "command/--json escapes what a message holds"

  fun apply(h: TestHelper) =>
    let message: String = "q\" b\\ n\n c\x01 bad" + _Bytes([0x80]) + "end"
    _Ended(h, ["hefermotor"; "check"; "/pkgs/d"; "--path=/pkgs"; "--json"],
      _Fixture.fs(),
      _ReportingChecker([
        diag.Diagnostic(_Cause("test/escape", message),
          diag.FileOnly("/pkgs/d", "d.pony"))
        diag.Diagnostic(_Cause("test/nowhere", "nowhere"), diag.Nowhere)]),
      {(ended, out, err, codes)(h) =>
        h.assert_eq[I32](1, ended)
        try
          let doc = _Json(h, out(0)?)?
          let diagnostics = doc("diagnostics")? as JSONArray
          let d = diagnostics(0)? as JSONObject
          h.assert_eq[String]("q\" b\\ n\n c\x01 bad\uFFFDend",
            d("message")? as String)
          let at = d("location")? as JSONObject
          h.assert_eq[USize](1, at.size())
          h.assert_eq[String]("/pkgs/d/d.pony", at("file")? as String)
          // A diagnostic with no file has a null location, and a
          // package this checker exported nothing for a null hash.
          h.assert_true((diagnostics(1)? as JSONObject)("location")? is None)
          let packages = doc("packages")? as JSONArray
          h.assert_eq[USize](2, packages.size())
          h.assert_true((packages(0)? as JSONObject)("export_hash")? is None)
        else
          h.fail("the document")
        end
      })

class \nodoc\ iso _TestRunStdlibSlotFirst is UnitTest
  """
  With a `ponyc` on `PATH` the packages beside it come before `--path`:
  the program's `builtin` is the slot's, not the one under `--path`.
  """
  fun name(): String => "command/the stdlib slot precedes --path"

  fun apply(h: TestHelper) =>
    let fs = _Fixture.fs()
    fs.file("/opt/pony/v1/bin/ponyc", "")
    fs.file("/opt/pony/v1/packages/builtin/builtin.pony", "primitive None\n")
    fs.link("/opt/pony/bin/ponyc", "/opt/pony/v1/bin/ponyc")
    _Ended(h, ["hefermotor"; "check"; "/pkgs/d"; "--path=/pkgs"; "--json"],
      fs, _StubChecker,
      {(ended, out, err, codes)(h) =>
        h.assert_eq[I32](0, ended)
        try
          let doc = _Json(h, out(0)?)?
          let groups = doc("groups")? as JSONArray
          h.assert_array_eq[String](["/opt/pony/v1/packages/builtin"],
            _Json.strings(groups(0)?)?)
        else
          h.fail("the document")
        end
      }
      where vars = ["PATH=/usr/bin:/opt/pony/bin"])

class \nodoc\ iso _TestRunReversedFixtureIsIdentical is UnitTest
  """
  The fixture with its files added in reverse gives, through `Run`, an
  identical JSON document.
  """
  fun name(): String => "command/insertion order does not reach the output"

  fun apply(h: TestHelper) =>
    let args: Array[String] val =
      ["hefermotor"; "check"; "/pkgs/c"; "--path=/pkgs"; "--json"]
    let first = _Capture
    let again = _Capture
    h.long_test(2_000_000_000)
    Run(_TestEnv(h, args, first, _Capture, _ExitCodes), _Fixture.fs(),
      "/work", _StubChecker)
      .next[None]({(ended: I32)(h, args, first, again) =>
        Run(_TestEnv(h, args, again, _Capture, _ExitCodes),
          _Fixture.reversed(), "/work", _StubChecker)
          .next[None]({(ended': I32)(h, first, again) =>
            first.contents(Promise[Array[String] val].>next[None](
              {(a: Array[String] val)(h, again) =>
                again.contents(Promise[Array[String] val].>next[None](
                  {(b: Array[String] val)(h, a) =>
                    h.assert_eq[USize](1, a.size())
                    h.assert_eq[USize](1, b.size())
                    try h.assert_eq[String](a(0)?, b(0)?) end
                    h.complete(true)
                  }))
              }))
          })
      })
