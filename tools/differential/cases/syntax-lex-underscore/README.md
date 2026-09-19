# syntax-lex-underscore

A number with two underscores in a row. Both report at the `1`: ponyc's lexer refuses the literal where it starts, and hefermotor's records the refusal over the bytes ponyc read.

ponyc: `main.pony:3:13: Invalid duplicate underscore in decimal number`.
