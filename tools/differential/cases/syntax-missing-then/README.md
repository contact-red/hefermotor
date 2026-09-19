# syntax-missing-then

An `if` whose condition is followed by its body with no `then`. `true 1` reads as two statements, so both report at the `end`.

ponyc: `main.pony:3:15: syntax error: expected then after condition expression`.
