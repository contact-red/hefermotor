# The order fixture

Three one-line modules `a.pony`, `b.pony` and `c.pony`, and `d.pony`, which holds only a comment and so prints as a bare `module` atom on ponyc's side. ponyc prints a package's modules in reverse strcmp order of their file names (`D`, `C`, `B`, `A`), and `tools/syntax/agree.py` reverses its split before pairing with the tool's sorted order; `expected.ast` holds that raw output, regenerated with `ponyc --pass=parse --astpackage order 2>&1 >/dev/null | grep -v '^Building'` from this directory's parent, so an `agree.py` that stopped reversing would pair `A` with `D`.
