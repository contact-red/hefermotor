use "collections"
use source = "../source"

class val UnreadableDirectory
  """
  The directory could not be listed; `why` is the file system's reason.
  """
  let why: String

  new val create(why': String) =>
    why = why'

  fun describe(): String => why

primitive NoPonySources
  """
  The directory holds no `.pony` file.
  """
  fun describe(): String => "no Pony source files"

class val FilesUnreadable
  """
  The package's load failed because a source file could not be opened.
  `files` names each one with the file system's reason, in name order.
  """
  let files: Array[(String, String)] val

  new val create(files': Array[(String, String)] val) =>
    files = files'

  fun describe(): String => "a source file couldn't be opened"

type ReadFailure is (UnreadableDirectory | NoPonySources | FilesUnreadable)
  """
  Why a located directory could not become a package.
  """

type LoadFailure is (LocateFailure | ReadFailure)
  """
  Why a directory, located or not, could not become a package.
  """

class val PackageFiles
  """
  A package directory's source files: every entry ending in `.pony` that
  does not start with a dot and is not a directory, sorted bytewise by
  name, whatever order the file system listed them in.
  """
  let files: Array[source.SourceFile] val

  new val create(files': Array[source.SourceFile] val) =>
    files = files'

primitive _PonySource
  """
  Whether `name` is a source file name: longer than `.pony` and ending in
  it. A name is checked from its own end, so one shorter than the
  extension is never a source file.
  """
  fun apply(name: String): Bool =>
    (name.size() > 5) and name.at(".pony", (name.size() - 5).isize())

primitive ReadPackage
  """
  Reads a located directory into its source files. A directory that
  cannot be listed is `UnreadableDirectory`; one with no `.pony` file is
  `NoPonySources`; one where any `.pony` file cannot be read is
  `FilesUnreadable`, naming every such file, and the package's load fails
  as ponyc's does.
  """
  fun apply(fs: FileSystem box, dir: PackageDir)
    : (PackageFiles | ReadFailure)
  =>
    let names = Array[String]
    match fs.entries(dir.path)
    | let listed: Array[String] val =>
      for name in listed.values() do
        if name.at(".") then continue end
        if not _PonySource(name) then continue end
        match fs.kind(_Paths.join(dir.path, name))
        | IsDirectory => continue
        end
        names.push(name)
      end
    | let denied: Denied => return UnreadableDirectory(denied.why)
    end
    if names.size() == 0 then return NoPonySources end
    Sort[Array[String], String](names)
    let files = recover iso Array[source.SourceFile] end
    let unreadable = recover iso Array[(String, String)] end
    for name in names.values() do
      match fs.read(_Paths.join(dir.path, name))
      | let content: String =>
        files.push(source.SourceFile(dir.path, name, content))
      | let denied: Denied => unreadable.push((name, denied.why))
      end
    end
    if unreadable.size() > 0 then
      return FilesUnreadable(consume unreadable)
    end
    PackageFiles(consume files)
