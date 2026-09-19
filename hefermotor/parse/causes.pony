use diag = "../diagnostics"

primitive UnterminatedLiteral
  """
  A string or character literal that reaches the end of the source
  before its closing quote; ponyc's "Literal doesn't terminate".
  """
  fun message(): String => "Literal doesn't terminate"

primitive UnterminatedComment
  """
  A `/* */` comment that reaches the end of the source before its
  closer; ponyc's "Nested comment doesn't terminate".
  """
  fun message(): String => "Nested comment doesn't terminate"

primitive TripleQuoteNotBelowOpener
  """
  A triple-quoted string of more than one line with text after the
  opening quotes on their line; ponyc's "multi-line triple-quoted
  string must be started below the opening triple-quote".
  """
  fun message(): String =>
    "multi-line triple-quoted string must be started below the opening " +
      "triple-quote"

primitive UnknownEscape
  """
  A `\` followed by a character that names no escape, or one the
  literal's kind does not admit: `\'` in a string, `\"` or a unicode
  escape in a character literal.
  """

class val HexDigitsRequired
  """
  A `\x`, `\u` or `\U` escape with fewer hex digits than it takes.
  """
  let required: USize
    """
    The hex digits the escape takes: 2, 4 or 6.
    """

  new val create(required': USize) =>
    required = required'

primitive ExceedsUnicodeRange
  """
  A `\U` escape whose value is above 0x10FFFF.
  """

type EscapeFault is (UnknownEscape | HexDigitsRequired | ExceedsUnicodeRange)
  """
  Why an escape sequence was refused; ponyc's three escape errors.
  """

class val InvalidEscape
  """
  An escape sequence in a string or character literal that the lexer
  refused. The literal keeps its kind and the escape drops out of its
  value, as in ponyc, which reports and carries on. `text` is the
  escape as written, from the `\` to the last character ponyc read;
  the message shows each of its bytes as `LexError` describes.
  """
  let text: String
  let fault: EscapeFault

  new val create(text': String, fault': EscapeFault) =>
    text = text'
    fault = fault'

  fun message(): String =>
    match fault
    | UnknownEscape => "Invalid escape sequence \"" + _Bytes(text) + "\""
    | let h: HexDigitsRequired =>
      "Invalid escape sequence \"" + _Bytes(text) + "\", " +
        h.required.string() + " hex digits required"
    | ExceedsUnicodeRange =>
      "Escape sequence \"" + _Bytes(text) +
        "\" exceeds unicode range (0x10FFFF)"
    end

primitive EmptyCharacterLiteral
  """
  `''`; ponyc's "Empty character literal".
  """
  fun message(): String => "Empty character literal"

primitive DecimalNumber
  """
  The digits of a decimal integer, or the integral part of a float.
  """
  fun text(): String => "decimal number"

primitive HexadecimalNumber
  """
  The digits after `0x`.
  """
  fun text(): String => "hexadecimal number"

primitive BinaryNumber
  """
  The digits after `0b`.
  """
  fun text(): String => "binary number"

primitive RealMantissa
  """
  The digits after a float's `.`.
  """
  fun text(): String => "real number mantissa"

primitive RealExponent
  """
  The digits after a float's `e`, and its sign.
  """
  fun text(): String => "real number exponent"

type NumberContext is
  ( DecimalNumber | HexadecimalNumber | BinaryNumber | RealMantissa
  | RealExponent )
  """
  Which part of a numeric literal a refusal names, as ponyc's messages
  name it.
  """

class val DuplicateUnderscore
  """
  Two `_` in a row in a numeric literal.
  """
  let context: NumberContext

  new val create(context': NumberContext) =>
    context = context'

  fun message(): String =>
    "Invalid duplicate underscore in " + context.text()

class val InvalidDigit
  """
  A digit or letter in a numeric literal that is no digit of its base:
  `0b2`, `1a`, `0x1g`.
  """
  let context: NumberContext
  let byte: U8
    """
    The byte, as it was in the source.
    """

  new val create(context': NumberContext, byte': U8) =>
    context = context'
    byte = byte'

  fun message(): String =>
    "Invalid character in " + context.text() + ": " + _Byte(byte)

primitive NumericOverflow
  """
  A numeric literal, or a part of one, whose digits exceed
  `U128.max_value()`, ponyc's widest literal.
  """
  fun message(): String => "overflow in numeric literal"

class val NoDigits
  """
  A base prefix or an exponent `e`, with its sign, with no digit after
  it.
  """
  let context: NumberContext

  new val create(context': NumberContext) =>
    context = context'

  fun message(): String => "No digits in " + context.text()

class val TrailingUnderscore
  """
  A numeric literal, or a part of one, ending in `_`.
  """
  let context: NumberContext

  new val create(context': NumberContext) =>
    context = context'

  fun message(): String =>
    "Numeric literal cannot end with underscore in " + context.text()

class val UnrecognizedCharacter
  """
  A byte that starts no token; ponyc's "Unrecognized character".
  """
  let byte: U8
    """
    The byte, as it was in the source.
    """

  new val create(byte': U8) =>
    byte = byte'

  fun message(): String => "Unrecognized character: " + _Byte(byte)

type LexFailure is
  ( UnterminatedLiteral | UnterminatedComment | TripleQuoteNotBelowOpener
  | InvalidEscape | EmptyCharacterLiteral | DuplicateUnderscore
  | InvalidDigit | NumericOverflow | NoDigits | TrailingUnderscore
  | UnrecognizedCharacter )
  """
  Why the lexer refused a token, or an escape inside one; each member
  is one of the errors ponyc's lexer reports through `lex_error` or
  `lex_error_at`, and `message` is ponyc's text.
  """

class val LexError is diag.DiagnosticCause
  """
  `parse/lex`: the lexer refused a token, or an escape inside one, for
  one of ponyc's reasons. Positioned as ponyc positions it: over the
  token, or over the escape inside the literal. A refused token is a
  `TkLexError` leaf; a string or character literal with a bad escape
  keeps its kind, as ponyc's does. The message is ponyc's text with no
  prefix, since ponyc's lexer errors carry none; a source byte in it
  renders as itself when it is printable ASCII and as `\xNN`
  otherwise, so a message never holds a control character or a lone
  lead byte. Never dropped by the budget: one per refused token or
  escape. ponyc's parser stops at the first refused token, so a file
  of refused bytes is one record on ponyc's side and one per byte
  here; a refused escape stops nothing on either side.
  """
  let failure: LexFailure

  new val create(failure': LexFailure) =>
    failure = failure'

  fun code(): String => "parse/lex"

  fun message(): String => failure.message()

primitive _Byte
  """
  A source byte as a message shows it: itself when printable ASCII,
  else `\xNN`.
  """
  fun apply(byte: U8): String =>
    if (byte >= 0x20) and (byte <= 0x7E) then
      recover val String.from_utf32(byte.u32()) end
    else
      "\\x" + _hex_digit(byte >> 4) + _hex_digit(byte and 0x0F)
    end

  fun _hex_digit(nibble: U8): String =>
    let c: U8 = if nibble < 10 then '0' + nibble else ('a' + nibble) - 10 end
    recover val String.from_utf32(c.u32()) end

primitive _Bytes
  """
  Every byte of a string under `_Byte`'s rule.
  """
  fun apply(text: String): String =>
    let out = recover iso String(text.size()) end
    for b in text.values() do
      out.append(_Byte(b))
    end
    consume out

class val SyntaxExpected is diag.DiagnosticCause
  """
  `parse/expected`: `what` was required here and `found` is here
  instead. `what` is ponyc's rule description at every site that
  corresponds to a ponyc expectation; for a missing expression it is
  the enclosing site's noun, as ponyc's not-found propagation reports
  it ("then value", "argument", "while body", "value" after an
  operator or a `;`); at a recovery site it names what the rule
  expected ("field or method"). Positioned at `found`'s start with
  width 0; at the end of the file, at the start of the last significant
  token, as ponyc positions it. The message is `syntax error: expected
  <what>, found <found>`, where `found` is the token's text or a
  description; ponyc says "after <last matched>" instead. The `syntax
  error: ` prefix is ponyc's for every parser error.
  """
  let what: String
  let found: TokenKind

  new val create(what': String, found': TokenKind) =>
    what = what'
    found = found'

  fun code(): String => "parse/expected"

  fun message(): String =>
    "syntax error: expected " + what + ", found " + _Describe(found)

class val SyntaxUnterminated is diag.DiagnosticCause
  """
  `parse/unterminated`: the parser reached no closer for the construct
  `what` opened at this token, either because the source has none or
  because the rules inside the construct stopped short of it; ponyc's
  `TERMINATE` reports both the same way. Positioned over the opening
  token. `before` is the byte where the parser stopped looking: the
  current token's start, or the last significant token's at the end of
  the file; it is not part of the message.
  """
  let what: String
  let before: USize

  new val create(what': String, before': USize) =>
    what = what'
    before = before'

  fun code(): String => "parse/unterminated"

  fun message(): String => "syntax error: unterminated " + what

class val NestingTooDeep is diag.DiagnosticCause
  """
  `parse/nesting`: the grammar recursion limit `limit` was reached
  parsing `what`. Positioned over the token the parser was at; at the
  end of the file, at the start of the last significant token with
  width 0, as `SyntaxExpected` is. ponyc has no such limit. Never
  dropped by the budget.
  """
  let what: String
  let limit: USize

  new val create(what': String, limit': USize) =>
    what = what'
    limit = limit'

  fun code(): String => "parse/nesting"

  fun message(): String =>
    what + " nested past the grammar depth limit of " + limit.string()

class val SyntaxLimit is diag.DiagnosticCause
  """
  `parse/limit`: this file has more than `limit` `parse/expected` and
  `parse/unterminated` records; those past the budget are not
  reported. Located at the file rather than at a span, so it sorts
  before the records it counts.
  """
  let limit: USize

  new val create(limit': USize) =>
    limit = limit'

  fun code(): String => "parse/limit"

  fun message(): String =>
    "more than " + limit.string() +
      " syntax errors in this file; the rest are not reported"

primitive _Describe
  """
  A token kind as a diagnostic names it: its text for a kind whose text
  is fixed, else a description.
  """
  fun apply(kind: TokenKind): String =>
    match kind.text()
    | let t: String => t
    else
      match kind
      | TkId => "an identifier"
      | TkString => "a string literal"
      | TkInt => "an integer literal"
      | TkFloat => "a float literal"
      | TkEof => "the end of the file"
      | TkLexError => "an unreadable token"
      | TkWhitespace => "whitespace"
      | TkLineComment | TkNestedComment => "a comment"
      else
        kind.name()
      end
    end
