use "collections"
use diag = "../diagnostics"

class val Group
  """
  A set of packages that reach each other through `use`, the unit the
  scheduler runs. `index` is the group's position in `Program.groups`;
  `needs` refers to groups by it. It identifies the group within this
  `Program` only and never enters export data or a cache key. `members`
  are in `PackageDir` order.
  `needs` holds the index of every group this one depends on, directly
  or through another, ascending and never including itself; every group
  but `builtin`'s has `builtin`'s index in it.
  """
  let index: USize
  let members: Array[Package] val
  let needs: Array[USize] val

  new val create(
    index': USize,
    members': Array[Package] val,
    needs': Array[USize] val)
  =>
    index = index'
    members = members'
    needs = needs'

class val Program
  """
  Everything discovery found: the groups in an order where every group
  comes after the groups it needs, `builtin`'s directory, the root's
  directory or `None` when the root did not load, and the diagnostics
  discovery raised, sorted by `DiagnosticOrder`. A package that failed to
  load is in no group; the `use`s that named it carry the reason.
  """
  let groups: Array[Group] val
  let builtin: PackageDir
  let root: (PackageDir | None)
  let diagnostics: Array[diag.Diagnostic] val
  let _packages: Map[String, Package] val
  let _group_of: Map[String, USize] val
  let _contents: Map[String, String] val

  new val create(
    groups': Array[Group] val,
    builtin': PackageDir,
    root': (PackageDir | None),
    diagnostics': Array[diag.Diagnostic] val)
  =>
    groups = groups'
    builtin = builtin'
    root = root'
    diagnostics = diagnostics'
    let packages = recover iso Map[String, Package] end
    let group_of' = recover iso Map[String, USize] end
    let contents = recover iso Map[String, String] end
    for g in groups'.values() do
      for p in g.members.values() do
        packages(p.dir.path) = p
        group_of'(p.dir.path) = g.index
        for f in p.files.values() do contents(f.path()) = f.content end
      end
    end
    _packages = consume packages
    _group_of = consume group_of'
    _contents = consume contents

  fun package(dir_path: String): Package ? =>
    """
    The loaded package at a canonical directory path.
    """
    _packages(dir_path)?

  fun group_of(dir: PackageDir): USize ? =>
    """
    The index of the group holding a loaded package.
    """
    _group_of(dir.path)?

  fun content_of(path: String): (String | None) =>
    """
    The text of a loaded package's source file, by the file's path, so a
    renderer can show the line a diagnostic points at.
    """
    try _contents(path)? end
