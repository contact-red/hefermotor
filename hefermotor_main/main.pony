use "files"
use hm = "../hefermotor"
use command = "../hefermotor/command"
use discover = "../hefermotor/discover"

actor Main
  new create(env: Env) =>
    command.Run(env, discover.DiskFileSystem(FileAuth(env.root)),
      Path.cwd(), hm.Check)
