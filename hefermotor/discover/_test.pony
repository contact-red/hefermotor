use "collections"
use "files"
use "pony_test"
use diag = "../diagnostics"
use source = "../source"

actor \nodoc\ Main is TestList
  new create(env: Env) => PonyTest(env, this)
  new make() => None

  fun tag tests(test: PonyTest) =>
    test(_TestMemoryFileSystem)
    test(_TestMemoryLinks)
    test(_TestLocateAbsoluteAndRelative)
    test(_TestLocateExplicitRelativeStops)
    test(_TestLocatePonyPackagesWalk)
    test(_TestLocateWalkFromProgramRoot)
    test(_TestLocateSearchRoots)
    test(_TestLocateFilesArePassedOver)
    test(_TestLocateTarget)
    test(_TestPackageDirIdentity)
    test(_TestPonySource)
    test(_TestReadPackageFilterAndOrder)
    test(_TestReadPackageFailures)
    test(_TestClassifyUse)
    test(_TestCauseCodesDistinct)
    test(_TestDiskFileSystem)
    _ProgramTests(test)

primitive \nodoc\ _Denied
  fun apply(r: (String | Array[String] val | Denied)): Bool =>
    match r
    | let _: Denied => true
    else
      false
    end

primitive \nodoc\ _Fs
  """
  A memory file system with a stdlib root at `/std` holding `builtin`,
  and a program at `/w/app`.
  """
  fun apply(): MemoryFileSystem ref =>
    let fs = MemoryFileSystem
    fs.dir("/std/builtin")
    fs.dir("/std/collections")
    fs.dir("/w/app")
    fs

  fun roots(): SearchRoots =>
    SearchRoots.with_stdlib("/std", [])

  fun pkg(h: TestHelper, fs: FileSystem box, path: String): PackageDir ? =>
    match LocateTarget(fs, SearchRoots([]), "/", path)
    | let l: Located => l.dir
    | let f: LocateFailure =>
      h.fail("fixture directory missing: " + path)
      error
    end

  fun located(h: TestHelper, r: (Located | LocateFailure), path: String,
    what: String)
  =>
    match r
    | let l: Located => h.assert_eq[String](path, l.dir.path, what)
    | NotLocated => h.fail(what + ": not located")
    | NotADirectory => h.fail(what + ": not a directory")
    end

class \nodoc\ iso _TestMemoryFileSystem is UnitTest
  fun name(): String => "discover/memory fs: files, dirs, deny, entries"

  fun apply(h: TestHelper) ? =>
    let fs = MemoryFileSystem
    fs.file("/a/b/c.pony", "c")
    fs.file("/a/b/a.pony", "a")
    fs.dir("/a/d")
    h.assert_true(fs.kind("/a") is IsDirectory)
    h.assert_true(fs.kind("/a/b") is IsDirectory)
    h.assert_true(fs.kind("/a/b/c.pony") is IsFile)
    h.assert_true(fs.kind("/a/nope") is Missing)
    h.assert_true(fs.kind("relative") is Missing)
    h.assert_true(fs.canonical("relative") is None)
    h.assert_eq[String]("/a/b", fs.canonical("/a/./b/") as String)
    h.assert_eq[String]("/a", fs.canonical("/a/b/..") as String)
    // Entries come back in insertion order.
    h.assert_array_eq[String](["c.pony"; "a.pony"],
      fs.entries("/a/b") as Array[String] val)
    h.assert_array_eq[String](["b"; "d"],
      fs.entries("/a") as Array[String] val)
    h.assert_eq[String]("c", fs.read("/a/b/c.pony") as String)
    // Adding a file again replaces its content and lists it once.
    fs.file("/a/b/c.pony", "c2")
    h.assert_eq[String]("c2", fs.read("/a/b/c.pony") as String)
    h.assert_array_eq[String](["c.pony"; "a.pony"],
      fs.entries("/a/b") as Array[String] val)
    h.assert_true(_Denied(fs.read("/a/b/nope")))
    fs.deny("/a/b/c.pony")
    h.assert_true(_Denied(fs.read("/a/b/c.pony")))
    h.assert_true(fs.kind("/a/b/c.pony") is IsFile)
    fs.deny("/a/d")
    h.assert_true(fs.kind("/a/d") is IsDirectory)
    h.assert_true(_Denied(fs.entries("/a/d")))
    h.assert_true(_Denied(fs.entries("/a/b/c.pony")))

class \nodoc\ iso _TestMemoryLinks is UnitTest
  fun name(): String => "discover/memory fs: links resolve like realpath"

  fun apply(h: TestHelper) ? =>
    let fs = MemoryFileSystem
    fs.file("/real/pkg/a.pony", "")
    fs.link("/alias", "/real")
    fs.link("/real/link_pkg", "/real/pkg")
    h.assert_eq[String]("/real/pkg", fs.canonical("/alias/pkg") as String)
    h.assert_eq[String]("/real/pkg", fs.canonical("/real/link_pkg") as String)
    h.assert_eq[String]("/real/pkg/a.pony",
      fs.canonical("/alias/link_pkg/a.pony") as String)
    h.assert_true(fs.kind("/alias/pkg") is IsDirectory)
    h.assert_true(fs.canonical("/alias/missing") is None)
    // A link to a link resolves through both; a cycle answers None.
    fs.link("/x", "/y")
    fs.link("/y", "/x")
    h.assert_true(fs.canonical("/x") is None)
    h.assert_true(fs.canonical("/x/anything") is None)
    // `..` steps out of the link's target, not out of the link.
    fs.dir("/real/pkg/sub")
    fs.link("/w/here", "/real/pkg/sub")
    h.assert_eq[String]("/real/pkg", fs.canonical("/w/here/..") as String)
    h.assert_eq[String]("/real/pkg/a.pony",
      fs.canonical("/w/here/../a.pony") as String)
    h.assert_true(fs.canonical("/w/here/../here") is None)
    h.assert_eq[String]("/real/pkg/sub", fs.canonical("/w/here/") as String)
    h.assert_eq[String]("/", fs.canonical("/..") as String)
    h.assert_eq[String]("/", fs.canonical("/") as String)
    // A file is not a directory: nothing resolves through it.
    h.assert_true(fs.canonical("/real/pkg/a.pony/..") is None)
    h.assert_true(fs.canonical("/real/pkg/a.pony/") is None)
    // Nothing beneath a denied directory can be reached, not even a
    // link out of it.
    fs.dir("/locked/inside")
    fs.link("/door", "/locked/inside")
    fs.link("/locked/out", "/real")
    fs.deny("/locked")
    h.assert_true(fs.canonical("/door") is None)
    h.assert_true(fs.canonical("/locked/inside") is None)
    h.assert_true(fs.canonical("/locked/out") is None)
    // Path arithmetic the builders rely on.
    h.assert_eq[String]("/", _Paths.clean("/.."))
    h.assert_eq[String]("/a", _Paths.clean("//a//"))
    h.assert_eq[String]("/a", _Paths.clean("/a/b/../"))
    h.assert_eq[String]("../a", _Paths.clean("../a"))
    h.assert_eq[String](".", _Paths.clean(""))
    h.assert_eq[String]("/", _Paths.dir("/a"))
    h.assert_eq[String]("/a", _Paths.dir("/a/b"))
    h.assert_eq[String]("b", _Paths.base("/a/b"))
    h.assert_eq[String]("/a/b", _Paths.join("/a", "b"))
    h.assert_eq[String]("/b", _Paths.join("/a", "/b"))
    h.assert_eq[String]("/a/b", _Paths.join("/a/", "b"))
    h.assert_eq[String]("b", _Paths.join("", "b"))
    // A join leaves `..` for the file system, as ponyc leaves it to
    // `realpath`.
    h.assert_eq[String]("/a/../b", _Paths.join("/a", "../b"))

class \nodoc\ iso _TestLocateAbsoluteAndRelative is UnitTest
  fun name(): String =>
    "discover/locate: absolute, then relative to the package"

  fun apply(h: TestHelper) ? =>
    let fs = _Fs()
    fs.dir("/w/app/sub")
    fs.dir("/elsewhere/abs")
    let app = _Fs.pkg(h, fs, "/w/app")?
    _Fs.located(h, Locate(fs, _Fs.roots(), app, app, "/elsewhere/abs"),
      "/elsewhere/abs", "absolute")
    match Locate(fs, _Fs.roots(), app, app, "sub")
    | let l: Located =>
      h.assert_eq[String]("/w/app/sub", l.dir.path)
      h.assert_true(l.relative)
    else
      h.fail("sub")
    end
    // A bare locator found relative to the package beats a root.
    fs.dir("/std/sub")
    _Fs.located(h, Locate(fs, _Fs.roots(), app, app, "sub"), "/w/app/sub",
      "relative beats root")
    match Locate(fs, _Fs.roots(), app, app, "collections")
    | let l: Located =>
      h.assert_eq[String]("/std/collections", l.dir.path)
      h.assert_false(l.relative)
    else
      h.fail("collections")
    end
    h.assert_true(Locate(fs, _Fs.roots(), app, app, "/nowhere") is NotLocated)

class \nodoc\ iso _TestLocateExplicitRelativeStops is UnitTest
  """
  A locator written `./x` or `../x` that is not found relative to the
  package is not found at all: the roots are never consulted.
  """
  fun name(): String => "discover/locate: ./ and ../ never fall through"

  fun apply(h: TestHelper) ? =>
    let fs = _Fs()
    fs.dir("/std/nope")
    fs.dir("/w/pony_packages/nope")
    let app = _Fs.pkg(h, fs, "/w/app")?
    h.assert_true(Locate(fs, _Fs.roots(), app, app, "./nope") is NotLocated)
    h.assert_true(Locate(fs, _Fs.roots(), app, app, "../nope") is NotLocated)
    fs.dir("/w/app/nope")
    _Fs.located(h, Locate(fs, _Fs.roots(), app, app, "./nope"),
      "/w/app/nope", "./nope found")
    fs.dir("/w/up")
    _Fs.located(h, Locate(fs, _Fs.roots(), app, app, "../up"), "/w/up",
      "../up found")

class \nodoc\ iso _TestLocatePonyPackagesWalk is UnitTest
  """
  The walk tries `<ancestor>/pony_packages/<locator>` from the package's
  parent upward, never `<package>/pony_packages`, and a linked package
  walks its target's ancestors.
  """
  fun name(): String => "discover/locate: the pony_packages walk"

  fun apply(h: TestHelper) ? =>
    let fs = _Fs()
    fs.dir("/w/app/pony_packages/x")
    fs.dir("/w/pony_packages/y")
    fs.dir("/pony_packages/z")
    let app = _Fs.pkg(h, fs, "/w/app")?
    h.assert_true(Locate(fs, _Fs.roots(), app, app, "x") is NotLocated)
    _Fs.located(h, Locate(fs, _Fs.roots(), app, app, "y"),
      "/w/pony_packages/y", "parent's pony_packages")
    _Fs.located(h, Locate(fs, _Fs.roots(), app, app, "z"),
      "/pony_packages/z", "root's pony_packages")
    // Nearer ancestors win over farther ones and over the search roots.
    fs.dir("/pony_packages/y")
    fs.dir("/std/y")
    _Fs.located(h, Locate(fs, _Fs.roots(), app, app, "y"),
      "/w/pony_packages/y", "nearest")
    // A linked package directory walks from its target.
    fs.link("/elsewhere/app", "/w/app")
    let linked = _Fs.pkg(h, fs, "/elsewhere/app")?
    h.assert_eq[String]("/w/app", linked.path)
    _Fs.located(h, Locate(fs, _Fs.roots(), linked, linked, "y"),
      "/w/pony_packages/y", "through link")
    // A package at the root walks once: /pony_packages is tried.
    fs.dir("/rootpkg")
    let at_root = _Fs.pkg(h, fs, "/rootpkg")?
    _Fs.located(h, Locate(fs, _Fs.roots(), at_root, at_root, "z"),
      "/pony_packages/z", "walk from a root package")
    // A denied pony_packages directory is passed over.
    fs.deny("/w/pony_packages")
    _Fs.located(h, Locate(fs, _Fs.roots(), app, app, "y"),
      "/pony_packages/y", "denied ancestor passed over")

class \nodoc\ iso _TestLocateWalkFromProgramRoot is UnitTest
  fun name(): String => "discover/locate: the walk from the program root"

  fun apply(h: TestHelper) ? =>
    let fs = _Fs()
    fs.dir("/w/pony_packages/shared")
    fs.dir("/opt/dep")
    let root = _Fs.pkg(h, fs, "/w/app")?
    let dep = _Fs.pkg(h, fs, "/opt/dep")?
    // From /opt/dep no ancestor holds shared; the root's ancestors do.
    _Fs.located(h, Locate(fs, _Fs.roots(), dep, root, "shared"),
      "/w/pony_packages/shared", "root's walk")
    h.assert_true(Locate(fs, _Fs.roots(), dep, dep, "shared") is NotLocated)

class \nodoc\ iso _TestLocateSearchRoots is UnitTest
  fun name(): String => "discover/locate: search roots in order"

  fun apply(h: TestHelper) ? =>
    let fs = _Fs()
    fs.dir("/std/dup")
    fs.dir("/extra/dup")
    fs.dir("/extra/only")
    let app = _Fs.pkg(h, fs, "/w/app")?
    let roots = SearchRoots.with_stdlib("/std", ["/extra"])
    h.assert_array_eq[String](["/std"; "/extra"], roots.dirs)
    _Fs.located(h, Locate(fs, roots, app, app, "dup"), "/std/dup",
      "stdlib first")
    _Fs.located(h, Locate(fs, roots, app, app, "only"), "/extra/only",
      "later root")
    let reversed = SearchRoots(["/extra"; "/std"])
    _Fs.located(h, Locate(fs, reversed, app, app, "dup"), "/extra/dup",
      "order as given")

class \nodoc\ iso _TestLocateFilesArePassedOver is UnitTest
  """
  A file at a candidate does not stop the search; `NotADirectory` is the
  failure only when every candidate failed and one of them was a file.
  """
  fun name(): String => "discover/locate: files are passed over"

  fun apply(h: TestHelper) ? =>
    let fs = _Fs()
    fs.file("/w/app/json", "")
    fs.dir("/std/json")
    let app = _Fs.pkg(h, fs, "/w/app")?
    _Fs.located(h, Locate(fs, _Fs.roots(), app, app, "json"), "/std/json",
      "file then directory")
    fs.file("/w/app/notdir", "")
    h.assert_true(Locate(fs, _Fs.roots(), app, app, "notdir")
      is NotADirectory)
    h.assert_true(Locate(fs, _Fs.roots(), app, app, "missing")
      is NotLocated)
    // The same for the target branch.
    fs.file("/w/target_file", "")
    _Fs.located(h, LocateTarget(fs, _Fs.roots(), "/w", "json"), "/std/json",
      "target: file then directory")
    h.assert_true(LocateTarget(fs, _Fs.roots(), "/w", "target_file")
      is NotADirectory)

class \nodoc\ iso _TestLocateTarget is UnitTest
  """
  The root and `builtin` resolve relative to the base directory, then
  through the roots, with no `pony_packages` walk; `.` is the base and
  `builtin/` in the base shadows the roots.
  """
  fun name(): String => "discover/locate target"

  fun apply(h: TestHelper) =>
    let fs = _Fs()
    fs.dir("/w/pony_packages/walked")
    fs.dir("/w/app/local")
    _Fs.located(h, LocateTarget(fs, _Fs.roots(), "/w/app", "."), "/w/app",
      "dot is the base")
    _Fs.located(h, LocateTarget(fs, _Fs.roots(), "/w/app", "local"),
      "/w/app/local", "relative to base")
    _Fs.located(h, LocateTarget(fs, _Fs.roots(), "/w/app", "collections"),
      "/std/collections", "through the roots")
    _Fs.located(h, LocateTarget(fs, _Fs.roots(), "/w/app", "/std/builtin"),
      "/std/builtin", "absolute")
    h.assert_true(LocateTarget(fs, _Fs.roots(), "/w/app", "walked")
      is NotLocated)
    h.assert_true(LocateTarget(fs, _Fs.roots(), "/w/app", "./collections")
      is NotLocated)
    h.assert_true(LocateTarget(fs, _Fs.roots(), "/w/app", "") is NotLocated)
    _Fs.located(h, LocateTarget(fs, _Fs.roots(), "/w/app", "builtin"),
      "/std/builtin", "builtin from the roots")
    fs.dir("/w/app/builtin")
    _Fs.located(h, LocateTarget(fs, _Fs.roots(), "/w/app", "builtin"),
      "/w/app/builtin", "builtin in the base shadows the roots")

class \nodoc\ iso _TestPackageDirIdentity is UnitTest
  """
  Two locates of one directory, by different paths, give equal
  identities that hash alike; different directories order by path.
  """
  fun name(): String => "discover/package dir: identity by canonical path"

  fun apply(h: TestHelper) ? =>
    let fs = _Fs()
    fs.dir("/w/app/pkg")
    fs.link("/w/alias", "/w/app")
    let a = _Fs.pkg(h, fs, "/w/app/pkg")?
    let b = _Fs.pkg(h, fs, "/w/alias/pkg")?
    let c = _Fs.pkg(h, fs, "/w/app/../app/pkg")?
    h.assert_true(a == b)
    h.assert_true(a == c)
    h.assert_eq[USize](a.hash(), b.hash())
    let other = _Fs.pkg(h, fs, "/w/app")?
    h.assert_false(a == other)
    h.assert_true(other < a)
    h.assert_false(a < other)
    let map = Map[PackageDir, USize]
    map(a) = 1
    map(b) = 2
    h.assert_eq[USize](1, map.size())
    h.assert_eq[USize](2, try map(c)? else 0 end)

class \nodoc\ iso _TestPonySource is UnitTest
  fun name(): String => "discover/pony source: the extension test"

  fun apply(h: TestHelper) =>
    h.assert_true(_PonySource("a.pony"))
    h.assert_true(_PonySource("a.b.pony"))
    h.assert_false(_PonySource(".pony"))
    h.assert_false(_PonySource("pony"))
    h.assert_false(_PonySource("y"))
    h.assert_false(_PonySource(""))
    h.assert_false(_PonySource("apony"))
    h.assert_false(_PonySource("a.ponyx"))
    h.assert_false(_PonySource("a.pony.bak"))

class \nodoc\ iso _TestReadPackageFilterAndOrder is UnitTest
  """
  Only `.pony` files that do not start with a dot and are not
  directories count, sorted by name whatever order the listing gave.
  """
  fun name(): String => "discover/read package: filter and order"

  fun apply(h: TestHelper) ? =>
    let fs = _Fs()
    fs.file("/w/app/pon", "")
    fs.file("/w/app/y", "")
    fs.file("/w/app/z.pony", "z")
    fs.file("/w/app/a.pony", "a")
    fs.file("/w/app/.hidden.pony", "h")
    fs.file("/w/app/notes.md", "")
    fs.file("/w/app/pony", "")
    fs.file("/w/app/shim.c", "")
    fs.dir("/w/app/dir.pony")
    fs.file("/w/app/m.pony", "m")
    let app = _Fs.pkg(h, fs, "/w/app")?
    match ReadPackage(fs, app)
    | let p: PackageFiles =>
      let names = Array[String]
      for f in p.files.values() do names.push(f.name) end
      h.assert_array_eq[String](["a.pony"; "m.pony"; "z.pony"], names)
      try
        h.assert_eq[String]("/w/app", p.files(0)?.dir)
        h.assert_eq[String]("a", p.files(0)?.content)
        h.assert_eq[String]("/w/app/z.pony", p.files(2)?.path())
      else
        h.fail("three files")
      end
    | let f: ReadFailure => h.fail("read failed: " + f.describe())
    end

class \nodoc\ iso _TestReadPackageFailures is UnitTest
  fun name(): String => "discover/read package: each failure"

  fun apply(h: TestHelper) ? =>
    let fs = _Fs()
    fs.dir("/w/empty")
    fs.file("/w/nopony/readme.md", "")
    fs.file("/w/locked/a.pony", "")
    fs.deny("/w/locked")
    fs.file("/w/secret/a.pony", "a")
    fs.file("/w/secret/b.pony", "b")
    fs.file("/w/secret/c.pony", "c")
    fs.deny("/w/secret/c.pony")
    fs.deny("/w/secret/a.pony")
    h.assert_true(ReadPackage(fs, _Fs.pkg(h, fs, "/w/empty")?)
      is NoPonySources)
    h.assert_true(ReadPackage(fs, _Fs.pkg(h, fs, "/w/nopony")?)
      is NoPonySources)
    match ReadPackage(fs, _Fs.pkg(h, fs, "/w/locked")?)
    | let u: UnreadableDirectory => h.assert_eq[String]("permission denied",
      u.why)
    else
      h.fail("locked")
    end
    match ReadPackage(fs, _Fs.pkg(h, fs, "/w/secret")?)
    | let u: FilesUnreadable =>
      h.assert_eq[USize](2, u.files.size())
      try
        h.assert_eq[String]("a.pony", u.files(0)?._1)
        h.assert_eq[String]("permission denied", u.files(0)?._2)
        h.assert_eq[String]("c.pony", u.files(1)?._1)
      else
        h.fail("two names")
      end
    else
      h.fail("secret")
    end

class \nodoc\ iso _TestClassifyUse is UnitTest
  fun name(): String => "discover/classify use: ponyc's scheme table"

  fun apply(h: TestHelper) =>
    (let s, let rest) = ClassifyUse("collections")
    h.assert_true(s is UsePackage)
    h.assert_eq[String]("collections", rest)
    (let s2, let rest2) = ClassifyUse("package:net/notifier")
    h.assert_true(s2 is UsePackage)
    h.assert_eq[String]("net/notifier", rest2)
    for scheme in ["lib:"; "path:"; "cincludedir:"; "cdefine:"].values() do
      (let d, let r) = ClassifyUse(scheme + "x")
      h.assert_true(d is UseDirective, scheme)
      h.assert_eq[String]("x", r)
    end
    match ClassifyUse("test:x")._1
    | let u: UseUnknown => h.assert_eq[String]("test:", u.scheme)
    else
      h.fail("test: has no handler")
    end
    match ClassifyUse("c:/windows/path")._1
    | let u: UseUnknown => h.assert_eq[String]("c:", u.scheme)
    else
      h.fail("c: is unknown")
    end
    h.assert_true(UsePackage.allow_alias())
    h.assert_false(UsePackage.allow_guard())
    h.assert_false(UseDirective.allow_alias())
    h.assert_true(UseDirective.allow_guard())

class \nodoc\ iso _TestCauseCodesDistinct is UnitTest
  """
  Every cause this package can raise has its own code, and the messages
  read as ponyc's do.
  """
  fun name(): String => "discover/causes: distinct codes"

  fun apply(h: TestHelper) =>
    let codes: Array[String] = [
      CantLoadPackage("x", NotLocated).code()
      RootFailed("x", NoPonySources).code()
      UnreadableFile("/p", "a.pony", "why").code()
      UseSchemeUnknown("z:").code()
      UseAliasNotAllowed("lib:").code()
      UseGuardNotAllowed("package:").code()]
    let as_causes: Array[diag.DiagnosticCause] = [
      CantLoadPackage("x", NotLocated); RootFailed("x", NoPonySources)
      UnreadableFile("/p", "a.pony", "why"); UseSchemeUnknown("z:")
      UseAliasNotAllowed("lib:"); UseGuardNotAllowed("package:")]
    h.assert_eq[USize](codes.size(), as_causes.size())
    let seen = Set[String]
    for c in codes.values() do
      h.assert_false(seen.contains(c), "duplicate code " + c)
      h.assert_true(c.at("discover/"), c)
      seen.set(c)
    end
    h.assert_eq[String]("can't load package 'x': couldn't locate this path",
      CantLoadPackage("x", NotLocated).message())
    h.assert_eq[String]("can't open file /p/a.pony",
      UnreadableFile("/p", "a.pony", "why").message())
    h.assert_eq[String]("Use scheme lib: may not have an alias",
      UseAliasNotAllowed("lib:").message())
    h.assert_eq[String]("Use scheme package: may not have a guard",
      UseGuardNotAllowed("package:").message())

class \nodoc\ iso _TestDiskFileSystem is UnitTest
  """
  The real disk, over the fixture beside this file: a stub `builtin`, a
  package `real` holding a link `via` to `../linked_target`, and a link
  `linked` to that same target directory.
  """
  fun name(): String => "discover/disk fs: the fixture"

  fun apply(h: TestHelper) ? =>
    let fixture = Path.join(Path.dir(__loc.file()), "testdata/roots")
    let fs = DiskFileSystem(FileAuth(h.env.root))
    let roots = SearchRoots.with_stdlib(fixture, [])
    // The base is a fixture directory holding none of the names looked
    // up, so nothing on the machine outside the fixture can answer.
    let base = Path.join(fixture, "real")
    match LocateTarget(fs, roots, base, "builtin")
    | let l: Located =>
      h.assert_true(l.dir.path.at("/builtin", -8))
      h.assert_false(l.relative)
      match ReadPackage(fs, l.dir)
      | let p: PackageFiles =>
        h.assert_eq[USize](1, p.files.size())
        try h.assert_eq[String]("builtin.pony", p.files(0)?.name) end
      | let f: ReadFailure => h.fail(f.describe())
      end
    else
      h.fail("builtin not located under " + fixture)
    end
    match LocateTarget(fs, roots, base, "linked")
    | let l: Located =>
      h.assert_true(l.dir.path.at("/linked_target", -14),
        "link resolves to target: " + l.dir.path)
      match LocateTarget(fs, roots, base, "linked_target")
      | let t: Located => h.assert_true(l.dir == t.dir)
      else
        h.fail("target")
      end
    else
      h.fail("linked not located")
    end
    h.assert_true(LocateTarget(fs, roots, base, "absent") is NotLocated)
    // A relative path that would resolve against the current directory
    // is refused before the disk sees it.
    let rel = Path.rel(Path.cwd(), fixture + "/real/real.pony")?
    h.assert_true(fs.canonical(rel) is None)
    h.assert_true(fs.kind(rel) is Missing)
    h.assert_true(_Denied(fs.entries(Path.dir(rel))))
    h.assert_true(_Denied(fs.read(rel)))
    // `real/via` links to `../linked_target`, so `..` after it steps out
    // of the target; lexically the same path would stay under `real`.
    // `Path.join` would clean the `..` away, which is the point.
    h.assert_eq[String](fixture + "/linked_target/target.pony",
      fs.canonical(fixture + "/real/via/../linked_target/target.pony")
        as String)
    h.assert_true(fs.canonical(fixture + "/real/via/../real.pony") is None)
    match fs.kind(Path.join(fixture, "real/real.pony"))
    | IsFile => None
    else
      h.fail("real.pony is a file")
    end
