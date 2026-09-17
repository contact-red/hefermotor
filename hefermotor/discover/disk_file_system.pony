use "files"

class DiskFileSystem is FileSystem
  """
  The real disk. Every path it opens carries the read and stat
  capabilities and nothing more; `canonical` is `realpath`, which takes
  no capability. A relative path is refused by every call, so nothing
  here reads the process's current directory.
  """
  let _auth: FileAuth
  let _caps: FileCaps val

  new create(auth: FileAuth) =>
    _auth = auth
    _caps = recover val FileCaps.>set(FileRead).>set(FileStat) end

  fun canonical(path: String): (String | None) =>
    if not Path.is_abs(path) then return None end
    try Path.canonical(path)? else None end

  fun kind(path: String): PathKind =>
    if not Path.is_abs(path) then return Missing end
    try
      let info = FileInfo(FilePath(_auth, path, _caps))?
      if info.directory then IsDirectory else IsFile end
    else
      Missing
    end

  fun entries(dir: String): (Array[String] val | Denied) =>
    if not Path.is_abs(dir) then return Denied("not an absolute path") end
    try
      let d = Directory(FilePath(_auth, dir, _caps))?
      let names: Array[String] val = d.entries()?
      d.dispose()
      names
    else
      Denied("couldn't read directory")
    end

  fun read(path: String): (String | Denied) =>
    if not Path.is_abs(path) then return Denied("not an absolute path") end
    match OpenFile(FilePath(_auth, path, _caps))
    | let f: File =>
      let content: String val = f.read_string(f.size())
      f.dispose()
      content
    | let err: FileErrNo =>
      Denied(_describe(err))
    end

  fun _describe(err: FileErrNo): String =>
    match \exhaustive\ err
    | FilePermissionDenied => "permission denied"
    | FileBadFileNumber => "bad file descriptor"
    | FileExists => "file exists"
    | FileEOF => "end of file"
    | FileOK => "ok"
    | FileError => "couldn't open file"
    end
