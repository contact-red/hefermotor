use "pony_test"
use source = "./source"
use diag = "./diagnostics"

actor \nodoc\ Main is TestList
  new create(env: Env) => PonyTest(env, this)
  new make() => None

  fun tag tests(test: PonyTest) =>
    source.Main.make().tests(test)
    diag.Main.make().tests(test)
