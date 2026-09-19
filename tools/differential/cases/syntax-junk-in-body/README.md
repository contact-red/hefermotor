# syntax-junk-in-body

A `:` where a statement should start, inside a method body that is otherwise well formed. Both report at the `:`: ponyc's sequence stops there and the entity's restart check reports the token; hefermotor's statement rule reports it and the sequence rule takes it as an error and parses on.

ponyc: `main.pony:4:5: syntax error: unexpected token : after type, interface, trait, primitive, class or actor definition`.
