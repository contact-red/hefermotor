use "files"
use parse = "../../hefermotor/parse"
use source = "../../hefermotor/source"

primitive _Mutation
  """
  The single-edit mutants of a file: at each of `cut_points` byte
  offsets, evenly spaced through the file, a truncation, a four-byte
  deletion and an insertion of each of `"`, `(`, `end` and `/*`;
  `per_file` mutants, numbered by operation then by cut point.
  """
  fun cut_points(): USize => 8

  fun per_file(): USize => 6 * cut_points()

  fun parameters(): String =>
    "m = " + cut_points().string() + " cut points at k/" +
    (cut_points() + 1).string() + " of the file: truncation, 4-byte " +
    "deletion, insertion of \", (, end, /*"

  fun apply(content: String val, k: USize): (String val, String val) =>
    """
    Mutant `k` of `content`, and a label naming the edit.
    """
    let cut = k % cut_points()
    let at = (content.size() * (cut + 1)) / (cut_points() + 1)
    match k / cut_points()
    | 0 => (content.trim(0, at), "truncated at " + at.string())
    | 1 => (_splice(content, at, at + 4, ""),
        "4 bytes deleted at " + at.string())
    | 2 => (_splice(content, at, at, "\""), "\" inserted at " + at.string())
    | 3 => (_splice(content, at, at, "("), "( inserted at " + at.string())
    | 4 => (_splice(content, at, at, "end"),
        "end inserted at " + at.string())
    | 5 => (_splice(content, at, at, "/*"),
        "/* inserted at " + at.string())
    else
      _Unreachable(); ("", "")
    end

  fun _splice(content: String val, from: USize, to: USize, insert: String)
    : String val
  =>
    recover val
      String(content.size() + insert.size())
        .> append(content.trim(0, from))
        .> append(insert)
        .> append(content.trim(to))
    end

primitive _Histogram
  """
  The buckets the diagnostic-count distribution is printed in. The
  last starts at 500, the parser's per-file budget
  (`parse/_records.pony`, `_DiagnosticBudget`), so every mutant that
  reached the budget lands in it.
  """
  fun labels(): Array[String] val =>
    ["0"; "1"; "2"; "3"; "4"; "5-9"; "10-99"; "100-499"; "500+"]

  fun bucket(n: USize): USize =>
    if n < 5 then n
    elseif n < 10 then 5
    elseif n < 100 then 6
    elseif n < 500 then 7
    else 8
    end

class val _Report
  """
  What one `--check` actor found over its file and mutants.
  """
  let violations: String
  let violation_count: USize
  let histogram: Array[USize] val
  let lines: USize
  let file_diagnostics: USize
  let files: USize
  let mutants: USize

  new val create(violations': String, violation_count': USize,
    histogram': Array[USize] val, lines': USize, file_diagnostics': USize,
    files': USize, mutants': USize)
  =>
    violations = violations'
    violation_count = violation_count'
    histogram = histogram'
    lines = lines'
    file_diagnostics = file_diagnostics'
    files = files'
    mutants = mutants'

  new val unread() =>
    """
    The report for a file that could not be read.
    """
    violations = ""
    violation_count = 0
    histogram = recover val
      Array[USize].init(0, _Histogram.labels().size())
    end
    lines = 0
    file_diagnostics = 0
    files = 0
    mutants = 0

class _Totals
  """
  The sums over the reports printed so far.
  """
  var files: USize = 0
  var mutants: USize = 0
  var violations: USize = 0
  var lines: USize = 0
  var files_with_diagnostics: USize = 0
  embed _histogram: Array[USize] =
    Array[USize].init(0, _Histogram.labels().size())

  fun ref add(r: _Report) =>
    files = files + r.files
    mutants = mutants + r.mutants
    violations = violations + r.violation_count
    lines = lines + r.lines
    if r.file_diagnostics > 0 then
      files_with_diagnostics = files_with_diagnostics + 1
    end
    var b: USize = 0
    while b < _histogram.size() do
      try _histogram(b)? = _histogram(b)? + r.histogram(b)?
      else _Unreachable()
      end
      b = b + 1
    end

  fun histogram(): String =>
    let out = recover iso String end
    var b: USize = 0
    while b < _histogram.size() do
      if b > 0 then out.append(", ") end
      try
        out.append(_Histogram.labels()(b)? + ": " + _histogram(b)?.string())
      else
        _Unreachable()
      end
      b = b + 1
    end
    consume out

actor _Checker
  """
  Parses one file and each of its mutants, one behaviour per parse so
  that no more than one tree is live at a time, and reports to `Main`.
  """
  let _index: USize
  let _path: String
  let _content: String val
  let _main: Main
  embed _violations: String ref = String
  var _violation_count: USize = 0
  embed _histogram: Array[USize] =
    Array[USize].init(0, _Histogram.labels().size())
  var _lines: USize = 0
  var _file_diagnostics: USize = 0

  new create(index: USize, path: String, content: String val, main: Main) =>
    _index = index
    _path = path
    _content = content
    _main = main
    _run(0)

  be _run(k: USize) =>
    """
    Parse `k`: the file itself at 0, then its mutants.
    """
    if k > _Mutation.per_file() then
      let size = _histogram.size()
      let histogram = recover iso Array[USize](size) end
      for n in _histogram.values() do histogram.push(n) end
      _main._checked(_index, _Report(_violations.clone(), _violation_count,
        consume histogram, _lines, _file_diagnostics, 1,
        _Mutation.per_file()))
      return
    end
    (let text, let label) =
      if k == 0 then (_content, "unmutated")
      else _Mutation(_content, k - 1)
      end
    let file = source.SourceFile(Path.dir(_path), Path.base(_path), text)
    let pf = parse.Parse(file)
    for v in parse.TreeCheck(pf.tree, pf.diagnostics).values() do
      _violation(label, v.string())
    end
    if not _same(pf.uses(), parse.Parse.uses_only(file)) then
      _violation(label, "uses_only differs from the tree's uses")
    end
    if k == 0 then
      _file_diagnostics = pf.diagnostics.size()
    else
      let b = _Histogram.bucket(pf.diagnostics.size())
      try _histogram(b)? = _histogram(b)? + 1 else _Unreachable() end
    end
    _lines = _lines + _Lines(text)
    _run(k + 1)

  fun ref _violation(label: String, what: String) =>
    _violation_count = _violation_count + 1
    _violations.append(_path + " " + label + ": " + what + "\n")

  fun _same(a: Array[parse.UseDecl] val, b: Array[parse.UseDecl] val): Bool =>
    if a.size() != b.size() then return false end
    var i: USize = 0
    while i < a.size() do
      try
        if a(i)? != b(i)? then return false end
      else
        _Unreachable()
      end
      i = i + 1
    end
    true

primitive _Lines
  """
  The number of newlines in `text`, as `wc -l` counts lines.
  """
  fun apply(text: String): USize =>
    var n: USize = 0
    for b in text.values() do
      if b == '\n' then n = n + 1 end
    end
    n
