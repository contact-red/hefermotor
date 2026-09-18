interface val DiagnosticCause
  """
  What a diagnostic reports. A cause holds the structured facts as fields
  and renders them on request: `code` names the kind of problem, stable
  across wording changes and namespaced by the layer that raises it, as
  in `discover/use-not-found`; `message` is the text a person reads.
  """
  fun code(): String
  fun message(): String

class val Diagnostic is (Comparable[Diagnostic] & Stringable)
  """
  A cause at a location. Two diagnostics are equal when `DiagnosticOrder`
  places neither before the other: equal in location, code and message;
  other fields of a cause do not take part.
  """
  let cause: DiagnosticCause
  let location: Location

  new val create(cause': DiagnosticCause, location': Location) =>
    cause = cause'
    location = location'

  fun eq(that: Diagnostic box): Bool =>
    DiagnosticOrder.compare(this, that) is Equal

  fun lt(that: Diagnostic box): Bool =>
    DiagnosticOrder.compare(this, that) is Less

  fun string(): String iso^ =>
    """
    The code, the message and the location: the fields `DiagnosticOrder`
    compares.
    """
    let s = recover iso String end
    s.>append(cause.code()).>append(": ").>append(cause.message())
      .>append(" at ")
    match \exhaustive\ location
    | Nowhere => s.append("nowhere")
    | let f: FileOnly => s.append(f.path())
    | let sp: Span =>
      s.append(sp.path())
      s.push(':')
      s.append(sp.start.string())
      s.push('+')
      s.append(sp.length.string())
    end
    consume s

primitive DiagnosticOrder
  """
  A total order on diagnostics: by location kind (no file, then a whole
  file, then a byte range), then by the file's path, start and length,
  then by code, then by message.

  The path is the directory joined with the name, not the pair: when one
  package directory is a prefix of another, `/p/net/notifier/y.pony` sorts
  before `/p/net/x.pony` by path and after it by pair; the path is what a
  listing prints, so a listing sorted here is in the order of its paths as
  text. The order reads a cause only through `code` and `message`, so two
  causes with different fields and the same text are equal here.
  """
  fun compare(a: Diagnostic box, b: Diagnostic box): Compare =>
    match _compare_location(a.location, b.location)
    | Equal =>
      match a.cause.code().compare(b.cause.code())
      | Equal => a.cause.message().compare(b.cause.message())
      | let c: Compare => c
      end
    | let c: Compare => c
    end

  fun _compare_location(a: Location, b: Location): Compare =>
    match \exhaustive\ (a, b)
    | (Nowhere, Nowhere) => Equal
    | (Nowhere, _) => Less
    | (_, Nowhere) => Greater
    | (let x: FileOnly, let y: FileOnly) =>
      _PathOrder(x.dir, x.name, y.dir, y.name)
    | (let _: FileOnly, let _: Span) => Less
    | (let _: Span, let _: FileOnly) => Greater
    | (let x: Span, let y: Span) =>
      match _PathOrder(x.dir, x.name, y.dir, y.name)
      | Equal =>
        match x.start.compare(y.start)
        | Equal => x.length.compare(y.length)
        | let c: Compare => c
        end
      | let c: Compare => c
      end
    end

primitive _PathOrder
  """
  The order of two files' paths, `dir + "/" + name` compared byte by
  byte as `String.compare` does, without building either path. Two
  locations built from one file share its `dir` and `name` objects and
  compare equal at once.
  """
  fun apply(dir_a: String, name_a: String, dir_b: String, name_b: String)
    : Compare
  =>
    if (dir_a is dir_b) and (name_a is name_b) then return Equal end
    let len_a = (dir_a.size() + 1) + name_a.size()
    let len_b = (dir_b.size() + 1) + name_b.size()
    let shorter = len_a.min(len_b)
    var i: USize = 0
    while i < shorter do
      let x = _byte(dir_a, name_a, i)
      let y = _byte(dir_b, name_b, i)
      if x < y then return Less end
      if x > y then return Greater end
      i = i + 1
    end
    len_a.compare(len_b)

  fun _byte(dir: String, name: String, i: USize): U8 =>
    """
    Byte `i` of `dir + "/" + name`, for `i` inside it.
    """
    if i < dir.size() then
      try dir(i)? else _Unreachable(); 0 end
    elseif i == dir.size() then
      '/'
    else
      try name(i - (dir.size() + 1))? else _Unreachable(); 0 end
    end
