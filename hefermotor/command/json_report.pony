use "collections"
use diag = "../diagnostics"
use discover = "../discover"
use export = "../export"
use schedule = "../schedule"
use sort = "../sort"

primitive JsonReport
  """
  The report as one JSON document, keys in a fixed order: `format`,
  `export_digest`, `packages` (each with `dir`, `name`, `group` and
  `export_hash`, in `PackageDir` order), `groups` (each group's member
  directories, in group order) and `diagnostics` (each with `code`,
  `message` and `location`, in report order). A package whose group
  never completed has `null` for `export_hash`; a location is `null` for
  no file, `{"file"}` for a whole file, `{"file","start","length"}` for
  a byte range. Every control character is escaped, `\n`, `\r` and `\t`
  by name and the rest as `\uXXXX`, and every byte that is not part of
  a well-formed UTF-8 sequence is replaced with U+FFFD, so the document
  is valid JSON whatever bytes a path or a message holds.
  """
  fun apply(program: discover.Program, report: schedule.Report): String =>
    let out = recover iso String end
    out.append("{\"format\":1,\"export_digest\":\"")
    out.append(report.export_digest().hex())
    out.append("\",\"packages\":[")
    var first = true
    for p in _packages(program).values() do
      if not first then out.append(",") end
      first = false
      out.append("{\"dir\":")
      out.append(_JsonString(p.dir.path))
      out.append(",\"name\":")
      out.append(_JsonString(p.name.text))
      out.append(",\"group\":")
      out.append(try program.group_of(p.dir)?.string() else
        _Unreachable(); "" end)
      out.append(",\"export_hash\":")
      match report.export_of(p.dir)
      | let e: export.ExportData => out.append("\"" + e.hash.hex() + "\"")
      | None => out.append("null")
      end
      out.append("}")
    end
    out.append("],\"groups\":[")
    first = true
    for g in program.groups.values() do
      if not first then out.append(",") end
      first = false
      out.append("[")
      var first_member = true
      for m in g.members.values() do
        if not first_member then out.append(",") end
        first_member = false
        out.append(_JsonString(m.dir.path))
      end
      out.append("]")
    end
    out.append("],\"diagnostics\":[")
    first = true
    for d in report.diagnostics.values() do
      if not first then out.append(",") end
      first = false
      out.append("{\"code\":")
      out.append(_JsonString(d.cause.code()))
      out.append(",\"message\":")
      out.append(_JsonString(d.cause.message()))
      out.append(",\"location\":")
      match \exhaustive\ d.location
      | diag.Nowhere => out.append("null")
      | let f: diag.FileOnly =>
        out.append("{\"file\":")
        out.append(_JsonString(f.path()))
        out.append("}")
      | let s: diag.Span =>
        out.append("{\"file\":")
        out.append(_JsonString(s.path()))
        out.append(",\"start\":" + s.start.string())
        out.append(",\"length\":" + s.length.string() + "}")
      end
      out.append("}")
    end
    out.append("]}")
    consume out

  fun _packages(program: discover.Program): Array[discover.Package] =>
    """
    Every package in the program, in `PackageDir` order.
    """
    let by_dir = Map[discover.PackageDir, discover.Package]
    let dirs = Array[discover.PackageDir]
    for g in program.groups.values() do
      for m in g.members.values() do
        by_dir(m.dir) = m
        dirs.push(m.dir)
      end
    end
    sort.MergeSort[discover.PackageDir](dirs)
    let out = Array[discover.Package]
    for d in dirs.values() do
      try out.push(by_dir(d)?) else _Unreachable() end
    end
    out

primitive _JsonString
  """
  A byte string as a quoted JSON string: `"` and `\` escaped, every
  control character escaped (`\n`, `\r` and `\t` by name, the rest as
  `\uXXXX`), every byte that is not part of a well-formed UTF-8 sequence
  replaced with U+FFFD.
  """
  fun apply(text: String): String =>
    let out = recover iso String end
    out.push('"')
    var i: USize = 0
    while i < text.size() do
      let b = try text(i)? else _Unreachable(); 0 end
      if b == '"' then out.append("\\\"")
      elseif b == '\\' then out.append("\\\\")
      elseif b == '\n' then out.append("\\n")
      elseif b == '\r' then out.append("\\r")
      elseif b == '\t' then out.append("\\t")
      elseif b < 0x20 then
        out.append("\\u00")
        out.push(_hex(b >> 4))
        out.push(_hex(b and 0xF))
      elseif b < 0x80 then out.push(b)
      else
        let width = _sequence_width(text, i)
        if width == 0 then
          out.append("\uFFFD")
        else
          out.append(text.substring(i.isize(), (i + width).isize()))
          i = i + (width - 1)
        end
      end
      i = i + 1
    end
    out.push('"')
    consume out

  fun _hex(nibble: U8): U8 =>
    if nibble < 10 then '0' + nibble else ('a' + nibble) - 10 end

  fun _sequence_width(text: String, at: USize): USize =>
    """
    The width of the well-formed UTF-8 sequence starting at `at`, or 0
    when the bytes there are not one: a lead byte outside the lead
    ranges, a truncated sequence, a bad continuation byte, an overlong
    encoding, a surrogate, or a code point past U+10FFFF.
    """
    let lead = try text(at)? else return 0 end
    (let width: USize, let min: U32) =
      if (lead and 0xE0) == 0xC0 then (2, 0x80)
      elseif (lead and 0xF0) == 0xE0 then (3, 0x800)
      elseif (lead and 0xF8) == 0xF0 then (4, 0x10000)
      else return 0
      end
    if (at + width) > text.size() then return 0 end
    var code: U32 = (lead and (0x7F >> width.u8())).u32()
    var k: USize = 1
    while k < width do
      let c = try text(at + k)? else return 0 end
      if (c and 0xC0) != 0x80 then return 0 end
      code = (code << 6) or (c and 0x3F).u32()
      k = k + 1
    end
    if (code < min) or (code > 0x10FFFF) then return 0 end
    if (code >= 0xD800) and (code <= 0xDFFF) then return 0 end
    width
