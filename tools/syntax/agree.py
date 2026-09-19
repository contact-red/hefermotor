#!/usr/bin/env python3
"""Compare hefermotor's items and types with ponyc's parse-pass AST.

Usage: agree.py [--known-gaps DIR] [--root DIR]... [--expected RAW]
                [--jobs N] <syntax binary> <package dir>...

Per package directory: ponyc's `--pass=parse --astpackage` output (on
stderr; `--expected RAW` reads it from a file instead, for one package,
a fixture) is split into modules, which ponyc prints in reverse strcmp
order of their file names, and paired with `syntax --shape` over the
directory's `.pony` files in strcmp order, each preceded by its
`;; <name>` sentinel. ponyc's side is normalised to the shape the tool
prints, so that a projection that printed too much or too little
differs: `:scope` suffixes are dropped; the expression slots (a use's
guard, a field's initialiser, a parameter's default, a method's body)
become `x` or `(seq ...)`, a body whose first expression is a string
with something after it and whose docstring slot is `x` becoming
`(seq "<text>" ...)`, since that is the string ponyc's
`sugar_docstring` moves; and a value type argument becomes `value`,
or `(value \\annotation ...\\)` when annotated. Both sides are then
laid out one token per line, a newline inside a string written as
`\\n`, and diffed per module. Strings otherwise compare as ponyc
prints them (`"`, `\\` and NUL escaped).

A module listed under `--known-gaps DIR` as `<package>__<file>.diff`,
where `<package>` is the package directory's path under the `--root`
that holds it (else its base name) with `/` as `__` and `<file>` the
module's file name, must differ by exactly the diff the file holds;
one that agrees fails as `known gap closed`, one that differs
otherwise is a DIFFER, and a gap file no compared module matches
fails as stale. Prints `DIFFER <file>` with the first differing line,
then the diff, then `modules N, agree M, differ D, known K, closed C`;
exits 1 on any DIFFER, closed gap or stale gap file, 2 on a bad
option, when ponyc or the tool fails, cannot be run, or prints a dump
that does not parse, or when the module counts disagree.
"""

import difflib
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

EXPRESSION_SLOTS = {
    "fun": 6, "be": 6, "new": 6,
    "flet": 2, "fvar": 2, "embed": 2,
    "param": 2,
    "use": 2,
}
DOC_SLOT = {"fun": 7, "be": 7, "new": 7}


class Node:
    """A parenthesised form: a head and its children, which are nodes,
    annotation groups, or atoms (strings included, as printed)."""

    def __init__(self, head, children):
        self.head = head
        self.children = children


class Annotation:
    """`\\annotation (id a) (id b)\\`, one child wherever it appears."""

    def __init__(self, items):
        self.items = items


def tokenize(text):
    """Parens, and atoms; a string atom runs to its closing quote with
    `\\"`, `\\\\` and `\\0` inside it, over raw newlines; a sentinel
    line `;; <name>` at the start of a line is one token."""
    tokens = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c.isspace():
            i += 1
        elif text.startswith(";; ", i) and (i == 0 or text[i - 1] == "\n"):
            j = text.find("\n", i)
            j = n if j < 0 else j
            tokens.append(text[i:j])
            i = j
        elif c in "()":
            tokens.append(c)
            i += 1
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            tokens.append(text[i:j + 1])
            i = j + 1
        else:
            j = i
            while j < n and not text[j].isspace() and text[j] not in "()":
                j += 1
            tokens.append(text[i:j])
            i = j
    return tokens


def parse(tokens, i=0):
    """The form at `tokens[i]`, and the index after it."""
    t = tokens[i]
    if t == "(":
        head = tokens[i + 1]
        i += 2
        children = []
        while tokens[i] != ")":
            child, i = parse(tokens, i)
            children.append(child)
        return Node(head, children), i + 1
    if t == "\\annotation":
        i += 1
        items = []
        while tokens[i] != "\\":
            item, i = parse(tokens, i)
            items.append(item)
        return Annotation(items), i + 1
    return t, i + 1


def normalise(form):
    """The comparable shape of a form: the form, normalised in place,
    or `value` for a `valueformalarg`, keeping its annotation."""
    if isinstance(form, Annotation):
        for item in form.items:
            normalise(item)
        return form
    if not isinstance(form, Node):
        return form
    form.head = form.head.split(":")[0]
    if form.head == "valueformalarg":
        if form.children and isinstance(form.children[0], Annotation):
            return Node("value", [form.children[0]])
        return "value"
    # Slots are counted after a leading annotation group.
    offset = 1 if form.children and isinstance(form.children[0], Annotation) \
        else 0
    slot = EXPRESSION_SLOTS.get(form.head)
    if slot is not None and len(form.children) > slot + offset:
        i = slot + offset
        doc = DOC_SLOT.get(form.head)
        # Only a method has a docstring slot the body's string can move
        # to; every other slot reduces to the bare marker.
        doc_empty = doc is not None and (
            len(form.children) > doc + offset
            and form.children[doc + offset] == "x")
        form.children[i] = marker(form.children[i], doc_empty)
    form.children = [normalise(c) for c in form.children]
    return form


def marker(expression, doc_empty):
    """`x`, `(seq ...)`, or `(seq "<text>" ...)`."""
    if expression == "x":
        return "x"
    if isinstance(expression, Node) and expression.head.split(":")[0] == "seq":
        first = expression.children[0] if expression.children else None
        if (doc_empty and isinstance(first, str) and first.startswith('"')
                and len(expression.children) > 1):
            return Node("seq", [first, "..."])
    return Node("seq", ["..."])


def lines(form, out):
    """One token per line, a newline inside a string as `\\n`."""
    if isinstance(form, Annotation):
        out.append("\\annotation")
        for item in form.items:
            lines(item, out)
        out.append("\\")
    elif isinstance(form, Node):
        out.append("(" + form.head)
        for c in form.children:
            lines(c, out)
        out.append(")")
    else:
        out.append(form.replace("\n", "\\n"))
    return out


def modules_of_ponyc(text):
    """The `(module ...)` forms of a `(package ...)` dump, as printed."""
    if "(package" not in text:
        raise RuntimeError(f"no package dump in ponyc's output:\n{text}")
    tokens = tokenize(text[text.index("(package"):])
    package, _ = parse(tokens, 0)
    out = []
    for m in package.children:
        if isinstance(m, Node) and m.head.startswith("module"):
            out.append(m)
        elif isinstance(m, str) and m.split(":")[0] == "module":
            # A module with no docstring, use or entity prints as a bare
            # atom, as every childless node does.
            out.append(Node("module", []))
    return out


def modules_of_syntax(text):
    """The `(module ...)` forms after each `;; <name>` sentinel."""
    tokens = tokenize(text)
    out = []
    i = 0
    while i < len(tokens):
        sentinel = tokens[i]
        if not sentinel.startswith(";; "):
            raise RuntimeError(f"expected a sentinel, found {sentinel!r}")
        form, i = parse(tokens, i + 1)
        out.append((sentinel[3:], form))
    return out


def run(args, cwd=None):
    done = subprocess.run(args, cwd=cwd, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE)
    return done.returncode, \
        done.stdout.decode("utf8", "surrogateescape"), \
        done.stderr.decode("utf8", "surrogateescape")


def gap_key(pkg, roots):
    """The `<package>` part of a gap file's name: the package's path
    under the root that holds it, else its base name, `/` as `__`."""
    path = os.path.abspath(pkg)
    for root in roots:
        root = os.path.abspath(root)
        if path.startswith(root + os.sep):
            return os.path.relpath(path, root).replace(os.sep, "__")
    return os.path.basename(path)


def compare_package(syntax, pkg, expected, known_dir, roots):
    """(agreed, differed, known, closed, gaps used, messages) for one
    package."""
    files = sorted(f for f in os.listdir(pkg)
                   if f.endswith(".pony") and not f.startswith(".")
                   and os.path.isfile(os.path.join(pkg, f)))
    if expected is None:
        code, _, err = run(["ponyc", "--pass=parse", "--astpackage",
                            os.path.abspath(pkg)],
                           cwd=os.path.dirname(os.path.abspath(pkg)))
        if code != 0 or "(package" not in err:
            raise RuntimeError(f"ponyc failed on {pkg}:\n{err}")
        ponyc_text = err
    else:
        with open(expected, encoding="utf8", errors="surrogateescape",
                  newline="") as f:
            ponyc_text = f.read()
    code, out, err = run([syntax, "--shape"]
                         + [os.path.join(pkg, f) for f in files])
    if code != 0:
        raise RuntimeError(f"syntax --shape failed on {pkg}:\n{err}")
    theirs = list(reversed(modules_of_ponyc(ponyc_text)))
    ours = modules_of_syntax(out)
    if len(theirs) != len(ours) or [n for n, _ in ours] != files:
        raise RuntimeError(
            f"{pkg}: ponyc printed {len(theirs)} modules, syntax printed "
            f"{[n for n, _ in ours]} for {files}")
    agreed = differed = known = closed = 0
    used = []
    messages = []
    for (name, ours_form), theirs_form in zip(ours, theirs):
        a = lines(normalise(theirs_form), [])
        b = lines(ours_form, [])
        diff = list(difflib.unified_diff(a, b, "ponyc", "hefermotor",
                                         lineterm="", n=2))
        gap = None
        if known_dir:
            gap_name = gap_key(pkg, roots) + "__" + name + ".diff"
            path = os.path.join(known_dir, gap_name)
            if os.path.exists(path):
                used.append(gap_name)
                with open(path, encoding="utf8", errors="surrogateescape",
                          newline="") as f:
                    gap = f.read()
                    if gap.endswith("\n"):
                        gap = gap[:-1]
        label = os.path.join(pkg, name)
        if not diff:
            if gap is not None:
                closed += 1
                messages.append(f"known gap closed: {label}")
            else:
                agreed += 1
        elif gap is not None and "\n".join(diff) == gap:
            known += 1
            messages.append(f"known gap: {label}")
        else:
            differed += 1
            first = next((l for l in diff[2:]
                          if l.startswith(("-", "+")) and not
                          l.startswith(("---", "+++"))), "")
            messages.append(f"DIFFER {label}: {first}")
            messages.extend(diff)
    return agreed, differed, known, closed, used, messages


def main(argv):
    known_dir = None
    roots = []
    expected = None
    jobs = os.cpu_count() or 1
    args = []
    i = 0
    try:
        while i < len(argv):
            if argv[i] == "--known-gaps":
                known_dir = argv[i + 1]
                i += 2
            elif argv[i] == "--root":
                roots.append(argv[i + 1])
                i += 2
            elif argv[i] == "--expected":
                expected = argv[i + 1]
                i += 2
            elif argv[i] == "--jobs":
                jobs = int(argv[i + 1])
                i += 2
            elif argv[i].startswith("--"):
                raise ValueError(argv[i])
            else:
                args.append(argv[i])
                i += 1
    except (IndexError, ValueError):
        print(__doc__)
        return 2
    if len(args) < 2 or (expected is not None and len(args) != 2) \
            or jobs < 1:
        print(__doc__)
        return 2
    syntax, packages = args[0], args[1:]
    totals = [0, 0, 0, 0]
    used = set()
    try:
        with ThreadPoolExecutor(max_workers=jobs) as pool:
            results = list(pool.map(
                lambda p: compare_package(syntax, p, expected, known_dir,
                                          roots),
                packages))
    except (RuntimeError, OSError, IndexError, UnicodeDecodeError) as e:
        print(e, file=sys.stderr)
        return 2
    for agreed, differed, known, closed, gaps, messages in results:
        for m in messages:
            print(m)
        used.update(gaps)
        for k, v in enumerate((agreed, differed, known, closed)):
            totals[k] += v
    stale = 0
    if known_dir and os.path.isdir(known_dir):
        for name in sorted(os.listdir(known_dir)):
            if name.endswith(".diff") and name not in used:
                stale += 1
                print(f"stale gap file, no module compared: {name}")
    agreed, differed, known, closed = totals
    print(f"modules {sum(totals)}, agree {agreed}, differ {differed}, "
          f"known {known}, closed {closed}")
    return 1 if differed or closed or stale else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
