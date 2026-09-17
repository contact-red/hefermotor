class HashBuilder
  """
  Hashes a sequence of fields into one `ContentHash`.

  The hash is SipHash-2-4 under the runtime's fixed key, 64 bits wide on
  every machine. Its input is the fields in order: each field as its
  length in bytes (eight bytes, least significant first) followed by its
  bytes, and each `ContentHash` field as its eight bytes with no length.
  So `("ab", "c")` and `("a", "bc")` hash differently, and an empty field
  still contributes its length.
  """
  embed _buffer: String ref = _buffer.create()

  fun ref field(bytes: ByteSeq): HashBuilder ref =>
    """
    Appends one field: its length, then its bytes.
    """
    _append_u64(bytes.size().u64())
    _buffer.append(bytes)
    this

  fun ref field_hash(h: ContentHash): HashBuilder ref =>
    """
    Appends a hash as its eight bytes.
    """
    _append_u64(h._u64())
    this

  fun done(): ContentHash =>
    """
    The hash of every field appended so far.
    """
    ContentHash._create(_buffer.hash64())

  fun ref _append_u64(v: U64) =>
    var i: U64 = 0
    while i < 8 do
      _buffer.push(((v >> (i * 8)) and 0xFF).u8())
      i = i + 1
    end
