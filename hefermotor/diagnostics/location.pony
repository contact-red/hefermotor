class val Span is Equatable[Span]
  """
  A byte range in one file. The file is named as its package directory plus
  the file name within it, so a consumer that stores locations can keep
  the name and the offsets and leave the directory out. Callers pass `dir`
  already canonical; nothing here normalises it.
  """
  let dir: String
  let name: String
  let start: USize
  let length: USize

  new val create(dir': String, name': String, start': USize,
    length': USize)
  =>
    dir = dir'
    name = name'
    start = start'
    length = length'

  fun path(): String =>
    """
    The directory joined with the name.
    """
    dir + "/" + name

  fun finish(): USize =>
    """
    The byte offset just past the range.
    """
    start + length

  fun eq(that: Span box): Bool =>
    (dir == that.dir) and (name == that.name) and (start == that.start)
      and (length == that.length)

class val FileOnly
  """
  A whole file, for a diagnostic about the file rather than a place in it.
  Named as `Span` names its file.
  """
  let dir: String
  let name: String

  new val create(dir': String, name': String) =>
    dir = dir'
    name = name'

  fun path(): String =>
    """
    The directory joined with the name.
    """
    dir + "/" + name

primitive Nowhere
  """
  No file at all, for a diagnostic about the run's inputs.
  """

type Location is (Span | FileOnly | Nowhere)
  """
  Where a diagnostic points: a byte range, a whole file, or nothing.
  """
