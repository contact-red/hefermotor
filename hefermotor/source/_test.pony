use "pony_test"

actor \nodoc\ Main is TestList
  new create(env: Env) => PonyTest(env, this)
  new make() => None

  fun tag tests(test: PonyTest) =>
    test(_TestFileHashVectors)
    test(_TestBuilderVectors)
    test(_TestBuilderFraming)
    test(_TestHashOrdering)
    test(_TestSourceFileHashesContentOnly)
    test(_TestBuildConfigHost)

class \nodoc\ iso _TestFileHashVectors is UnitTest
  """
  The expected values are SipHash-2-4 of the file's bytes under the
  runtime's fixed key, computed by an independent SipHash implementation,
  so the test fails if the runtime's key or function changes.
  """
  fun name(): String => "source/file hash vectors"

  fun apply(h: TestHelper) =>
    h.assert_eq[String]("985af2ac39b395d9",
      SourceFile("/d", "f", "").hash.hex())
    h.assert_eq[String]("69e72d1c0d7db0da",
      SourceFile("/d", "f", "hello").hash.hex())

class \nodoc\ iso _TestBuilderVectors is UnitTest
  """
  The expected values are SipHash-2-4 of the builder's framing, length
  then bytes per field and eight bytes per hash field, computed by an
  independent SipHash implementation.
  """
  fun name(): String => "source/builder vectors"

  fun apply(h: TestHelper) =>
    h.assert_eq[String]("985af2ac39b395d9", HashBuilder.done().hex())
    h.assert_eq[String]("980dfc98e5fc21f5",
      HashBuilder.>field("ab").>field("c").done().hex())
    h.assert_eq[String]("df36d621415d351d",
      HashBuilder.>field("a").>field("bc").done().hex())
    // An empty field is still a field: eight zero length bytes.
    h.assert_eq[String]("fbe5f1fc9f31af2b",
      HashBuilder.>field("").done().hex())
    h.assert_eq[String]("5ce4149d53c1b423",
      HashBuilder.>field("").>field("a").done().hex())
    let hello = SourceFile("/d", "f", "hello").hash
    h.assert_eq[String]("5b17675d2e969b70",
      HashBuilder.>field("x").>field_hash(hello).done().hex())
    h.assert_eq[String]("b0a7bad28c9f1aa9",
      HashBuilder.>field_hash(hello).>field("x").done().hex())

class \nodoc\ iso _TestBuilderFraming is UnitTest
  fun name(): String => "source/builder framing"

  fun apply(h: TestHelper) =>
    h.assert_ne[ContentHash](
      HashBuilder.>field("ab").>field("c").done(),
      HashBuilder.>field("a").>field("bc").done())
    h.assert_ne[ContentHash](
      HashBuilder.>field("ab").done(),
      HashBuilder.>field("a").>field("b").done())
    // `done` reads the buffer and leaves it, so a builder can be asked
    // twice and appended to after.
    let b = HashBuilder.>field("a")
    h.assert_eq[ContentHash](b.done(), b.done())
    b.field("b")
    h.assert_eq[ContentHash](b.done(),
      HashBuilder.>field("a").>field("b").done())
    let hello = SourceFile("/d", "f", "hello").hash
    h.assert_ne[ContentHash](
      HashBuilder.>field("x").>field_hash(hello).done(),
      HashBuilder.>field_hash(hello).>field("x").done())
    // `field_hash` adds no length prefix, so it differs from the same
    // eight bytes passed through `field`.
    h.assert_ne[ContentHash](
      HashBuilder.>field_hash(hello).done(),
      HashBuilder.>field(hello.bytes()).done())

class \nodoc\ iso _TestHashOrdering is UnitTest
  fun name(): String => "source/hash equality, ordering and rendering"

  fun apply(h: TestHelper) =>
    let a = SourceFile("/d", "f", "a").hash
    let b = SourceFile("/d", "f", "b").hash
    h.assert_ne[ContentHash](a, b)
    h.assert_true((a < b) or (b < a))
    h.assert_false((a < b) and (b < a))
    h.assert_false(a < a)
    h.assert_eq[USize](16, a.hex().size())
    h.assert_eq[USize](8, a.bytes().size())
    // Bytes are least significant first: the hex string reads the other
    // way round.
    let zero = HashBuilder.done()
    try
      h.assert_eq[U8](0xd9, zero.bytes()(0)?)
      h.assert_eq[U8](0x98, zero.bytes()(7)?)
    else
      h.fail("eight bytes expected")
    end
    let small = ContentHash._create(0x1a)
    h.assert_eq[String]("000000000000001a", small.hex())
    h.assert_eq[String]("000000000000001a", small.string())
    // `lt` orders by the 64-bit integer; `eq` compares all 64 bits.
    h.assert_true(ContentHash._create(1) < ContentHash._create(2))
    h.assert_false(ContentHash._create(2) < ContentHash._create(1))
    h.assert_true(ContentHash._create(1) < ContentHash._create(1 << 32))
    h.assert_ne[ContentHash](ContentHash._create(1 << 32),
      ContentHash._create(0))
    h.assert_ne[ContentHash](ContentHash._create(1 << 63),
      ContentHash._create(1 << 31))
    h.assert_ne[ContentHash](ContentHash._create(1), ContentHash._create(0))
    h.assert_eq[USize](0x1a, small.hash())

class \nodoc\ iso _TestSourceFileHashesContentOnly is UnitTest
  fun name(): String => "source/file hash covers content only"

  fun apply(h: TestHelper) =>
    let f = SourceFile("/pkg", "a.pony", "actor Main")
    h.assert_eq[String]("/pkg/a.pony", f.path())
    h.assert_eq[ContentHash](f.hash,
      SourceFile("/elsewhere", "b.pony", "actor Main").hash)
    h.assert_ne[ContentHash](f.hash,
      SourceFile("/pkg", "a.pony", "actor Main ").hash)

class \nodoc\ iso _TestBuildConfigHost is UnitTest
  fun name(): String => "source/build config host"

  fun apply(h: TestHelper) =>
    h.assert_eq[String]("fff39ac8c7d5de97", BuildConfig.host().hash.hex())
