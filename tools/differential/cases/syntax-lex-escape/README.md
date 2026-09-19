# syntax-lex-escape

A string literal holding an escape ponyc does not know. Both report at the `\`, inside the literal, and the literal stays a string.

ponyc: `main.pony:3:14: Invalid escape sequence "\q"`.
