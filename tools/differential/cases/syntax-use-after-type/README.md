# syntax-use-after-type

A `use` after an entity. Both report at the `use`: ponyc's `class_def` restart check, and hefermotor's member list, whose error item it is; the entity after it is kept. The divergence "A `use` after a type definition is a syntax error" in `docs/ponyc-divergences.md`.

ponyc: `main.pony:3:1: syntax error: unexpected token use after type, interface, trait, primitive, class or actor definition`.
