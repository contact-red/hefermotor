#!/usr/bin/env python3
"""Extract the inline Pony sources from ponyc's unit tests.

A TEST_F block in test/libponyc/*.cc with a verdict macro holds a Pony
program and asserts that ponyc accepts or rejects it. This writes each
such program out as `<output-dir>/sample-<suite>-<test>/main/main.pony`,
the layout in which `tools/differential/run.sh` scores a sample case
against the ponyc on PATH at `--pass=parse`, and writes `manifest.tsv`
beside them: per case, the suite, the test, the asserted verdict, the
pass the macro names, the case directory and ponyc's expected message.
The harness takes its verdict from ponyc itself, so the manifest is for
reading, not scoring.

A block is skipped, and counted, when it is not one program with one
verdict: it replaces builtin, adds a package or a magic path, names the
default package, compares two sources, resumes a compile, or asserts
through a macro that is not a verdict. pony-lsp2's extractor wrote the
magic-path fixture packages beside the program; the parse pass resolves
no `use`, so this one does not.

Usage: extract_corpus.py <ponyc-checkout> <output-dir> [suite...]
"""

import os
import re
import shutil
import sys

# The macros that state a verdict, and what they expect. A block whose
# TEST_ macro is neither (TEST_EQUIV, TEST_COMPILE_IR, ...) is skipped.
ACCEPT = re.compile(r"^TEST_COMPILE$")
REJECT = re.compile(r"^TEST_ERRORS?(_\d+)?$|^TEST_ERROR_WITH_NOTE$")

# The calls that make a block more than one program with one verdict.
SKIP_CALLS = re.compile(
    r"\b(add_package|add_package_path|set_builtin|test_equiv|TEST_EQUIV|"
    r"default_package_name|test_compile_resume|TEST_COMPILE_RESUME|"
    r"package_add_magic_path)\b"
)

STRING_PIECE = re.compile(r'"((?:[^"\\]|\\.)*)"')

ESCAPES = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "0": "\0"}

# A string literal, kept, or a comment, dropped: matching the literal
# first keeps a `/*` inside a Pony program's source.
COMMENT_OR_STRING = re.compile(
    r'"(?:[^"\\]|\\.)*"|/\*.*?\*/|//[^\n]*', re.S
)


def unescape(text):
    """The C string's bytes: each escape decoded once, in one pass, so
    that `\\n` is a backslash and an `n`."""
    return re.sub(r"\\(.)", lambda m: ESCAPES.get(m.group(1), m.group(1)),
                  text)


def uncomment(text):
    """The file without its C comments; its string literals untouched."""
    return COMMENT_OR_STRING.sub(
        lambda m: m.group(0) if m.group(0).startswith('"') else "", text
    )


def blocks(text):
    """Yield (test_name, body) for each TEST_F in a file that is not
    inside a comment."""
    text = uncomment(text)
    for m in re.finditer(r"TEST_F\(\s*\w+\s*,\s*(\w+)\s*\)\s*\{", text):
        depth = 1
        i = m.end()

        while i < len(text) and depth > 0:
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
            i += 1

        yield m.group(1), text[m.end() : i - 1]


def sources(body):
    """The `const char* name = "..." ...;` definitions in a block."""
    out = {}

    for m in re.finditer(
        r'const\s+char\*\s+(\w+)\s*=\s*((?:\s*"(?:[^"\\]|\\.)*")+)\s*;', body
    ):
        pieces = STRING_PIECE.findall(m.group(2))
        out[m.group(1)] = unescape("".join(pieces))

    return out


def macro_defs(text):
    """Each verdict macro's parameter names and embedded pass, from its
    #define.

    Three shapes exist in the suites. A one-argument define embeds the pass
    in its body (`#define TEST_ERROR(src) DO(test_error(src, "flatten"))`).
    A define whose second parameter is named `pass` takes it per call
    (`#define TEST_COMPILE(src, pass) ...`). Any other extra parameter is a
    message, never a pass -- `TEST_ERROR(src, err)` exists -- which is why
    the parameter *names* are read rather than the arity.
    """
    defs = {}
    for m in re.finditer(
        r"#define\s+(TEST_\w+)\s*\(([^)]*)\)((?:[^\n]*\\\n)*[^\n]*)",
        text,
    ):
        name = m.group(1)
        params = [x.strip() for x in m.group(2).split(",") if x.strip()]
        # The pass is the string literal handed to the test_* helper in the
        # body, wherever the continuation lines put it.
        body_pass = re.search(
            r"test_\w+\(src,\s*\"(\w+)\"", m.group(3)
        )
        defs[name] = (params, body_pass.group(1) if body_pass else None)
    return defs


def case_pass(macro, rest, defs):
    """The pass one macro invocation runs to, or "?" when unrecoverable."""
    params, embedded = defs.get(macro, ([], None))
    if len(params) >= 2 and params[1] == "pass":
        m = STRING_PIECE.search(rest)
        return m.group(1) if m else "?"
    return embedded or "?"


def verdict(body, defs):
    """The expected verdict, source variable, pass, and ponyc's message."""
    for m in re.finditer(r"\b(TEST_\w+)\s*\(\s*(\w+)([^;]*)", body):
        macro, var, rest = m.group(1), m.group(2), m.group(3)

        if ACCEPT.match(macro):
            return "accept", var, case_pass(macro, rest, defs), ""

        if REJECT.match(macro):
            params, _ = defs.get(macro, ([], None))
            msgs = STRING_PIECE.findall(rest)
            # When the define takes the pass per call it is the first
            # string; the expected message, if any, follows it.
            if len(params) >= 2 and params[1] == "pass":
                message = unescape(msgs[1]) if len(msgs) > 1 else ""
            else:
                message = unescape(msgs[0]) if msgs else ""
            return "reject", var, case_pass(macro, rest, defs), message

    return None, None, "?", ""


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1

    ponyc, out_dir = sys.argv[1], sys.argv[2]
    suites = sys.argv[3:]
    test_dir = os.path.join(ponyc, "test", "libponyc")
    manifest = []
    skipped = 0

    for name in sorted(os.listdir(test_dir)):
        if not name.endswith(".cc"):
            continue

        suite = name[:-3]

        if suites and suite not in suites:
            continue

        text = open(os.path.join(test_dir, name), encoding="utf8").read()
        defs = macro_defs(text)

        for test, body in blocks(text):
            if SKIP_CALLS.search(body):
                skipped += 1
                continue

            expect, var, case_target, message = verdict(body, defs)

            if expect is None:
                if re.search(r"\bTEST_\w+\s*\(", body):
                    skipped += 1
                continue

            srcs = sources(body)

            if var not in srcs:
                skipped += 1
                continue

            case = os.path.join(out_dir, f"sample-{suite}-{test}")
            shutil.rmtree(case, ignore_errors=True)
            os.makedirs(os.path.join(case, "main"))

            with open(os.path.join(case, "main", "main.pony"), "w",
                      encoding="utf8") as f:
                f.write(srcs[var])

            manifest.append((suite, test, expect, case_target, case, message))

    with open(os.path.join(out_dir, "manifest.tsv"), "w",
              encoding="utf8") as f:
        for row in manifest:
            f.write("\t".join(row) + "\n")

    print(f"{len(manifest)} cases extracted, "
          f"{skipped} skipped as not a plain verdict")
    return 0


if __name__ == "__main__":
    sys.exit(main())
