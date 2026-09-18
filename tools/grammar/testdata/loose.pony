primitive _Loose
  """
  Descends without a guard: `descend` alone does not count.
  """
  fun apply(p: _Parser ref) =>
    p.descend()
    _Looser(p)
    p.ascend()

primitive _Looser
  fun apply(p: _Parser ref) =>
    _Loose(p)
