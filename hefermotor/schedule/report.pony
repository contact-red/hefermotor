use "collections"
use diag = "../diagnostics"
use discover = "../discover"
use export = "../export"
use source = "../source"

class val Report
  """
  What a run delivers: every diagnostic, discovery's, the groups' and
  the scheduler's own, sorted by `DiagnosticOrder`, and the export of
  every package whose group completed, in `PackageDir` order. A group
  whose result was refused contributes neither.
  """
  let diagnostics: Array[diag.Diagnostic] val
  let exports: Array[export.PackageExport] val

  new val create(
    diagnostics': Array[diag.Diagnostic] val,
    exports': Array[export.PackageExport] val)
  =>
    diagnostics = diagnostics'
    exports = exports'

  fun has_errors(): Bool =>
    """
    Whether anything was reported. Every diagnostic is an error.
    """
    diagnostics.size() > 0

  fun has_internal_errors(): Bool =>
    """
    Whether a diagnostic's code begins `internal/`: the run is not a
    verdict.
    """
    for d in diagnostics.values() do
      if d.cause.code().at("internal/") then return true end
    end
    false

  fun export_of(dir: discover.PackageDir): (export.ExportData | None) =>
    """
    The export of the package at `dir`, or `None` when no group
    delivered one.
    """
    for e in exports.values() do
      if e.dir == dir then return e.data end
    end
    None

  fun export_digest(): source.ContentHash =>
    """
    One hash over every export's hash, taken in ascending order of the
    hashes themselves, so it depends on the exports' content and on
    nothing run-local.
    """
    let hashes = Array[source.ContentHash]
    for e in exports.values() do hashes.push(e.data.hash) end
    Sort[Array[source.ContentHash], source.ContentHash](hashes)
    let builder: source.HashBuilder ref = source.HashBuilder
    for h in hashes.values() do builder.field_hash(h) end
    builder.done()
