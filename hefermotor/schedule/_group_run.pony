use diag = "../diagnostics"
use discover = "../discover"
use export = "../export"
use parse = "../parse"
use source = "../source"

primitive _Parsing
primitive _Reported

actor _GroupRun
  """
  One in-flight group: the parse fan-out over every member file, then
  the group analysis, then one `finished`. Parse diagnostics enter the
  report here.
  """
  let _index: USize
  let _members: Array[discover.Package] val
  let _deps: export.DepExports
  let _config: source.BuildConfig
  let _parse_file: Step[source.SourceFile, parse.ParsedFile]
  let _analysis: GroupAnalysis
  let _back: _Scheduler
  var _state: (_Parsing | _Reported) = _Parsing

  new create(index: USize, members: Array[discover.Package] val,
    deps: export.DepExports, config: source.BuildConfig,
    parse_file: Step[source.SourceFile, parse.ParsedFile],
    analysis: GroupAnalysis, back: _Scheduler)
  =>
    _index = index
    _members = members
    _deps = deps
    _config = config
    _parse_file = parse_file
    _analysis = analysis
    _back = back

  be run() =>
    let files = recover iso Array[source.SourceFile] end
    for m in _members.values() do files.append(m.files) end
    let me: _GroupRun tag = this
    _FanOut[source.SourceFile, parse.ParsedFile](_parse_file, consume files)
      .next[None]({(out: Array[parse.ParsedFile] val) => me.parsed(out) })

  be parsed(trees: Array[parse.ParsedFile] val) =>
    match _state
    | _Parsing =>
      _state = _Reported
      // Re-slice by member; a trim of a val array is a shared view.
      let members = recover iso Array[discover.ParsedPackage] end
      let reported = recover iso Array[diag.Diagnostic] end
      var at: USize = 0
      for m in _members.values() do
        let stop = at + m.files.size()
        let mine = trees.trim(at, stop)
        for t in mine.values() do reported.append(t.diagnostics) end
        members.push(discover.ParsedPackage(m, mine))
        at = stop
      end
      let result = _analysis(consume members, _deps, _config)
      reported.append(result.diagnostics)
      _back.finished(_index,
        export.GroupResult(result.exports, consume reported))
    | _Reported =>
      // Only this actor's own fan-out promise calls parsed, once.
      _Unreachable()
    end
