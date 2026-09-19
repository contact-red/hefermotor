# syntax-junk-between-uses

An identifier between two `use` commands. Both report at it and read the command after it: ponyc's `use` restart check rejects it and skips to the next command; hefermotor's use section takes it as an error item. The entry "Junk between `use` commands" in `docs/ponyc-divergences.md` records the parity.

ponyc: `main.pony:2:1: syntax error: unexpected token junk after use command`.
