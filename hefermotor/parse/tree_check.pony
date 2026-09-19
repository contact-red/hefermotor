primitive OneRoot
  """
  Element 0 is an `NdModule` spanning every element.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "OneRoot"

primitive EofLast
  """
  The last element is a `TkEof` leaf at the file's size.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "EofLast"

primitive SubtreeSizes
  """
  An interior node's subtree size is one plus its children's, and a
  leaf's is one.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "SubtreeSizes"

primitive OffsetsMonotone
  """
  Offsets never decrease in pre-order.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "OffsetsMonotone"

primitive FirstLeafOffset
  """
  An interior node's offset is its first child's, or the next element's
  when it has no child.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "FirstLeafOffset"

primitive Reprint
  """
  The leaves tile the file: the first starts at 0, each starts where
  the one before it ended, and the last ends at the file's size.
  """
  fun name(): String =>
    """
    The invariant's name, as a violation prints it.
    """
    "Reprint"

type TreeInvariant is
  ( OneRoot
  | EofLast
  | SubtreeSizes
  | OffsetsMonotone
  | FirstLeafOffset
  | Reprint )
  """
  What every tree this package builds keeps.
  """

class val TreeViolation
  """
  An invariant a tree broke, at an element: the element's index, or 0
  for a fact about the whole tree. A test and tool artifact, never a
  diagnostic; `string` is the invariant's name and the index.
  """
  let invariant: TreeInvariant
  let index: USize

  new val create(invariant': TreeInvariant, index': USize) =>
    invariant = invariant'
    index = index'

  fun string(): String iso^ =>
    (recover String end)
      .> append(invariant.name())
      .> append(" at element ")
      .> append(index.string())

primitive TreeCheck
  """
  Checks the invariants every tree this package builds keeps, and
  costs one pass over the elements.
  """
  fun apply(tree: SyntaxTree): Array[TreeViolation] val =>
    """
    Every invariant `tree` breaks, with where; empty when it breaks
    none.
    """
    let out = recover iso Array[TreeViolation] end
    let n = tree.size()
    let file_size = tree.file.content.size()
    if n == 0 then
      out.push(TreeViolation(OneRoot, 0))
      out.push(TreeViolation(EofLast, 0))
      return consume out
    end
    if (tree._size(0) != n) or (not (tree._kind(0) is NdModule)) then
      out.push(TreeViolation(OneRoot, 0))
    end
    if not ((tree._kind(n - 1) is TkEof) and
      (tree._offset(n - 1) == file_size))
    then
      out.push(TreeViolation(EofLast, n - 1))
    end
    // Open interior nodes as (index, end): `end` is the index just past
    // the subtree, and `seen` counts the elements its children's sizes
    // have accounted for.
    let open = Array[(USize, USize)]
    let seen = Array[USize]
    var previous_offset: USize = 0
    var previous_finish: USize = 0
    var i: USize = 0
    while i < n do
      let offset = tree._offset(i)
      let size = tree._size(i)
      if offset < previous_offset then
        out.push(TreeViolation(OffsetsMonotone, i))
      end
      previous_offset = offset
      // Close every open node whose subtree ended before this element.
      while true do
        try
          (let parent, let stop) = open(open.size() - 1)?
          if stop > i then break end
          if seen(seen.size() - 1)? != (stop - parent - 1) then
            out.push(TreeViolation(SubtreeSizes, parent))
          end
          open.pop()?
          seen.pop()?
        else
          break
        end
      end
      // `counted == 0`: this element is the parent's first child.
      try
        (let parent, _) = open(open.size() - 1)?
        let counted = seen(seen.size() - 1)?
        if (counted == 0) and (tree._offset(parent) != offset) then
          out.push(TreeViolation(FirstLeafOffset, parent))
        end
        seen(seen.size() - 1)? = counted + size
      end
      match tree._kind(i)
      | let _: TokenKind =>
        if size != 1 then out.push(TreeViolation(SubtreeSizes, i)) end
        if previous_finish != offset then
          out.push(TreeViolation(Reprint, i))
        end
        previous_finish = tree._finish(i)
      else
        if size == 0 then out.push(TreeViolation(SubtreeSizes, i)) end
        if size <= 1 then
          let next =
            if (i + 1) < n then tree._offset(i + 1) else file_size end
          if offset != next then
            out.push(TreeViolation(FirstLeafOffset, i))
          end
        else
          open.push((i, i + size))
          seen.push(0)
        end
      end
      i = i + 1
    end
    while true do
      try
        (let parent, let stop) = open.pop()?
        if seen.pop()? != (stop - parent - 1) then
          out.push(TreeViolation(SubtreeSizes, parent))
        end
      else
        break
      end
    end
    if previous_finish != file_size then
      out.push(TreeViolation(Reprint, n - 1))
    end
    consume out
