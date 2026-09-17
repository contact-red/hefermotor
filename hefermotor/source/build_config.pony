class val BuildConfig
  """
  The configuration a check runs under. Every phase after discovery is a
  function of the configuration, so its hash is a term of every cache
  key. A `BuildConfig` carries only that hash, and every run on every
  machine has the same one.
  """
  let hash: ContentHash

  new val host() =>
    """
    The one configuration there is: a fixed string's hash.
    """
    hash = HashBuilder.>field("config/0/host").done()
