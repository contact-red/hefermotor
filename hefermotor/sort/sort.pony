"""
# hefermotor/sort

One sort for every array whose size or order the checked tree controls.
The stdlib `Sort` is a quicksort that takes its pivots from the ends, so
on input that is already in order its recursion is as deep as the array
and its time is quadratic; `MergeSort` does not recurse and takes
O(n log n) time on any input.
"""

primitive MergeSort[A: Comparable[A] #read]
  """
  A merge sort: O(n log n) time on any input, no recursion, one auxiliary
  array; stable, so elements that compare equal keep their order. Sorts
  in place and returns the array.
  """
  fun apply(a: Array[A] ref): Array[A] ref^ =>
    let n = a.size()
    if n < 2 then return a end
    let aux = Array[A](n)
    try
      for i in a.values() do aux.push(i) end
      var width: USize = 1
      // src and dst alternate between a and aux; the runs are in src.
      var src: Array[A] ref = a
      var dst: Array[A] ref = aux
      while width < n do
        var lo: USize = 0
        while lo < n do
          let mid = (lo + width).min(n)
          let hi = (lo + (2 * width)).min(n)
          _merge(src, dst, lo, mid, hi)?
          lo = hi
        end
        let swap = src
        src = dst
        dst = swap
        width = width * 2
      end
      if src isnt a then
        var i: USize = 0
        while i < n do
          a(i)? = src(i)?
          i = i + 1
        end
      end
    else
      _Unreachable()
    end
    a

  fun _merge(src: Array[A] ref, dst: Array[A] ref, lo: USize, mid: USize,
    hi: USize) ?
  =>
    """
    Merges the runs `[lo, mid)` and `[mid, hi)` of `src` into `dst`,
    taking from the left run when the two heads compare equal.
    """
    var i = lo
    var j = mid
    var k = lo
    while k < hi do
      if (i < mid) and ((j >= hi) or (not (src(j)? < src(i)?))) then
        dst(k)? = src(i)?
        i = i + 1
      else
        dst(k)? = src(j)?
        j = j + 1
      end
      k = k + 1
    end
