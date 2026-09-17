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
    | (let x: FileOnly, let y: FileOnly) => x.path().compare(y.path())
    | (let _: FileOnly, let _: Span) => Less
    | (let _: Span, let _: FileOnly) => Greater
    | (let x: Span, let y: Span) =>
      match x.path().compare(y.path())
      | Equal =>
        match x.start.compare(y.start)
        | Equal => x.length.compare(y.length)
        | let c: Compare => c
        end
      | let c: Compare => c
      end
    end
