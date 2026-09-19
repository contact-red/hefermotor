# The shape fixture

Two modules whose `--shape` projection is compared with ponyc's raw `--pass=parse --astpackage` output in `expected.ast` under `make test`, through `tools/syntax/agree.py`'s normaliser, so that the projection and the normaliser are tested without the stdlib. `expected.ast` is regenerated with `ponyc --pass=parse --astpackage shape 2>&1 >/dev/null | grep -v '^Building'` from this directory's parent, a step of the ponyc-bump procedure.

The branches the two modules cover:

- `items.pony`:
  - a package docstring with a quote, a backslash and a second line
  - a `use` with no alias and no guard, with both, with a bare-string guard, with a parenthesised guard, with a guard that is a sequence starting with a string (a slot with no docstring, so its marker stays `(seq ...)`)
  - an FFI declaration with an annotated return type, an annotated parameter with a default, an ellipsis and `?`; one with a string name, an alias and a guard; one with only an ellipsis; one with a parameter and no ellipsis; annotated union and value return type arguments
  - a type alias; an interface, a trait, a struct and a primitive with no members, one with a docstring
  - a class with annotations, `@`, a capability, type parameters with and without a constraint and a default, a provides list, a docstring and members
  - fields `let`, `var` and `embed` with and without a value and a docstring, one whose value is a sequence starting with a string
  - a constructor whose body starts with a string and continues after a semicolon
  - a method with annotations, a capability, type parameters, parameters with a default and an ellipsis, a return type and `?`
  - a body that is only a string; a string before `=>` beside a body string; a string before `=>` alone; a behaviour whose body starts with a string and continues; a multi-statement body that starts with no string
  - a bare-capability return type with a body string that continues on a new line; a bare method; a bodiless partial method with an aliased return type
- `types.pony`:
  - a lambda type with a receiver capability, a name, a constrained type parameter, parameters, a return type, a capability and `^`; a bare lambda type; a lambda type with nothing but its braces
  - grouping parentheses; a tuple with a nested tuple; a viewpoint that nests right
  - the two mixed infix folds and a grouped inner union (the three-member union is `items.pony`'s type alias)
  - `this`; bare capabilities as type arguments
  - a type parameter with a viewpoint constraint and a value default beside one with neither
  - a body string holding `\0` before a semicolon
