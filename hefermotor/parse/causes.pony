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
