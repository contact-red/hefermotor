"""
# hefermotor/discover

Finds the packages a program reaches and reads their files. A `use`
locator resolves through `Locate` as ponyc's `find_path` resolves it; the
program's root and `builtin` resolve through `LocateTarget`, the
compile-target branch of the same function. `ReadPackage` turns a located
directory into its source files under ponyc's rules for which files count
and what an unreadable one means. Every path reaches the disk through a
`FileSystem`, so a test can run all of it in memory.
"""
