"""
# hefermotor/command

The `hefermotor check` command as a library: argument parsing, the
search-root order, discovery, the run through a `Checker`, rendering
as text or JSON, and the exit code. `Run` takes the file system, the
base directory and the checker, so the whole command can run over a
memory file system with stub phases.
"""
use "promises"
use diag = "../diagnostics"
use discover = "../discover"
use schedule = "../schedule"
use source = "../source"

interface val Checker
  """
  What the command calls to analyse a discovered program under a build
  configuration.
  """
  fun apply(program: discover.Program, config: source.BuildConfig)
    : Promise[schedule.Report]

primitive Run
  """
  Runs `hefermotor check [<target>] [--path=DIR ...] [--json]` as
  `env.args` gives it. The target defaults to `.`, as ponyc's does.
  `base` is the absolute directory a relative target, search root or
  `PATH` entry resolves against; for the binary it is the process's
  working directory. Exit 0 with nothing to report; 1 when the run
  reported at least one diagnostic; 2 when it could not start, `base`
  not being absolute included; 70 when the report holds an `internal/*`
  diagnostic. `help` prints the usage to stdout and exits 0. The exit
  code is 70 from before the check starts until the report arrives, so
  a process that ends before the report exits as a crash. The returned
  promise carries the code the run ended with, fulfilled after every
  print was sent and `env.exitcode` was called with it. If the
  checker's promise is rejected the returned promise is rejected too
  and the code stays 70.
  """
  fun apply(env: Env, fs: discover.FileSystem box, base: String,
    check: Checker)
    : Promise[I32]
  =>
    if not base.at("/") then
      env.err.print("hefermotor: the working directory is not absolute: " +
        base)
      return _ended(env, 2)
    end
    let cmd =
      match CheckArgs(env.args, env.vars, StdlibSlot(fs, env.vars, base),
        base)
      | let c: CheckCommand => c
      | let help: HelpRequested =>
        env.out.write(help.text)
        return _ended(env, 0)
      | let u: UsageError =>
        env.err.print(u.string())
        return _ended(env, 2)
      end
    let program =
      match discover.Discover(fs, cmd.search_roots, base, cmd.target)
      | let p: discover.Program => p
      | let b: discover.BuiltinNotFound =>
        env.err.print(
          "hefermotor: no 'builtin' package in " + base +
          " or under any search root (" + b.reason.describe() +
          "); pass --path=<ponyc packages dir> or set PONYPATH")
        return _ended(env, 2)
      | let b: discover.BuiltinNotLoaded =>
        env.err.print(
          "hefermotor: the 'builtin' package at " + b.dir.path +
          " could not be loaded: " + b.reason.describe())
        return _ended(env, 2)
      end
    // 70 until the fulfil handler runs: a process that ends first exits
    // as a crash.
    env.exitcode(70)
    check(program, cmd.config)
      .next[I32]({(report: schedule.Report): I32 =>
        if cmd.json then
          env.out.print(JsonReport(program, report))
        else
          let render = diag.RenderText(program)
          for d in report.diagnostics.values() do
            env.err.write(render(d))
          end
        end
        let code: I32 =
          if report.has_internal_errors() then 70
          elseif report.has_errors() then 1
          else 0
          end
        env.exitcode(code)
        code
      })

  fun _ended(env: Env, code: I32): Promise[I32] =>
    env.exitcode(code)
    let ended = Promise[I32]
    ended(code)
    ended
