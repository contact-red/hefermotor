use diag = "diagnostics"
use discover = "discover"
use export = "export"
use source = "source"

primitive AnalyzeGroup
  """
  The per-group pipeline. Until name resolution and signature extraction
  exist, every member's export is the stub over its source hash and no
  diagnostic is raised.
  """
  fun apply(
    members: Array[discover.ParsedPackage] val,
    deps: export.DepExports,
    config: source.BuildConfig)
    : export.GroupResult
  =>
    let exports = recover iso Array[export.PackageExport] end
    for m in members.values() do
      exports.push(export.PackageExport(m.package.dir,
        export.ExportData.stub(m.package.source_hash)))
    end
    export.GroupResult(consume exports,
      recover val Array[diag.Diagnostic] end)
