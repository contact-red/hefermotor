"""
# hefermotor/export

What one group may see of another. `ExportData` is one package's
export: a `signature`, which is what downstream analysis and
invalidation key on, and a `hash` over it. `DepExports` is the set of
exports a group receives. `GroupResult` is what a group analysis
returns.
"""
use diag = "../diagnostics"
use discover = "../discover"
use source = "../source"

class val ExportData
  """
  What a downstream group may see of a package. `signature` is the
  contract: what invalidation and downstream analysis key on. `hash` is
  `HashBuilder` over `signature` as one field and nothing else; every
  constructor computes it from `signature` and none accepts it, so the
  two cannot disagree. Nothing run-local (a path, a group index, a
  package name) and nothing already in a cache key (a dependency's
  export hash, the configuration hash, the package's own source hash)
  may appear in a signature. `stub` is the one exception for the source
  hash: a stub's hash moves with every edit to the sources, so a
  dependent may be analysed again when nothing it reads changed, but is
  never reused when something did.
  """
  let signature: Array[U8] val
  let hash: source.ContentHash

  new val create(signature': Array[U8] val) =>
    signature = signature'
    hash = _hash_of(signature')

  new val stub(source_hash: source.ContentHash) =>
    """
    The export of a package whose signatures have not been extracted:
    one format-version byte, then the eight bytes of the package's
    source hash. The version byte changes whenever the layout does.
    """
    let bytes = recover iso Array[U8] end
    bytes.push(_StubFormat.version())
    bytes.append(source_hash.bytes())
    signature = consume bytes
    hash = _hash_of(signature)

  fun tag _hash_of(bytes: Array[U8] val): source.ContentHash =>
    source.HashBuilder.>field(bytes).done()

primitive _StubFormat
  fun version(): U8 => 0

class val PackageExport
  """
  A package's export, keyed by its directory. The directory is run-local
  and is not in the export's bytes.
  """
  let dir: discover.PackageDir
  let data: ExportData

  new val create(dir': discover.PackageDir, data': ExportData) =>
    dir = dir'
    data = data'

class val DepExports
  """
  The exports a group may read: every member export of every group in
  its `Group.needs`, one entry per directory, in the order the scheduler
  built them, which is run-local. Every group but `builtin`'s needs
  `builtin`, so `builtin`'s export is among them for every other group.
  """
  let entries: Array[PackageExport] val

  new val create(entries': Array[PackageExport] val) =>
    entries = entries'

  fun find(dir: discover.PackageDir): (ExportData | None) =>
    """
    The export of the package at `dir`, or `None` when no entry has
    that directory.
    """
    for e in entries.values() do
      if e.dir == dir then return e.data end
    end
    None

class val GroupResult
  """
  What a group analysis returns: one export per member, in member order,
  and the diagnostics it raised.
  """
  let exports: Array[PackageExport] val
  let diagnostics: Array[diag.Diagnostic] val

  new val create(
    exports': Array[PackageExport] val,
    diagnostics': Array[diag.Diagnostic] val)
  =>
    exports = exports'
    diagnostics = diagnostics'
