# syntax-field-after-method-in-object

A field after a method inside an object literal that has its `end`. ponyc's `members` stops at the field and the `TERMINATE` for `end` fails there, so it reports the literal unterminated at `object` with the field's keyword as its `Info:` frame; hefermotor reports the keyword and finds the `end`. The entry "A field after a method is reported and parsed" in `docs/ponyc-divergences.md`; `KNOWN_GAP positions`.

ponyc: `main.pony:2:14: syntax error: unterminated object literal`, with `2:29: expected terminating end before here`. hefermotor: `2:29: syntax error: expected method, found let`.
