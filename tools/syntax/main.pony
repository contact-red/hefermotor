"""
# tools/syntax

Reads Pony files with hefermotor's parser and prints their token kinds
for comparison with ponyc's lexer.

`syntax --tokens <file>...` prints, per file, a `### <path>` line and
then one line per token that is not whitespace, a comment or the end,
holding ponyc's name for the token's kind, so that
`tools/agreement/check.py` can compare the sequence with what
`tools/agreement/ponyc_dump.c` prints from ponyc's own lexer over the
same file; the dumper stops before the end token.
"""
use "files"
use parse = "../../hefermotor/parse"
use source = "../../hefermotor/source"

actor Main
  """
  One file per behaviour, so that the tree and stream of each file are
  collected before the next file is read.
  """
  let _env: Env
  let _auth: FileAuth
  let _paths: Array[String] val

  new create(env: Env) =>
    _env = env
    _auth = FileAuth(env.root)
    var tokens = false
    let paths = recover iso Array[String] end
    for a in env.args.slice(1).values() do
      if a == "--tokens" then tokens = true else paths.push(a) end
    end
    _paths = consume paths
    if not tokens then
      env.err.print("usage: syntax --tokens <file>...")
      env.exitcode(2)
      return
    end
    _next(0)

  be _next(i: USize) =>
    let path = try _paths(i)? else return end
    match OpenFile(FilePath(_auth, path))
    | let f: File =>
      // The parser addresses a file with 32-bit offsets, as
      // DiskFileSystem.read enforces for the command.
      if f.size() > U32.max_value().usize() then
        _env.err.print("syntax: " + path + " is 4 GiB or larger")
        _env.exitcode(1)
      else
        let content: String val = f.read_string(f.size())
        _tokens(path, content)
      end
      f.dispose()
    else
      _env.err.print("syntax: can't open file " + path)
      _env.exitcode(1)
    end
    _next(i + 1)

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
