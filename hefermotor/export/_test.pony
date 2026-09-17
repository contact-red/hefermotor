use "pony_test"
use diag = "../diagnostics"
use discover = "../discover"
use source = "../source"

actor \nodoc\ Main is TestList
  new create(env: Env) => PonyTest(env, this)
  new make() => None

  fun tag tests(test: PonyTest) =>
    test(_TestExportHash)
    test(_TestStubExport)
    test(_TestDepExports)

class \nodoc\ iso _TestExportHash is UnitTest
  """
  `hash` is `HashBuilder` over `signature` as one field and nothing
  else: equal signatures give equal hashes, and a one-byte change moves
  it.
  """
  fun name(): String => "export/hash is over the signature alone"

  fun apply(h: TestHelper) =>
    let bytes: Array[U8] val = [1; 2; 3]
    let one = ExportData(bytes)
    let again = ExportData([1; 2; 3])
    let other = ExportData([1; 2; 4])
    h.assert_array_eq[U8](bytes, one.signature)
    h.assert_eq[source.ContentHash](one.hash, again.hash)
    h.assert_ne[source.ContentHash](one.hash, other.hash)
    h.assert_eq[source.ContentHash](
      source.HashBuilder.>field(bytes).done(), one.hash)
    // Hashed as one field, not byte by byte.
    h.assert_ne[source.ContentHash](
      source.HashBuilder.>field([as U8: 1]).>field([as U8: 2])
        .>field([as U8: 3]).done(),
      one.hash)
    h.assert_eq[source.ContentHash](ExportData([]).hash,
      source.HashBuilder.>field("").done())

class \nodoc\ iso _TestStubExport is UnitTest
  """
  A stub's signature is the version byte and the source hash's bytes,
  and nothing else: the same hash gives the same bytes wherever it came
  from, and no path or name is in them.
  """
  fun name(): String => "export/stub: version byte then the source hash"

  fun apply(h: TestHelper) ? =>
    let content = source.SourceFile("/x/p", "a.pony", "actor Main")
    let stub = ExportData.stub(content.hash)
    h.assert_eq[USize](9, stub.signature.size())
    h.assert_eq[U8](0, stub.signature(0)?)
    h.assert_array_eq[U8](content.hash.bytes(), stub.signature.slice(1))
    h.assert_eq[source.ContentHash](stub.hash, ExportData(stub.signature).hash)
    let moved = source.SourceFile("/y/q", "b.pony", "actor Main")
    h.assert_array_eq[U8](stub.signature,
      ExportData.stub(moved.hash).signature)
    let edited = source.SourceFile("/x/p", "a.pony", "actor Main2")
    h.assert_ne[source.ContentHash](stub.hash,
      ExportData.stub(edited.hash).hash)
    let text = String.from_array(stub.signature)
    h.assert_false(text.contains("/x/p"))
    h.assert_false(text.contains("a.pony"))

class \nodoc\ iso _TestDepExports is UnitTest
  """
  `find` matches a directory located twice and through a link, and a
  `GroupResult` holds what it is given.
  """
  fun name(): String => "export/dep exports, group result"

  fun apply(h: TestHelper) ? =>
    let fs: discover.MemoryFileSystem ref = discover.MemoryFileSystem
    fs.file("/p/a/a.pony", "")
    fs.file("/p/b/b.pony", "")
    fs.link("/p/link_to_a", "/p/a")
    let a = _Dir(h, fs, "/p/a")?
    let b = _Dir(h, fs, "/p/b")?
    let a_data = ExportData.stub(source.SourceFile("/p/a", "a.pony", "").hash)
    let b_data = ExportData([7])
    let deps = DepExports([PackageExport(a, a_data); PackageExport(b, b_data)])
    h.assert_eq[source.ContentHash](a_data.hash,
      (deps.find(_Dir(h, fs, "/p/a")?) as ExportData).hash)
    h.assert_eq[source.ContentHash](a_data.hash,
      (deps.find(_Dir(h, fs, "/p/link_to_a")?) as ExportData).hash)
    h.assert_eq[source.ContentHash](b_data.hash,
      (deps.find(b) as ExportData).hash)
    fs.dir("/p/c")
    h.assert_true(deps.find(_Dir(h, fs, "/p/c")?) is None)
    h.assert_true(DepExports([]).find(a) is None)
    let result = GroupResult(deps.entries,
      [diag.Diagnostic(_Noted, diag.Nowhere)])
    h.assert_eq[USize](2, result.exports.size())
    h.assert_eq[USize](1, result.diagnostics.size())

primitive \nodoc\ _Noted
  fun code(): String => "export-test/noted"
  fun message(): String => "noted"

primitive \nodoc\ _Dir
  """
  A `PackageDir` built the only way one can be from outside `discover`:
  by locating the directory.
  """
  fun apply(h: TestHelper, fs: discover.FileSystem box, path: String)
    : discover.PackageDir ?
  =>
    match discover.LocateTarget(fs, discover.SearchRoots([]), "/", path)
    | let l: discover.Located => l.dir
    | let f: discover.LocateFailure =>
      h.fail("fixture directory missing: " + path)
      error
    end
