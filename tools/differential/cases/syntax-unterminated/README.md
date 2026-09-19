# syntax-unterminated

One entity per construct ponyc's `TERMINATE` rules close, each left open at the end of its line, twenty-one in all. ponyc restarts at each entity keyword, so it reports all twenty-one in one run, each at the construct's opener; hefermotor reports the same twenty-one at the same positions.

ponyc: `main.pony:1:9: syntax error: unterminated type arguments` through `42:14: syntax error: unterminated recover expression`, one per entity.
