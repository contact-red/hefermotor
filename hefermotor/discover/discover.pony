"""
# hefermotor/discover

Finds the packages a program reaches and reads their files. A `use`
locator resolves through `Locate` as ponyc's `find_path` resolves it; the
program's root and `builtin` resolve through `LocateTarget`, the
compile-target branch of the same function. `ReadPackage` turns a located
directory into its source files under ponyc's rules for which files count
and what an unreadable one means. `Discover` runs all of it from `builtin`
and the root outward, and `Condense` turns the packages it found into
groups in a canonical order. Every path reaches the disk through a
`FileSystem`, so a test can run all of it in memory.
"""
use "collections"
use diag = "../diagnostics"
use parse = "../parse"
use sort = "../sort"
use source = "../source"

primitive Discover
  """
  Reads the program reachable from `target` and from `builtin`. `target`
  is an absolute path, a path relative to `base`, or a name found through
  `roots`; `base` is an absolute directory, the process's current
  directory for the command line. A `builtin` that cannot be located or
  loaded ends the run before it starts; a root that cannot be loaded is a
  diagnostic, and the program holds `builtin` and nothing reached only
  through the root. Every other package is reached breadth-first through
  the `use`s of the packages before it; only each file's `use` section
  is parsed here. Every package gets an edge to `builtin`, as ponyc's
  sugar pass gives it one. Synchronous: returns once the whole program
  is read.
  """
  fun apply(fs: FileSystem box, roots: SearchRoots, base: String,
    target: String)
    : (Program | BuiltinFailure)
  =>
    let builtin =
      match LocateTarget(fs, roots, base, "builtin")
      | let l: Located => l.dir
      | let f: LocateFailure => return BuiltinNotFound(f)
      end
    let builtin_files =
      match ReadPackage(fs, builtin)
      | let p: PackageFiles => p
      | let f: ReadFailure => return BuiltinNotLoaded(builtin, f)
      end
    let loader = _Loader(fs, roots, builtin)
    loader.enqueue(builtin, source.PackageName(_Paths.base(builtin.path)),
      builtin_files)
    let root: (PackageDir | None) =
      match LocateTarget(fs, roots, base, target)
      | let l: Located =>
        if l.dir == builtin then
          l.dir
        else
          match loader.load(l.dir,
            source.PackageName(_Paths.base(l.dir.path)))
          | None => l.dir
          | let f: ReadFailure =>
            loader.report(RootFailed(target, f), diag.Nowhere)
            None
          end
        end
      | let f: LocateFailure =>
        loader.report(RootFailed(target, f), diag.Nowhere)
        None
      end
    loader.run(match root | let d: PackageDir => d | None => builtin end)
    loader.program(root)

class _Loader
  """
  The breadth-first load from `builtin` and the root outward.
  """
  let _fs: FileSystem box
  let _roots: SearchRoots
  let _builtin: PackageDir
  embed _queue: Array[(PackageDir, source.PackageName, PackageFiles)] =
    _queue.create()
  embed _loaded: Set[String] = _loaded.create()
  embed _failed: Map[String, ReadFailure] = _failed.create()
  embed _packages: Array[Package] = _packages.create()
  embed _edges: Array[(PackageDir, PackageDir)] = _edges.create()
  embed _diagnostics: Array[diag.Diagnostic] = _diagnostics.create()

  new create(fs: FileSystem box, roots: SearchRoots, builtin: PackageDir) =>
    _fs = fs
    _roots = roots
    _builtin = builtin

  fun ref report(cause: diag.DiagnosticCause, at: diag.Location) =>
    _diagnostics.push(diag.Diagnostic(cause, at))

  fun ref enqueue(dir: PackageDir, name: source.PackageName,
    files: PackageFiles)
  =>
    _loaded.set(dir.path)
    _queue.push((dir, name, files))

  fun ref load(dir: PackageDir, name: source.PackageName)
    : (None | ReadFailure)
  =>
    """
    Reads a directory reached for the first time and queues it, or
    records why it could not be read. An unreadable file is reported
    here, once, whatever later reaches the directory.
    """
    match ReadPackage(_fs, dir)
    | let p: PackageFiles =>
      enqueue(dir, name, p)
      None
    | let f: FilesUnreadable =>
      for (file, why) in f.files.values() do
        report(UnreadableFile(dir.path, file, why),
          diag.FileOnly(dir.path, file))
      end
      _failed(dir.path) = f
      f
    | let f: ReadFailure =>
      _failed(dir.path) = f
      f
    end

  fun ref run(program_root: PackageDir) =>
    var i: USize = 0
    while i < _queue.size() do
      (let dir, let name, let files) =
        try _queue(i)? else _Unreachable(); break end
      i = i + 1
      let uses = recover iso Array[PackageUse] end
      for file in files.files.values() do
        for decl in parse.Parse.uses_only(file).values() do
          match _resolve(dir, name, program_root, decl)
          | let u: PackageUse => uses.push(u)
          end
        end
      end
      let package = Package(dir, name, files.files, consume uses)
      _packages.push(package)
      if dir != _builtin then _edges.push((dir, _builtin)) end
      for u in package.uses.values() do
        match u.outcome
        | let d: PackageDir => _edges.push((dir, d))
        end
      end
    end

  fun ref _resolve(from: PackageDir, from_name: source.PackageName,
    program_root: PackageDir, decl: parse.UseDecl)
    : (PackageUse | None)
  =>
    """
    One `use`: ponyc's checks in ponyc's order (scheme, then alias, then
    guard), then for a package `use` the locate and the load. A directive
    `use` takes no further part.
    """
    (let scheme, let locator) = ClassifyUse(decl.locator)
    let rules =
      match scheme
      | let u: UseUnknown =>
        report(UseSchemeUnknown(u.scheme), decl.locator_span)
        return None
      | UsePackage => UsePackage
      | UseDirective => UseDirective
      end
    let scheme_text: String =
      if decl.locator.size() == locator.size() then "package:"
      else decl.locator.substring(0,
        (decl.locator.size() - locator.size()).isize())
      end
    if (decl.alias isnt None) and (not rules.allow_alias()) then
      report(UseAliasNotAllowed(scheme_text), decl.span)
      return None
    end
    if (decl.guard isnt None) and (not rules.allow_guard()) then
      report(UseGuardNotAllowed(scheme_text), decl.span)
      return None
    end
    if rules isnt UsePackage then return None end
    match Locate(_fs, _roots, from, program_root, locator)
    | let l: Located =>
      if not (_loaded.contains(l.dir.path) or _failed.contains(l.dir.path))
      then
        let name =
          if l.relative then _RelativeName(from_name, locator)
          else source.PackageName(locator)
          end
        load(l.dir, name)
      end
      match try _failed(l.dir.path)? end
      | let f: ReadFailure =>
        let cause = CantLoadPackage(locator, f)
        report(cause, decl.span)
        PackageUse(decl, cause)
      | None => PackageUse(decl, l.dir)
      end
    | let f: LocateFailure =>
      let cause = CantLoadPackage(locator, f)
      report(cause, decl.span)
      PackageUse(decl, cause)
    end

  fun ref program(root: (PackageDir | None)): Program =>
    let packages = recover iso Array[Package] end
    for p in _packages.values() do packages.push(p) end
    let edges = recover iso Array[(PackageDir, PackageDir)] end
    for e in _edges.values() do edges.push(e) end
    sort.MergeSort[diag.Diagnostic](_diagnostics)
    let diagnostics = recover iso Array[diag.Diagnostic] end
    for d in _diagnostics.values() do diagnostics.push(d) end
    Program(Condense(consume packages, consume edges), _builtin, root,
      consume diagnostics)

primitive _RelativeName
  """
  ponyc's qualified name for a package found relative to the one using
  it: the using package's name with one trailing component removed per
  leading `../` in the locator, then `/`, then the locator with its
  leading `./` and `../` removed.
  """
  fun apply(parent: source.PackageName, locator: String)
    : source.PackageName
  =>
    var rest: String = locator
    var ups: USize = 0
    while true do
      if rest.at("../") then
        rest = rest.substring(3)
        ups = ups + 1
      elseif rest.at("./") then
        rest = rest.substring(2)
      else
        break
      end
    end
    var base: String = parent.text
    while (ups > 0) and (base.size() > 0) do
      if base.at("/", (base.size() - 1).isize()) then ups = ups - 1 end
      base = base.substring(0, (base.size() - 1).isize())
    end
    source.PackageName(base + "/" + rest)
