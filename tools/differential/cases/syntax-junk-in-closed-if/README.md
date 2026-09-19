# syntax-junk-in-closed-if

A `:` inside an `if` that has its `end`. ponyc's sequence stops at the junk and the `TERMINATE` for `end` fails there, so it reports the `if` unterminated at the `if`; hefermotor reports the junk and finds the `end`. The divergence "Junk inside a closed construct" in `docs/ponyc-divergences.md`; `KNOWN_GAP positions`.

ponyc: `main.pony:3:5: syntax error: unterminated if expression`, with `3:20: expected terminating end before here`. hefermotor: `3:20: syntax error: expected value, found :`.
