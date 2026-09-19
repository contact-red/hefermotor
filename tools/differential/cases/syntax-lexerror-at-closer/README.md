# syntax-lexerror-at-closer

A type argument list whose closer's place holds an unterminated string literal. ponyc's lexer reports the literal and its parser stops; hefermotor reports the literal where the lexer refused it and the list unterminated at the `[`.

ponyc: `main.pony:3:14: Literal doesn't terminate`. hefermotor: `3:10: syntax error: unterminated type arguments` and `3:14: Literal doesn't terminate`.
