// A cycle that a guard breaks, and the spellings the scan must not
// count: a rule named in a comment, in a string, after a quote in a
// character literal, and a call whose first argument is not `p`.

class val _Widget
  """
  A class with a capability, so the name after it is the node.
  """
  fun apply(p: _Parser ref) =>
    _Guarded(p)

primitive _Guarded
  fun apply(p: _Parser ref) =>
    if p.too_deep("thing") then return end
    _Unguarded(p, "not _Loose(p)")

primitive _Unguarded
  fun apply(p: _Parser ref) =>
    let q = '"'
    // _Loose(p) is only named here
    p.expect(TkId, "id") // and "here
    _Guarded(p)
    _Predicate(p.current())
    _TokenSets.lparen()

primitive _Predicate
  fun apply(k: TokenKind): Bool => k is TkId
