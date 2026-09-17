use "collections"
use "files"
use "pony_test"
use diag = "../diagnostics"
use parse = "../parse"
use source = "../source"

primitive \nodoc\ _ProgramTests
  fun apply(test: PonyTest) =>
    test(_TestCondenseChain)
    test(_TestCondenseDiamond)
    test(_TestCondenseCycles)
    test(_TestCondenseTieBreak)
    test(_TestCondenseSelfUse)
    test(_TestDiscoverUseOrder)
    test(_TestCondenseLongChain)
    test(_TestCondenseStdlibShape)
    test(_TestCondenseDepsTable)
    test(_TestDiscoverFixture)
    test(_TestDiscoverLookups)
    test(_TestDiscoverUnreadableFile)
    test(_TestDiscoverUseFailures)
    test(_TestDiscoverUseSchemes)
    test(_TestDiscoverAliasedDirectory)
    test(_TestDiscoverRoot)
    test(_TestDiscoverBuiltin)
    test(_TestDiscoverNames)
    test(_TestSourceHash)
    test(_TestMembershipIsGraphOnly)

primitive \nodoc\ _Pkg
  """
  A package with no files, for graph tests.
  """
  fun apply(path: String): Package =>
    Package(PackageDir._create(path), source.PackageName(_Paths.base(path)),
      recover val Array[source.SourceFile] end,
      recover val Array[PackageUse] end)

  fun dir(path: String): PackageDir => PackageDir._create(path)

  fun edges(pairs: Array[(String, String)] val)
    : Array[(PackageDir, PackageDir)] val
  =>
    let out = recover iso Array[(PackageDir, PackageDir)] end
    for (a, b) in pairs.values() do out.push((dir(a), dir(b))) end
    consume out

  fun packages(paths: Array[String] val): Array[Package] val =>
    let out = recover iso Array[Package] end
    for p in paths.values() do out.push(_Pkg(p)) end
    consume out

  fun members(g: Group): Array[String] =>
    let out = Array[String]
    for m in g.members.values() do out.push(m.dir.path) end
    out

  fun groups(h: TestHelper, groups': Array[Group] val,
    expected: Array[Array[String] val] val)
  =>
    """
    Asserts the groups' members and order, and that each group carries
    its own index.
    """
    h.assert_eq[USize](expected.size(), groups'.size(), "group count")
    for (i, g) in groups'.pairs() do
      h.assert_eq[USize](i, g.index)
      try
        h.assert_array_eq[String](expected(i)?, members(g), "group " +
          i.string())
      end
    end

class \nodoc\ iso _TestCondenseChain is UnitTest
  fun name(): String => "discover/condense: a chain"

  fun apply(h: TestHelper) ? =>
    let groups = Condense(_Pkg.packages(["/p/a"; "/p/b"; "/p/c"]),
      _Pkg.edges([("/p/a", "/p/b"); ("/p/b", "/p/c")]))
    _Pkg.groups(h, groups, [["/p/c"]; ["/p/b"]; ["/p/a"]])
    h.assert_array_eq[USize]([], groups(0)?.needs)
    h.assert_array_eq[USize]([0], groups(1)?.needs)
    h.assert_array_eq[USize]([0; 1], groups(2)?.needs)

class \nodoc\ iso _TestCondenseDiamond is UnitTest
  """
  `needs` is the closure: the top of a diamond needs both sides and the
  bottom, and the sides are ordered by directory.
  """
  fun name(): String => "discover/condense: a diamond"

  fun apply(h: TestHelper) ? =>
    let groups = Condense(_Pkg.packages(["/p/d"; "/p/c"; "/p/b"; "/p/a"]),
      _Pkg.edges([("/p/a", "/p/b"); ("/p/a", "/p/c"); ("/p/b", "/p/d")
        ("/p/c", "/p/d"); ("/p/a", "/p/b")]))
    _Pkg.groups(h, groups, [["/p/d"]; ["/p/b"]; ["/p/c"]; ["/p/a"]])
    h.assert_array_eq[USize]([0], groups(1)?.needs)
    h.assert_array_eq[USize]([0], groups(2)?.needs)
    h.assert_array_eq[USize]([0; 1; 2], groups(3)?.needs)

class \nodoc\ iso _TestCondenseCycles is UnitTest
  """
  A two-cycle is one group; a three-cycle with a tail is two, the tail
  first; an edge to a directory that is not a package is ignored.
  """
  fun name(): String => "discover/condense: cycles"

  fun apply(h: TestHelper) ? =>
    let two = Condense(_Pkg.packages(["/p/a"; "/p/b"; "/p/c"]),
      _Pkg.edges([("/p/a", "/p/b"); ("/p/b", "/p/a"); ("/p/c", "/p/a")]))
    _Pkg.groups(h, two, [["/p/a"; "/p/b"]; ["/p/c"]])
    h.assert_array_eq[USize]([0], two(1)?.needs)
    let three = Condense(_Pkg.packages(["/p/a"; "/p/b"; "/p/c"; "/p/d"]),
      _Pkg.edges([("/p/a", "/p/b"); ("/p/b", "/p/c"); ("/p/c", "/p/a")
        ("/p/c", "/p/d"); ("/p/d", "/p/missing")]))
    _Pkg.groups(h, three, [["/p/d"]; ["/p/a"; "/p/b"; "/p/c"]])
    h.assert_array_eq[USize]([0], three(1)?.needs)

class \nodoc\ iso _TestCondenseTieBreak is UnitTest
  """
  Of two ready groups, the one whose smallest member sorts lowest comes
  first: a cycle whose smallest member sorts before a singleton goes
  first even though its largest member sorts after it, and a singleton
  goes before a cycle it sorts under whatever order the cycle was found
  in.
  """
  fun name(): String => "discover/condense: the tie-break"

  fun apply(h: TestHelper) =>
    _Pkg.groups(h, Condense(_Pkg.packages(["/p/z"; "/p/m"; "/p/a"]),
      _Pkg.edges([("/p/a", "/p/z"); ("/p/z", "/p/a")])),
      [["/p/a"; "/p/z"]; ["/p/m"]])
    _Pkg.groups(h, Condense(_Pkg.packages(["/p/a"; "/p/m"; "/p/y"; "/p/z"]),
      _Pkg.edges([("/p/a", "/p/y"); ("/p/y", "/p/z"); ("/p/z", "/p/y")])),
      [["/p/m"]; ["/p/y"; "/p/z"]; ["/p/a"]])

class \nodoc\ iso _TestCondenseSelfUse is UnitTest
  fun name(): String => "discover/condense: a package using itself"

  fun apply(h: TestHelper) ? =>
    let groups = Condense(_Pkg.packages(["/p/a"]),
      _Pkg.edges([("/p/a", "/p/a")]))
    _Pkg.groups(h, groups, [["/p/a"]])
    h.assert_array_eq[USize]([], groups(0)?.needs)

class \nodoc\ iso _TestCondenseLongChain is UnitTest
  """
  A thousand packages in a chain: every group is placed in order and
  every closure is complete.
  """
  fun name(): String => "discover/condense: a thousand-package chain"

  fun apply(h: TestHelper) ? =>
    let n: USize = 1000
    let paths = recover iso Array[String] end
    let pairs = recover iso Array[(String, String)] end
    for i in Range(0, n) do
      paths.push("/p/" + _Pad(i))
      if i > 0 then pairs.push(("/p/" + _Pad(i - 1), "/p/" + _Pad(i))) end
    end
    let groups = Condense(_Pkg.packages(consume paths),
      _Pkg.edges(consume pairs))
    h.assert_eq[USize](n, groups.size())
    h.assert_eq[String]("/p/" + _Pad(n - 1), groups(0)?.members(0)?.dir.path)
    h.assert_eq[String]("/p/" + _Pad(0), groups(n - 1)?.members(0)?.dir.path)
    h.assert_eq[USize](0, groups(0)?.needs.size())
    h.assert_eq[USize](n - 1, groups(n - 1)?.needs.size())
    h.assert_eq[USize](499, groups(499)?.needs.size())

primitive \nodoc\ _Pad
  fun apply(i: USize): String =>
    let s: String = i.string()
    if s.size() >= 4 then s
    else
      let padded: String = String.from_array(Array[U8].init('0', 4 - s.size()))
      padded + s
    end

class \nodoc\ iso _TestCondenseStdlibShape is UnitTest
  """
  The shape of the standard library's `use` graph, as a hand-written
  edge list: four cycles, everything else a singleton, `builtin` first.
  """
  fun name(): String => "discover/condense: the stdlib's shape"

  fun apply(h: TestHelper) ? =>
    let s = "/std/"
    let names: Array[String] val = [
      "builtin"; "collections"; "pony_test"; "random"; "time"; "capsicum"
      "files"; "term"; "collections/persistent"; "itertools"; "pony_check"
      "net"; "net/notifier"; "format"; "json"; "buffered"; "signals"]
    let paths = recover iso Array[String] end
    let pairs = recover iso Array[(String, String)] end
    for n in names.values() do
      paths.push(s + n)
      if n != "builtin" then pairs.push((s + n, s + "builtin")) end
    end
    for (a, b) in [
      ("collections", "random"); ("random", "time"); ("time", "pony_test")
      ("pony_test", "collections"); ("files", "term"); ("term", "capsicum")
      ("capsicum", "files"); ("files", "collections")
      ("itertools", "pony_check"); ("pony_check", "collections/persistent")
      ("collections/persistent", "itertools"); ("pony_check", "collections")
      ("pony_check", "pony_test"); ("net", "net/notifier")
      ("net/notifier", "net"); ("net", "files"); ("net", "buffered")
      ("json", "collections"); ("json", "format"); ("signals", "time")
    ].values() do
      pairs.push((s + a, s + b))
    end
    let groups = Condense(_Pkg.packages(consume paths),
      _Pkg.edges(consume pairs))
    h.assert_eq[USize](9, groups.size())
    h.assert_array_eq[String]([s + "builtin"], _Pkg.members(groups(0)?))
    let sets = Set[String]
    for g in groups.values() do
      sets.set("|".join(_Pkg.members(g).values()))
    end
    for expected in [
      "/std/collections|/std/pony_test|/std/random|/std/time"
      "/std/capsicum|/std/files|/std/term"
      "/std/collections/persistent|/std/itertools|/std/pony_check"
      "/std/net|/std/net/notifier"; "/std/format"; "/std/json"
      "/std/buffered"; "/std/signals"].values()
    do
      h.assert_true(sets.contains(expected), expected)
    end
    // A group comes after every group it needs.
    for g in groups.values() do
      for n in g.needs.values() do h.assert_true(n < g.index) end
    end

class \nodoc\ iso _TestCondenseDepsTable is UnitTest
  """
  `tools/imports/deps.txt`, read from disk beside this source tree, as an
  edge list over hefermotor's own packages condenses to singletons: the
  package graph of this program has no cycle.
  """
  fun name(): String => "discover/condense: the import table has no cycle"

  fun apply(h: TestHelper) ? =>
    let table = Path.join(Path.dir(__loc.file()),
      "../../tools/imports/deps.txt")
    let text =
      match OpenFile(FilePath(FileAuth(h.env.root), table))
      | let f: File => f.read_string(f.size())
      else
        h.fail("cannot read " + table)
        return
      end
    // The table's format, as `tools/imports/check.sh` parses it: a `key:`
    // line with its dependencies, continued
    // on following lines that start with whitespace; comments start with
    // `#`, directives with `!`, patterns with `*`. A key naming a file
    // belongs to its package.
    let listed = Map[String, Array[String]]
    var key: String = ""
    for line in text.split("\n").values() do
      if line.at("#") or line.at("!") or line.at("*") or (line.size() == 0)
      then
        continue
      end
      var rest: String = line
      if not (line.at(" ") or line.at("\t")) then
        let colon = line.find(":")?
        key = line.substring(0, colon)
        try key = key.substring(0, key.find("/")?) end
        rest = line.substring(colon + 1)
      end
      let deps = try listed(key)? else
        let fresh = Array[String]
        listed(key) = fresh
        fresh
      end
      for dep in rest.split(" \t").values() do
        if dep.size() > 0 then deps.push(dep) end
      end
    end
    // A continuation line's edge is in the graph.
    h.assert_true(listed("hefermotor")?.contains("command",
      {(a, b) => a == b }), "hefermotor -> command from a continuation")
    h.assert_false(listed.contains("# One line per package"))
    let paths = recover iso Array[String] end
    let pairs = recover iso Array[(String, String)] end
    for (k, deps) in listed.pairs() do
      paths.push("/h/" + k)
      for dep in deps.values() do
        if listed.contains(dep) then pairs.push(("/h/" + k, "/h/" + dep)) end
      end
    end
    h.assert_true(listed.contains("discover") and listed.contains("source"))
    let count = listed.size()
    let groups = Condense(_Pkg.packages(consume paths),
      _Pkg.edges(consume pairs))
    h.assert_eq[USize](count, groups.size())
    for g in groups.values() do
      h.assert_eq[USize](1, g.members.size(), g.members(0)?.dir.path)
    end

primitive \nodoc\ _Fixture
  """
  `builtin`; `a` and `b` use each other; `c` is the target and uses `a`,
  `d` and a missing package; `d` uses nothing. Groups in canonical order:
  `builtin`, `{a, b}`, `d`, `c`. The base directory is `/work`, an empty
  directory.
  """
  fun fs(): MemoryFileSystem ref =>
    let fs' = MemoryFileSystem
    fs'.file("/pkgs/builtin/builtin.pony", "primitive None\n")
    fs'.file("/pkgs/a/a.pony", "use \"b\"\n")
    fs'.file("/pkgs/b/b.pony", "use \"a\"\n")
    fs'.file("/pkgs/c/c.pony", "use \"a\"\nuse \"d\"\nuse \"missing\"\n")
    fs'.file("/pkgs/d/d.pony", "primitive D\n")
    fs'.dir("/work")
    fs'

  fun roots(): SearchRoots => SearchRoots(["/pkgs"])

  fun program(h: TestHelper, fs': FileSystem box, target: String = "/pkgs/c")
    : Program ?
  =>
    match Discover(fs', roots(), "/work", target)
    | let p: Program => p
    | let f: BuiltinNotFound =>
      h.fail("builtin not found: " + f.reason.describe())
      error
    | let f: BuiltinNotLoaded =>
      h.fail("builtin not loaded: " + f.reason.describe())
      error
    end

  fun codes(p: Program): Array[String] =>
    let out = Array[String]
    for d in p.diagnostics.values() do out.push(d.string()) end
    out

  fun use_span(fs': FileSystem box, dir: String, file: String, n: USize)
    : diag.Span ?
  =>
    """
    The span of the n-th `use` in a fixture file, as the parser reports
    it, so a test asserts a diagnostic's position without a byte count.
    """
    let content = fs'.read(dir + "/" + file) as String
    parse.Parse.uses_only(source.SourceFile(dir, file, content))(n)?.span

  fun locator_span(fs': FileSystem box, dir: String, file: String, n: USize)
    : diag.Span ?
  =>
    let content = fs'.read(dir + "/" + file) as String
    parse.Parse.uses_only(source.SourceFile(dir, file, content))(n)?
      .locator_span

class \nodoc\ iso _TestDiscoverFixture is UnitTest
  fun name(): String => "discover/discover: the fixture"

  fun apply(h: TestHelper) ? =>
    let fs = _Fixture.fs()
    let p = _Fixture.program(h, fs)?
    _Pkg.groups(h, p.groups,
      [["/pkgs/builtin"]; ["/pkgs/a"; "/pkgs/b"]; ["/pkgs/d"]; ["/pkgs/c"]])
    h.assert_array_eq[USize]([], p.groups(0)?.needs)
    h.assert_array_eq[USize]([0], p.groups(1)?.needs)
    h.assert_array_eq[USize]([0], p.groups(2)?.needs)
    h.assert_array_eq[USize]([0; 1; 2], p.groups(3)?.needs)
    h.assert_eq[String]("/pkgs/builtin", p.builtin.path)
    h.assert_eq[String]("/pkgs/c", (p.root as PackageDir).path)
    // The one diagnostic: the missing package, at its use.
    h.assert_eq[USize](1, p.diagnostics.size())
    let d = p.diagnostics(0)?
    h.assert_eq[String]("discover/use-not-found", d.cause.code())
    h.assert_eq[String]("can't load package 'missing': couldn't locate this " +
      "path", d.cause.message())
    h.assert_true((d.location as diag.Span) ==
      _Fixture.use_span(fs, "/pkgs/c", "c.pony", 2)?)
    // c's uses, in source order, with their outcomes.
    let c = p.package("/pkgs/c")?
    h.assert_eq[USize](3, c.uses.size())
    h.assert_eq[String]("/pkgs/a", (c.uses(0)?.outcome as PackageDir).path)
    h.assert_eq[String]("/pkgs/d", (c.uses(1)?.outcome as PackageDir).path)
    h.assert_eq[String]("missing",
      (c.uses(2)?.outcome as CantLoadPackage).locator)
    h.assert_eq[String]("missing", c.uses(2)?.decl.locator)
    // Names are the locators that reached the packages, and the root's
    // basename.
    h.assert_eq[String]("c", c.name.text)
    h.assert_eq[String]("a", p.package("/pkgs/a")?.name.text)
    h.assert_eq[String]("builtin", p.package("/pkgs/builtin")?.name.text)
    h.assert_eq[String]("d", p.package("/pkgs/d")?.name.text)
    h.assert_eq[USize](1, p.package("/pkgs/d")?.files.size())
    h.assert_eq[USize](0, p.package("/pkgs/d")?.uses.size())

class \nodoc\ iso _TestDiscoverLookups is UnitTest
  fun name(): String => "discover/program: lookups"

  fun apply(h: TestHelper) ? =>
    let p = _Fixture.program(h, _Fixture.fs())?
    h.assert_eq[USize](1, p.group_of(_Pkg.dir("/pkgs/b"))?)
    h.assert_eq[USize](3, p.group_of(_Pkg.dir("/pkgs/c"))?)
    h.assert_error({() ? => p.group_of(_Pkg.dir("/pkgs/missing"))? })
    h.assert_error({() ? => p.package("/pkgs/missing")? })
    h.assert_eq[String]("primitive D\n", p.content_of("/pkgs/d/d.pony")
      as String)
    h.assert_true(p.content_of("/pkgs/d/nope.pony") is None)
    h.assert_true(p.content_of("/pkgs/d") is None)

class \nodoc\ iso _TestDiscoverUnreadableFile is UnitTest
  """
  A package with a file that cannot be opened: the file is reported once,
  every `use` of the package fails with the reason, the package is in no
  group and nothing is reached through it, and as the root it leaves the
  program with `builtin` alone.
  """
  fun name(): String => "discover/discover: an unreadable file"

  fun apply(h: TestHelper) ? =>
    let fs = _Fixture.fs()
    fs.file("/pkgs/a/secret.pony", "")
    fs.deny("/pkgs/a/secret.pony")
    fs.file("/pkgs/d/d.pony", "use \"a\"\n")
    let p = _Fixture.program(h, fs)?
    // b is reached only through a, so it is not reached at all.
    _Pkg.groups(h, p.groups, [["/pkgs/builtin"]; ["/pkgs/d"]; ["/pkgs/c"]])
    h.assert_array_eq[String]([
      "discover/unreadable-file: can't open file /pkgs/a/secret.pony at " +
        "/pkgs/a/secret.pony"
      "discover/use-not-found: can't load package 'a': a source file " +
        "couldn't be opened at /pkgs/c/c.pony:0+7"
      "discover/use-not-found: can't load package 'missing': couldn't " +
        "locate this path at /pkgs/c/c.pony:16+13"
      "discover/use-not-found: can't load package 'a': a source file " +
        "couldn't be opened at /pkgs/d/d.pony:0+7"], _Fixture.codes(p))
    match p.package("/pkgs/d")?.uses(0)?.outcome
    | let c: CantLoadPackage =>
      let f = c.reason as FilesUnreadable
      h.assert_eq[String]("secret.pony", f.files(0)?._1)
      h.assert_eq[String]("permission denied", f.files(0)?._2)
    else
      h.fail("d's use of a carries the failure")
    end
    // As the root.
    let r = _Fixture.program(h, fs, "/pkgs/a")?
    _Pkg.groups(h, r.groups, [["/pkgs/builtin"]])
    h.assert_true(r.root is None)
    h.assert_array_eq[String]([
      "discover/root-not-loaded: can't load '/pkgs/a': a source file " +
        "couldn't be opened at nowhere"
      "discover/unreadable-file: can't open file /pkgs/a/secret.pony at " +
        "/pkgs/a/secret.pony"], _Fixture.codes(r))

class \nodoc\ iso _TestDiscoverUseFailures is UnitTest
  """
  Every way a package `use` fails to load, each at its `use`: a file
  where a directory is needed, an empty directory, a directory that
  cannot be listed, an explicitly relative locator that never falls
  through to the roots, and a link cycle.
  """
  fun name(): String => "discover/discover: each use failure"

  fun apply(h: TestHelper) ? =>
    let fs = _Fixture.fs()
    fs.file("/pkgs/notdir", "")
    fs.dir("/pkgs/empty")
    fs.dir("/pkgs/locked")
    fs.deny("/pkgs/locked")
    fs.dir("/pkgs/nope")
    fs.link("/pkgs/loop1", "/pkgs/loop2")
    fs.link("/pkgs/loop2", "/pkgs/loop1")
    fs.file("/pkgs/e/e.pony", "use \"notdir\"\nuse \"empty\"\n" +
      "use \"locked\"\nuse \"./nope\"\nuse \"loop1\"\n")
    let p = _Fixture.program(h, fs, "/pkgs/e")?
    _Pkg.groups(h, p.groups, [["/pkgs/builtin"]; ["/pkgs/e"]])
    let e = p.package("/pkgs/e")?
    h.assert_eq[USize](5, e.uses.size())
    let reasons = Array[String]
    for u in e.uses.values() do
      reasons.push((u.outcome as CantLoadPackage).reason.describe())
    end
    h.assert_array_eq[String]([
      "couldn't locate this path (a 'use' must name a directory)"
      "no Pony source files"; "permission denied"; "couldn't locate this path"
      "couldn't locate this path"], reasons)
    h.assert_eq[USize](5, p.diagnostics.size())
    for (i, d) in p.diagnostics.pairs() do
      h.assert_eq[String]("discover/use-not-found", d.cause.code())
      h.assert_true((d.location as diag.Span) ==
        _Fixture.use_span(fs, "/pkgs/e", "e.pony", i)?, i.string())
    end

class \nodoc\ iso _TestDiscoverUseSchemes is UnitTest
  """
  ponyc's scheme table: an unknown scheme is reported at the locator; an
  alias or a guard the scheme forbids is reported at the `use` and makes
  no edge; a directive is silent and makes no edge; `package:` resolves.
  """
  fun name(): String => "discover/discover: use schemes"

  fun apply(h: TestHelper) ? =>
    let fs = _Fixture.fs()
    fs.file("/pkgs/e/e.pony", "use \"zip:foo\"\nuse x = \"lib:foo\"\n" +
      "use \"package:d\" if windows\nuse \"lib:foo\"\nuse \"path:./x\" if " +
      "linux\nuse \"package:d\"\nuse dd = \"d\"\nuse \"d\" if windows\n" +
      "use x = \"lib:foo\" if linux\n")
    let p = _Fixture.program(h, fs, "/pkgs/e")?
    _Pkg.groups(h, p.groups, [["/pkgs/builtin"]; ["/pkgs/d"]; ["/pkgs/e"]])
    let e = p.package("/pkgs/e")?
    h.assert_eq[USize](2, e.uses.size())
    h.assert_eq[String]("/pkgs/d", (e.uses(0)?.outcome as PackageDir).path)
    h.assert_eq[String]("package:d", e.uses(0)?.decl.locator)
    h.assert_eq[String]("dd", e.uses(1)?.decl.alias as String)
    // d was first reached through `package:d`: the scheme is not in the
    // name.
    h.assert_eq[String]("d", p.package("/pkgs/d")?.name.text)
    // A use with both an alias and a guard gets one diagnostic, for the
    // one its scheme forbids.
    h.assert_eq[USize](5, p.diagnostics.size())
    h.assert_array_eq[String]([
      "discover/use-scheme-unknown: Use scheme zip: not found at " +
        "/pkgs/e/e.pony:4+9"
      "discover/use-alias-not-allowed: Use scheme lib: may not have an " +
        "alias at /pkgs/e/e.pony:14+17"
      "discover/use-guard-not-allowed: Use scheme package: may not have a " +
        "guard at /pkgs/e/e.pony:32+26"
      "discover/use-guard-not-allowed: Use scheme package: may not have a " +
        "guard at /pkgs/e/e.pony:126+18"
      "discover/use-alias-not-allowed: Use scheme lib: may not have an " +
        "alias at /pkgs/e/e.pony:145+26"], _Fixture.codes(p))
    h.assert_true((p.diagnostics(0)?.location as diag.Span) ==
      _Fixture.locator_span(fs, "/pkgs/e", "e.pony", 0)?)
    h.assert_true((p.diagnostics(1)?.location as diag.Span) ==
      _Fixture.use_span(fs, "/pkgs/e", "e.pony", 1)?)

class \nodoc\ iso _TestDiscoverAliasedDirectory is UnitTest
  """
  Two locators for one directory, one of them a link to it, give one
  package, named by the locator that reached it first, and its `use`s
  are followed.
  """
  fun name(): String => "discover/discover: one directory, two locators"

  fun apply(h: TestHelper) ? =>
    let fs = _Fixture.fs()
    fs.link("/pkgs/alias_of_a", "/pkgs/a")
    fs.file("/pkgs/e/e.pony", "use \"alias_of_a\"\nuse \"a\"\n")
    let p = _Fixture.program(h, fs, "/pkgs/e")?
    _Pkg.groups(h, p.groups,
      [["/pkgs/builtin"]; ["/pkgs/a"; "/pkgs/b"]; ["/pkgs/e"]])
    h.assert_eq[String]("alias_of_a", p.package("/pkgs/a")?.name.text)
    let e = p.package("/pkgs/e")?
    h.assert_true((e.uses(0)?.outcome as PackageDir) ==
      (e.uses(1)?.outcome as PackageDir))
    h.assert_eq[USize](0, p.diagnostics.size())

class \nodoc\ iso _TestDiscoverRoot is UnitTest
  """
  The root through the compile-target branch: absolute, relative to the
  base, through the roots, explicitly relative with no fallthrough, and
  `.` as the base itself. A root that cannot be located is a diagnostic
  with no position and the program holds `builtin` alone.
  """
  fun name(): String => "discover/discover: the root"

  fun apply(h: TestHelper) ? =>
    let fs = _Fixture.fs()
    let none = _Fixture.program(h, fs, "/nowhere")?
    _Pkg.groups(h, none.groups, [["/pkgs/builtin"]])
    h.assert_true(none.root is None)
    h.assert_array_eq[String](["discover/root-not-loaded: can't load " +
      "'/nowhere': couldn't locate this path at nowhere"],
      _Fixture.codes(none))
    match Discover(fs, _Fixture.roots(), "/anywhere", "a")
    | let p: Program =>
      h.assert_eq[String]("/pkgs/a", (p.root as PackageDir).path)
      h.assert_eq[String]("a", p.package("/pkgs/a")?.name.text)
    else
      h.fail("a through the roots")
    end
    match Discover(fs, _Fixture.roots(), "/anywhere", "./a")
    | let p: Program =>
      h.assert_true(p.root is None)
      h.assert_eq[String]("discover/root-not-loaded",
        p.diagnostics(0)?.cause.code())
    else
      h.fail("./a")
    end
    match Discover(fs, _Fixture.roots(), "/pkgs/d", ".")
    | let p: Program =>
      h.assert_eq[String]("/pkgs/d", (p.root as PackageDir).path)
      h.assert_eq[String]("d", p.package("/pkgs/d")?.name.text)
    else
      h.fail(". is the base")
    end
    match Discover(fs, _Fixture.roots(), "/work", ".")
    | let p: Program =>
      h.assert_true(p.root is None)
      h.assert_array_eq[String](["discover/root-not-loaded: can't load " +
        "'.': no Pony source files at nowhere"], _Fixture.codes(p))
    else
      h.fail("an empty base as the root")
    end
    match Discover(fs, _Fixture.roots(), "/pkgs", "d")
    | let p: Program =>
      h.assert_eq[String]("/pkgs/d", (p.root as PackageDir).path)
    else
      h.fail("relative to the base")
    end
    // The root is builtin itself.
    match Discover(fs, _Fixture.roots(), "/work", "builtin")
    | let p: Program =>
      h.assert_eq[String]("/pkgs/builtin", (p.root as PackageDir).path)
      _Pkg.groups(h, p.groups, [["/pkgs/builtin"]])
    else
      h.fail("builtin as the root")
    end

class \nodoc\ iso _TestDiscoverBuiltin is UnitTest
  """
  `builtin/` in the base directory shadows every root; no `builtin`
  anywhere, or one that cannot be read, ends the run before it starts.
  """
  fun name(): String => "discover/discover: builtin"

  fun apply(h: TestHelper) ? =>
    let fs = _Fixture.fs()
    fs.file("/work/builtin/b.pony", "primitive None\n")
    let p = _Fixture.program(h, fs)?
    h.assert_eq[String]("/work/builtin", p.builtin.path)
    h.assert_eq[String]("/work/builtin", p.groups(0)?.members(0)?.dir.path)
    match Discover(MemoryFileSystem, SearchRoots([]), "/work", "/pkgs/c")
    | let f: BuiltinNotFound => h.assert_true(f.reason is NotLocated)
    else
      h.fail("no builtin anywhere")
    end
    let empty: MemoryFileSystem ref = MemoryFileSystem
    empty.dir("/pkgs/builtin")
    match Discover(empty, _Fixture.roots(), "/work", "/pkgs/c")
    | let f: BuiltinNotLoaded =>
      h.assert_eq[String]("/pkgs/builtin", f.dir.path)
      h.assert_true(f.reason is NoPonySources)
    else
      h.fail("empty builtin")
    end
    empty.deny("/pkgs/builtin")
    match Discover(empty, _Fixture.roots(), "/work", "/pkgs/c")
    | let f: BuiltinNotLoaded =>
      h.assert_eq[String]("permission denied",
        (f.reason as UnreadableDirectory).why)
    else
      h.fail("denied builtin")
    end
    let locked: MemoryFileSystem ref = _Fixture.fs()
    locked.deny("/pkgs/builtin/builtin.pony")
    match Discover(locked, _Fixture.roots(), "/work", "/pkgs/c")
    | let f: BuiltinNotLoaded =>
      h.assert_eq[String]("builtin.pony",
        (f.reason as FilesUnreadable).files(0)?._1)
    else
      h.fail("unreadable builtin file")
    end

class \nodoc\ iso _TestDiscoverNames is UnitTest
  """
  ponyc's qualified names: a package found relative to the one using it
  takes the using package's name plus the locator, with `./` dropped and each
  `../` removing a component; one found elsewhere is named by the
  locator as written.
  """
  fun name(): String => "discover/discover: package names"

  fun apply(h: TestHelper) ? =>
    h.assert_eq[String]("app/sub",
      _RelativeName(source.PackageName("app"), "./sub").text)
    h.assert_eq[String]("app/sub",
      _RelativeName(source.PackageName("app"), "sub").text)
    h.assert_eq[String]("app/sib",
      _RelativeName(source.PackageName("app/sub"), "../sib").text)
    // More `../` than the name has components leaves ponyc's leading
    // slash; the name is display only.
    h.assert_eq[String]("/sib",
      _RelativeName(source.PackageName("app/sub"), "../../sib").text)
    h.assert_eq[String]("/x",
      _RelativeName(source.PackageName("app"), "../../x").text)
    let fs = _Fixture.fs()
    fs.file("/pkgs/c/sub/s.pony", "use \"../sib\"\nuse \"deeper\"\n")
    fs.file("/pkgs/c/sub/deeper/x.pony", "")
    fs.file("/pkgs/c/sib/y.pony", "")
    fs.file("/pkgs/c/c.pony", "use \"./sub\"\nuse \"/pkgs/d\"\n")
    let p = _Fixture.program(h, fs)?
    h.assert_eq[USize](0, p.diagnostics.size())
    h.assert_eq[String]("c/sub", p.package("/pkgs/c/sub")?.name.text)
    h.assert_eq[String]("c/sub/deeper",
      p.package("/pkgs/c/sub/deeper")?.name.text)
    h.assert_eq[String]("c/sib", p.package("/pkgs/c/sib")?.name.text)
    // d was first reached through c's absolute use: the name is the
    // locator as written.
    h.assert_eq[String]("/pkgs/d", p.package("/pkgs/d")?.name.text)

class \nodoc\ iso _TestDiscoverUseOrder is UnitTest
  """
  A package's `uses` are in file order, the files sorted by name, then
  in source order within each file.
  """
  fun name(): String => "discover/discover: uses in file then source order"

  fun apply(h: TestHelper) ? =>
    let fs = _Fixture.fs()
    fs.file("/pkgs/e/z.pony", "use \"m1\"\nuse \"m2\"\n")
    fs.file("/pkgs/e/a.pony", "use \"m3\"\nuse \"m4\"\n")
    let p = _Fixture.program(h, fs, "/pkgs/e")?
    let locators = Array[String]
    for u in p.package("/pkgs/e")?.uses.values() do
      locators.push(u.decl.locator)
    end
    h.assert_array_eq[String](["m3"; "m4"; "m1"; "m2"], locators)

class \nodoc\ iso _TestSourceHash is UnitTest
  """
  A package's hash follows its file names and contents and nothing else:
  not the directory it sits in, not the order the file system listed it.
  """
  fun name(): String => "discover/package: source hash"

  fun apply(h: TestHelper) ? =>
    let one = _hash_at("/x/p", ["a.pony"; "b.pony"], ["A"; "B"])?
    let moved = _hash_at("/y/q", ["a.pony"; "b.pony"], ["A"; "B"])?
    let renamed = _hash_at("/x/p", ["a.pony"; "c.pony"], ["A"; "B"])?
    let edited = _hash_at("/x/p", ["a.pony"; "b.pony"], ["A"; "B!"])?
    let reversed = _hash_at("/x/p", ["b.pony"; "a.pony"], ["B"; "A"])?
    h.assert_eq[source.ContentHash](one, moved)
    h.assert_eq[source.ContentHash](one, reversed)
    h.assert_ne[source.ContentHash](one, renamed)
    h.assert_ne[source.ContentHash](one, edited)
    // The hash is the builder over (name, content hash) pairs in order.
    let builder: source.HashBuilder ref = source.HashBuilder
    builder.>field("a.pony").>field_hash(source.SourceFile("/x/p", "a.pony",
      "A").hash).>field("b.pony").>field_hash(
      source.SourceFile("/x/p", "b.pony", "B").hash)
    h.assert_eq[source.ContentHash](builder.done(), one)

  fun _hash_at(dir: String, names: Array[String] val,
    contents: Array[String] val)
    : source.ContentHash ?
  =>
    let fs: MemoryFileSystem ref = MemoryFileSystem
    for (i, n) in names.pairs() do fs.file(dir + "/" + n, contents(i)?) end
    match ReadPackage(fs, PackageDir._create(dir))
    | let p: PackageFiles =>
      Package(PackageDir._create(dir), source.PackageName("p"), p.files,
        recover val Array[PackageUse] end).source_hash
    | let f: ReadFailure => error
    end

class \nodoc\ iso _TestMembershipIsGraphOnly is UnitTest
  """
  Group membership is a function of the graph alone: the same packages
  with their `use` lines permuted, and with another member as the root,
  condense to the same groups.
  """
  fun name(): String => "discover/discover: membership is graph-only"

  fun apply(h: TestHelper) ? =>
    let fs: MemoryFileSystem ref = MemoryFileSystem
    fs.file("/pkgs/builtin/builtin.pony", "primitive None\n")
    fs.file("/pkgs/a/a.pony", "use \"b\"\nuse \"e\"\n")
    fs.file("/pkgs/b/b.pony", "use \"e\"\nuse \"c\"\n")
    fs.file("/pkgs/c/c.pony", "use \"a\"\nuse \"e\"\n")
    fs.file("/pkgs/e/e.pony", "primitive E\n")
    fs.dir("/work")
    let expected: Array[Array[String] val] val =
      [["/pkgs/builtin"]; ["/pkgs/e"]; ["/pkgs/a"; "/pkgs/b"; "/pkgs/c"]]
    for root in ["/pkgs/a"; "/pkgs/b"; "/pkgs/c"].values() do
      _Pkg.groups(h, _Fixture.program(h, fs, root)?.groups, expected)
    end
    let permuted: MemoryFileSystem ref = MemoryFileSystem
    permuted.file("/pkgs/builtin/builtin.pony", "primitive None\n")
    permuted.file("/pkgs/a/a.pony", "use \"e\"\nuse \"b\"\n")
    permuted.file("/pkgs/b/b.pony", "use \"c\"\nuse \"e\"\n")
    permuted.file("/pkgs/c/c.pony", "use \"e\"\nuse \"a\"\n")
    permuted.file("/pkgs/e/e.pony", "primitive E\n")
    permuted.dir("/work")
    _Pkg.groups(h, _Fixture.program(h, permuted, "/pkgs/c")?.groups,
      expected)
