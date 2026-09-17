use "collections"

class val SearchRoots
  """
  The absolute directories a bare locator is looked up under, in order.
  When a standard-library directory is given through `with_stdlib` it
  comes first, so that no other root can shadow a standard-library
  package, as ponyc orders its own list. A relative directory never
  matches anything.
  """
  let dirs: Array[String] val

  new val create(dirs': Array[String] val) =>
    dirs = dirs'

  new val with_stdlib(stdlib: String, dirs': Array[String] val) =>
    let all = recover iso Array[String] end
    all.push(stdlib)
    for d in dirs'.values() do all.push(d) end
    dirs = consume all

class val PackageDir is (Hashable & Comparable[PackageDir])
  """
  A package's identity within a run: its canonical directory. Only this
  package's locators build one, so a `use` string can never stand in for
  a package. Two built from one directory compare equal and hash alike,
  and the order over them is the order over their paths. It never enters
  export data or a cache key. There is no `string()`: code that writes a
  package's path out takes `path` explicitly, and cannot pass a
  `PackageDir` by accident.
  """
  let path: String

  new val _create(path': String) =>
    path = path'

  fun eq(that: PackageDir box): Bool =>
    path == that.path

  fun lt(that: PackageDir box): Bool =>
    path < that.path

  fun hash(): USize =>
    path.hash()

class val Located
  """
  A locator that resolved: the directory, and whether it was found
  relative to the directory it was resolved from, the using package's
  for `Locate` and the base for `LocateTarget`. An absolute locator, a
  `pony_packages` hit and a search-root hit are not relative.
  """
  let dir: PackageDir
  let relative: Bool

  new val create(dir': PackageDir, relative': Bool) =>
    dir = dir'
    relative = relative'

primitive NotLocated
  """
  No candidate for the locator is a directory.
  """
  fun describe(): String => "couldn't locate this path"

primitive NotADirectory
  """
  No candidate for the locator is a directory, and one of them is a file.
  """
  fun describe(): String =>
    "couldn't locate this path (a 'use' must name a directory)"

type LocateFailure is (NotLocated | NotADirectory)
  """
  Why a locator resolved to no directory.
  """

primitive Locate
  """
  Resolves a `use` written inside a package, as ponyc's `find_path` does:
  an absolute locator as given; otherwise relative to the package's
  directory; otherwise, unless the locator is written with a leading `./`
  or `../`, the `pony_packages` walk: under `pony_packages` in each
  ancestor of the package's directory starting with its parent, then the
  same from the program root's directory; then under each search root in
  order. A candidate counts only when it is a directory. A file, or a
  path that cannot be reached because it is missing or lies beneath a
  directory that cannot be searched, is passed over and the next
  candidate is tried. A directory that cannot be listed still counts;
  `ReadPackage` reports it.
  """
  fun apply(fs: FileSystem box, roots: SearchRoots, from: PackageDir,
    program_root: PackageDir, locator: String)
    : (Located | LocateFailure)
  =>
    let probe = _Probe(fs)
    if _Paths.is_abs(locator) then
      return _finish(probe, probe.dir(locator), false)
    end
    match probe.dir(_Paths.join(from.path, locator))
    | let d: PackageDir => return Located(d, true)
    end
    if _explicitly_relative(locator) then
      return _finish(probe, None, false)
    end
    match _walk(probe, from.path, locator)
    | let d: PackageDir => return Located(d, false)
    end
    match _walk(probe, program_root.path, locator)
    | let d: PackageDir => return Located(d, false)
    end
    for root in roots.dirs.values() do
      match probe.dir(_Paths.join(root, locator))
      | let d: PackageDir => return Located(d, false)
      end
    end
    _finish(probe, None, false)

  fun _walk(probe: _Probe, base: String, locator: String)
    : (PackageDir | None)
  =>
    """
    Tries `<ancestor>/pony_packages/<locator>` for each ancestor of
    `base`, its parent first, up to and including the file system's
    root. Each parent is made canonical before its `pony_packages` is
    tried; a parent that cannot be made canonical is tried as written.
    """
    var here = base
    repeat
      let parent = _Paths.dir(here)
      here = match probe.fs.canonical(parent) | let c: String => c
        else parent end
      match probe.dir(_Paths.join(_Paths.join(here, "pony_packages"), locator))
      | let d: PackageDir => return d
      end
    until here == "/" end
    None

  fun _explicitly_relative(locator: String): Bool =>
    locator.at("./") or locator.at("../")

  fun _finish(probe: _Probe, found: (PackageDir | None), relative: Bool)
    : (Located | LocateFailure)
  =>
    match found
    | let d: PackageDir => Located(d, relative)
    | None => if probe.saw_file then NotADirectory else NotLocated end
    end

primitive LocateTarget
  """
  Resolves the program's root or `builtin`, as `find_path` resolves the
  compile target: an absolute locator as given; otherwise relative to
  `base`, the process's current directory; otherwise, unless the locator
  is written with a leading `./` or `../`, under each search root in
  order. There is no `pony_packages` walk. A file, or a path that cannot
  be reached, at a candidate is passed over, as for `Locate`. An empty
  locator names nothing.
  """
  fun apply(fs: FileSystem box, roots: SearchRoots, base: String,
    locator: String)
    : (Located | LocateFailure)
  =>
    let probe = _Probe(fs)
    if locator.size() == 0 then return NotLocated end
    if _Paths.is_abs(locator) then
      return Locate._finish(probe, probe.dir(locator), false)
    end
    match probe.dir(_Paths.join(base, locator))
    | let d: PackageDir => return Located(d, true)
    end
    if Locate._explicitly_relative(locator) then
      return Locate._finish(probe, None, false)
    end
    for root in roots.dirs.values() do
      match probe.dir(_Paths.join(root, locator))
      | let d: PackageDir => return Located(d, false)
      end
    end
    Locate._finish(probe, None, false)

class _Probe
  """
  Tries candidates against the file system and records whether any of
  them was a file; the failure is `NotADirectory` when one was,
  `NotLocated` otherwise.
  """
  let fs: FileSystem box
  var saw_file: Bool = false

  new create(fs': FileSystem box) =>
    fs = fs'

  fun ref dir(candidate: String): (PackageDir | None) =>
    """
    The candidate's canonical directory, or `None` when it is not a
    directory.
    """
    match fs.canonical(candidate)
    | let c: String =>
      match fs.kind(c)
      | IsDirectory => PackageDir._create(c)
      | IsFile => saw_file = true; None
      else
        None
      end
    | None => None
    end
