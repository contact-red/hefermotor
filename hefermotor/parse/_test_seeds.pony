primitive \nodoc\ _Seeds
  """
  Four sources the properties mutate, each well formed and each
  reaching a different part of the grammar: a use section and
  entities of every kind; fields, methods and an object literal;
  control structures and lambdas; type grammar and FFI.
  """
  fun apply(): Array[String val] val =>
    [ sections(); members(); control(); types() ]

  fun sections(): String val =>
    "\"\"\"\nA package docstring.\n\"\"\"\n" +
    "use \"collections\"\n" +
    "use c = \"collections/persistent\"\n" +
    "use \"time\" if linux\n" +
    "use @printf[I32](fmt: Pointer[U8] tag, ...)\n" +
    "use \"lib:z\" if (windows or osx)\n" +
    "\n" +
    "type Pair is (U8, U8)\n" +
    "\n" +
    "interface Named\n" +
    "  fun name(): String\n" +
    "\n" +
    "trait Greeter is Named\n" +
    "  fun greet(): String => \"hello \" + name()\n" +
    "\n" +
    "primitive Unit\n" +
    "\n" +
    "struct \\packed\\ Point\n" +
    "  var x: F64 = 0\n" +
    "  var y: F64 = 0\n" +
    "\n" +
    "class val Box[A: Any val]\n" +
    "  let value: A\n" +
    "  new val create(value': A) => value = value'\n" +
    "\n" +
    "actor Main\n" +
    "  new create(env: Env) =>\n" +
    "    env.out.print(Box[U8](1).value.string())\n"

  fun members(): String val =>
    "class Counter\n" +
    "  \"\"\"A counter.\"\"\"\n" +
    "  var _count: U64 = 0\n" +
    "  let _step: U64\n" +
    "  embed _log: Array[String] = Array[String]\n" +
    "\n" +
    "  new create(step: U64 = 1) =>\n" +
    "    _step = step\n" +
    "\n" +
    "  fun ref bump(): U64 =>\n" +
    "    \"\"\"Add a step.\"\"\"\n" +
    "    _count = _count + _step\n" +
    "    _count\n" +
    "\n" +
    "  fun observer(): Observer =>\n" +
    "    object is Observer\n" +
    "      let base: U64 = 3\n" +
    "      fun seen(n: U64): Bool => n > base\n" +
    "    end\n" +
    "\n" +
    "  fun \\nodoc\\ hidden[T: Stringable #read](t: T): String ? =>\n" +
    "    let s = t.string()\n" +
    "    if s.size() == 0 then error end\n" +
    "    s\n" +
    "\n" +
    "  be later(n: U64) =>\n" +
    "    _log.push(n.string())\n" +
    "\n" +
    "interface Observer\n" +
    "  fun seen(n: U64): Bool\n"

  fun control(): String val =>
    "actor Main\n" +
    "  new create(env: Env) =>\n" +
    "    let xs: Array[U8] = [1; 2; 3]\n" +
    "    var total: U64 = 0\n" +
    "    for x in xs.values() do\n" +
    "      total = total + x.u64()\n" +
    "    end\n" +
    "    while total > 10 do total = total - 1 else total = 0 end\n" +
    "    repeat\n" +
    "      total = total + 1\n" +
    "    until total >= 4 end\n" +
    "    let kind = match total\n" +
    "      | 0 => \"none\"\n" +
    "      | let n: U64 if n > 3 => \"many\"\n" +
    "      | if true => \"guarded\"\n" +
    "      else \"some\"\n" +
    "      end\n" +
    "    let f = {(a: U64, b: U64 = 1): U64 => a + b}\n" +
    "    let g = @{(p: Pointer[U8] tag): U8 => 0}\n" +
    "    try\n" +
    "      let y = xs(9)?\n" +
    "      env.out.print(y.string())\n" +
    "    else\n" +
    "      env.out.print(kind + f(total, 2).string())\n" +
    "    then\n" +
    "      None\n" +
    "    end\n" +
    "    with r = Resource do r.open() end\n" +
    "    ifdef debug then env.out.print(\"debug\") end\n" +
    "    let s = recover val String.>append(\"a\") end\n" +
    "    env.out.print(consume s)\n" +
    "    if (total == 1) and not (kind is \"x\") then return end\n" +
    "\n" +
    "class Resource\n" +
    "  fun open(): None => None\n" +
    "  fun dispose(): None => None\n"

  fun types(): String val =>
    "use @strlen[USize](s: Pointer[U8] tag)\n" +
    "\n" +
    "type Reader is {(String): (U8 | None)} val\n" +
    "\n" +
    "class Holder[A: (Stringable #read & Equatable[A]) = String]\n" +
    "  let items: Array[A] iso\n" +
    "  let lookup: Map[String, (A | None)] val\n" +
    "  let pair: (A, this->Array[A] box)\n" +
    "  let cap: Array[A] ref^\n" +
    "\n" +
    "  new iso create(items': Array[A] iso) =>\n" +
    "    items = consume items'\n" +
    "    lookup = recover val Map[String, (A | None)] end\n" +
    "    pair = (items(0)?, items)\n" +
    "    cap = items\n" +
    "\n" +
    "  fun apply(i: USize): A ? => items(i)?\n" +
    "\n" +
    "  fun each(f: {(A)} box, g: Reader) =>\n" +
    "    for x in items.values() do f(x) end\n" +
    "    iftype A <: String then g(\"x\") end\n" +
    "\n" +
    "  fun size(): USize => @strlen(\"abc\".cstring())\n"
