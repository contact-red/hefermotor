use "promises"

primitive _Filling
primitive _SlotFilled
primitive _SlotOutOfRange

class _Slots[Out: Any val]
  """
  Results by input index, whatever order they arrive in. `arrived`
  reports a second arrival at one index, or an index past the end, as
  data; `take` returns `_Filling` until every slot is filled, then the
  results in index order.
  """
  embed _filled: Array[Bool]
  embed _values: Array[(Out | None)]
  var _remaining: USize

  new create(size: USize) =>
    _filled = Array[Bool].init(false, size)
    _values = Array[(Out | None)].init(None, size)
    _remaining = size

  fun ref arrived(index: USize, out: Out)
    : (None | _SlotFilled | _SlotOutOfRange)
  =>
    try
      if _filled(index)? then return _SlotFilled end
      _filled(index)? = true
      _values(index)? = out
      _remaining = _remaining - 1
      None
    else
      _SlotOutOfRange
    end

  fun take(): (Array[Out] val | _Filling) =>
    if _remaining > 0 then return _Filling end
    let out = recover iso Array[Out] end
    for v in _values.values() do
      match v
      | let o: Out => out.push(o)
      else
        _Unreachable()
      end
    end
    consume out

actor _Collect[Out: Any val]
  """
  Fills one `_Slots` from `_Task` arrivals and fulfils the promise when
  the last one lands.
  """
  embed _slots: _Slots[Out]
  let _done: Promise[Array[Out] val]

  new create(size: USize, done: Promise[Array[Out] val]) =>
    _slots = _Slots[Out](size)
    _done = done

  be arrived(index: USize, out: Out) =>
    match _slots.arrived(index, out)
    | None =>
      match _slots.take()
      | let results: Array[Out] val => _done(results)
      | _Filling => None
      end
    else
      // Only this package's tasks send here, once each.
      _Unreachable()
    end

actor _Task[In: Any val, Out: Any val]
  """
  One unit of work on its own actor.
  """
  let _step: Step[In, Out]
  let _index: USize
  let _input: In
  let _back: _Collect[Out]

  new create(step: Step[In, Out], index: USize, input: In,
    back: _Collect[Out])
  =>
    _step = step
    _index = index
    _input = input
    _back = back

  be run() =>
    _back.arrived(_index, _step(_input))

primitive _FanOut[In: Any val, Out: Any val]
  """
  Runs `step` over every input, each on its own actor, and fulfils with
  the results in input order. An empty input fulfils at once.
  """
  fun apply(step: Step[In, Out], inputs: Array[In] val)
    : Promise[Array[Out] val]
  =>
    let done = Promise[Array[Out] val]
    if inputs.size() == 0 then
      done(recover val Array[Out] end)
      return done
    end
    let collect = _Collect[Out](inputs.size(), done)
    for (i, input) in inputs.pairs() do
      _Task[In, Out](step, i, input, collect).run()
    end
    done
