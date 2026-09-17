class val PackageName is Stringable
  """
  A package's name as ponyc would print it: the locator as written for a
  package found on a search root, the directory's basename for the program
  root, or the using package's name joined with the locator for a relative
  `use`. It depends on how the package was reached and on the checkout's
  directory name, and two packages can share one, so it is for display
  only: never an identity, never an ordering key, never part of export
  data.
  """
  let text: String

  new val create(text': String) =>
    text = text'

  fun string(): String iso^ =>
    text.clone()
