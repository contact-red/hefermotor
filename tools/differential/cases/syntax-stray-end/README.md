# syntax-stray-end

An `end` with nothing open, between two methods. Both report at the `end`; hefermotor takes it as the member list's error item and keeps both methods.

ponyc: `main.pony:3:3: syntax error: unexpected token end after type, interface, trait, primitive, class or actor definition`.
