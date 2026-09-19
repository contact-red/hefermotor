use diag = "../diagnostics"

primitive UnterminatedLiteral
  """
  A string or character literal that reaches the end of the source
  before its closing quote; ponyc's "Literal doesn't terminate".
  """

primitive UnterminatedComment
  """
  A `/* */` comment that reaches the end of the source before its
  closer; ponyc's "Nested comment doesn't terminate".
  """

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

type LexFailure is
  ( UnterminatedLiteral
  | UnterminatedComment
  | UnrecognizedCharacter )
  """
  Why the lexer refused a token; each member is one of the errors
  ponyc's lexer reports through `lex_error`.
  """

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
  `parse/unterminated`: the construct `what` opened at this token was
  not closed. Positioned over the opening token. `before` is the byte
  where the parser stopped looking for the closer: the current token's
  start, or the last significant token's at the end of the file; it is
  data for a renderer, not part of the message.
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
