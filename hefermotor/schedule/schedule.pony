"""
# hefermotor/schedule

Runs a program's groups in dependency order: each group's files are
parsed in parallel, its analysis runs once every group it needs is
complete, and one `Report` is delivered at the end. The phases are
injected: `Schedule` takes the parse step and the group analysis, and
holds no phase of its own.
"""
use "promises"
use diag = "../diagnostics"
use discover = "../discover"
use export = "../export"
use parse = "../parse"
use source = "../source"

interface val GroupAnalysis
  """
  The per-group pipeline: from a group's parsed members, the exports of
  every group it needs, and the configuration, to one export per member
  and the diagnostics raised. A production
  implementer is a primitive; a `class val` or lambda implementer
  belongs in a test.
  """
  fun apply(
    members: Array[discover.ParsedPackage] val,
    deps: export.DepExports,
    config: source.BuildConfig)
    : export.GroupResult

interface val Step[In: Any val, Out: Any val]
  """
  A pure phase over one unit of work, spread by the scheduler over every
  unit of a group at once. A production implementer is a primitive.
  """
  fun apply(input: In): Out

primitive Schedule
  """
  Runs `program` under `config`: for each group, once every group it
  needs is complete, `parse_file` over every member file in parallel,
  then `analysis`. Returns a promise that is fulfilled exactly once,
  with the report, and never rejected. When the scheduler's own
  contract was violated the report carries an `internal/*` diagnostic
  and is not a verdict. Nothing fulfils the promise if the process ends
  first, so a consumer that must tell that from a finished run sets its
  exit code before calling.
  """
  fun apply(
    program: discover.Program,
    config: source.BuildConfig,
    parse_file: Step[source.SourceFile, parse.ParsedFile],
    analysis: GroupAnalysis)
    : Promise[Report]
  =>
    let done = Promise[Report]
    _Scheduler(program, config, parse_file, analysis, done).start()
    done

class val InternalError is diag.DiagnosticCause
  """
  A contract violation inside the scheduler, reported as a diagnostic
  rather than a crash: `internal/scheduler-contract` when a group's
  result was refused by the ready set, `internal/scheduler-stalled` when
  groups remain, none is running and none is ready. `detail` gives the
  reason and, for `scheduler-contract`, the group. A report holding one
  is not a verdict.
  """
  let code_suffix: String
  let detail: String

  new val create(code_suffix': String, detail': String) =>
    code_suffix = code_suffix'
    detail = detail'

  fun code(): String => "internal/" + code_suffix

  fun message(): String => detail
