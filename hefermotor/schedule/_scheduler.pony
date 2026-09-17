use "promises"
use diag = "../diagnostics"
use discover = "../discover"
use export = "../export"
use parse = "../parse"
use source = "../source"

primitive _Live
primitive _Draining
primitive _Fulfilled

class val _Turn
  """
  What the scheduler does after one event: the groups to launch, and the
  report when the run is over.
  """
  let launch: Array[USize] val
  let report: (Report | None)

  new val create(launch': Array[USize] val, report': (Report | None)) =>
    launch = launch'
    report = report'

class _Progress
  """
  The scheduler's decisions over a ready set, as a plain class so a test
  can drive the events in any order. `start` returns the first groups to
  launch; `finished` records a result and returns the next groups to
  launch, or the report once nothing is in flight. A result the ready
  set refuses is noted as `internal/scheduler-contract` and nothing more
  is launched. Nothing in flight, the set not done and nothing ready,
  with no result refused, is noted as `internal/scheduler-stalled`. The
  report is returned exactly once.
  """
  embed _ready: _ReadySet
  var _state: (_Live | _Draining | _Fulfilled) = _Live
  var _in_flight: USize = 0

  new create(program: discover.Program) =>
    _ready = _ReadySet(program)

  fun ref start(): _Turn =>
    let batch = _ready.ready()
    _in_flight = _in_flight + batch.size()
    _Turn(batch, _settle())

  fun ref finished(index: USize, result: export.GroupResult): _Turn =>
    """
    Records one group's result. `index` must be a group handed out by
    an earlier turn and not yet finished.
    """
    match _state
    | _Fulfilled =>
      // Each group finishes once, and nothing is launched after the
      // report is returned.
      _Unreachable()
      _Turn([], None)
    | _Draining =>
      _in_flight = _in_flight - 1
      _record(index, result)
      _Turn([], _settle())
    | _Live =>
      _in_flight = _in_flight - 1
      let batch: Array[USize] val =
        if _record(index, result) then _ready.ready() else [] end
      _in_flight = _in_flight + batch.size()
      _Turn(batch, _settle())
    end

  fun ref members(group: USize): Array[discover.Package] val =>
    _ready.members(group)

  fun ref deps_for(group: USize): export.DepExports =>
    _ready.deps_for(group)

  fun ref _record(index: USize, result: export.GroupResult): Bool =>
    """
    Records a group's result; on refusal notes the violation and stops
    launching. Returns whether the result was accepted.
    """
    match _ready.complete(index, result)
    | None => true
    | let e: _CompleteError =>
      let why = match e
        | _NotRunning => "not running"
        | _ExportsMismatch => "exports are not the members in order"
        end
      _ready.note(diag.Diagnostic(
        InternalError("scheduler-contract",
          "group " + index.string() + ": result refused, " + why),
        diag.Nowhere))
      _state = _Draining
      false
    end

  fun ref _settle(): (Report | None) =>
    """
    The report once nothing is in flight, with a stall noted first when
    no result was refused and the set is not done.
    """
    if _in_flight > 0 then return None end
    if (_state is _Live) and (not _ready.done()) then
      _ready.note(diag.Diagnostic(
        InternalError("scheduler-stalled",
          "groups remain, none is running and none is ready"),
        diag.Nowhere))
    end
    _state = _Fulfilled
    _ready.report()

actor _Scheduler
  """
  Runs `_Progress`'s decisions: launches a `_GroupRun` per group it
  names, feeds it each result, and fulfils the promise with the report
  it returns.
  """
  embed _progress: _Progress
  let _config: source.BuildConfig
  let _parse_file: Step[source.SourceFile, parse.ParsedFile]
  let _analysis: GroupAnalysis
  let _done: Promise[Report]

  new create(program: discover.Program, config: source.BuildConfig,
    parse_file: Step[source.SourceFile, parse.ParsedFile],
    analysis: GroupAnalysis, done: Promise[Report])
  =>
    _progress = _Progress(program)
    _config = config
    _parse_file = parse_file
    _analysis = analysis
    _done = done

  be start() =>
    _act(_progress.start())

  be finished(index: USize, result: export.GroupResult) =>
    _act(_progress.finished(index, result))

  fun ref _act(turn: _Turn) =>
    for g in turn.launch.values() do
      _GroupRun(g, _progress.members(g), _progress.deps_for(g), _config,
        _parse_file, _analysis, this).run()
    end
    match turn.report
    | let r: Report => _done(r)
    end
