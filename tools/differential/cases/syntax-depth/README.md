# syntax-depth

1300 nested parentheses, balanced. ponyc accepts the file; hefermotor refuses the region at its grammar recursion limit and reports `parse/nesting` at the 1251st `(`, skips to the first `)`, closes the 1250 groups it entered, and reports the first of the 50 `)` left over from the member list. The divergence "Grammar recursion is bounded" in `docs/ponyc-divergences.md`; `KNOWN_GAP verdict`.

ponyc: accepts. hefermotor: `3:1255: expression nested past the grammar depth limit of 2500`, `3:2556: syntax error: expected field or method, found )`.
