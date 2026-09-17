primitive _Paths
  """
  Path arithmetic on strings, for POSIX paths, touching no file system.
  """
  fun is_abs(path: String): Bool =>
    path.at("/")

  fun join(path: String, next: String): String =>
    """
    `path` then `next` with one separator between, or `next` alone when it
    is absolute. Nothing is cleaned: `.` and `..` are left for the file
    system to resolve, as ponyc leaves them to `realpath`, so that a `..`
    after a symbolic link steps out of the link's target.
    """
    if is_abs(next) then next
    elseif path.size() == 0 then next
    elseif path.at("/", -1) then path + next
    else path + "/" + next
    end

  fun clean(path: String): String =>
    """
    The path with `.` and empty segments dropped, `..` applied to the
    segment before it (or dropped at the root), and no trailing slash.
    A relative path stays relative and keeps any leading `..`.
    """
    let absolute = is_abs(path)
    let out = Array[String]
    for seg in path.split("/").values() do
      if (seg == "") or (seg == ".") then continue end
      if seg == ".." then
        let last_is_up = try out(out.size() - 1)? == ".." else true end
        if (out.size() > 0) and (not last_is_up) then
          try out.pop()? else _Unreachable() end
        elseif not absolute then
          out.push(seg)
        end
        continue
      end
      out.push(seg)
    end
    let joined: String = "/".join(out.values())
    if absolute then "/" + joined
    elseif joined.size() == 0 then "."
    else joined
    end

  fun dir(path: String): String =>
    """
    The cleaned path before the last separator; `/` when the only
    separator is the leading one.
    """
    let cleaned = clean(path)
    try
      let cut = cleaned.rfind("/")?.usize()
      if cut == 0 then "/" else cleaned.substring(0, cut.isize()) end
    else
      "."
    end

  fun base(path: String): String =>
    """
    The name after the last separator.
    """
    let cleaned = clean(path)
    try
      cleaned.substring(cleaned.rfind("/")?.isize() + 1)
    else
      cleaned
    end
