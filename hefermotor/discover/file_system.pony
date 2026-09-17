use "collections"

primitive IsDirectory
primitive IsFile
primitive Missing

class val Denied
  """
  The file system refused the access; `why` is the reason, in the file
  system's words.
  """
  let why: String

  new val create(why': String) =>
    why = why'

type PathKind is (IsDirectory | IsFile | Missing)
  """
  What a path names, as far as it can be told without opening it. A path
  that cannot be reached is `Missing`, as `stat` reports it.
  """

interface box FileSystem
  """
  What discovery reads. A file system has no current directory; a process
  does. Every path a caller passes is absolute; discovery joins a relative
  locator with its base directory before passing it here.
  """
  fun canonical(path: String): (String | None)
    """
    The canonical form of `path`, with every symbolic link resolved, or
    `None` when nothing exists there or `path` is not absolute.
    """
  fun kind(path: String): PathKind
    """
    Whether `path` is a directory, a file, or nothing reachable.
    """
  fun entries(dir: String): (Array[String] val | Denied)
    """
    The names in a directory, in no particular order.
    """
  fun read(path: String): (String | Denied)
    """
    A file's bytes.
    """

class MemoryFileSystem is FileSystem
  """
  A file system built in a test. Every path given to `file`, `dir`,
  `deny` or `link` must be absolute; it is cleaned lexically. `canonical`
  resolves a path as `realpath` does: a link is followed where it
  appears, `..` steps out of what the path resolved to so far, and a
  path through a file or a denied directory is `None`. `entries` returns
  names in the order they were added, so a test that adds files in
  reverse checks that a reader sorts them.
  """
  embed _files: Map[String, String] = _files.create()
  embed _dirs: Set[String] = _dirs.create()
  embed _denied: Set[String] = _denied.create()
  embed _links: Map[String, String] = _links.create()
  embed _order: Map[String, Array[String]] = _order.create()

  fun ref file(path: String, content: String) =>
    """
    A file, and every directory above it. A path that is already a
    directory or a link is a fixture mistake.
    """
    let p = _normalize(path)
    if _dirs.contains(p) or _links.contains(p) then _Unreachable() end
    _files(p) = content
    _mkdirs(_Paths.dir(p))
    _record(p)

  fun ref dir(path: String) =>
    """
    A directory, and every directory above it. A path that is already a
    file or a link is a fixture mistake.
    """
    let p = _normalize(path)
    if _files.contains(p) or _links.contains(p) then _Unreachable() end
    _mkdirs(p)

  fun ref deny(path: String) =>
    """
    A denied file cannot be read. A denied directory is still a directory
    but cannot be listed, and nothing beneath it can be reached, as with
    a directory that lacks search permission. The root cannot be denied.
    """
    let p = _normalize(path)
    if p == "/" then _Unreachable() end
    _denied.set(p)

  fun ref link(path: String, target: String) =>
    """
    A symbolic link to an absolute `target`. `canonical` follows it where
    it appears in a path and returns `None` after 40 links in a row, as
    `realpath` does with `ELOOP`. A path that is already a file or a
    directory is a fixture mistake.
    """
    let p = _normalize(path)
    if _files.contains(p) or _dirs.contains(p) then _Unreachable() end
    _links(p) = _normalize(target)
    _mkdirs(_Paths.dir(p))
    _record(p)

  fun canonical(path: String): (String | None) =>
    if not _Paths.is_abs(path) then return None end
    _resolve(path, 0)

  fun _under_denied(p: String): Bool =>
    """
    Whether a denied directory lies strictly above `p`.
    """
    if p == "/" then return false end
    var here = _Paths.dir(p)
    while true do
      if _denied.contains(here) then return true end
      if here == "/" then return false end
      here = _Paths.dir(here)
    end
    false

  fun kind(path: String): PathKind =>
    match canonical(path)
    | let p: String =>
      if _dirs.contains(p) then IsDirectory
      elseif _files.contains(p) then IsFile
      else Missing
      end
    | None => Missing
    end

  fun entries(dir': String): (Array[String] val | Denied) =>
    match canonical(dir')
    | let p: String =>
      if _denied.contains(p) then return Denied("permission denied") end
      if not _dirs.contains(p) then return Denied("not a directory") end
      let out = recover iso Array[String] end
      try
        for name in _order(p)?.values() do out.push(name) end
      end
      consume out
    | None => Denied("no such directory")
    end

  fun read(path: String): (String | Denied) =>
    match canonical(path)
    | let p: String =>
      if _denied.contains(p) then return Denied("permission denied") end
      try _files(p)? else Denied("no such file") end
    | None => Denied("no such file")
    end

  fun _exists(p: String): Bool =>
    _dirs.contains(p) or _files.contains(p)

  fun _resolve(p: String, depth: USize): (String | None) =>
    """
    Resolves `p` one segment at a time, as `realpath` does: `.` and an
    empty segment are skipped, `..` steps up from what has resolved so
    far (and stays at the root), a link is followed as soon as its
    segment is reached, and the walk fails at a segment that is not a
    directory or lies beneath a denied one. A trailing `/` requires a
    directory. The result must exist.
    """
    if depth > 40 then return None end
    var built = "/"
    for seg in p.split("/").values() do
      if (seg == "") or (seg == ".") then continue end
      if not _dirs.contains(built) then return None end
      if _denied.contains(built) then return None end
      if seg == ".." then
        built = _Paths.dir(built)
        continue
      end
      let next: String =
        if built == "/" then "/" + seg else built + "/" + seg end
      try
        let target = _links(next)?
        match _resolve(target, depth + 1)
        | let t: String => built = t
        | None => return None
        end
      else
        built = next
      end
    end
    if p.at("/", -1) and (not _dirs.contains(built)) then return None end
    if _exists(built) and (not _under_denied(built)) then built else None end

  fun ref _mkdirs(p: String) =>
    var built = ""
    for seg in p.split("/").values() do
      if seg == "" then continue end
      let parent = if built == "" then "/" else built end
      built = built + "/" + seg
      if not _dirs.contains(built) then
        _dirs.set(built)
        _record_in(parent, seg)
      end
    end
    _dirs.set("/")

  fun ref _record(p: String) =>
    _record_in(_Paths.dir(p), _Paths.base(p))

  fun ref _record_in(parent: String, name: String) =>
    let names = try _order(parent)? else
      let fresh = Array[String]
      _order(parent) = fresh
      fresh
    end
    if not names.contains(name) then names.push(name) end

  fun _normalize(path: String): String =>
    """
    The cleaned path. A relative path is a caller error; the class
    requires absolute ones.
    """
    if not _Paths.is_abs(path) then _Unreachable() end
    _Paths.clean(path)
