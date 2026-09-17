"""
# hefermotor

A semantic analyzer for Pony, built beside ponyc rather than inside it. It
will parse a program, resolve names, extract signatures, check method
bodies and reference capabilities, and report diagnostics. It generates no
code.

`Check` is the front door: it takes a program that `discover.Discover`
found and runs it through the scheduler with the production phases. What
runs today is discovery and the `use` graph; the phases after parsing are
stubs, so the only diagnostics are discovery's.
"""
