use "collections"
use sort = "../sort"

primitive Condense
  """
  Turns packages and the `use` edges between them into groups in a
  canonical order. Membership is by strongly connected components, as
  ponyc's `package_dependency_groups` computes it; a chain of any length
  is handled, and the graph's depth never bounds the call stack. Order
  is Kahn's: of the groups whose dependencies are all
  placed, the one whose smallest member's `PackageDir` sorts lowest
  comes next, so the order depends on the graph and the directories and
  on nothing else. Each group's `needs` is the closure of its
  dependencies. An edge to or from a directory not in `packages`, and an
  edge from a package to itself, is ignored; of two packages with one
  directory, the first is kept.
  """
  fun apply(
    packages: Array[Package] val,
    edges: Array[(PackageDir, PackageDir)] val)
    : Array[Group] val
  =>
    let nodes = _Nodes(packages, edges)
    let component = _Tarjan(nodes)
    let order = _Kahn(nodes, component.of, component.count)
    let position = Array[USize].init(0, order.size())
    let members = Array[Array[USize]]
    try
      for (pos, c) in order.pairs() do
        position(c)? = pos
        members.push(Array[USize])
      end
      // Nodes are in PackageDir order, so each group's members are too.
      for n in Range(0, nodes.packages.size()) do
        members(position(component.of(n)?)?)?.push(n)
      end
    else
      _Unreachable()
    end
    let needs = _Needs(nodes, component.of, order)
    let sorted = nodes.packages
    let groups = recover iso Array[Group] end
    for g in Range(0, order.size()) do
      try
        let group_members = recover iso Array[Package] end
        for n in members(g)?.values() do group_members.push(sorted(n)?) end
        groups.push(Group(g, consume group_members, needs(g)?))
      else
        _Unreachable()
      end
    end
    consume groups

class _Nodes
  """
  The packages in `PackageDir` order, and each one's out-edges as node
  indices, ascending and without duplicates.
  """
  let packages: Array[Package] val
  let out: Array[Array[USize]]

  new create(
    packages': Array[Package] val,
    edges: Array[(PackageDir, PackageDir)] val)
  =>
    let by_path = Map[String, Package]
    let dirs = Array[PackageDir]
    for p in packages'.values() do
      if by_path.contains(p.dir.path) then continue end
      by_path(p.dir.path) = p
      dirs.push(p.dir)
    end
    sort.MergeSort[PackageDir](dirs)
    let frozen = recover iso Array[Package] end
    let index = Map[String, USize]
    for d in dirs.values() do
      index(d.path) = frozen.size()
      try frozen.push(by_path(d.path)?) else _Unreachable() end
    end
    packages = consume frozen
    let sets = Array[Set[USize]]
    for i in Range(0, packages.size()) do sets.push(Set[USize]) end
    for (from, to) in edges.values() do
      try
        let a = index(from.path)?
        let b = index(to.path)?
        if a != b then sets(a)?.set(b) end
      end
    end
    out = Array[Array[USize]]
    for s in sets.values() do
      let targets = Array[USize]
      for t in s.values() do targets.push(t) end
      sort.MergeSort[USize](targets)
      out.push(targets)
    end

class _Tarjan
  """
  Strongly connected components by Tarjan's algorithm, with the recursion
  held in an explicit stack of (node, next out-edge) frames so that the
  depth of the graph is not the depth of the thread's stack. `of` maps a
  node to its component number; the numbering carries no order.
  """
  let of: Array[USize]
  var count: USize = 0

  new create(nodes: _Nodes) =>
    let n = nodes.packages.size()
    let unset = USize.max_value()
    let index = Array[USize].init(unset, n)
    let low = Array[USize].init(unset, n)
    let on_stack = Array[Bool].init(false, n)
    of = Array[USize].init(unset, n)
    var next_index: USize = 0
    let stack = Array[USize]
    let frames = Array[(USize, USize)]
    for start in Range(0, n) do
      try
        if index(start)? != unset then continue end
        index(start)? = next_index
        low(start)? = next_index
        next_index = next_index + 1
        stack.push(start)
        on_stack(start)? = true
        frames.push((start, 0))
        while frames.size() > 0 do
          (let v, let i) = frames(frames.size() - 1)?
          let out = nodes.out(v)?
          if i < out.size() then
            let w = out(i)?
            frames(frames.size() - 1)? = (v, i + 1)
            if index(w)? == unset then
              index(w)? = next_index
              low(w)? = next_index
              next_index = next_index + 1
              stack.push(w)
              on_stack(w)? = true
              frames.push((w, 0))
            elseif on_stack(w)? then
              low(v)? = low(v)?.min(index(w)?)
            end
          else
            frames.pop()?
            if low(v)? == index(v)? then
              var member = stack.pop()?
              on_stack(member)? = false
              of(member)? = count
              while member != v do
                member = stack.pop()?
                on_stack(member)? = false
                of(member)? = count
              end
              count = count + 1
            end
            if frames.size() > 0 then
              (let u, _) = frames(frames.size() - 1)?
              low(u)? = low(u)?.min(low(v)?)
            end
          end
        end
      else
        _Unreachable()
      end
    end

primitive _Kahn
  """
  The components in canonical order: repeatedly the ready component
  whose lowest node index is smallest, where a component is ready once
  every component it has an edge to is placed. Returns component numbers
  in placement order.
  """
  fun apply(nodes: _Nodes, of: Array[USize], count: USize): Array[USize] =>
    let lowest = Array[USize].init(USize.max_value(), count)
    let deps = Array[Set[USize]]
    for c in Range(0, count) do deps.push(Set[USize]) end
    try
      for v in Range(0, nodes.packages.size()) do
        let c = of(v)?
        lowest(c)? = lowest(c)?.min(v)
        for w in nodes.out(v)?.values() do
          let d = of(w)?
          if d != c then deps(c)?.set(d) end
        end
      end
    else
      _Unreachable()
    end
    let placed = Array[Bool].init(false, count)
    let order = Array[USize]
    while order.size() < count do
      var best: (USize | None) = None
      for c in Range(0, count) do
        try
          if placed(c)? then continue end
          var ready = true
          for d in deps(c)?.values() do
            if not placed(d)? then ready = false; break end
          end
          if not ready then continue end
          match best
          | let b: USize => if lowest(c)? < lowest(b)? then best = c end
          | None => best = c
          end
        else
          _Unreachable()
        end
      end
      match best
      | let c: USize =>
        try placed(c)? = true else _Unreachable() end
        order.push(c)
      | None => _Unreachable()  // components form a DAG
      end
    end
    order

primitive _Needs
  """
  Each placed group's closure of dependencies as group positions,
  ascending. A group's dependencies are placed before it, so each
  closure is its direct dependencies' closures plus themselves.
  """
  fun apply(nodes: _Nodes, of: Array[USize], order: Array[USize])
    : Array[Array[USize] val]
  =>
    let position = Array[USize].init(0, order.size())
    try
      for (pos, c) in order.pairs() do position(c)? = pos end
    else
      _Unreachable()
    end
    let direct = Array[Set[USize]]
    for g in Range(0, order.size()) do direct.push(Set[USize]) end
    try
      for v in Range(0, nodes.packages.size()) do
        let g = position(of(v)?)?
        for w in nodes.out(v)?.values() do
          let d = position(of(w)?)?
          if d != g then direct(g)?.set(d) end
        end
      end
    else
      _Unreachable()
    end
    let closures = Array[Array[USize] val]
    for g in Range(0, order.size()) do
      let all = Set[USize]
      try
        for d in direct(g)?.values() do
          all.set(d)
          for dd in closures(d)?.values() do all.set(dd) end
        end
      else
        _Unreachable()
      end
      let sorted = Array[USize]
      for d in all.values() do sorted.push(d) end
      sort.MergeSort[USize](sorted)
      let frozen = recover iso Array[USize] end
      for d in sorted.values() do frozen.push(d) end
      closures.push(consume frozen)
    end
    closures
