"""
# tools/syntax

Reads Pony files with hefermotor's parser and prints what it finds, for
comparison with ponyc and for running the parser over a corpus. A path
that names a directory stands for every `.pony` file under it, sorted.

`syntax --tokens <path>...` prints, per file, a `### <path>` line and
then one line per token that is not whitespace, a comment or the end,
holding ponyc's name for the token's kind, so that
`tools/agreement/check.py` can compare the sequence with what
`tools/agreement/ponyc_dump.c` prints from ponyc's own lexer over the
same file; the dumper stops before the end token.

`syntax --tree <path>...` prints, per file, a `### <path>` line, one
line per element of the tree in pre-order, indented two spaces per
level of depth, holding the kind's name, `<offset>+<width>` and, for a
leaf, its text quoted (`\n`, `\t`, `\"`, `\\`, and `\xNN` for any other
byte outside printable ASCII), and then one line per diagnostic:
`<code> <offset>+<width>: <message>`, without the `<offset>+<width>`
when the diagnostic has no span.

`syntax --check <path>...` parses every file and each of its mutants,
one actor per file, runs `TreeCheck` on every tree and compares
`Parse.uses_only` with the tree's `uses`; prints one line per
violation, `<path> <mutant>: <what>`, in file order, then two summary
lines: the counts with the mutation parameters, and the distribution
of diagnostic counts over the mutants; exits 1 when any tree broke an
invariant, the two readers disagreed, or a file could not be read.

`syntax --mutants <path>... [--emit <dir> --every N]` counts the
mutants of every file and, with `--emit`, writes every Nth of them, in
file order, as `<dir>/sample-<file>-<k>/main/<name>.pony`, where
`<file>` is the file's label (`_Files`) and `<k>` is the mutant's
index within its file.
"""
use "files"
use diag = "../../hefermotor/diagnostics"
use parse = "../../hefermotor/parse"
use sort = "../../hefermotor/sort"
use source = "../../hefermotor/source"

primitive _Tokens
primitive _Tree
primitive _Check
primitive _Mutants

type _Mode is (_Tokens | _Tree | _Check | _Mutants)

primitive _ModeFlag
  fun apply(arg: String): (_Mode | None) =>
    match arg
    | "--tokens" => _Tokens
    | "--tree" => _Tree
    | "--check" => _Check
    | "--mutants" => _Mutants
    else
      None
    end

class val _Input
  """
  One file to read: its path, and the name a sample of its mutants is
  written under.
  """
  let path: String
  let label: String

  new val create(path': String, label': String) =>
    path = path'
    label = label'

actor Main
  """
  Reads the files one behaviour at a time, so that under `--tokens` and
  `--tree` the trees of each file are collected before the next file is
  read, and collects the reports of the `--check` actors, printing them
  in file order.
  """
  let _env: Env
  let _auth: FileAuth
  let _inputs: Array[_Input] val
  let _mode: _Mode
  let _emit: (String | None)
  let _every: USize
  let _reports: Array[(_Report | None)]
  var _printed: USize = 0
  var _emitted: USize = 0
  embed _totals: _Totals = _Totals

  new create(env: Env) =>
    _env = env
    _auth = FileAuth(env.root)
    var mode: (_Mode | None) = None
    var emit: (String | None) = None
    var every: USize = 0
    var usage = false
    var empty = false
    let inputs = recover iso Array[_Input] end
    let args = env.args.slice(1)
    var i: USize = 0
    while i < args.size() do
      let a = try args(i)? else _Unreachable(); "" end
      match _ModeFlag(a)
      | let m: _Mode =>
        if mode isnt None then usage = true end
        mode = m
      | None =>
        match a
        | "--emit" =>
          i = i + 1
          try emit = args(i)? else usage = true end
        | "--every" =>
          i = i + 1
          try every = args(i)?.usize()? else usage = true end
          if every == 0 then usage = true end
        else
          if a.at("--") then
            usage = true
          else
            let found = _Files(_auth, a)
            if found.size() == 0 then
              env.err.print("syntax: no .pony files under " + a)
              empty = true
            end
            inputs.append(found)
          end
        end
      end
      i = i + 1
    end
    _inputs = consume inputs
    _emit = emit
    _every = every
    _reports = Array[(_Report | None)].init(None, _inputs.size())
    match mode
    | None => usage = true
    | _Mutants =>
      // --emit and --every go together.
      if (emit is None) != (every == 0) then usage = true end
    else
      if (emit isnt None) or (every != 0) then usage = true end
    end
    if usage or (_inputs.size() == 0) then
      if not empty then
        env.err.print(
          "usage: syntax --tokens <path>...\n" +
          "       syntax --tree <path>...\n" +
          "       syntax --check <path>...\n" +
          "       syntax --mutants <path>... [--emit <dir> --every N]")
      end
      env.exitcode(2)
      _mode = _Tokens
      return
    end
    _mode = (try mode as _Mode else _Unreachable(); _Tokens end)
    _next(0)

  be _next(i: USize) =>
    let input = try
      _inputs(i)?
    else
      // Under --check the last report's arrival ends the run.
      if _mode isnt _Check then _finish() end
      return
    end
    match _read(input.path)
    | let content: String val =>
      match _mode
      | _Tokens => _tokens(input.path, content)
      | _Tree => _tree(input.path, content)
      | _Check => _Checker(i, input.path, content, this)
      | _Mutants => _mutants(i, input, content)
      end
    | None =>
      if _mode is _Check then _checked(i, _Report.unread()) end
    end
    _next(i + 1)

  fun _read(path: String): (String val | None) =>
    match OpenFile(FilePath(_auth, path))
    | let f: File =>
      // The parser addresses a file with 32-bit offsets, as
      // DiskFileSystem.read enforces for the command.
      if f.size() > U32.max_value().usize() then
        _env.err.print("syntax: " + path + " is 4 GiB or larger")
        _env.exitcode(1)
        f.dispose()
        None
      else
        let content: String val = f.read_string(f.size())
        f.dispose()
        content
      end
    else
      _env.err.print("syntax: can't open file " + path)
      _env.exitcode(1)
      None
    end

  fun _tokens(path: String, content: String val) =>
    let file = source.SourceFile(Path.dir(path), Path.base(path), content)
    let out = recover iso String end
    out.append("### " + path + "\n")
    for node in parse.Parse.tree(file).nodes() do
      match node.kind()
      | parse.TkEof | parse.TkWhitespace | parse.TkLineComment
      | parse.TkNestedComment => None
      | let t: parse.TokenKind =>
        out.append(t.ponyc_name())
        out.push('\n')
      end
    end
    _env.out.write(consume out)

  fun _tree(path: String, content: String val) =>
    let file = source.SourceFile(Path.dir(path), Path.base(path), content)
    _env.out.write(_TreeText(path, parse.Parse(file)))

  fun ref _mutants(i: USize, input: _Input, content: String val) =>
    _totals.files = _totals.files + 1
    _totals.mutants = _totals.mutants + _Mutation.per_file()
    match _emit
    | let dir: String =>
      var k: USize = 0
      while k < _Mutation.per_file() do
        if (((i * _Mutation.per_file()) + k) % _every) == 0 then
          _write(dir, input, k, _Mutation(content, k)._1)
        end
        k = k + 1
      end
    end

  fun ref _write(dir: String, input: _Input, k: USize, text: String val) =>
    let case_dir = FilePath(_auth,
      Path.join(dir, "sample-" + input.label + "-" + k.string()))
    let package = FilePath(_auth, Path.join(case_dir.path, "main"))
    let target = FilePath(_auth,
      Path.join(package.path, Path.base(input.path)))
    // A case directory that exists already may be another input's
    // with the same label, or an earlier run's; its file must not be
    // overwritten.
    if case_dir.exists() then
      _env.err.print("syntax: " + case_dir.path + " exists")
      _env.exitcode(1)
    elseif package.mkdir() then
      match CreateFile(target)
      | let f: File =>
        if f.write(text) then
          _emitted = _emitted + 1
        else
          _env.err.print("syntax: can't write " + target.path)
          _env.exitcode(1)
        end
        f.dispose()
      else
        _env.err.print("syntax: can't create " + target.path)
        _env.exitcode(1)
      end
    else
      _env.err.print("syntax: can't create directory " + package.path)
      _env.exitcode(1)
    end

  be _checked(i: USize, report: _Report) =>
    """
    A `--check` actor's report, printed after the reports of every
    file before it.
    """
    try _reports(i)? = report else _Unreachable() end
    while _printed < _reports.size() do
      match try _reports(_printed)? else _Unreachable(); None end
      | let r: _Report =>
        _env.out.write(r.violations)
        _totals.add(r)
        try _reports(_printed)? = None else _Unreachable() end
        _printed = _printed + 1
      | None => return
      end
    end
    _finish()

  fun ref _finish() =>
    """
    The summary line, once every input has been read and, under
    `--check`, every report has been printed.
    """
    match _mode
    | _Check =>
      _env.out.print(
        "check: " + _totals.files.string() + " files, " +
        _totals.mutants.string() + " mutants (" + _Mutation.parameters() +
        "), " + _totals.violations.string() + " violations, " +
        _totals.files_with_diagnostics.string() +
        " files with diagnostics, " + _totals.lines.string() +
        " lines parsed")
      _env.out.print("diagnostics per mutant: " + _totals.histogram())
      if _totals.violations > 0 then _env.exitcode(1) end
    | _Mutants =>
      let out = recover iso String end
      out.append("mutants: " + _totals.files.string() + " files, " +
        _totals.mutants.string() + " mutants (" + _Mutation.parameters() +
        ")")
      match _emit
      | let dir: String =>
        out.append(", " + _emitted.string() + " emitted, every " +
          _every.string() + ", to " + dir)
      end
      _env.out.print(consume out)
    end

primitive _Files
  """
  The inputs a command-line path stands for: the file, or every `.pony`
  file under the directory, sorted by path. A file's label is its
  base name without `.pony`; a file under the directory is labelled by
  its path under the directory with `/` as `_`. A link given as the
  path is resolved; links below the directory are not followed.
  """
  fun apply(auth: FileAuth, path: String): Array[_Input] val =>
    let root = try FilePath(auth, path).canonical()?
      else FilePath(auth, path) end
    let is_dir = try FileInfo(root)?.directory else false end
    if not is_dir then
      return [_Input(path, _label(Path.base(path)))]
    end
    let found = Array[String]
    root.walk(object ref is WalkHandler
      fun ref apply(dir_path: FilePath, entries: Array[String] ref) =>
        for e in entries.values() do
          if Path.ext(e) == "pony" then
            found.push(Path.join(dir_path.path, e))
          end
        end
      end)
    sort.MergeSort[String](found)
    let out = recover iso Array[_Input] end
    let prefix: String val = root.path + Path.sep()
    for f in found.values() do
      let under = if f.at(prefix) then f.trim(prefix.size()) else f end
      out.push(_Input(f, _label(under)))
    end
    consume out

  fun _label(under: String): String =>
    let s = if Path.ext(under) == "pony" then
      under.trim(0, under.size() - 5)
    else
      under
    end
    let out = recover iso String end
    for b in s.values() do
      out.push(if b == '/' then '_' else b end)
    end
    consume out

primitive _TreeText
  """
  The `--tree` rendering of a parsed file.
  """
  fun apply(path: String, pf: parse.ParsedFile): String iso^ =>
    var out = recover iso String end
    out.append("### " + path + "\n")
    out = _node(consume out, pf.tree.root(), 0)
    for d in pf.diagnostics.values() do
      out.append(d.cause.code())
      match d.location
      | let s: diag.Span =>
        out.append(" " + s.start.string() + "+" + s.length.string())
      end
      out.append(": " + d.cause.message() + "\n")
    end
    consume out

  fun _node(out': String iso, node: parse.Node, depth: USize): String iso^
  =>
    var out = consume out'
    var d = depth
    while d > 0 do
      out.append("  ")
      d = d - 1
    end
    out.append(node.kind().name())
    out.append(" " + node.offset().string() + "+" + node.width().string())
    if node.is_leaf() then
      out.append(" ")
      out = _quote(consume out, node.text())
      out.push('\n')
    else
      out.push('\n')
      for c in node.children() do out = _node(consume out, c, depth + 1) end
    end
    consume out

  fun _quote(out': String iso, text: String): String iso^ =>
    let out = consume out'
    out.push('"')
    for b in text.values() do
      match b
      | '\n' => out.append("\\n")
      | '\t' => out.append("\\t")
      | '"' => out.append("\\\"")
      | '\\' => out.append("\\\\")
      else
        if (b >= 0x20) and (b < 0x7f) then
          out.push(b)
        else
          out.append("\\x")
          out.push(_hex(b >> 4))
          out.push(_hex(b and 0xf))
        end
      end
    end
    out.push('"')
    consume out

  fun _hex(nibble: U8): U8 =>
    if nibble < 10 then '0' + nibble else ('a' + nibble) - 10 end
