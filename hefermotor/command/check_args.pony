use "cli"
use discover = "../discover"
use source = "../source"

class val CheckCommand
  """
  A parsed `check` command: the target as written, the search roots in
  resolution order, whether to print JSON, and the configuration.
  """
  let target: String
  let search_roots: discover.SearchRoots
  let json: Bool
  let config: source.BuildConfig

  new val create(target': String, search_roots': discover.SearchRoots,
    json': Bool, config': source.BuildConfig)
  =>
    target = target'
    search_roots = search_roots'
    json = json'
    config = config'

class val UsageError
  """
  A command line the command cannot act on, with the parser's reason;
  `string` is the reason and the usage line.
  """
  let _text: String

  new val create(text: String) => _text = text

  fun string(): String =>
    _text + "\nusage: hefermotor check [<target>] [--path=DIR ...] [--json]"

class val HelpRequested
  """
  A command line with the help option or command; `text` is the help to
  print.
  """
  let text: String

  new val create(text': String) => text = text'

primitive CheckArgs
  """
  Parses `hefermotor check [<target>] [--path=DIR ...] [--json]`. The
  target defaults to `.`. The search roots are the stdlib slot first,
  when there is one, then each `--path` in order, then the entries of
  `PONYPATH` from `vars`, then `/usr/local/lib` and `/opt/local/lib`, as
  ponyc orders its own list. A `--path` value is split on `:` as ponyc
  splits it, an empty entry is dropped, and a relative entry is taken
  under `base`, the directory ponyc would resolve it against. The
  configuration is the host's.
  """
  fun apply(args: Array[String] val, vars: Array[String] val,
    stdlib: (String | None), base: String)
    : (CheckCommand | HelpRequested | UsageError)
  =>
    let spec =
      try
        let check = CommandSpec.leaf("check", "Check a Pony program", [
          OptionSpec.string_seq("path",
            "A directory to search for packages; may be repeated")
          OptionSpec.bool("json", "Print the report as JSON"
            where default' = false)
        ], [
          ArgSpec.string("target", "The program's directory or package name"
            where default' = ".")
        ])?
        CommandSpec.parent("hefermotor", "A Pony semantic analyzer", [],
          [check])? .> add_help()?
      else
        _Unreachable()
        return UsageError("")
      end
    let cmd =
      match CommandParser(spec).parse(args)
      | let c: Command => c
      | let help: CommandHelp => return HelpRequested(help.help_string())
      | let e: SyntaxError => return UsageError(e.string())
      end
    // The spec's only command leaf is check; help is a CommandHelp.
    if cmd.fullname() != "hefermotor/check" then _Unreachable() end
    let dirs = recover iso Array[String] end
    let lists = Array[String]
    for p in cmd.option("path").string_seq().values() do lists.push(p) end
    lists.push(_EnvVar(vars, "PONYPATH"))
    for list in lists.values() do
      for p in list.split(":").values() do
        if p.size() > 0 then dirs.push(_under(base, p)) end
      end
    end
    dirs.push("/usr/local/lib")
    dirs.push("/opt/local/lib")
    let roots =
      match stdlib
      | let s: String => discover.SearchRoots.with_stdlib(s, consume dirs)
      | None => discover.SearchRoots(consume dirs)
      end
    CheckCommand(cmd.arg("target").string(), roots,
      cmd.option("json").bool(), source.BuildConfig.host())

  fun _under(base: String, dir: String): String =>
    if dir.at("/") then dir else base + "/" + dir end

primitive StdlibSlot
  """
  The packages directory beside the `ponyc` on `PATH`: the first `PATH`
  entry from `vars` holding a `ponyc` file, an empty or relative entry
  taken under `base`, made canonical through the file system so a
  symbolic link resolves to the real binary; then the `packages`
  directory beside that binary's directory, or beside its parent, the
  two layouts ponyc's own `add_pony_installation_dir` tries. `None`
  when no entry holds one or neither directory is there. Only that the
  file exists is checked, not that it runs.
  """
  fun apply(fs: discover.FileSystem box, vars: Array[String] val,
    base: String)
    : (String | None)
  =>
    for entry in _EnvVar(vars, "PATH").split(":").values() do
      let dir = if entry.size() == 0 then base else _under(base, entry) end
      match fs.canonical(dir + "/ponyc")
      | let ponyc: String =>
        if fs.kind(ponyc) isnt discover.IsFile then continue end
        let bin = _Dir(ponyc)
        let beside: String = _Dir(bin) + "/packages"
        let above: String = _Dir(_Dir(bin)) + "/packages"
        for candidate in [beside; above].values() do
          match fs.canonical(candidate)
          | let packages: String =>
            if fs.kind(packages) is discover.IsDirectory then
              return packages
            end
          end
        end
        return None
      end
    end
    None

  fun _under(base: String, dir: String): String =>
    if dir.at("/") then dir else base + "/" + dir end

primitive _EnvVar
  """
  The value of `name` in `vars`, or the empty string.
  """
  fun apply(vars: Array[String] val, name: String): String =>
    for v in vars.values() do
      if v.at(name + "=") then return v.substring((name.size() + 1).isize())
      end
    end
    ""

primitive _Dir
  """
  The directory part of an absolute path.
  """
  fun apply(path: String): String =>
    try
      let cut = path.rfind("/")?
      if cut == 0 then "/" else path.substring(0, cut) end
    else
      path
    end
