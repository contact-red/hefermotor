actor Main
  new create(env: Env) =>
    env.err.print("usage: hefermotor check [<dir>]")
    env.exitcode(2)
