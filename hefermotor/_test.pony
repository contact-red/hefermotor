use "pony_test"
use source = "./source"
use diag = "./diagnostics"
use parse = "./parse"
use discover = "./discover"
use export = "./export"
use schedule = "./schedule"

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
