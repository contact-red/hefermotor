use "collections"
use diag = "../diagnostics"
use discover = "../discover"
use export = "../export"

primitive _NotRunning
primitive _ExportsMismatch
type _CompleteError is (_NotRunning | _ExportsMismatch)

class _Waiting
  """
  A group not yet handed out; `remaining` counts the groups in its
  `needs` not yet complete.
  """
  var remaining: USize

  new create(remaining': USize) => remaining = remaining'

primitive _Running
primitive _Done

class _ReadySet
  """
  The ready set over a program's groups. `ready` yields the groups whose
  `needs` are all complete, each exactly once, in index order, and marks
  them running. `deps_for` builds a group's `DepExports` from its needs
  and the exports recorded so far. `complete` records a running group's
  result when its exports are exactly the members' directories in
  order, and otherwise reports why not: `_NotRunning` when the group was
  not handed out by `ready` or is already complete, `_ExportsMismatch`
  when the directories differ. A rejected `complete` changes nothing,
  so the group stays running and a correct result can follow. `report`
  merges and sorts everything recorded so far, and may be read before
  `done()`.

  Progress, for a program whose `needs` are as `Group` documents them:
  while `done()` is false and no group handed out by `ready` is
  uncompleted, `ready()` is non-empty. `_Progress` reports a program
  for which that fails.
  """
  let _program: discover.Program
  embed _states: Array[(_Waiting | _Running | _Done)]
  embed _dependents: Array[Array[USize]]
  embed _exports: Map[discover.PackageDir, export.PackageExport]
  embed _diagnostics: Array[diag.Diagnostic]

  new create(program: discover.Program) =>
    _program = program
    _states = Array[(_Waiting | _Running | _Done)]
    _dependents = Array[Array[USize]]
    _exports = Map[discover.PackageDir, export.PackageExport]
    _diagnostics = Array[diag.Diagnostic]
    for g in program.groups.values() do
      _states.push(_Waiting(g.needs.size()))
      _dependents.push(Array[USize])
    end
    for (i, g) in program.groups.pairs() do
      for n in g.needs.values() do
        try _dependents(n)?.push(i) else _Unreachable() end
      end
    end

  fun ref ready(): Array[USize] val =>
    """
    Every waiting group whose needs are all complete, in index order,
    each now running.
    """
    let out = recover iso Array[USize] end
    for (i, s) in _states.pairs() do
      match s
      | let w: _Waiting if w.remaining == 0 =>
        try _states(i)? = _Running else _Unreachable() end
        out.push(i)
      end
    end
    consume out

  fun members(group: USize): Array[discover.Package] val =>
    try _program.groups(group)?.members else _Unreachable(); [] end

  fun deps_for(group: USize): export.DepExports =>
    """
    The exports of every member of every group in `group`'s needs, in
    needs order then member order. `group` must have been handed out by
    `ready`, so that every need is complete.
    """
    let entries = recover iso Array[export.PackageExport] end
    try
      for n in _program.groups(group)?.needs.values() do
        for m in _program.groups(n)?.members.values() do
          entries.push(_exports(m.dir)?)
        end
      end
    else
      _Unreachable()
    end
    export.DepExports(consume entries)

  fun ref complete(group: USize, result: export.GroupResult)
    : (None | _CompleteError)
  =>
    match try _states(group)? else _NotRunning end
    | _Running => None
    else
      return _NotRunning
    end
    let members' = members(group)
    if result.exports.size() != members'.size() then
      return _ExportsMismatch
    end
    for (i, e) in result.exports.pairs() do
      try
        if e.dir != members'(i)?.dir then return _ExportsMismatch end
      else
        _Unreachable()
      end
    end
    for e in result.exports.values() do _exports(e.dir) = e end
    _diagnostics.append(result.diagnostics)
    try
      _states(group)? = _Done
      for d in _dependents(group)?.values() do
        match _states(d)?
        | let w: _Waiting => w.remaining = w.remaining - 1
        else
          _Unreachable()
        end
      end
    else
      _Unreachable()
    end
    None

  fun done(): Bool =>
    for s in _states.values() do
      if s isnt _Done then return false end
    end
    true

  fun ref note(d: diag.Diagnostic) =>
    """
    Records a diagnostic raised by the scheduler itself.
    """
    _diagnostics.push(d)

  fun report(): Report =>
    let diagnostics = Array[diag.Diagnostic]
    diagnostics.append(_program.diagnostics)
    diagnostics.append(_diagnostics)
    Sort[Array[diag.Diagnostic], diag.Diagnostic](diagnostics)
    let sorted = recover iso Array[diag.Diagnostic] end
    for d in diagnostics.values() do sorted.push(d) end
    let dirs = Array[discover.PackageDir]
    for dir in _exports.keys() do dirs.push(dir) end
    Sort[Array[discover.PackageDir], discover.PackageDir](dirs)
    let exports = recover iso Array[export.PackageExport] end
    for dir in dirs.values() do
      try exports.push(_exports(dir)?) else _Unreachable() end
    end
    Report(consume sorted, consume exports)
