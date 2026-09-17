class val SourceFile
  """
  One Pony file: where it is, what it holds, and the hash of what it
  holds. The hash covers the content alone, so moving or renaming the file
  leaves the hash unchanged.
  """
  let dir: String
    """
    The package directory the file was read from; discovery passes the
    directory's canonical path.
    """
  let name: String
    """
    The directory entry the file was read as.
    """
  let content: String
    """
    The file's bytes as read.
    """
  let hash: ContentHash
    """
    The hash of `content` and nothing else.
    """

  new val create(dir': String, name': String, content': String) =>
    dir = dir'
    name = name'
    content = content'
    hash = ContentHash._create(content'.hash64())

  fun path(): String =>
    """
    The directory joined with the name, which is how ponyc prints a file's
    location.
    """
    dir + "/" + name
