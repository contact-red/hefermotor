use diag = "../diagnostics"
use source = "../source"

type SyntaxElement is (SyntaxKind, U32, U32)
  """
  Kind, byte offset of the first byte, subtree size in elements: a
  primitive union and two `U32`s, 16 bytes, so a `val` send of a tree
  traces none of its elements. `SourceFile` documents the bound the
  offset puts on a file.
  """

class val SyntaxTree
  """
  A file and the lossless tree over it, flattened in pre-order. Leaves
  tile the file in order, so `reprint` reproduces it byte for byte.
  Element 0 is the `NdModule`; the last element is the `TkEof` leaf at
  the file's size. Leafness is by kind: a `TokenKind` is a leaf, a
  `NodeKind` is not, whatever its subtree size.
  """
  let file: source.SourceFile
    """
    The file the tree covers.
    """
  let diagnostics: Array[SyntaxDiagnostic val] val
    """
    What the parser recorded while building the tree.
    """
  let _elems: Array[SyntaxElement] val

  new val _create(
    file': source.SourceFile,
    elems: Array[SyntaxElement] val,
    diagnostics': Array[SyntaxDiagnostic val] val)
  =>
    """
    Takes the elements as the parser lays them out: the children of
    element `i` start at `i + 1`, its next sibling is at `i` plus its
    subtree size, a leaf spans one element, and an element's width is
    the next element's offset after its subtree (or the file's size)
    minus its own. Over elements that break that layout only
    `TreeCheck` is total; `path_to` and `children` may not end.
    """
    file = file'
    _elems = elems
    diagnostics = diagnostics'

  fun size(): USize =>
    """
    The number of elements, leaves and interior nodes together.
    """
    _elems.size()

  fun val root(): Node =>
    """
    The `NdModule` element.
    """
    Node._create(this, 0)

  fun val nodes(): Iterator[Node] =>
    """
    Every element in pre-order.
    """
    _Nodes(this)

  fun val path_to(byte: USize): Array[Node] val =>
    """
    The elements covering `byte`, outermost first, ending at a leaf.
    Ranges are half-open, so a zero-width element covers no byte, with
    one exception: the path to the file's size is the path to `TkEof`,
    the zero-width leaf that is always last, so a position at the end
    of the file has a path and an empty file gives the module and the
    `TkEof`. Empty for a byte past that. At each level the covering
    child is the last child whose offset is at most `byte`.
    """
    let n = file.content.size()
    if byte > n then return recover val Array[Node] end end
    let path = recover iso Array[Node] end
    var index: USize = 0
    while true do
      path.push(Node._create(this, index))
      match _kind(index)
      | let _: TokenKind => break
      end
      let stop = index + _size(index)
      var child = index + 1
      var covering: (USize | None) = None
      while child < stop do
        if _offset(child) <= byte then covering = child end
        child = child + _size(child)
      end
      match covering
      | let c: USize => index = c
      | None => break
      end
    end
    consume path

  fun reprint(): String iso^ =>
    """
    Concatenate the leaves. Equal to the file's content for any tree this
    package builds, which is what lossless means.
    """
    let out = recover String(file.content.size()) end
    var i: USize = 0
    while i < _elems.size() do
      match _kind(i)
      | let _: TokenKind =>
        out.append(file.content, _offset(i), _finish(i) - _offset(i))
      end
      i = i + 1
    end
    consume out

  fun val _node(i: USize): Node ? =>
    if i >= _elems.size() then error end
    Node._create(this, i)

  fun _kind(i: USize): SyntaxKind =>
    try _elems(i)?._1 else _Unreachable(); NdError end

  fun _offset(i: USize): USize =>
    try _elems(i)?._2.usize() else _Unreachable(); 0 end

  fun _size(i: USize): USize =>
    try _elems(i)?._3.usize() else _Unreachable(); 0 end

  fun _finish(i: USize): USize =>
    """
    The byte offset just past element `i`: the next element's after the
    subtree, or the file's size.
    """
    let next = i + _size(i)
    if next < _elems.size() then _offset(next) else file.content.size() end

  fun _elements(): Array[SyntaxElement] val =>
    _elems

class val Node is Equatable[Node]
  """
  One element of a tree, with the tree. Built only by the tree from an
  index it produced, so every method is total. Two nodes are equal when
  they are the same element of the same tree object; a node from an
  earlier parse of the same file is never equal to one from a later.
  A kept `Node` keeps its whole tree alive.
  """
  let _tree: SyntaxTree
  let _i: USize

  new val _create(tree: SyntaxTree, index: USize) =>
    _tree = tree
    _i = index

  fun _index(): USize =>
    _i

  fun _size(): USize =>
    _tree._size(_i)

  fun kind(): SyntaxKind =>
    """
    A `TokenKind` for a leaf, a `NodeKind` for an interior node.
    """
    _tree._kind(_i)

  fun offset(): USize =>
    """
    The byte offset of the first byte.
    """
    _tree._offset(_i)

  fun finish(): USize =>
    """
    The byte offset just past the last byte.
    """
    _tree._finish(_i)

  fun width(): USize =>
    """
    The number of bytes covered.
    """
    finish() - offset()

  fun is_leaf(): Bool =>
    """
    Whether the kind is a `TokenKind`.
    """
    match kind()
    | let _: TokenKind => true
    else
      false
    end

  fun is_trivia(): Bool =>
    """
    Whether this is a whitespace or comment leaf.
    """
    match kind()
    | TkWhitespace | TkLineComment | TkNestedComment => true
    else
      false
    end

  fun text(): String =>
    """
    The bytes covered, as a view of the file's content.
    """
    _tree.file.content.trim(offset(), finish())

  fun span(): diag.Span =>
    """
    The bytes covered, as a span in the tree's file.
    """
    diag.Span(_tree.file.dir, _tree.file.name, offset(), width())

  fun children(): Iterator[Node] =>
    """
    The direct children in order, trivia included.
    """
    _Children(_tree, _i)

  fun child(k: SyntaxKind): (Node | None) =>
    """
    The first direct child of kind `k`.
    """
    for c in children() do
      if c.kind() is k then return c end
    end
    None

  fun first_token(): (TokenKind | None) =>
    """
    The kind of the first direct child that is a leaf and not trivia.
    """
    for c in children() do
      match c.kind()
      | TkWhitespace | TkLineComment | TkNestedComment => None
      | let t: TokenKind => return t
      end
    end
    None

  fun eq(that: Node box): Bool =>
    """
    The same element of the same tree object.
    """
    (_tree is that._tree) and (_i == that._i)

class _Nodes is Iterator[Node]
  let _tree: SyntaxTree
  var _next: USize = 0

  new create(tree: SyntaxTree) =>
    _tree = tree

  fun has_next(): Bool =>
    _next < _tree.size()

  fun ref next(): Node =>
    let n = Node._create(_tree, _next)
    _next = _next + 1
    n

class _Children is Iterator[Node]
  let _tree: SyntaxTree
  let _limit: USize
  var _next: USize

  new create(tree: SyntaxTree, parent: USize) =>
    _tree = tree
    _next = parent + 1
    _limit = parent + tree._size(parent)

  fun has_next(): Bool =>
    _next < _limit

  fun ref next(): Node =>
    let n = Node._create(_tree, _next)
    _next = _next + _tree._size(_next)
    n
