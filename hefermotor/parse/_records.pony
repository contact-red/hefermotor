use diag = "../diagnostics"
use source = "../source"

primitive _DiagnosticBudget
  """
  `parse/expected` and `parse/unterminated` records kept per file before
  `SyntaxLimit`. These are the two families hefermotor's recovery
  can produce beyond ponyc's count: ponyc reports at most one parser
  error per restart region, while hefermotor resyncs at members and
  statements too. `parse/nesting` and `parse/lex` are never dropped.
  """
  fun apply(): USize => 500

class _Records
  """
  The diagnostics of one parse, in emission order. `note_expected`
  returns whether an expectation at a significant token is the first
  there, so that the parser records at most one per token; the first
  budgeted record past the budget is replaced by one `SyntaxLimit` at
  the file and later budgeted records are dropped; other families are
  always kept.
  """
  let _file: source.SourceFile
  var _records: Array[diag.Diagnostic] iso = recover Array[diag.Diagnostic] end
  var _budgeted: USize = 0
  var _noted: (USize | None) = None

  new create(file: source.SourceFile) =>
    _file = file

  fun ref record(cause: diag.DiagnosticCause, start: USize, length: USize) =>
    """
    Records `cause` over the bytes from `start`, subject to the budget.
    """
    match cause
    | let _: (SyntaxExpected | SyntaxUnterminated) =>
      _budgeted = _budgeted + 1
      if _budgeted == (_DiagnosticBudget() + 1) then
        _records.push(diag.Diagnostic(SyntaxLimit(_DiagnosticBudget()),
          diag.FileOnly(_file.dir, _file.name)))
      end
      if _budgeted > _DiagnosticBudget() then return end
    end
    _records.push(diag.Diagnostic(cause,
      diag.Span(_file.dir, _file.name, start, length)))

  fun ref note_expected(token_index: USize): Bool =>
    """
    Whether this is the first expectation noted at significant token
    `token_index`; false when one was already noted there.
    """
    match _noted
    | let noted: USize if noted == token_index => false
    else
      _noted = token_index
      true
    end

  fun ref take(): Array[diag.Diagnostic] iso^ =>
    """
    The records so far, leaving none behind.
    """
    _records = recover Array[diag.Diagnostic] end
