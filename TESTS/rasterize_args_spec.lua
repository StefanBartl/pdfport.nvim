-- TESTS/rasterize_args_spec.lua — pdfport.core.rasterize.args
--
-- The pdftoppm command line for one page. Pure `-> string[]`, so it is
-- assertable without poppler installed and without a PDF, the same reason
-- `util/page_range.lua` is a pure parser.
--
-- What is worth pinning here is the crop window, because it is the half a
-- consumer cannot verify from the outside: a wrong `-x` produces a perfectly
-- valid PNG of the wrong part of the page, and it looks like the caller's
-- arithmetic rather than like a bug.

return function(H)
  local rasterize = require("pdfport.core.rasterize")

  ---Index of `flag` in `args`, or nil.
  ---@param args string[]
  ---@param flag string
  ---@return integer|nil
  local function at(args, flag)
    for i, a in ipairs(args) do
      if a == flag then
        return i
      end
    end
    return nil
  end

  -- ------------------------------------------------------------ no crop

  do
    local args = rasterize.args("/tmp/doc.pdf", 3, 216, "/tmp/out")
    H.eq(at(args, "-x"), nil, "no crop: no -x")
    H.eq(at(args, "-W"), nil, "no crop: no -W")
    H.eq(args[#args - 1], "/tmp/doc.pdf", "the PDF is the second-to-last argument")
    H.eq(args[#args], "/tmp/out", "the output base is last")
    H.eq(args[at(args, "-r") + 1], "216", "dpi follows -r")
    H.eq(args[at(args, "-f") + 1], "3", "the page follows -f")
    H.eq(args[at(args, "-l") + 1], "3", "and -l, so one page is rendered")
    H.ok(at(args, "-singlefile") ~= nil, "-singlefile, so the name is predictable")
  end

  -- ---------------------------------------------------------- with a crop

  do
    local args =
      rasterize.args("/tmp/doc.pdf", 1, 486, "/tmp/out", { x = 12, y = 34, w = 800, h = 600 })
    H.eq(args[at(args, "-x") + 1], "12", "-x carries the left edge")
    H.eq(args[at(args, "-y") + 1], "34", "-y carries the top edge")
    H.eq(args[at(args, "-W") + 1], "800", "-W carries the width")
    H.eq(args[at(args, "-H") + 1], "600", "-H carries the height")
    H.eq(args[#args - 1], "/tmp/doc.pdf", "the PDF still comes before the output base")
    H.eq(args[#args], "/tmp/out", "and the output base is still last")
  end

  -- A zero origin is a real coordinate, not an absent one: the top-left
  -- window is exactly what a caller asks for when the centre of interest is
  -- against an edge, and dropping it would silently move the window.
  do
    local args = rasterize.args("/tmp/doc.pdf", 1, 216, "/tmp/out", { x = 0, y = 0, w = 10, h = 10 })
    H.eq(args[at(args, "-x") + 1], "0", "x = 0 survives")
    H.eq(args[at(args, "-y") + 1], "0", "y = 0 survives")
  end

  -- pdftoppm takes integers. A caller computing a window from a zoom factor
  -- has fractions, and passing one through would make it reject the whole
  -- run over a decimal point.
  do
    local args =
      rasterize.args("/tmp/doc.pdf", 1, 216, "/tmp/out", { x = 12.7, y = 0.9, w = 99.6, h = 50.2 })
    H.eq(args[at(args, "-x") + 1], "12", "a fractional x is floored")
    H.eq(args[at(args, "-y") + 1], "0", "a fractional y is floored")
    H.eq(args[at(args, "-W") + 1], "99", "a fractional width is floored")
  end

  -- ------------------------------------------------------- refused shapes

  -- A partial window is refused rather than completed. pdftoppm reads a
  -- half-given window as a window anyway — the missing edges default to 0 and
  -- to the page — so guessing here would rasterize a region nobody asked for
  -- and hand it back as if it were the answer.
  do
    ---@diagnostic disable-next-line: missing-fields
    local ok = pcall(rasterize.args, "/tmp/doc.pdf", 1, 216, "/tmp/out", { x = 1, y = 2 })
    H.falsy(ok, "a crop missing w and h is refused")
  end

  do
    local ok = pcall(
      rasterize.args,
      "/tmp/doc.pdf",
      1,
      216,
      "/tmp/out",
      { x = 1, y = 2, w = 0, h = 5 }
    )
    H.falsy(ok, "a zero-width window is refused")
  end

  do
    local ok = pcall(
      rasterize.args,
      "/tmp/doc.pdf",
      1,
      216,
      "/tmp/out",
      { x = -5, y = 2, w = 10, h = 5 }
    )
    H.falsy(ok, "a negative origin is refused")
  end
end
