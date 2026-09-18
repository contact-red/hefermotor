use "collections"

interface box SourceLookup
  """
  A file's text, by the file's path. `None` means the lookup has no text
  for that path.
  """
  fun content_of(path: String): (String | None)

class RenderText
  """
  Renders diagnostics as ponyc prints its errors: an `Error:` line, then
  `file:line:col: message` with a 1-based line and a 1-based byte column,
  then the source line, then a caret under the column, with the line's
  tabs copied into the padding so the caret lands under the column at
  any tab width. A line longer than 200 bytes is cut to 200 bytes around
  the column, `...` marking each cut edge. A diagnostic about a whole
  file gets `file: message`; one about nothing gets the message alone. A
  range in a file whose text the lookup cannot supply is rendered as the
  whole file, `file: message`.
  The source line is the line's content before its `\n` and any `\r`
  before it.

  A renderer reads each file's text on the first range in it and keeps
  the result for its lifetime, so make one renderer per report.
  """
  let _sources: SourceLookup box
  embed _indexes: Map[String, LineIndex] = _indexes.create()

  new create(sources: SourceLookup box) =>
    _sources = sources

  fun ref apply(d: Diagnostic): String =>
    """
    The rendering of one diagnostic, ending in a newline.
    """
    let out = recover iso String end
    out.append("Error:\n")
    match \exhaustive\ d.location
    | Nowhere =>
      out.append(d.cause.message())
      out.push('\n')
    | let f: FileOnly =>
      out.append(f.path())
      out.append(": ")
      out.append(d.cause.message())
      out.push('\n')
    | let s: Span =>
      let path = s.path()
      out.append(path)
      match _index(path)
      | let index: LineIndex =>
        (let line, let column) = index.position(s.start)
        out.push(':')
        out.append((line + 1).string())
        out.push(':')
        out.append((column + 1).string())
        out.append(": ")
        out.append(d.cause.message())
        out.push('\n')
        // A trim of a val string shares its buffer: the line is not
        // copied before it is cut to the window.
        let text: String = index.source.trim(
          index.line_start(line), index.line_end(line))
        (let shown, let caret) = _Window(text, column)
        out.append(shown)
        out.push('\n')
        var i: USize = 0
        while i < caret do
          let c = try shown(i)? else ' ' end
          out.push(if c == '\t' then '\t' else ' ' end)
          i = i + 1
        end
        out.append("^\n")
      | None =>
        out.append(": ")
        out.append(d.cause.message())
        out.push('\n')
      end
    end
    consume out

  fun ref _index(path: String): (LineIndex | None) =>
    try
      _indexes(path)?
    else
      match _sources.content_of(path)
      | let content: String =>
        let index = LineIndex(content)
        _indexes(path) = index
        index
      | None => None
      end
    end

primitive _Window
  """
  The part of a source line a rendering shows: the whole line when it is
  at most `width` bytes, otherwise `width` bytes of the line that include
  the caret, centred on it where the line allows, with `...` at each cut
  edge. Returns the text to print and the caret's column within it. The
  cut is at bytes, as the column is, so an edge can fall inside a
  multibyte character.
  """
  fun width(): USize => 200

  fun apply(text: String, column: USize): (String, USize) =>
    if text.size() <= width() then return (text, column) end
    let half = width() / 2
    let start =
      if column < half then 0
      else (column - half).min(text.size() - width())
      end
    let stop = start + width()
    let shown = recover iso String end
    if start > 0 then shown.append("...") end
    shown.append(text.substring(start.isize(), stop.isize()))
    if stop < text.size() then shown.append("...") end
    let caret = (column - start) + (if start > 0 then 3 else 0 end)
    (consume shown, caret)
