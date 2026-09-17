use "collections"

class Sets
  """
  A docstring mentioning SetIs and @exit(1) is not scanned.
  """
  let _s: SetIs[String] = SetIs[String]
  fun apply() => None // a comment mentioning digestof and @exit(1)
  fun doc() => None // handles """ docstrings
  fun after() => digestof this
  fun url(): String => "http://x" + digestof this
