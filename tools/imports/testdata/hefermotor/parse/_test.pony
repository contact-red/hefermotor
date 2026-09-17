use "pony_test"
use "pony_check"
use "collections"

actor Main is TestList
  new create(env: Env) => PonyTest(env, this)
  new make() => None
  fun tag tests(test: PonyTest) => None
  fun d(): USize => digestof this
