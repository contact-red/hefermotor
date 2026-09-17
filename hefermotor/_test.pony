use "files"
use "pony_test"
use source = "./source"
use diag = "./diagnostics"
use parse = "./parse"
use discover = "./discover"
use export = "./export"
use schedule = "./schedule"
use command = "./command"

actor \nodoc\ Main is TestList
  new create(env: Env) => PonyTest(env, this)
  new make() => None

  fun tag tests(test: PonyTest) =>
    source.Main.make().tests(test)
    diag.Main.make().tests(test)
    parse.Main.make().tests(test)
    discover.Main.make().tests(test)
    export.Main.make().tests(test)
    schedule.Main.make().tests(test)
    command.Main.make().tests(test)
    test(_TestCheckOverDisk)

class \nodoc\ iso _TestCheckOverDisk is UnitTest
  """
  `Check` end to end over the disk fixture in `discover/testdata/roots`,
  with the fixture as the only search root: `builtin` and `real` load,
  every file is parsed, both packages are exported, nothing is
  reported.
  """
  fun name(): String => "hefermotor/check over the disk fixture"

  fun apply(h: TestHelper) ? =>
    let fixture = Path.canonical(Path.join(Path.dir(__loc.file()),
      "discover/testdata/roots"))?
    let fs = discover.DiskFileSystem(FileAuth(h.env.root))
    let program = discover.Discover(fs,
      discover.SearchRoots.with_stdlib(fixture, []),
      Path.join(fixture, "real"), "real") as discover.Program
    h.assert_eq[USize](2, program.groups.size())
    h.long_test(2_000_000_000)
    Check(program, source.BuildConfig.host())
      .next[None]({(r: schedule.Report)(h, program) =>
        h.assert_false(r.has_errors())
        h.assert_eq[USize](2, r.exports.size())
        try
          let real = program.package(Path.join(fixture, "real"))?
          match r.export_of(real.dir)
          | let e: export.ExportData =>
            h.assert_eq[source.ContentHash](e.hash,
              export.ExportData.stub(real.source_hash).hash)
          | None => h.fail("real's export")
          end
        else
          h.fail("real is a package")
        end
        h.complete(true)
      })
