#!/usr/bin/env python3
"""Fail when a grammar recursion cycle contains no depth-guarded rule.

The parser recurses on the machine stack and bounds itself with
hand-placed guards (`_Parser.too_deep`). A guard set chosen by
inspection misses cycles that crash, so this check derives the
invariant from the source instead: it reads the primitives in
`hefermotor/parse`, takes every call of the form `_Rule(p, ...)` as an
edge, removes every rule that calls `too_deep`, and requires what
remains to be acyclic. A rule that opens an unguarded cycle exits 1
here, with the cycle printed, instead of waiting for a file deep enough
to demonstrate it.

The model is per rule: a rule counts as guarded when any path through
it calls `too_deep`, so a guard on one branch of a rule whose other
branch recurses is trusted. This is a check against mistakes, not a
proof. It exits 1 over a directory in which it finds no rule.

Usage: guard.py <directory of the parse package>
"""

import os
import re
import sys


NONCODE = re.compile(
    r'"""(?:.*?"""+)'      # a docstring, closed by the last of its quotes
    r"|/\*.*?\*/"          # a block comment, not nested here
    r'|"(?:[^"\\\n]|\\.)*"'  # a string
    r"|'(?:[^'\\\n]|\\.)*'"  # a character
    r"|//[^\n]*",          # a line comment
    re.S)


def strip_noncode(text):
    """Replace docstrings, comments and literals with blanks, keeping
    line structure, so calls are only counted in code. One left-to-right
    scan, so a quote inside a comment or a character literal cannot pair
    with a later string and blank the code between."""
    return NONCODE.sub(lambda m: "\n" * m.group(0).count("\n"), text)


def primitives(text):
    """Yield (name, body) for each primitive in a source file."""
    matches = list(re.finditer(
        r"^(?:primitive|class|actor|type)\s+(?:\\\w+\\\s+)?"
        r"(?:(?:iso|trn|ref|val|box|tag)\s+)?(\w+)",
        text, re.M))
    for i, m in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        yield m.group(1), text[m.end():end]


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    src_dir = sys.argv[1]

    calls = {}
    guarded = set()
    for name in sorted(os.listdir(src_dir)):
        if not name.endswith(".pony"):
            continue
        text = strip_noncode(
            open(os.path.join(src_dir, name), encoding="utf8").read())
        for prim, body in primitives(text):
            edges = set(re.findall(r"\b(_?[A-Z]\w*)\s*\(\s*p\s*[,)]", body))
            calls.setdefault(prim, set()).update(edges)
            if re.search(r"\.too_deep\(", body):
                guarded.add(prim)

    callees = set().union(*calls.values()) & set(calls)
    rules = {prim for prim, edges in calls.items() if edges} | callees
    if not rules:
        print("grammar guard: no rule found in " + src_dir)
        return 1

    # Only rules that exist as primitives are nodes; a call like
    # _TokenSets.lparen() never matches the (p pattern.
    graph = {
        prim: {e for e in edges if e in calls and e not in guarded}
        for prim, edges in calls.items()
        if prim not in guarded
    }

    # The unguarded subgraph must be acyclic. Iterative colouring DFS;
    # a grey-to-grey edge is a cycle, reported with its path.
    WHITE, GREY, BLACK = 0, 1, 2
    colour = {n: WHITE for n in graph}
    for root in graph:
        if colour[root] != WHITE:
            continue
        stack = [(root, iter(sorted(graph[root])))]
        colour[root] = GREY
        path = [root]
        while stack:
            node, children = stack[-1]
            advanced = False
            for child in children:
                if colour[child] == GREY:
                    cycle = path[path.index(child):] + [child]
                    print("unguarded grammar recursion cycle:")
                    print("  " + " -> ".join(cycle))
                    print("guard one of its rules with _Parser.too_deep, "
                          "or the cycle grows the machine stack unbounded.")
                    return 1
                if colour[child] == WHITE:
                    colour[child] = GREY
                    stack.append((child, iter(sorted(graph[child]))))
                    path.append(child)
                    advanced = True
                    break
            if not advanced:
                colour[node] = BLACK
                stack.pop()
                path.pop()

    print(f"grammar guard: {len(rules)} rules, {len(guarded)} guarded, "
          f"no unguarded recursion cycle")
    return 0


if __name__ == "__main__":
    sys.exit(main())
