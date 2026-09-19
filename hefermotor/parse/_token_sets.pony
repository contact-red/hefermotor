primitive _TokenSets
  """
  The token sets the grammar tests against, in one place because several
  rules share them and because they are what bounds the cost of an error.
  """
  fun top_level(): Array[TokenKind] val =>
    """
    What a top-level item can start with. ponyc's `RESTART` set for both
    `use` and `class_def`, and the resync point for anything that fails.
    """
    [ TkUse; TkType; TkInterface; TkTrait
      TkPrimitive; TkStruct; TkClass; TkActor ]

  fun nesting_close(): Array[TokenKind] val =>
    """
    Where a region refused for depth ends: a closing token, the end of
    the source, or the start of the next item or member, so that a
    refusal inside a method body costs the rest of that body and not
    the rest of the file.
    """
    [ TkRparen; TkRsquare; TkRbrace; TkEnd; TkEof
      TkUse; TkType; TkInterface; TkTrait
      TkPrimitive; TkStruct; TkClass; TkActor
      TkFun; TkBe; TkNew ]

  fun field_start(): Array[TokenKind] val =>
    [TkVar; TkLet; TkEmbed]

  fun method_start(): Array[TokenKind] val =>
    [TkFun; TkBe; TkNew]

  fun member_or_entity(): Array[TokenKind] val =>
    """
    Where an error item in an entity's member list ends: the next
    member or the next entity. Not `use` or `end`, which are error
    items there.
    """
    [ TkVar; TkLet; TkEmbed; TkFun; TkBe; TkNew
      TkType; TkInterface; TkTrait
      TkPrimitive; TkStruct; TkClass; TkActor ]

  fun member_or_entity_or_end(): Array[TokenKind] val =>
    """
    Where an error item in an object literal's member list ends: as in
    an entity's, or the literal's `end`.
    """
    [ TkVar; TkLet; TkEmbed; TkFun; TkBe; TkNew
      TkType; TkInterface; TkTrait
      TkPrimitive; TkStruct; TkClass; TkActor
      TkEnd ]

  fun entities_or_end(): Array[TokenKind] val =>
    [ TkType; TkInterface; TkTrait; TkPrimitive
      TkStruct; TkClass; TkActor; TkEnd ]

  fun caps(): Array[TokenKind] val =>
    [TkIso; TkTrn; TkRef; TkVal; TkBox; TkTag]

  fun gencaps(): Array[TokenKind] val =>
    [TkCapRead; TkCapSend; TkCapShare; TkCapAlias; TkCapAny]

  fun any_cap(): Array[TokenKind] val =>
    [ TkIso; TkTrn; TkRef; TkVal; TkBox; TkTag
      TkCapRead; TkCapSend; TkCapShare; TkCapAlias; TkCapAny ]

  fun expr_start(): Array[TokenKind] val =>
    """
    The tokens an expression can start with: ponyc's `atom` first set
    with the prefix operators, the local declarations, the jumps and the
    control keywords, both forms of `(` and `[` included. Where an
    expression is optional, a rule enters it only on one of these.
    """
    [ TkId; TkThis; TkLocation; TkTrue; TkFalse; TkInt; TkFloat; TkString
      TkObject; TkLbrace; TkAtLbrace; TkAt
      TkLparen; TkLparenNew; TkLsquare; TkLsquareNew
      TkNot; TkAddress; TkDigestof; TkMinus; TkMinusNew; TkMinusTilde
      TkMinusTildeNew
      TkVar; TkLet; TkEmbed; TkMatchCapture
      TkReturn; TkBreak; TkContinue; TkError; TkCompileIntrinsic
      TkCompileError
      TkIf; TkIfdef; TkIftypeSet; TkMatch; TkWhile; TkRepeat; TkFor; TkWith
      TkTry; TkRecover; TkConsume; TkConstant ]

  fun case_pattern_start(): Array[TokenKind] val =>
    """
    The tokens a `match` case pattern can start with: ponyc's
    `casepattern` first set, which is `expr_start` without the jumps,
    the control keywords other than `while` and `for`, `consume` and
    `#`, since an `if` there is the case's guard.
    """
    [ TkId; TkThis; TkLocation; TkTrue; TkFalse; TkInt; TkFloat; TkString
      TkObject; TkLbrace; TkAtLbrace; TkAt
      TkLparen; TkLparenNew; TkLsquare; TkLsquareNew
      TkNot; TkAddress; TkDigestof; TkMinus; TkMinusNew; TkMinusTilde
      TkMinusTildeNew
      TkVar; TkLet; TkEmbed; TkMatchCapture
      TkWhile; TkFor ]

  fun type_start(): Array[TokenKind] val =>
    """
    The tokens `_AtomType` accepts, which is ponyc's `atomtype` first
    set with the generic capabilities.
    """
    [ TkThis; TkIso; TkTrn; TkRef; TkVal; TkBox; TkTag
      TkCapRead; TkCapSend; TkCapShare; TkCapAlias; TkCapAny
      TkLparen; TkLparenNew; TkId; TkLbrace; TkAtLbrace ]

  fun literals(): Array[TokenKind] val =>
    [TkTrue; TkFalse; TkInt; TkFloat; TkString]

  fun entities(): Array[TokenKind] val =>
    [ TkType; TkInterface; TkTrait; TkPrimitive
      TkStruct; TkClass; TkActor ]

  fun lparen(): Array[TokenKind] val =>
    """
    Pony distinguishes a `(` that follows a newline, so both forms have to
    be accepted wherever an open parenthesis is expected.
    """
    [TkLparen; TkLparenNew]

  fun lsquare(): Array[TokenKind] val =>
    [TkLsquare; TkLsquareNew]

