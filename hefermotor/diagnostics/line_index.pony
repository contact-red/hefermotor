class val LineIndex
  """
  Maps a byte offset in a source to its zero-based line and the byte
  column within that line. Diagnostics carry byte offsets and ponyc prints
  a position as a line and a byte column; this is the conversion from one
  to the other.
  """
  let source: String val
  let _line_starts: Array[USize] val
    """
    The byte offset at which each line begins. Always starts with 0, so
    there is always at least one line, even in an empty source.
    """

  new val create(source': String val) =>
    source = source'
    _line_starts =
      recover val
        let starts = Array[USize](16)
        starts.push(0)
        var i: USize = 0
        while i < source'.size() do
          try
            if source'(i)? == '\n' then
              starts.push(i + 1)
            end
          else
            _Unreachable()
          end
          i = i + 1
        end
        starts
      end

  fun line_count(): USize =>
    """
    How many lines the source has. A source with no newline has one line;
    a source ending in a newline has an empty line after it.
    """
    _line_starts.size()

  fun line_start(line: USize): USize =>
    """
    The byte offset at which `line` begins, clamped to the source.
    """
    try
      _line_starts(line)?
    else
      source.size()
    end

  fun line_end(line: USize): USize =>
    """
    The byte offset at which `line`'s content ends: before its `\n`, and
    before a `\r` that precedes the `\n`. For the last line, the source's
    size.
    """
    if (line + 1) >= _line_starts.size() then
      return source.size()
    end
    var stop = line_start(line + 1)
    if stop > line_start(line) then
      stop = stop - 1
      try
        if (stop > line_start(line)) and (source(stop - 1)? == '\r') then
          stop = stop - 1
        end
      else
        _Unreachable()
      end
    end
    stop

  fun position(byte: USize): (USize, USize) =>
    """
    The zero-based line and byte column at byte offset `byte`. An offset
    past the end of the source gives the last line's end.
    """
    let line = _line_of(byte)
    (line, byte.min(source.size()) - line_start(line))

  fun _line_of(byte: USize): USize =>
    var low: USize = 0
    var high = _line_starts.size()
    while (high - low) > 1 do
      let mid = low + ((high - low) / 2)
      if line_start(mid) <= byte then
        low = mid
      else
        high = mid
      end
    end
    low
