primitive UsePackage
  """
  A `use` that names a package: a locator with no scheme, or `package:`.
  It may carry an alias and may not carry a guard.
  """
  fun allow_alias(): Bool => true
  fun allow_guard(): Bool => false

primitive UseDirective
  """
  A `use` that directs the build rather than naming a package: `lib:`,
  `path:`, `cincludedir:` or `cdefine:`. It may carry a guard and may not
  carry an alias.
  """
  fun allow_alias(): Bool => false
  fun allow_guard(): Bool => true

class val UseUnknown
  """
  A scheme ponyc has no handler for; `scheme` is the text through the
  colon.
  """
  let scheme: String

  new val create(scheme': String) =>
    scheme = scheme'

type UseScheme is (UsePackage | UseDirective | UseUnknown)
  """
  What kind of `use` a locator's scheme makes it.
  """

primitive ClassifyUse
  """
  The scheme of a locator, split as ponyc's `use` handlers split it: the
  text up to and including the first colon names the scheme, and a
  locator with no colon is a package. Returns the scheme and the locator
  with its scheme stripped.
  """
  fun apply(locator: String): (UseScheme, String) =>
    try
      let colon = locator.find(":")?
      let scheme: String = locator.substring(0, colon + 1)
      let rest: String = locator.substring(colon + 1)
      match scheme
      | "package:" => (UsePackage, rest)
      | "lib:" => (UseDirective, rest)
      | "path:" => (UseDirective, rest)
      | "cincludedir:" => (UseDirective, rest)
      | "cdefine:" => (UseDirective, rest)
      else
        (UseUnknown(scheme), rest)
      end
    else
      (UsePackage, locator)
    end
