use "collections"
use "pony_test"

actor \nodoc\ Main is TestList
  new create(env: Env) => PonyTest(env, this)
  new make() => None

  fun tag tests(test: PonyTest) =>
    test(_TestMergeSortSmall)
    test(_TestMergeSortStable)
    test(_TestMergeSortLarge)

class \nodoc\ iso _TestMergeSortSmall is UnitTest
  fun name(): String => "sort/merge sort: small arrays, strings and sizes"

  fun apply(h: TestHelper) =>
    h.assert_array_eq[USize]([], MergeSort[USize](Array[USize]))
    h.assert_array_eq[USize]([7], MergeSort[USize]([7]))
    h.assert_array_eq[USize]([1; 2], MergeSort[USize]([2; 1]))
    h.assert_array_eq[USize]([1; 1; 2; 3; 5; 8; 9],
      MergeSort[USize]([9; 1; 8; 2; 5; 3; 1]))
    h.assert_array_eq[String](["a"; "b"; "b.pony"; "ba"],
      MergeSort[String](["ba"; "b.pony"; "a"; "b"]))
    // In place: the argument is the result.
    let a: Array[USize] = [3; 1; 2]
    h.assert_true(MergeSort[USize](a) is a)
    h.assert_array_eq[USize]([1; 2; 3], a)

class \nodoc\ val _Keyed is Comparable[_Keyed]
  """
  Ordered by `key` alone, so `seq` shows which of two equal elements came
  first.
  """
  let key: USize
  let seq: USize

  new val create(key': USize, seq': USize) =>
    key = key'
    seq = seq'

  fun eq(that: _Keyed box): Bool => key == that.key
  fun lt(that: _Keyed box): Bool => key < that.key

class \nodoc\ iso _TestMergeSortStable is UnitTest
  fun name(): String => "sort/merge sort: equal elements keep their order"

  fun apply(h: TestHelper) ? =>
    let a = Array[_Keyed]
    // Each key 0..4 five times, in the order 0 2 4 1 3 repeating; seq is
    // the push index.
    var i: USize = 0
    while i < 25 do
      a.push(_Keyed((i * 7) % 5, i))
      i = i + 1
    end
    MergeSort[_Keyed](a)
    var prev = a(0)?
    for e in a.slice(1).values() do
      h.assert_true(prev.key <= e.key)
      if prev.key == e.key then h.assert_true(prev.seq < e.seq) end
      prev = e
    end

class \nodoc\ iso _TestMergeSortLarge is UnitTest
  """
  A presorted input of 300,000 and a shuffled input of 100,000 sort
  without a crash; every adjacent pair is in order and the output is a
  permutation of the input. Each check is one assertion over the whole
  array, since every assertion builds and sends a log line.
  """
  fun name(): String => "sort/merge sort: 300,000 presorted, 100,000 shuffled"

  fun apply(h: TestHelper) ? =>
    let sorted = Array[USize](300_000)
    for i in Range(0, 300_000) do sorted.push(i) end
    MergeSort[USize](sorted)
    h.assert_eq[USize](300_000, sorted.size())
    var in_place = true
    for (i, v) in sorted.pairs() do
      if v != i then in_place = false end
    end
    h.assert_true(in_place, "presorted input comes back as it was")
    // i * 7919 mod 100,000 is a permutation of the residues (7919 is
    // prime), so the input holds each value 0..999 a hundred times in a
    // scrambled order.
    let shuffled = Array[USize](100_000)
    for i in Range(0, 100_000) do
      shuffled.push(((i * 7919) % 100_000) % 1000)
    end
    let counts = Array[USize].init(0, 1000)
    for v in shuffled.values() do counts(v)? = counts(v)? + 1 end
    MergeSort[USize](shuffled)
    var ordered = true
    var prev: USize = 0
    for (i, v) in shuffled.pairs() do
      if (i > 0) and (v < prev) then ordered = false end
      counts(v)? = counts(v)? - 1
      prev = v
    end
    h.assert_true(ordered, "every adjacent pair is in order")
    var permutation = true
    for c in counts.values() do if c != 0 then permutation = false end end
    h.assert_true(permutation, "the output is a permutation of the input")
