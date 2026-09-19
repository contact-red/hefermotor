# syntax-unclosed-paren

A call's argument list left open at the end of the file. Both report at the `(`: ponyc's `TERMINATE` and hefermotor's `close` position an unterminated construct at its opener.

ponyc: `main.pony:3:8: syntax error: unterminated call arguments`, with `3:9: expected terminating ) before here`.
