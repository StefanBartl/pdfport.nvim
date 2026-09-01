-- TESTS/page_range_spec.lua — pdfport.util.page_range.parse
--
-- Pure string -> integer[] parsing, so it is fully testable without a PDF,
-- a backend, or any external tool.

return function(H)
  local parse = require("pdfport.util.page_range").parse

  -- ------------------------------------------------------------- empty input

  -- nil means "no explicit selection"; callers fall back to their own default,
  -- which is why an empty selection must not come back as an empty list.
  H.eq(parse(""), nil, "empty string yields nil, not an empty list")
  H.eq(parse("   "), nil, "whitespace-only yields nil")
  -- Deliberately invalid: answering nil rather than raising is the point.
  ---@diagnostic disable-next-line: param-type-mismatch
  H.eq(parse(nil), nil, "nil input yields nil")

  -- --------------------------------------------------------- single pages

  H.eq_list(parse("5"), { 5 }, "a single page parses")
  H.eq_list(parse("1,3,7"), { 1, 3, 7 }, "a comma list parses")
  H.eq_list(parse(" 1 , 3 "), { 1, 3 }, "surrounding whitespace is trimmed")

  -- ---------------------------------------------------------------- ranges

  H.eq_list(parse("1-3"), { 1, 2, 3 }, "a range expands inclusively")
  H.eq_list(parse("2 - 4"), { 2, 3, 4 }, "whitespace inside a range is tolerated")
  H.eq_list(parse("1-3,5"), { 1, 2, 3, 5 }, "ranges and singles mix")

  -- A reversed range is not silently reinterpreted as its mirror: "5-3" is
  -- most likely a typo, and expanding it to 3,4,5 would quietly extract pages
  -- the user never asked for.
  H.eq(parse("5-3"), nil, "a reversed range contributes nothing")

  -- ------------------------------------------------------ dedup and ordering

  H.eq_list(parse("3,1,2"), { 1, 2, 3 }, "output is sorted regardless of input order")
  H.eq_list(parse("2,2,2"), { 2 }, "repeated pages are de-duplicated")
  H.eq_list(parse("1-3,2-4"), { 1, 2, 3, 4 }, "overlapping ranges are de-duplicated")

  -- ------------------------------------------------------------ junk input

  H.eq(parse("abc"), nil, "non-numeric input yields nil")
  H.eq(parse(",,,"), nil, "separators alone yield nil")
  -- Partially-valid input keeps what parses rather than rejecting everything:
  -- the prompt is interactive, and dropping a typo'd fragment is friendlier
  -- than discarding a long, otherwise-correct range list.
  H.eq_list(parse("1,abc,3"), { 1, 3 }, "unparseable fragments are skipped, valid ones kept")
end
