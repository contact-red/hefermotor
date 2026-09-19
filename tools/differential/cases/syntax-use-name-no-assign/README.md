# syntax-use-name-no-assign

A `use` with a name and no `=`. Both report at the string: ponyc's `use_name` has consumed the name, and hefermotor's `_Use` has too, taking the string as the command's error item rather than its locator.

ponyc: `main.pony:1:7: syntax error: expected = after x`.
