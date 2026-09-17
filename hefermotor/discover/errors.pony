class val CantLoadPackage
  """
  A `use` whose package could not be loaded, and why. ponyc reports a
  separate error for the reason (for a locate failure, a positionless
  "couldn't locate this path") and then "can't load package" at the
  `use`; here the diagnostic at the `use` carries the reason, and only an
  unopenable file gets a diagnostic of its own (`UnreadableFile`).
  """
  let locator: String
  let reason: LoadFailure

  new val create(locator': String, reason': LoadFailure) =>
    locator = locator'
    reason = reason'

  fun code(): String => "discover/use-not-found"

  fun message(): String =>
    "can't load package '" + locator + "': " + reason.describe()

class val RootFailed
  """
  The program's root could not be loaded, and why.
  """
  let target: String
  let reason: LoadFailure

  new val create(target': String, reason': LoadFailure) =>
    target = target'
    reason = reason'

  fun code(): String => "discover/root-not-loaded"

  fun message(): String =>
    "can't load '" + target + "': " + reason.describe()

class val UnreadableFile
  """
  A source file that could not be opened. The package it belongs to
  fails to load as well.
  """
  let dir: String
  let name: String
  let why: String

  new val create(dir': String, name': String, why': String) =>
    dir = dir'
    name = name'
    why = why'

  fun code(): String => "discover/unreadable-file"

  fun message(): String => "can't open file " + dir + "/" + name

class val UseSchemeUnknown
  """
  A `use` whose scheme ponyc has no handler for.
  """
  let scheme: String

  new val create(scheme': String) =>
    scheme = scheme'

  fun code(): String => "discover/use-scheme-unknown"

  fun message(): String => "Use scheme " + scheme + " not found"

class val UseAliasNotAllowed
  """
  A `use` with an alias on a scheme that takes none.
  """
  let scheme: String

  new val create(scheme': String) =>
    scheme = scheme'

  fun code(): String => "discover/use-alias-not-allowed"

  fun message(): String => "Use scheme " + scheme + " may not have an alias"

class val UseGuardNotAllowed
  """
  A `use` with a guard on a scheme that takes none.
  """
  let scheme: String

  new val create(scheme': String) =>
    scheme = scheme'

  fun code(): String => "discover/use-guard-not-allowed"

  fun message(): String => "Use scheme " + scheme + " may not have a guard"

class val BuiltinNotFound
  """
  No `builtin` directory in the base directory or under any search root.
  The run cannot start; this is not a diagnostic.
  """
  let reason: LocateFailure

  new val create(reason': LocateFailure) =>
    reason = reason'

class val BuiltinNotLoaded
  """
  A `builtin` directory was located and could not be read. The run
  cannot start; this is not a diagnostic.
  """
  let dir: PackageDir
  let reason: ReadFailure

  new val create(dir': PackageDir, reason': ReadFailure) =>
    dir = dir'
    reason = reason'

type BuiltinFailure is (BuiltinNotFound | BuiltinNotLoaded)
  """
  Why a run could not start.
  """
