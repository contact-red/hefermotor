"""
# hefermotor/diagnostics

A diagnostic is a cause and a location. The cause carries the structured
facts and renders its own code and message. The location names a file as
a package directory plus a file name, so a consumer that stores a
location can keep the name and the offsets and leave the directory out.
`DiagnosticOrder` is one total order over diagnostics, so every listing
sorts the same way, and `RenderText` prints them as ponyc prints its
errors.
"""
