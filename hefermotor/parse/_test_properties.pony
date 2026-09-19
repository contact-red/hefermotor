use "pony_check"
use "pony_test"
use source = "../source"

primitive \nodoc\ _PropertyTests is TestList
  fun tag tests(test: PonyTest) =>
    test(_TestSeedsAreClean)
    test(Property1UnitTest[_UseCase](_UseSectionFaults))
    test(_TestUseSectionExamples)
    test(Property1UnitTest[_ByteEdit](_ByteMutantsAreGraceful))
    test(Property1UnitTest[_TokenEdit](_TokenEditsAreLocal))
    test(_TestTokenEditRows)

class \nodoc\ iso _TestSeedsAreClean is UnitTest
  fun name(): String => "parse/properties: the seeds parse clean"

  fun apply(h: TestHelper) =>
    """
    Each seed reprints, records nothing and holds every invariant,
    and each has the entities and members its text shows, so that the
    properties mutate something the parser accepts.
    """
    let entities: Array[USize] = [7; 2; 2; 2]
    let members: Array[USize] = [7; 11; 3; 8]
    for (i, seed) in _Seeds().pairs() do
      let tree = _ParseText(seed)
      _Clean(h, tree, seed)
      try
        h.assert_eq[USize](entities(i)?, _Counts.entities(tree),
          "entities of seed " + i.string())
        h.assert_eq[USize](members(i)?, _Counts.members(tree),
          "members of seed " + i.string())
      else
        _Unreachable()
      end
    end

primitive \nodoc\ _Counts
  """
  What the locality property counts: entity declarations, and the
  fields and methods of every member list in the file, an entity's or
  an object literal's alike, so that a member moving between lists
  leaves the count unchanged.
  """
  fun entities(tree: SyntaxTree val): USize =>
    _Find.count(tree, NdClassDef)

  fun members(tree: SyntaxTree val): USize =>
    _Find.count(tree, NdField) + _Find.count(tree, NdMethod)

  fun members_within(node: Node): USize =>
    var n: USize = 0
    for child in node.children() do
      match child.kind()
      | NdField | NdMethod => n = n + 1
      end
      if not child.is_leaf() then n = n + members_within(child) end
    end
    n

primitive \nodoc\ _EntryPointsAgree
  """
  Asserts the two entry points' declarations are equal element by
  element; on a size mismatch, compares the shorter prefix.
  """
  fun apply(h: PropertyHelper, section: Array[UseDecl] val,
    whole: Array[UseDecl] val, label: String)
  =>
    h.assert_eq[USize](section.size(), whole.size(), label + ": uses")
    var i: USize = 0
    while (i < section.size()) and (i < whole.size()) do
      try
        h.assert_true(section(i)? == whole(i)?, label + ": use " + i.string())
      else
        _Unreachable()
      end
      i = i + 1
    end

class \nodoc\ val _UseCase
  """
  A generated use section with one fault, and what the parser must
  give for it: the commands that survive, as locator, alias and
  whether a guard follows, and where the one diagnostic starts.
  """
  let src: String val
  let survivors: Array[_Survivor] val
  let first: USize
  let label: String val

  new val create(src': String val, survivors': Array[_Survivor] val,
    first': USize, label': String val)
  =>
    src = src'
    survivors = survivors'
    first = first'
    label = label'

  fun string(): String iso^ =>
    (label + ": " + src).clone()

class \nodoc\ val _Survivor
  """
  What one surviving command must give: its decoded locator, its
  alias, and whether it has a guard.
  """
  let locator: String val
  let alias: (String val | None)
  let guarded: Bool

  new val create(locator': String val, alias': (String val | None),
    guarded': Bool)
  =>
    locator = locator'
    alias = alias'
    guarded = guarded'

class \nodoc\ val _UseLine
  """
  One well-formed command as text, with its decoded locator, its alias,
  which guard form it carries, and where its locator literal sits in
  the line: its offset and its width.
  """
  let text: String val
  let locator: String val
  let alias: (String val | None)
  let guard: USize
    """
    0 for no guard, 1 for an identifier, 2 for a parenthesised
    expression.
    """
  let literal_at: USize
  let literal_size: USize

  new val create(text': String val, locator': String val,
    alias': (String val | None), guard': USize, literal_at': USize,
    literal_size': USize)
  =>
    text = text'
    locator = locator'
    alias = alias'
    guard = guard'
    literal_at = literal_at'
    literal_size = literal_size'

  fun survivor(guarded: Bool = true): _Survivor =>
    _Survivor(locator, alias, guarded and (guard > 0))

primitive \nodoc\ _UseLines
  """
  The command forms the generator draws from: a plain, an escaped and
  a triple-quoted locator, with or without an alias, with a guard
  that is an identifier or a parenthesised expression or none.
  """
  fun apply(form: USize, i: USize): _UseLine =>
    let name: String val = "p" + i.string()
    (let literal: String val, let locator: String val) =
      match form % 3
      | 0 => ("\"" + name + "\"", name)
      | 1 => ("\"" + name + "\\t\\\"q\\\"\"", name + "\t\"q\"")
      else
        ("\"\"\"" + name + "/x\"\"\"", name + "/x")
      end
    let alias: (String val | None) =
      if ((form / 3) % 2) == 1 then "a" + i.string() else None end
    let head: String val =
      match alias
      | let a: String val => "use " + a + " = "
      | None => "use "
      end
    let guard = (form / 6) % 3
    let tail: String val =
      match guard
      | 0 => ""
      | 1 => " if linux"
      else
        " if (windows or osx)"
      end
    _UseLine(head + literal + tail, locator, alias, guard, head.size(),
      literal.size())

primitive \nodoc\ _UseCases
  """
  Builds the case from a fault kind, the section's lines, the line the
  fault lands on, and whether the entity keyword follows the last line
  with no separator, which it does only after a literal or a `)`,
  since after an identifier it would fuse into it.
  """
  fun apply(lines: Array[_UseLine] val, fault: USize, k: USize,
    flush: Bool): _UseCase
  =>
    let out = recover iso String end
    let survivors = recover iso Array[_Survivor] end
    var first: USize = 0
    // A report at the next significant token after this offset,
    // resolved once the source is whole.
    var first_after: (USize | None) = None
    var label: String val = ""
    var ends_with_entity = true
    var last_guard: USize = 0
    for (i, line) in lines.pairs() do
      let at = out.size()
      last_guard = line.guard
      match fault
      | 0 if i == k =>
        // A junk line before k: every command survives; the junk is
        // reported first. The junk starts no guard continuation.
        label = "junk before"
        first = at
        out.append(_junk(k))
        out.append("\n")
        out.append(line.text)
        survivors.push(line.survivor())
      | 1 if i == k =>
        // k's specifier deleted: k is dropped; the report is at the
        // next significant token after `use` and the alias: k's guard,
        // or the next line's first token.
        label = "specifier deleted"
        let head = line.text.trim(0, line.literal_at)
        let tail = line.text.trim(line.literal_at + line.literal_size)
        out.append(head)
        first_after = out.size()
        out.append(tail.trim(1))
      | 2 if i == k =>
        // k's alias without `=`: k is dropped; the report is at the
        // token after `x`, the literal or the line's own alias.
        label = "alias without ="
        out.append("use x ")
        first = out.size()
        out.append(line.text.trim("use ".size()))
      | 3 if i == k =>
        // k's guard cut by the entity keyword: k survives with no
        // guard, the section ends, and the report is at the keyword.
        label = "guard cut"
        out.append(line.text.trim(0, line.literal_at + line.literal_size))
        out.append(" if\n")
        survivors.push(line.survivor(false))
        first = out.size()
        out.append("class C\n")
        ends_with_entity = false
        break
      | 4 if i == k =>
        // A `use` alone on a line before k: it is dropped, k survives,
        // and the report is at k's `use`.
        label = "use alone"
        out.append("use\n")
        first = out.size()
        out.append(line.text)
        survivors.push(line.survivor())
      | 5 if i == (lines.size() - 1) =>
        // The last line's quote unterminated: that command is dropped
        // with the lexer's record at the quote, and the section ends
        // at the end of the file with no entity.
        label = "last quote unterminated"
        out.append(line.text.trim(0, line.literal_at))
        first = out.size()
        out.append(line.text.trim(line.literal_at,
          (line.literal_at + line.literal_size) - 1))
        ends_with_entity = false
        break
      else
        out.append(line.text)
        survivors.push(line.survivor())
      end
      if i < (lines.size() - 1) then out.append("\n") end
    end
    if ends_with_entity then
      if (not flush) or (last_guard == 1) then out.append("\n") end
      out.append("class C\n")
    end
    let src: String val = consume out
    match first_after
    | let from: USize =>
      var at = from
      while (at < src.size()) and
        (try _is_space(src(at)?) else false end)
      do
        at = at + 1
      end
      first = at
    end
    _UseCase(src, consume survivors, first, label)

  fun _junk(k: USize): String val =>
    """
    A junk line of a shape that starts no expression continuation: an
    identifier, an integer, a string or a closer, by `k`.
    """
    match k % 4
    | 0 => "junk"
    | 1 => "42"
    | 2 => "\"junk\""
    else
      ")"
    end

  fun _is_space(c: U8): Bool =>
    (c == ' ') or (c == '\n') or (c == '\t')

class \nodoc\ iso _UseSectionFaults is Property1[_UseCase]
  """
  A well-formed use section of one to five commands with one fault
  from a closed set gives the commands the fault leaves, with their
  aliases and guards, and one diagnostic where the fault is; the two
  entry points give the same declarations, and `TreeCheck` finds
  nothing.
  """
  fun name(): String => "parse/properties: use section faults"

  fun params(): PropertyParams =>
    PropertyParams(where num_samples' = 300)

  fun gen(): Generator[_UseCase] =>
    Generators.zip4[Array[USize] val, USize, USize, Bool](
      _Sized[USize](Generators.usize(0, 17), Generators.usize(1, 5)),
      Generators.usize(0, 5), Generators.usize(0, 4), Generators.bool())
      .map[_UseCase]({(drawn: (Array[USize] val, USize, USize, Bool)) =>
        (let forms, let fault, let k, let flush) = drawn
        let lines = recover iso Array[_UseLine] end
        for (i, form) in forms.pairs() do lines.push(_UseLines(form, i)) end
        _UseCases(consume lines, fault, k % forms.size(), flush) })

  fun property(sample: _UseCase, h: PropertyHelper) =>
    let file = _TestFile(sample.src)
    let section = Parse.uses_only(file)
    let parsed = Parse(file)
    h.assert_eq[USize](sample.survivors.size(), section.size(),
      sample.string() + ": survivors")
    var i: USize = 0
    while (i < section.size()) and (i < sample.survivors.size()) do
      try
        let want = sample.survivors(i)?
        let got = section(i)?
        h.assert_eq[String](want.locator, got.locator,
          sample.string() + ": locator " + i.string())
        h.assert_true(_same_alias(want.alias, got.alias),
          sample.string() + ": alias " + i.string())
        h.assert_eq[Bool](want.guarded, not (got.guard is None),
          sample.string() + ": guard " + i.string())
      else
        _Unreachable()
      end
      i = i + 1
    end
    _EntryPointsAgree(h, section, parsed.uses(), sample.string())
    h.assert_eq[USize](1, parsed.diagnostics.size(),
      sample.string() + ": diagnostics")
    try
      h.assert_eq[USize](sample.first, _Start(parsed.diagnostics(0)?),
        sample.string() + ": first diagnostic")
    end
    for v in TreeCheck(parsed.tree, parsed.diagnostics).values() do
      h.fail(sample.string() + ": " + v.string())
    end

  fun _same_alias(want: (String val | None), got: (String | None)): Bool =>
    match (want, got)
    | (None, None) => true
    | (let a: String val, let b: String) => a == b
    else
      false
    end

class \nodoc\ iso _TestUseSectionExamples is UnitTest
  fun name(): String => "parse/properties: use section examples"

  fun apply(h: TestHelper) =>
    """
    Two shapes: junk between commands keeps both (`use "a"`, `junk`,
    `use "b"`, `class C` on their lines give `["a"; "b"]`), and an
    unterminated quote on the last line drops that command with the
    lexer's record at the quote.
    """
    h.assert_array_eq[String](["a"; "b"],
      _Uses.locators("use \"a\"\njunk\nuse \"b\"\nclass C\n"))
    let src: String val = "use \"a\"\nuse \"b\n"
    h.assert_array_eq[String](["a"], _Uses.locators(src))
    _Exactly(h, src, [("parse/lex", 12, "Literal doesn't terminate")],
      "unterminated last line")

class \nodoc\ val _ByteEdit
  """
  One byte-level edit of a seed at a byte offset `at` within it: a
  truncation, a window of four bytes deleted, or one of the alphabet's
  strings inserted.
  """
  let seed: USize
  let kind: USize
  let at: USize
  let insert: USize

  new val create(seed': USize, kind': USize, at': USize, insert': USize) =>
    seed = seed'
    kind = kind'
    at = at'
    insert = insert'

  fun apply(): String val =>
    let src = try _Seeds()(seed)? else _Unreachable(); "" end
    match kind % 3
    | 0 => src.trim(0, at)
    | 1 => src.trim(0, at) + src.trim(at + 4)
    else
      src.trim(0, at) + inserted() + src.trim(at)
    end

  fun inserted(): String val =>
    try _Alphabet()(insert % 4)? else _Unreachable(); "" end

  fun string(): String iso^ =>
    ("seed " + seed.string() + " " +
      (match kind % 3
       | 0 => "truncate"
       | 1 => "delete"
       else
         "insert " + inserted()
       end) +
      " at " + at.string()).clone()

primitive \nodoc\ _Alphabet
  """
  What a byte-level insertion writes: each opens something the lexer or
  the parser must then close or refuse.
  """
  fun apply(): Array[String val] val =>
    ["\""; "("; "end"; "/*"]

class \nodoc\ iso _ByteMutantsAreGraceful is Property1[_ByteEdit]
  """
  Every byte-level mutant of every seed parses to a tree that holds
  every invariant, and its two entry points agree on the use section.
  """
  fun name(): String => "parse/properties: byte-level mutants are graceful"

  fun params(): PropertyParams =>
    PropertyParams(where num_samples' = 400)

  fun gen(): Generator[_ByteEdit] =>
    // The offset is drawn within the chosen seed, so every cut point
    // is drawn as often as any other.
    Generators.zip3[USize, USize, USize](Generators.usize(0, 3),
      Generators.usize(0, 2), Generators.usize(0, 3))
      .flat_map[_ByteEdit]({(drawn: (USize, USize, USize)) =>
        (let seed, let kind, let insert) = drawn
        let size = try _Seeds()(seed)?.size() else _Unreachable(); 0 end
        Generators.usize(0, size).map[_ByteEdit]({(at: USize) =>
          _ByteEdit(seed, kind, at, insert) }) })

  fun property(sample: _ByteEdit, h: PropertyHelper) =>
    let src = sample()
    let file = _TestFile(src)
    let parsed = Parse(file)
    for v in TreeCheck(parsed.tree, parsed.diagnostics).values() do
      h.fail(sample.string() + ": " + v.string())
    end
    _EntryPointsAgree(h, Parse.uses_only(file), parsed.uses(),
      sample.string())

class \nodoc\ val _SeedToken
  """
  One significant token of a seed with what `expected_change` reads
  off it: its offset and width; whether it is an entity keyword, the
  first entity's, and the members within that entity; whether it is a
  member keyword, and the locals within that member; the locals of
  its member at or after it; the fields at or after it of the
  innermost object literal it sits in; and, inside a field, the run of
  `var` and `let` fields after that field, which its value can take.
  """
  let offset: USize
  let width: USize
  let entity_keyword: Bool
  let first_entity: Bool
  let members_within: USize
  let member_keyword: Bool
  let locals_within: USize
  let locals_after: USize
  let fields_after: USize
  let fields_run: USize

  new val create(offset': USize, width': USize, entity_keyword': Bool,
    first_entity': Bool, members_within': USize, member_keyword': Bool,
    locals_within': USize, locals_after': USize, fields_after': USize,
    fields_run': USize)
  =>
    offset = offset'
    width = width'
    entity_keyword = entity_keyword'
    first_entity = first_entity'
    members_within = members_within'
    member_keyword = member_keyword'
    locals_within = locals_within'
    locals_after = locals_after'
    fields_after = fields_after'
    fields_run = fields_run'

primitive \nodoc\ _SeedTokens
  """
  The significant tokens of a seed's tree, `TkEof` left out, each with
  its row: the first leaf of an `NdClassDef` is an entity keyword, the
  first leaf of an `NdField` or `NdMethod` a member keyword. Locals
  are counted as `NdLocal` nodes inside a member's subtree outside a
  nested member list, since those are what become fields when the
  member's parse breaks; a token's locals after it include a local
  starting at it. A member keyword inside an object literal carries
  the literal's fields at or after it, since a token inserted before
  it can end the literal there.
  """
  fun apply(tree: SyntaxTree val): Array[_SeedToken] val =>
    let out = recover iso Array[_SeedToken] end
    var first_entity_seen = false
    for node in tree.nodes() do
      match node.kind()
      | NdClassDef | NdField | NdMethod =>
        let keyword =
          try
            _first_leaf(node)?
          else
            _Unreachable(); node
          end
        let entity = node.kind() is NdClassDef
        let first = entity and (not first_entity_seen)
        if entity then first_entity_seen = true end
        let path = tree.path_to(keyword.offset())
        out.push(_SeedToken(keyword.offset(), keyword.width(), entity,
          first, if entity then _Counts.members_within(node) else 0 end,
          not entity, if entity then 0 else _locals_within(node, 0) end,
          0, if entity then 0 else _fields_after(path, keyword.offset()) end,
          0))
      else
        if node.is_leaf() and (not node.is_trivia()) and
          (not (node.kind() is TkEof))
        then
          let path = tree.path_to(node.offset())
          if not _is_keyword_of(path, node) then
            out.push(_SeedToken(node.offset(), node.width(), false, false,
              0, false, 0, _locals_after(path, node.offset()),
              _fields_after(path, node.offset()), _fields_run(path)))
          end
        end
      end
    end
    consume out

  fun _first_leaf(node: Node): Node ? =>
    for child in node.children() do
      if child.is_leaf() and (not child.is_trivia()) then return child end
    end
    error

  fun _is_keyword_of(path: Array[Node] val, leaf: Node): Bool =>
    """
    Whether the leaf is the first leaf of an entity or member node,
    listed once under that node.
    """
    match leaf.kind()
    | TkType | TkInterface | TkTrait | TkPrimitive | TkStruct | TkClass
    | TkActor | TkFun | TkBe | TkNew =>
      true
    | TkVar | TkLet | TkEmbed =>
      try path(path.size() - 2)?.kind() is NdField else false end
    else
      false
    end

  fun _locals_after(path: Array[Node] val, offset: USize): USize =>
    """
    The locals at or after `offset` in the innermost member on `path`,
    or none when the leaf is in no member.
    """
    var i = path.size()
    while i > 0 do
      i = i - 1
      try
        let node = path(i)?
        match node.kind()
        | NdField | NdMethod => return _locals_within(node, offset)
        end
      else
        _Unreachable()
      end
    end
    0

  fun _fields_run(path: Array[Node] val): USize =>
    """
    Inside a field, the `var` and `let` fields that follow it in its
    member list up to the first `embed` or method: a value cut short
    reads each of them as a local declaration; none outside a field.
    """
    var i = path.size()
    while i > 1 do
      i = i - 1
      try
        let node = path(i)?
        match node.kind()
        | NdMethod => return 0
        | NdField =>
          var n: USize = 0
          var after = false
          for sibling in path(i - 1)?.children() do
            if sibling == node then
              after = true
            elseif after and (not sibling.is_trivia()) then
              match sibling.first_token()
              | TkVar | TkLet => n = n + 1
              else
                return n
              end
            end
          end
          return n
        end
      else
        _Unreachable()
      end
    end
    0

  fun _fields_after(path: Array[Node] val, offset: USize): USize =>
    """
    The fields at or after `offset` in the member list of the
    innermost object literal on `path`, which become locals when the
    literal's parse breaks there; none outside an object literal.
    """
    var i = path.size()
    while i > 0 do
      i = i - 1
      try
        let node = path(i)?
        if node.kind() is NdObject then
          var n: USize = 0
          match node.child(NdMembers)
          | let members: Node =>
            for member in members.children() do
              if (member.kind() is NdField) and (member.offset() >= offset)
              then
                n = n + 1
              end
            end
          end
          return n
        end
      else
        _Unreachable()
      end
    end
    0

  fun _locals_within(node: Node, from: USize): USize =>
    var n: USize = 0
    for child in node.children() do
      match child.kind()
      | NdLocal => if child.offset() >= from then n = n + 1 end
      | NdMembers => continue
      end
      if not child.is_leaf() then n = n + _locals_within(child, from) end
    end
    n

class \nodoc\ val _TokenEdit
  """
  One token-level edit of a seed, over the seed's tokens: delete
  token `slot`, duplicate it, or insert one of the named set before it
  (or at the end, when `slot` is the token count), with the outcome
  the table gives it.
  """
  let seed: USize
  let tokens: Array[_SeedToken] val
  let op: USize
  let slot: USize
  let insert: USize

  new val create(seed': USize, tokens': Array[_SeedToken] val, op': USize,
    slot': USize, insert': USize)
  =>
    seed = seed'
    tokens = tokens'
    op = op'
    slot = slot'
    insert = insert'

  fun source_text(): String val =>
    try _Seeds()(seed)? else _Unreachable(); "" end

  fun inserted(): String val =>
    try _Inserts()(insert % _Inserts().size())? else _Unreachable(); "" end

  fun apply(): String val =>
    let src = source_text()
    match op % 3
    | 0 =>
      let t = _token()
      src.trim(0, t.offset) + " " + src.trim(t.offset + t.width)
    | 1 =>
      let t = _token()
      src.trim(0, t.offset) + src.trim(t.offset, t.offset + t.width) + " " +
        src.trim(t.offset)
    else
      let at =
        if slot == tokens.size() then src.size() else _token().offset end
      src.trim(0, at) + " " + inserted() + " " + src.trim(at)
    end

  fun expected_change(): (ISize, ISize, ISize) =>
    """
    The outcome table's row for this edit, and this method is the
    table: the change in the entity count, and the least and the most
    the member count may change by. A deleted or duplicated entity
    keyword's row is exact, and so is a duplicated member keyword's; a
    deleted member keyword removes the member and turns its locals
    into fields, except those an earlier local's value takes as a
    field's value. Any other token deleted or duplicated inside a
    member, or a token inserted there, may break that member's parse
    at any later point, from where its locals become fields of the
    list; may end an object literal it sits in, from where the
    literal's fields become locals; and inside a field's value may
    leave the value to read the `var` and `let` fields after it as
    local declarations. So its row runs from minus those fields to
    plus those locals, and an insertion's entity delta is exact.
    Outside a member the range is zero.
    """
    match op % 3
    | 0 =>
      let t = _token()
      if t.entity_keyword then
        let m = if t.first_entity then -(t.members_within.isize()) else 0 end
        (-1, m, m)
      elseif t.member_keyword then
        (0, -1, t.locals_within.isize() - 1)
      else
        (0, _least(t), t.locals_after.isize())
      end
    | 1 =>
      let t = _token()
      if t.entity_keyword then (1, 0, 0)
      elseif t.member_keyword then (0, 1, 1)
      else (0, _least(t), t.locals_after.isize())
      end
    else
      (let least, let most) =
        if slot == tokens.size() then (0, 0)
        else
          let t = _token()
          (_least(t), t.locals_after.isize())
        end
      match inserted()
      | "end" | "use" | ")" | "then" | ";" => (0, least, most)
      else
        (1, least, most)
      end
    end

  fun _least(t: _SeedToken): ISize =>
    -(t.fields_after.isize()) - t.fields_run.isize()

  fun _token(): _SeedToken =>
    try tokens(slot)? else
      _Unreachable()
      _SeedToken(0, 0, false, false, 0, false, 0, 0, 0, 0)
    end

  fun string(): String iso^ =>
    ("seed " + seed.string() + " " +
      (match op % 3
       | 0 => "delete"
       | 1 => "duplicate"
       else
         "insert " + inserted()
       end) +
      " at token " + slot.string()).clone()

primitive \nodoc\ _Inserts
  """
  What a token-level insertion writes: the tokens that end a sequence
  or a list, and every entity keyword.
  """
  fun apply(): Array[String val] val =>
    [ "end"; "use"; ")"; "then"; ";"; "class"; "actor"; "primitive"
      "struct"; "trait"; "interface"; "type" ]

primitive \nodoc\ _SeedTokenTables
  """
  Each seed's tokens, computed once for a generator.
  """
  fun apply(): Array[Array[_SeedToken] val] val =>
    let out = recover iso Array[Array[_SeedToken] val] end
    for seed in _Seeds().values() do
      out.push(_SeedTokens(Parse(_TestFile(seed)).tree))
    end
    consume out

class \nodoc\ iso _TokenEditsAreLocal is Property1[_TokenEdit]
  """
  A token-level edit of a seed changes the entity count by what the
  outcome table says for the token it touches and the member count
  within the table's range, and the mutant holds every invariant.
  """
  fun name(): String => "parse/properties: token edits are local"

  fun params(): PropertyParams =>
    PropertyParams(where num_samples' = 400)

  fun gen(): Generator[_TokenEdit] =>
    // The slot is drawn within the chosen seed's tokens, so every edit
    // is drawn as often as any other of its kind.
    let tables = _SeedTokenTables()
    Generators.zip3[USize, USize, USize](Generators.usize(0, 3),
      Generators.usize(0, 2), Generators.usize(0, 11))
      .flat_map[_TokenEdit]({(drawn: (USize, USize, USize)) =>
        (let seed, let op, let insert) = drawn
        let tokens: Array[_SeedToken] val =
          try tables(seed)? else
            _Unreachable(); recover val Array[_SeedToken] end
          end
        let last =
          if (op % 3) == 2 then tokens.size() else tokens.size() - 1 end
        Generators.usize(0, last).map[_TokenEdit]({(slot: USize) =>
          _TokenEdit(seed, tokens, op, slot, insert) }) })

  fun property(sample: _TokenEdit, h: PropertyHelper) =>
    _TokenEditCheck(h, sample)

interface \nodoc\ val _Asserts
  """
  The assertions a token-edit check makes, which `PropertyHelper` and
  `TestHelper` both provide.
  """
  fun fail(msg: String = "Test failed")
  fun assert_true(actual: Bool, msg: String val = "", loc: SourceLoc = __loc)
    : Bool
  fun assert_eq[A: (Equatable[A] #read & Stringable #read)](expect: A,
    actual: A, msg: String val = "", loc: SourceLoc = __loc): Bool

primitive \nodoc\ _TokenEditCheck
  """
  Checks one token edit against its row, naming the edit and printing
  the mutant only when something fails.
  """
  fun apply(h: _Asserts, sample: _TokenEdit) =>
    let base = Parse(_TestFile(sample.source_text()))
    let text = sample()
    let mutant = Parse(_TestFile(text))
    for v in TreeCheck(mutant.tree, mutant.diagnostics).values() do
      h.fail(sample.string() + ": " + v.string() + "\n" + text)
    end
    (let d_entities, let least, let most) = sample.expected_change()
    let entities = _Counts.entities(base.tree).isize() + d_entities
    let got_entities = _Counts.entities(mutant.tree).isize()
    if got_entities != entities then
      h.assert_eq[ISize](entities, got_entities,
        sample.string() + ": entities of\n" + text)
    end
    let members = _Counts.members(mutant.tree).isize() -
      _Counts.members(base.tree).isize()
    if (members < least) or (members > most) then
      h.fail(sample.string() + ": members of\n" + text + "\n" +
        members.string() + " not in " + least.string() + ".." +
        most.string())
    end

class \nodoc\ iso _TestTokenEditRows is UnitTest
  fun name(): String => "parse/properties: each row of the outcome table"

  fun apply(h: TestHelper) =>
    """
    On the members seed, one edit per row of the outcome table and
    one per mechanism the ranges bound, each with the exact delta the
    parser gives: an entity keyword deleted (not the first), the first
    entity's keyword deleted, an entity keyword duplicated and one
    inserted, a member keyword deleted (`_count`'s `var`, −1, and
    `hidden`'s `fun`, whose `let s` becomes a field, 0) and one
    duplicated, a local's keyword deleted and duplicated, a stray
    `end` inserted before a field of the entity and before the object
    literal's field (which ends the literal: −1), `end` inserted past
    the last token, `object` deleted (its field becomes a local: −1),
    `hidden`'s `=>` deleted (its local becomes a field: +1), and the
    `0` of `_count`'s value deleted (the value reads `let _step` as a
    local: −1).
    """
    let src = _Seeds.members()
    let tokens = _SeedTokens(Parse(_TestFile(src)).tree)
    let at = {(text: String val, nth: USize = 0): USize =>
      var seen: USize = 0
      for (i, t) in tokens.pairs() do
        if src.trim(t.offset, t.offset + t.width) == text then
          if seen == nth then return i end
          seen = seen + 1
        end
      end
      h.fail("no token " + text)
      0
    }
    let interface_keyword = at("interface")
    let class_keyword = at("class")
    let first_var = at("var")
    let hidden_fun = at("fun", 3)
    let local_let = at("let", 2)
    let object_let = at("let", 1)
    let object_keyword = at("object")
    let hidden_arrow = at("=>", 4)
    let count_zero = at("0")
    h.assert_true(interface_keyword > class_keyword, "two entities")
    _exact(h, tokens, 0, interface_keyword, 0, -1, 0)
    _exact(h, tokens, 0, class_keyword, 0, -1, -10)
    _exact(h, tokens, 1, class_keyword, 0, 1, 0)
    _exact(h, tokens, 2, first_var, 5, 1, 0)
    _exact(h, tokens, 0, first_var, 0, 0, -1)
    _exact(h, tokens, 0, hidden_fun, 0, 0, 0)
    _exact(h, tokens, 1, first_var, 0, 0, 1)
    _exact(h, tokens, 0, local_let, 0, 0, 0)
    _exact(h, tokens, 1, local_let, 0, 0, 0)
    _exact(h, tokens, 2, first_var, 0, 0, 0)
    _exact(h, tokens, 2, object_let, 0, 0, -1)
    _exact(h, tokens, 2, tokens.size(), 0, 0, 0)
    _exact(h, tokens, 0, object_keyword, 0, 0, -1)
    _exact(h, tokens, 0, hidden_arrow, 0, 0, 1)
    _exact(h, tokens, 0, count_zero, 0, 0, -1)

  fun _exact(h: TestHelper, tokens: Array[_SeedToken] val, op: USize,
    slot: USize, insert: USize, d_entities: ISize, d_members: ISize)
  =>
    """
    The edit passes its row, and its deltas are exactly these.
    """
    let edit = _TokenEdit(1, tokens, op, slot, insert)
    _TokenEditCheck(h, edit)
    let base = Parse(_TestFile(edit.source_text())).tree
    let mutant = Parse(_TestFile(edit())).tree
    h.assert_eq[ISize](d_entities, _Counts.entities(mutant).isize() -
      _Counts.entities(base).isize(), edit.string() + ": entities")
    h.assert_eq[ISize](d_members, _Counts.members(mutant).isize() -
      _Counts.members(base).isize(), edit.string() + ": members")
