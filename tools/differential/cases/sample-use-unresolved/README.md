# sample-use-unresolved

A `use` of a package that does not exist, then a well-formed class. A `sample-` case is scored on the verdict at `--pass=parse`, where hefermotor's verdict is whether its document holds a `parse/` diagnostic: ponyc's parse pass resolves no `use` and accepts, and hefermotor's discovery diagnostic on the locator is not a parse rejection, so the case is `both accept`. Scored on the exit code it would be a `verdict` difference, which is what an emitted mutant with an edited locator would show.

ponyc: accepts.
