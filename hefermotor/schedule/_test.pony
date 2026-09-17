use "collections"
use "pony_test"
use "promises"
use diag = "../diagnostics"
use discover = "../discover"
use export = "../export"
use parse = "../parse"
use source = "../source"

actor \nodoc\ Main is TestList
  new create(env: Env) => PonyTest(env, this)
  new make() => None

  fun tag tests(test: PonyTest) =>
    test(_TestSlotsRejoinInIndexOrder)
    test(_TestFanOutEndToEnd)
    test(_TestFanOutEmpty)
    test(_TestReadySetStartsWithBuiltin)
    test(_TestReadySetHandsClosureExports)
    test(_TestReadySetReportsViolationsAsData)
    test(_TestReadySetOrderIndependentDeps)
    test(_TestReportDigest)
    test(_TestScheduleDeliversSortedReport)
    test(_TestScheduleHandsClosureExports)
    test(_TestParseRejoinsPerMember)
    test(_TestScheduleCycleIsOneGroup)
    test(_TestScheduleIsDeterministic)
    test(_TestScheduleReportsContractViolation)
    test(_TestScheduleBuiltinOnly)
    test(_TestScheduleStalls)
    test(_TestProgressDrains)

primitive \nodoc\ _NoParse
  """
  A parse step that reads nothing: no uses, no diagnostics.
  """
  fun apply(file: source.SourceFile): parse.ParsedFile =>
    parse.ParsedFile(file, recover val Array[parse.UseDecl] end,
      recover val Array[diag.Diagnostic] end)

class \nodoc\ val _FileNoted
  """
  A test-only cause: one per file that went through the parse step.
  """
  let path: String

  new val create(path': String) => path = path'

  fun code(): String => "schedule-test/file-noted"

  fun message(): String => "parsed " + path

primitive \nodoc\ _NotingParse
  """
  A parse step that leaves one diagnostic per file, so the path from
  `ParsedFile.diagnostics` into the report is exercised.
  """
  fun apply(file: source.SourceFile): parse.ParsedFile =>
    parse.ParsedFile(file, recover val Array[parse.UseDecl] end,
      recover val
        [diag.Diagnostic(_FileNoted(file.path()),
          diag.FileOnly(file.dir, file.name))]
      end)

primitive \nodoc\ _RecordingAnalysis
  """
  A test-only group analysis whose export signature names the member
  (by source hash: the fixture's members have distinct sources) and
  every dependency
  export it was handed, so a test reads the scheduling contract off the
  result. A production export must not do this.
  """
  fun apply(
    members: Array[discover.ParsedPackage] val,
    deps: export.DepExports,
    config: source.BuildConfig)
    : export.GroupResult
  =>
    let exports = recover iso Array[export.PackageExport] end
    for m in members.values() do
      let sig = recover iso Array[U8] end
      sig.append("member " + m.package.source_hash.hex())
      for dep in deps.entries.values() do
        sig.append("\ndep ")
        sig.append(dep.data.hash.hex())
      end
      exports.push(export.PackageExport(m.package.dir,
        export.ExportData(consume sig)))
    end
    export.GroupResult(consume exports,
      recover val Array[diag.Diagnostic] end)

primitive \nodoc\ _Noted
  fun code(): String => "schedule-test/noted"
  fun message(): String => "noted"

primitive \nodoc\ _DiagnosingAnalysis
  """
  One `FileOnly` diagnostic per member, so the test fails when group
  diagnostics are dropped from the report, and the final sort is
  exercised.
  """
  fun apply(
    members: Array[discover.ParsedPackage] val,
    deps: export.DepExports,
    config: source.BuildConfig)
    : export.GroupResult
  =>
    let exports = recover iso Array[export.PackageExport] end
    let diagnostics = recover iso Array[diag.Diagnostic] end
    for m in members.values() do
      exports.push(export.PackageExport(m.package.dir,
        export.ExportData.stub(m.package.source_hash)))
      diagnostics.push(diag.Diagnostic(
        _Noted, diag.FileOnly(m.package.dir.path, "x.pony")))
    end
    export.GroupResult(consume exports, consume diagnostics)

class \nodoc\ val _ParseOrderWrong
  let detail: String

  new val create(detail': String) => detail = detail'

  fun code(): String => "schedule-test/parse-order"

  fun message(): String => detail

primitive \nodoc\ _CheckingAnalysis
  """
  A test-only analysis that reports, as a diagnostic, any member whose
  parsed files are not its package's files in order. A pure analysis
  cannot assert; it can only report what it was given.
  """
  fun apply(
    members: Array[discover.ParsedPackage] val,
    deps: export.DepExports,
    config: source.BuildConfig)
    : export.GroupResult
  =>
    let found = recover iso Array[diag.Diagnostic] end
    let exports = recover iso Array[export.PackageExport] end
    for m in members.values() do
      if m.files.size() != m.package.files.size() then
        found.push(diag.Diagnostic(
          _ParseOrderWrong(m.package.name.text + ": count"), diag.Nowhere))
      end
      for (i, pf) in m.files.pairs() do
        try
          if pf.file.path() != m.package.files(i)?.path() then
            found.push(diag.Diagnostic(
              _ParseOrderWrong(pf.file.path() + " at " + i.string()),
              diag.Nowhere))
          end
        end
      end
      exports.push(export.PackageExport(m.package.dir,
        export.ExportData.stub(m.package.source_hash)))
    end
    export.GroupResult(consume exports, consume found)

primitive \nodoc\ _WrongExportsAnalysis
  """
  A test-only analysis that returns the members' exports in reverse
  order for a group of two or more, so the ready set refuses it.
  """
  fun apply(
    members: Array[discover.ParsedPackage] val,
    deps: export.DepExports,
    config: source.BuildConfig)
    : export.GroupResult
  =>
    let exports = recover iso Array[export.PackageExport] end
    for m in members.reverse().values() do
      exports.push(export.PackageExport(m.package.dir,
        export.ExportData.stub(m.package.source_hash)))
    end
    export.GroupResult(consume exports,
      recover val Array[diag.Diagnostic] end)

primitive \nodoc\ _Fixture
  """
  `builtin`; `a` and `b` use each other (one group); `c` is the target
  and uses `a`, `d` and a missing package; `d` uses nothing. Groups in
  canonical order: `builtin`, `{a, b}`, `d`, `c`. `c`'s closure is
  `{a, b}`, `d` and `builtin`; `d`'s is `builtin` alone. The base
  directory is `/work`, an empty directory.
  """
  fun apply(): discover.Program ? =>
    let fs: discover.MemoryFileSystem ref = discover.MemoryFileSystem
    fs.file("/pkgs/builtin/builtin.pony", "primitive None\n")
    fs.file("/pkgs/a/a.pony", "use \"b\"\n")
    fs.file("/pkgs/b/b.pony", "use \"a\"\n")
    fs.file("/pkgs/c/c.pony", "use \"a\"\nuse \"d\"\nuse \"missing\"\n")
    fs.file("/pkgs/d/d.pony", "primitive D\n")
    fs.dir("/work")
    discover.Discover(fs, discover.SearchRoots(["/pkgs"]), "/work",
      "/pkgs/c") as discover.Program

  fun config(): source.BuildConfig => source.BuildConfig.host()

  fun parsed(members: Array[discover.Package] val)
    : Array[discover.ParsedPackage] val
  =>
    """
    Each member with its files run through `_NoParse`, as `_GroupRun`
    builds them after its fan-out.
    """
    let out = recover iso Array[discover.ParsedPackage] end
    for m in members.values() do
      let files = recover iso Array[parse.ParsedFile] end
      for f in m.files.values() do files.push(_NoParse(f)) end
      out.push(discover.ParsedPackage(m, consume files))
    end
    consume out

  fun stub_result(members: Array[discover.Package] val)
    : export.GroupResult
  =>
    """
    A well-formed result for exactly these members, in order.
    """
    let exports = recover iso Array[export.PackageExport] end
    for m in members.values() do
      exports.push(export.PackageExport(m.dir,
        export.ExportData.stub(m.source_hash)))
    end
    export.GroupResult(consume exports,
      recover val Array[diag.Diagnostic] end)

  fun text_of(report: Report, program: discover.Program, path: String)
    : String ?
  =>
    """
    The recording export's signature bytes for the package at `path`.
    """
    String.from_array(
      (report.export_of(program.package(path)?.dir)
        as export.ExportData).signature)

class \nodoc\ iso _TestSlotsRejoinInIndexOrder is UnitTest
  fun name(): String => "schedule/slots rejoin by index, not arrival"

  fun apply(h: TestHelper) =>
    // Arrivals in reverse index order, delivered by the test itself, so
    // an append-on-arrival implementation cannot pass by luck.
    let slots = _Slots[USize](4)
    h.assert_true(slots.take() is _Filling)
    h.assert_true(slots.arrived(3, 30) is None)
    h.assert_true(slots.arrived(2, 20) is None)
    h.assert_true(slots.arrived(4, 40) is _SlotOutOfRange)
    h.assert_true(slots.arrived(2, 21) is _SlotFilled)
    h.assert_true(slots.take() is _Filling)
    h.assert_true(slots.arrived(1, 10) is None)
    h.assert_true(slots.arrived(0, 0) is None)
    match slots.take()
    | let out: Array[USize] val =>
      h.assert_array_eq[USize]([0; 10; 20; 30], out)
    | _Filling => h.fail("four arrivals did not fill four slots")
    end
    // A slot holds None as a value like any other.
    let none = _Slots[(USize | None)](1)
    h.assert_true(none.arrived(0, None) is None)
    match none.take()
    | let out: Array[(USize | None)] val => h.assert_eq[USize](1, out.size())
    | _Filling => h.fail("one arrival did not fill one slot")
    end

primitive \nodoc\ _Identity
  fun apply(input: USize): USize => input

class \nodoc\ iso _TestFanOutEndToEnd is UnitTest
  fun name(): String => "schedule/fan-out wires tasks and fulfils once"

  fun apply(h: TestHelper) =>
    // End to end over 64 actors: the task wiring and the last-arrival
    // fulfil. This test cannot control arrival order, so it does not
    // check slot order.
    let numbered = recover val
      let a = Array[USize]
      for i in Range(0, 64) do a.push(i) end
      a
    end
    h.long_test(2_000_000_000)
    _FanOut[USize, USize](_Identity, numbered)
      .next[None]({(out: Array[USize] val) =>
        h.assert_array_eq[USize](numbered, out)
        h.complete(true)
      })

class \nodoc\ iso _TestFanOutEmpty is UnitTest
  fun name(): String => "schedule/fan-out over nothing fulfils"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)
    _FanOut[USize, USize](_Identity, [])
      .next[None]({(out: Array[USize] val) =>
        h.assert_eq[USize](0, out.size())
        h.complete(true)
      })

class \nodoc\ iso _TestReadySetStartsWithBuiltin is UnitTest
  fun name(): String => "schedule/ready set starts with builtin alone"

  fun apply(h: TestHelper) ? =>
    let program = _Fixture()?
    let ready = _ReadySet(program)
    h.assert_false(ready.done())
    let builtin = program.group_of(program.builtin)?
    h.assert_array_eq[USize]([builtin], ready.ready())
    // Handed out once: a second call yields nothing until it completes.
    h.assert_eq[USize](0, ready.ready().size())
    h.assert_eq[USize](1, ready.members(builtin).size())
    h.assert_eq[USize](0, ready.deps_for(builtin).entries.size())

class \nodoc\ iso _TestReadySetHandsClosureExports is UnitTest
  fun name(): String => "schedule/ready set hands a group its closure"

  fun apply(h: TestHelper) ? =>
    // Drive the ready set by hand so every hand-off is visible.
    let program = _Fixture()?
    let config = _Fixture.config()
    let ready = _ReadySet(program)
    var seen: USize = 0
    while not ready.done() do
      // Nothing is running at the top of this loop, so an empty ready
      // set here is a bug, not a wait; fail rather than hang.
      let batch = ready.ready()
      if batch.size() == 0 then
        h.fail("ready set stalled with groups left")
        return
      end
      for g in batch.values() do
        let deps = ready.deps_for(g)
        for n in program.groups(g)?.needs.values() do
          for m in program.groups(n)?.members.values() do
            h.assert_true(deps.find(m.dir) isnt None,
              "export of " + m.name.text + " missing for group "
                + g.string())
          end
        end
        seen = seen + ready.members(g).size()
        match ready.complete(g, _RecordingAnalysis(
          _Fixture.parsed(ready.members(g)), deps, config))
        | None => None
        | _NotRunning => h.fail("complete rejected a running group")
        | _ExportsMismatch => h.fail("complete rejected right exports")
        end
      end
    end
    h.assert_eq[USize](5, seen)
    let report = ready.report()
    let a = report.export_of(program.package("/pkgs/a")?.dir)
      as export.ExportData
    let b = report.export_of(program.package("/pkgs/b")?.dir)
      as export.ExportData
    let d = report.export_of(program.package("/pkgs/d")?.dir)
      as export.ExportData
    let bi = report.export_of(program.builtin) as export.ExportData
    // c's closure is a, b (through a), d and builtin: all four present.
    let c_text = _Fixture.text_of(report, program, "/pkgs/c")?
    h.assert_true(c_text.contains(a.hash.hex()))
    h.assert_true(c_text.contains(b.hash.hex()))
    h.assert_true(c_text.contains(d.hash.hex()))
    h.assert_true(c_text.contains(bi.hash.hex()))
    // d's closure is builtin alone; a and b are not handed to it.
    let d_text = _Fixture.text_of(report, program, "/pkgs/d")?
    h.assert_true(d_text.contains(bi.hash.hex()))
    h.assert_false(d_text.contains(a.hash.hex()))
    // Inside a group members are not handed each other's exports.
    let a_text = _Fixture.text_of(report, program, "/pkgs/a")?
    h.assert_false(a_text.contains(b.hash.hex()))
    h.assert_false(a_text.contains(d.hash.hex()))
    // The report holds every export in directory order, and
    // discovery's diagnostic.
    h.assert_eq[USize](5, report.exports.size())
    h.assert_eq[String]("/pkgs/a", report.exports(0)?.dir.path)
    h.assert_eq[String]("/pkgs/d", report.exports(4)?.dir.path)
    h.assert_eq[USize](1, report.diagnostics.size())
    h.assert_true(report.has_errors())
    h.assert_false(report.has_internal_errors())

class \nodoc\ iso _TestReadySetReportsViolationsAsData is UnitTest
  fun name(): String => "schedule/contract violations are data"

  fun apply(h: TestHelper) ? =>
    let program = _Fixture()?
    let ready = _ReadySet(program)
    let builtin = program.group_of(program.builtin)?
    let ab = program.group_of(program.package("/pkgs/a")?.dir)?
    let none = recover val Array[diag.Diagnostic] end
    let empty = export.GroupResult(
      recover val Array[export.PackageExport] end, none)
    // Not running yet: nothing has been handed out.
    h.assert_true(ready.complete(builtin, empty) is _NotRunning)
    h.assert_true(ready.ready().contains(builtin))
    // Running, but the result names no export for the one member.
    h.assert_true(ready.complete(builtin, empty) is _ExportsMismatch)
    // Still running after a rejected completion: the right result lands.
    let ok = _Fixture.stub_result(ready.members(builtin))
    h.assert_true(ready.complete(builtin, ok) is None)
    // Done: a second completion is not running.
    h.assert_true(ready.complete(builtin, ok) is _NotRunning)
    // A group index past the end is not running either.
    h.assert_true(ready.complete(99, ok) is _NotRunning)
    // {a, b} is ready now; the dirs must be exactly the members' in
    // order, so a missing member, an extra package, and the right
    // members in the wrong order are each a mismatch.
    h.assert_true(ready.ready().contains(ab))
    let a = program.package("/pkgs/a")?
    let b = program.package("/pkgs/b")?
    let c = program.package("/pkgs/c")?
    let stub = {(p: discover.Package): export.PackageExport =>
      export.PackageExport(p.dir, export.ExportData.stub(p.source_hash))
    } val
    let a_only = export.GroupResult(recover val [stub(a)] end, none)
    h.assert_true(ready.complete(ab, a_only) is _ExportsMismatch)
    let a_b_c = export.GroupResult(
      recover val [stub(a); stub(b); stub(c)] end, none)
    h.assert_true(ready.complete(ab, a_b_c) is _ExportsMismatch)
    let b_a = export.GroupResult(recover val [stub(b); stub(a)] end, none)
    h.assert_true(ready.complete(ab, b_a) is _ExportsMismatch)
    // A rejected result recorded nothing.
    h.assert_true(ready.report().export_of(a.dir) is None)
    let a_b = export.GroupResult(recover val [stub(a); stub(b)] end, none)
    h.assert_true(ready.complete(ab, a_b) is None)
    h.assert_true(ready.report().export_of(a.dir) isnt None)
    // A noted diagnostic reaches the report.
    ready.note(diag.Diagnostic(InternalError("scheduler-test", "noted"),
      diag.Nowhere))
    h.assert_true(ready.report().has_internal_errors())

class \nodoc\ iso _TestReadySetOrderIndependentDeps is UnitTest
  """
  Two admissible completion orders hand every group the same
  `DepExports`, entry for entry: `d` completed before `{a, b}` and
  after.
  """
  fun name(): String => "schedule/deps do not depend on completion order"

  fun apply(h: TestHelper) ? =>
    let program = _Fixture()?
    let canonical = _run_in_order(h, program, false)?
    let shuffled = _run_in_order(h, program, true)?
    h.assert_eq[USize](canonical.size(), shuffled.size())
    for (g, entries) in canonical.pairs() do
      let other = shuffled(g)?
      h.assert_eq[USize](entries.size(), other.size(), "group " + g.string())
      for (i, e) in entries.pairs() do
        h.assert_true(e.dir == other(i)?.dir, "group " + g.string())
        h.assert_eq[source.ContentHash](e.data.hash, other(i)?.data.hash)
      end
    end

  fun _run_in_order(h: TestHelper, program: discover.Program, reverse: Bool)
    : Array[Array[export.PackageExport] val] ?
  =>
    """
    Drives the ready set, completing each batch in index order or in
    reverse, and returns each group's `DepExports` entries by group.
    """
    let ready = _ReadySet(program)
    let deps = Array[Array[export.PackageExport] val]
      .init(recover val Array[export.PackageExport] end,
        program.groups.size())
    while not ready.done() do
      let batch = ready.ready()
      if batch.size() == 0 then error end
      let order: Array[USize] val =
        if reverse then recover val batch.reverse() end else batch end
      for g in order.values() do
        let d = ready.deps_for(g)
        deps(g)? = d.entries
        match ready.complete(g, _RecordingAnalysis(
          _Fixture.parsed(ready.members(g)), d, _Fixture.config()))
        | None => None
        else
          h.fail("complete refused a well-formed result")
        end
      end
    end
    deps

class \nodoc\ iso _TestReportDigest is UnitTest
  """
  The export digest is the same for two reports whose exports are
  permuted, and differs when one export's hash does.
  """
  fun name(): String => "schedule/export digest is order-free"

  fun apply(h: TestHelper) ? =>
    let program = _Fixture()?
    let a = export.PackageExport(program.package("/pkgs/a")?.dir,
      export.ExportData([1]))
    let b = export.PackageExport(program.package("/pkgs/b")?.dir,
      export.ExportData([2]))
    let b2 = export.PackageExport(program.package("/pkgs/b")?.dir,
      export.ExportData([3]))
    let none = recover val Array[diag.Diagnostic] end
    let ab = Report(none, [a; b])
    let ba = Report(none, [b; a])
    let ab2 = Report(none, [a; b2])
    h.assert_eq[source.ContentHash](ab.export_digest(), ba.export_digest())
    h.assert_ne[source.ContentHash](ab.export_digest(), ab2.export_digest())
    h.assert_ne[source.ContentHash](ab.export_digest(),
      Report(none, [a]).export_digest())
    h.assert_false(ab.has_errors())
    h.assert_true((ab.export_of(a.dir) as export.ExportData).hash ==
      a.data.hash)
    h.assert_true(ab.export_of(program.builtin) is None)

primitive \nodoc\ _CountByCode
  """
  How many diagnostics in the report carry each code.
  """
  fun apply(r: Report): Map[String, USize] =>
    let counts = Map[String, USize]
    for d in r.diagnostics.values() do
      counts.upsert(d.cause.code(), 1, {(acc, inc) => acc + inc })
    end
    counts

class \nodoc\ iso _TestScheduleDeliversSortedReport is UnitTest
  fun name(): String => "schedule/Schedule delivers one sorted report"

  fun apply(h: TestHelper) ? =>
    let program = _Fixture()?
    h.long_test(2_000_000_000)
    Schedule(program, _Fixture.config(), _NotingParse, _DiagnosingAnalysis)
      .next[None]({(r: Report) =>
        h.assert_true(r.has_errors())
        h.assert_false(r.has_internal_errors())
        // One noted file per package (five), one note per member
        // (five), one from discovery (missing), counted per code, so a
        // dropped class cannot hide behind another's surplus.
        let counts = _CountByCode(r)
        h.assert_eq[USize](5,
          counts.get_or_else("schedule-test/file-noted", 0))
        h.assert_eq[USize](5,
          counts.get_or_else("schedule-test/noted", 0))
        h.assert_eq[USize](1,
          counts.get_or_else("discover/use-not-found", 0))
        h.assert_eq[USize](3, counts.size())
        // Each file was parsed exactly once: the five noted paths are
        // the fixture's five files.
        let noted = Set[String]
        for d in r.diagnostics.values() do
          match d.cause
          | let f: _FileNoted => noted.set(f.path)
          end
        end
        for p in ["/pkgs/a/a.pony"; "/pkgs/b/b.pony"; "/pkgs/c/c.pony"
          "/pkgs/d/d.pony"; "/pkgs/builtin/builtin.pony"].values()
        do
          h.assert_true(noted.contains(p), p)
        end
        try
          // Nowhere < FileOnly < Span, so the use-not-found span sorts
          // last and the ten FileOnly entries are in path order, a's
          // before builtin's although builtin's group reported first.
          let first = r.diagnostics(0)?
          h.assert_eq[String]("schedule-test/file-noted",
            first.cause.code())
          match first.location
          | let f: diag.FileOnly =>
            h.assert_eq[String]("/pkgs/a/a.pony", f.path())
          else
            h.fail("expected a file")
          end
          let last = r.diagnostics(10)?
          h.assert_eq[String]("discover/use-not-found", last.cause.code())
        else
          h.fail("eleven diagnostics")
        end
        h.complete(true)
      })

class \nodoc\ iso _TestScheduleHandsClosureExports is UnitTest
  fun name(): String => "schedule/Schedule hands closures too"

  fun apply(h: TestHelper) ? =>
    // Two of the hand-driven test's closure checks, run through
    // Schedule, so a scheduler that dispatched a group early would show
    // a missing dependency hash here.
    let program = _Fixture()?
    h.long_test(2_000_000_000)
    Schedule(program, _Fixture.config(), _NoParse, _RecordingAnalysis)
      .next[None]({(r: Report) =>
        try
          let b = r.export_of(program.package("/pkgs/b")?.dir)
            as export.ExportData
          let a = r.export_of(program.package("/pkgs/a")?.dir)
            as export.ExportData
          h.assert_true(
            _Fixture.text_of(r, program, "/pkgs/c")?.contains(b.hash.hex()))
          h.assert_false(
            _Fixture.text_of(r, program, "/pkgs/d")?.contains(a.hash.hex()))
          h.assert_eq[USize](5, r.exports.size())
        else
          h.fail("an export was missing from the report")
        end
        h.complete(true)
      })

class \nodoc\ iso _TestParseRejoinsPerMember is UnitTest
  """
  A member with several files gets exactly its own files back, in
  order: `a` has three, `b` one, `builtin` two.
  """
  fun name(): String => "schedule/parsed files rejoin under their member"

  fun apply(h: TestHelper) ? =>
    let fs: discover.MemoryFileSystem ref = discover.MemoryFileSystem
    fs.file("/pkgs/builtin/builtin.pony", "primitive None\n")
    fs.file("/pkgs/builtin/more.pony", "primitive More\n")
    fs.file("/pkgs/a/z.pony", "primitive Z\n")
    fs.file("/pkgs/a/a.pony", "use \"b\"\n")
    fs.file("/pkgs/a/m.pony", "primitive M\n")
    fs.file("/pkgs/b/b.pony", "primitive B\n")
    fs.dir("/work")
    let program = discover.Discover(fs, discover.SearchRoots(["/pkgs"]),
      "/work", "/pkgs/a") as discover.Program
    h.long_test(2_000_000_000)
    Schedule(program, _Fixture.config(), _NoParse, _CheckingAnalysis)
      .next[None]({(r: Report) =>
        for d in r.diagnostics.values() do
          h.assert_ne[String]("schedule-test/parse-order", d.cause.code(),
            d.cause.message())
        end
        h.assert_eq[USize](0, r.diagnostics.size())
        h.assert_eq[USize](3, r.exports.size())
        h.complete(true)
      })

class \nodoc\ iso _TestScheduleCycleIsOneGroup is UnitTest
  fun name(): String => "schedule/a use cycle is one group"

  fun apply(h: TestHelper) ? =>
    let program = _Fixture()?
    let a = program.group_of(program.package("/pkgs/a")?.dir)?
    let b = program.group_of(program.package("/pkgs/b")?.dir)?
    let c = program.group_of(program.package("/pkgs/c")?.dir)?
    let d = program.group_of(program.package("/pkgs/d")?.dir)?
    h.assert_eq[USize](a, b)
    h.assert_true(a < c)
    h.assert_true(d < c)
    h.assert_eq[USize](0, program.group_of(program.builtin)?)

class \nodoc\ iso _TestScheduleIsDeterministic is UnitTest
  fun name(): String => "schedule/two runs produce equal reports"

  fun apply(h: TestHelper) ? =>
    let program = _Fixture()?
    let config = _Fixture.config()
    h.long_test(2_000_000_000)
    Schedule(program, config, _NotingParse, _RecordingAnalysis)
      .next[None]({(first: Report)(h, program, config) =>
        Schedule(program, config, _NotingParse, _RecordingAnalysis)
          .next[None]({(second: Report)(h, first) =>
            h.assert_eq[USize](first.diagnostics.size(),
              second.diagnostics.size())
            for (i, d) in first.diagnostics.pairs() do
              try
                h.assert_true(d == second.diagnostics(i)?, i.string())
              end
            end
            h.assert_eq[source.ContentHash](first.export_digest(),
              second.export_digest())
            h.complete(true)
          })
      })

class \nodoc\ iso _TestScheduleReportsContractViolation is UnitTest
  """
  An analysis whose result the ready set refuses: the promise is still
  fulfilled, with one `internal/scheduler-contract` diagnostic, and a
  group that needs the refused one never runs.
  """
  fun name(): String => "schedule/a refused result is an internal error"

  fun apply(h: TestHelper) ? =>
    let program = _Fixture()?
    h.long_test(2_000_000_000)
    Schedule(program, _Fixture.config(), _NoParse, _WrongExportsAnalysis)
      .next[None]({(r: Report) =>
        h.assert_true(r.has_internal_errors())
        let counts = _CountByCode(r)
        h.assert_eq[USize](1,
          counts.get_or_else("internal/scheduler-contract", 0))
        h.assert_eq[USize](0,
          counts.get_or_else("internal/scheduler-stalled", 0))
        for d in r.diagnostics.values() do
          if d.cause.code() == "internal/scheduler-contract" then
            // The detail names the group and the reason.
            h.assert_true(d.cause.message().contains("group 1"),
              d.cause.message())
            h.assert_true(d.cause.message().contains("exports"),
              d.cause.message())
          end
        end
        // builtin and d are singletons, so their reversed results are
        // fine; {a, b} is refused, and c, which needs it, never runs.
        try
          h.assert_true(r.export_of(program.builtin) isnt None)
          h.assert_true(r.export_of(program.package("/pkgs/d")?.dir)
            isnt None)
          h.assert_true(r.export_of(program.package("/pkgs/a")?.dir) is None)
          h.assert_true(r.export_of(program.package("/pkgs/c")?.dir) is None)
        else
          h.fail("fixture packages")
        end
        h.complete(true)
      })

class \nodoc\ iso _TestScheduleBuiltinOnly is UnitTest
  """
  A program whose root failed runs `builtin` alone and reports the root
  diagnostic beside `builtin`'s export.
  """
  fun name(): String => "schedule/a builtin-only program"

  fun apply(h: TestHelper) ? =>
    let fs: discover.MemoryFileSystem ref = discover.MemoryFileSystem
    fs.file("/pkgs/builtin/builtin.pony", "primitive None\n")
    fs.dir("/work")
    let program = discover.Discover(fs, discover.SearchRoots(["/pkgs"]),
      "/work", "/nowhere") as discover.Program
    h.long_test(2_000_000_000)
    Schedule(program, _Fixture.config(), _NoParse, _DiagnosingAnalysis)
      .next[None]({(r: Report) =>
        let counts = _CountByCode(r)
        h.assert_eq[USize](1,
          counts.get_or_else("discover/root-not-loaded", 0))
        h.assert_eq[USize](1, counts.get_or_else("schedule-test/noted", 0))
        h.assert_eq[USize](1, r.exports.size())
        h.assert_true(r.export_of(program.builtin) isnt None)
        h.complete(true)
      })

class \nodoc\ iso _TestScheduleStalls is UnitTest
  """
  A program whose one group needs itself can never become ready: the
  promise is still fulfilled, with one `internal/scheduler-stalled`
  diagnostic and no export.
  """
  fun name(): String => "schedule/a stalled ready set is an internal error"

  fun apply(h: TestHelper) ? =>
    let builtin = _Fixture()?.builtin
    let program = discover.Program([discover.Group(0, [], [0])], builtin,
      None, [])
    h.long_test(2_000_000_000)
    Schedule(program, _Fixture.config(), _NoParse, _DiagnosingAnalysis)
      .next[None]({(r: Report) =>
        h.assert_true(r.has_internal_errors())
        h.assert_eq[USize](1, r.diagnostics.size())
        h.assert_eq[USize](1,
          _CountByCode(r).get_or_else("internal/scheduler-stalled", 0))
        h.assert_eq[USize](0, r.exports.size())
        h.complete(true)
      })

class \nodoc\ iso _TestProgressDrains is UnitTest
  """
  The scheduler's decisions, driven by hand in a fixed order: after a
  refused result nothing more is launched, not even a group that became
  ready; a result already in flight is still recorded; and the report
  comes once with the last of them, with no stall noted. The fixture
  gains `e`, which uses `d` alone, so that `d`'s completion makes a
  group ready while draining.
  """
  fun name(): String => "schedule/progress drains after a refusal"

  fun apply(h: TestHelper) ? =>
    let fs: discover.MemoryFileSystem ref = discover.MemoryFileSystem
    fs.file("/pkgs/builtin/builtin.pony", "primitive None\n")
    fs.file("/pkgs/a/a.pony", "use \"b\"\n")
    fs.file("/pkgs/b/b.pony", "use \"a\"\n")
    fs.file("/pkgs/c/c.pony", "use \"a\"\nuse \"d\"\nuse \"e\"\n")
    fs.file("/pkgs/d/d.pony", "primitive D\n")
    fs.file("/pkgs/e/e.pony", "use \"d\"\n")
    fs.dir("/work")
    let program = discover.Discover(fs, discover.SearchRoots(["/pkgs"]),
      "/work", "/pkgs/c") as discover.Program
    let progress = _Progress(program)
    let builtin = program.group_of(program.builtin)?
    let ab = program.group_of(program.package("/pkgs/a")?.dir)?
    let d = program.group_of(program.package("/pkgs/d")?.dir)?
    let first = progress.start()
    h.assert_array_eq[USize]([builtin], first.launch)
    h.assert_true(first.report is None)
    let second = progress.finished(builtin,
      _Fixture.stub_result(progress.members(builtin)))
    h.assert_array_eq[USize]([ab; d], second.launch)
    h.assert_true(second.report is None)
    // {a, b}'s result is refused: nothing launches, and d is still in
    // flight so there is no report yet.
    let refused = progress.finished(ab, _WrongExportsAnalysis(
      _Fixture.parsed(progress.members(ab)), progress.deps_for(ab),
      _Fixture.config()))
    h.assert_eq[USize](0, refused.launch.size())
    h.assert_true(refused.report is None)
    // d's result lands while draining: recorded, e is ready but not
    // launched, and the run is over.
    let last = progress.finished(d,
      _Fixture.stub_result(progress.members(d)))
    h.assert_eq[USize](0, last.launch.size())
    match last.report
    | let r: Report =>
      let counts = _CountByCode(r)
      h.assert_eq[USize](1,
        counts.get_or_else("internal/scheduler-contract", 0))
      h.assert_eq[USize](0,
        counts.get_or_else("internal/scheduler-stalled", 0))
      h.assert_true(r.export_of(program.package("/pkgs/d")?.dir) isnt None)
      h.assert_true(r.export_of(program.package("/pkgs/a")?.dir) is None)
      h.assert_eq[USize](2, r.exports.size())
    | None => h.fail("the last result in flight ends the run")
    end
