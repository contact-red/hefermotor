use "promises"
use discover = "discover"
use parse = "parse"
use schedule = "schedule"
use source = "source"

primitive Check
  """
  The library's front door: analyse a discovered program under a build
  configuration. The one place the scheduler is composed with the
  production phases; a consumer that injects a phase calls
  `schedule.Schedule` itself. The promise is fulfilled exactly once and
  never rejected.
  """
  fun apply(program: discover.Program, config: source.BuildConfig)
    : Promise[schedule.Report]
  =>
    schedule.Schedule(program, config, parse.Parse, AnalyzeGroup)
