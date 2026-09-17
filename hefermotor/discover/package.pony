use parse = "../parse"
use source = "../source"

class val PackageUse
  """
  A package-scheme `use` and what became of it: the directory it resolved
  to and that loaded, or why it did not. A `use` whose scheme, alias or
  guard ponyc rejects is not here; it is a diagnostic and nothing else.
  """
  let decl: parse.UseDecl
  let outcome: (PackageDir | CantLoadPackage)

  new val create(
    decl': parse.UseDecl,
    outcome': (PackageDir | CantLoadPackage))
  =>
    decl = decl'
    outcome = outcome'

class val Package
  """
  A loaded package: its directory, its display name, its source files
  sorted bytewise by name, the hash of those files, and its package
  `use`s in file order then source order. `source_hash` covers each
  file's name and content hash in order and nothing else, so it is the
  same wherever the directory sits and changes when a file is renamed,
  added, removed or edited.
  """
  let dir: PackageDir
  let name: source.PackageName
  let files: Array[source.SourceFile] val
  let source_hash: source.ContentHash
  let uses: Array[PackageUse] val

  new val create(
    dir': PackageDir,
    name': source.PackageName,
    files': Array[source.SourceFile] val,
    uses': Array[PackageUse] val)
  =>
    dir = dir'
    name = name'
    files = files'
    uses = uses'
    let builder: source.HashBuilder ref = source.HashBuilder
    for f in files'.values() do
      builder.>field(f.name).field_hash(f.hash)
    end
    source_hash = builder.done()

class val ParsedPackage
  """
  A group member with its files parsed: one `ParsedFile` per entry of
  `package.files`, in the same order.
  """
  let package: Package
  let files: Array[parse.ParsedFile] val

  new val create(package': Package, files': Array[parse.ParsedFile] val) =>
    package = package'
    files = files'
