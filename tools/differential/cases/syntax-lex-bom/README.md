# syntax-lex-bom

A byte-order mark before the first token. ponyc's lexer refuses the first byte and its parser stops there; hefermotor refuses each of the three bytes, so its positions are `1:1`, `1:2` and `1:3`, and ponyc's `1:1` is among them. The entry "Every refused byte is reported" in `docs/ponyc-divergences.md` records it.

ponyc: `main.pony:1:1: Unrecognized character: \xef` (ponyc prints the byte itself).
