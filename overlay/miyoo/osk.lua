-- On-screen keyboard for text fields (the Miyoo has no keyboard).
-- Opens whenever the game calls love.keyboard.setTextInput(true) and turns
-- button presses into love.textinput / key events:
--   D-pad move, A type, B delete, X upper/lower case, Start = OK, Select = cancel

local OSK = { active = false, row = 1, col = 1, upper = true }

-- Panel Attack names allow letters, digits and underscores
local LETTERS = { "ABCDEFGHIJKLM", "NOPQRSTUVWXYZ", "0123456789_" }
local SPECIAL = { "Aa", "DEL", "OK" }

local pending = {}   -- key releases to send on the next pump

local function rows()
  return #LETTERS + 1
end

local function rowLength(r)
  if r <= #LETTERS then return #LETTERS[r] end
  return #SPECIAL
end

local function clampCol()
  OSK.col = math.max(1, math.min(OSK.col, rowLength(OSK.row)))
end

local function tapKey(key)
  love.event.push("keypressed", key, key, false)
  pending[#pending + 1] = key
end

function OSK.open()
  if not OSK.active then
    OSK.active = true
    OSK.row, OSK.col = 1, 1
  end
end

function OSK.close()
  OSK.active = false
end

-- called at the start of each event pump
function OSK.flush()
  for i = 1, #pending do
    love.event.push("keyreleased", pending[i], pending[i])
    pending[i] = nil
  end
end

-- button name -> action; returns true if consumed
function OSK.button(name)
  if name == "up" then
    OSK.row = OSK.row == 1 and rows() or OSK.row - 1; clampCol()
  elseif name == "down" then
    OSK.row = OSK.row == rows() and 1 or OSK.row + 1; clampCol()
  elseif name == "left" then
    OSK.col = OSK.col == 1 and rowLength(OSK.row) or OSK.col - 1
  elseif name == "right" then
    OSK.col = OSK.col == rowLength(OSK.row) and 1 or OSK.col + 1
  elseif name == "a" then
    if OSK.row <= #LETTERS then
      local ch = LETTERS[OSK.row]:sub(OSK.col, OSK.col)
      if not OSK.upper then ch = ch:lower() end
      love.event.push("textinput", ch)
    else
      local s = SPECIAL[OSK.col]
      if s == "Aa" then OSK.upper = not OSK.upper
      elseif s == "DEL" then tapKey("backspace")
      elseif s == "OK" then tapKey("return") end
    end
  elseif name == "b" then
    tapKey("backspace")
  elseif name == "x" then
    OSK.upper = not OSK.upper
  elseif name == "start" then
    tapKey("return")
  elseif name == "select" or name == "menu" then
    tapKey("escape")
  end
  return true
end

-- drawn into the game's canvas, over the lower part of the screen
function OSK.draw(G)
  if not OSK.active then return end
  local U = require("miyoo.ui")
  local C = U.C
  G.push("all")
  G.origin()
  local canvas = GAME and GAME.globalCanvas
  if canvas then G.setCanvas(canvas) end
  G.setScissor()
  U.onScreen()
  local x0, y0, cell, keyW, keyH, step = 32, 268, 44, 40, 32, 38
  U.rrect(16, y0 - 16, U.W - 32, step * rows() + 24, 10, C.card)
  local f = U.font("medium", 17)
  local fb = U.font("bold", 17)
  for r = 1, rows() do
    local n = rowLength(r)
    local cw = r <= #LETTERS and cell or math.floor(13 * cell / n)
    local kw = r <= #LETTERS and keyW or cw - 4
    for c = 1, n do
      local label
      if r <= #LETTERS then
        label = LETTERS[r]:sub(c, c)
        if not OSK.upper then label = label:lower() end
      else
        label = SPECIAL[c]
        if label == "Aa" then label = OSK.upper and "ABC" or "abc" end
      end
      local kx, ky = x0 + (c - 1) * cw, y0 + (r - 1) * step
      local sel = (r == OSK.row and c == OSK.col)
      U.rrect(kx, ky, kw, keyH, 6, sel and C.p1 or C.row)
      U.text(label, kx, ky + 7, sel and fb or f, sel and C.bg or C.text, "center", kw)
    end
  end
  U.hintBar({ { "A", "Type" }, { "B", "Delete" }, { "X", "Case" }, { "START", "OK" }, { "SELECT", "Cancel" } }, 448, 32)
  U.reset()
  G.pop()
end

return OSK
