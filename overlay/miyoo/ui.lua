-- Small drawing kit for the handheld UI. Everything here is in Miyoo screen
-- pixels (640x480); calls are translated into Panel Attack's 1280x720 canvas,
-- of which the middle 960x720 is visible at 2/3 scale.

local G = love.graphics
local U = {}

local SCALE = 1.5   -- canvas units per screen pixel
local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"
local OX = 160      -- canvas x of screen x = 0
U.W, U.H = 640, 480

-- Drawing normally maps screen pixels onto the canvas. Inside Panel Attack UI
-- elements (which draw under a translate), U.inElement() switches to "local"
-- units: canvas units / 1.5, no offset. U.onScreen() switches back.
function U.inElement() OX = 0 end
function U.onScreen() OX = 160 end

function U.cx(x) return x * SCALE + OX end
function U.cy(y) return y * SCALE end
function U.sx(x) return (x - OX) / SCALE end
function U.sy(y) return y / SCALE end

---------------------------------------------------------------------------
-- palette (matches the mockups)
---------------------------------------------------------------------------
local function hex(s, a)
  local r, g, b = tonumber(s:sub(2, 3), 16), tonumber(s:sub(4, 5), 16), tonumber(s:sub(6, 7), 16)
  return { r / 255, g / 255, b / 255, a or 1 }
end
U.hex = hex
U.C = {
  bg = hex("#0e1220"),
  card = hex("#1a2136"),
  row = hex("#141a2b"),
  sel = hex("#1f2a48"),
  board = hex("#161b2c"),
  key = hex("#2a3350"),
  text = hex("#e8ecf6"),
  dim = hex("#c5cce0"),
  muted = hex("#9aa4bd"),
  faint = hex("#6d7690"),
  p1 = hex("#4c8dff"),
  p2 = hex("#ff8a3d"),
  garbage = hex("#5a6275"),
  garbageEdge = hex("#8a93a8"),
  green = hex("#5fd38d"),
  greenBg = hex("#1d3a2c"),
  amber = hex("#ffb067"),
  amberBg = hex("#3a2a1a"),
  greyBg = hex("#262d45"),
  red = hex("#ff5c7a"),
  shade = { 0.03, 0.04, 0.08, 0.82 },
}

---------------------------------------------------------------------------
-- fonts: sizes are screen pixels
---------------------------------------------------------------------------
local FONT_DIR = "miyoo/fonts/"
local files = {
  display = "ChakraPetch-Bold.ttf",
  regular = "Rubik-400.ttf",
  medium = "Rubik-500.ttf",
  bold = "Rubik-700.ttf",
}
local fontCache = {}
function U.font(kind, px)
  local key = kind .. px
  local f = fontCache[key]
  if not f then
    f = G.newFont(FONT_DIR .. files[kind], px * SCALE)
    fontCache[key] = f
  end
  return f
end

---------------------------------------------------------------------------
-- primitives
---------------------------------------------------------------------------
local function setColor(c, alpha)
  G.setColor(c[1], c[2], c[3], (c[4] or 1) * (alpha or 1))
end
U.setColor = setColor

function U.rect(x, y, w, h, c, alpha)
  if w <= 0 or h <= 0 then return end
  setColor(c, alpha)
  G.rectangle("fill", x * SCALE + OX, y * SCALE, w * SCALE, h * SCALE)
end

-- corner insets per radius, computed once
local insetCache = {}
local function insets(r)
  local t = insetCache[r]
  if not t then
    t = {}
    for i = 0, r - 1 do
      local dy = r - i - 0.5
      t[i] = math.floor(r - math.sqrt(r * r - dy * dy) + 0.5)
    end
    insetCache[r] = t
  end
  return t
end

-- filled rectangle with rounded corners
function U.rrect(x, y, w, h, r, c, alpha)
  x, y, w, h = math.floor(x + 0.5), math.floor(y + 0.5), math.floor(w + 0.5), math.floor(h + 0.5)
  r = math.min(r or 0, math.floor(w / 2), math.floor(h / 2))
  if r <= 1 then return U.rect(x, y, w, h, c, alpha) end
  local t = insets(r)
  U.rect(x, y + r, w, h - 2 * r, c, alpha)
  for i = 0, r - 1 do
    local s = t[i]
    U.rect(x + s, y + i, w - 2 * s, 1, c, alpha)
    U.rect(x + s, y + h - 1 - i, w - 2 * s, 1, c, alpha)
  end
end

-- rectangle outline of thickness t
function U.frame(x, y, w, h, t, c, alpha)
  U.rect(x, y, w, t, c, alpha)
  U.rect(x, y + h - t, w, t, c, alpha)
  U.rect(x, y + t, t, h - 2 * t, c, alpha)
  U.rect(x + w - t, y + t, t, h - 2 * t, c, alpha)
end

-- rounded outline: ring between two rounded rects; per-row spans only in
-- the corner zones
function U.rframe(x, y, w, h, r, t, c, alpha)
  x, y, w, h = math.floor(x + 0.5), math.floor(y + 0.5), math.floor(w + 0.5), math.floor(h + 0.5)
  r = math.min(r or 0, math.floor(w / 2), math.floor(h / 2))
  if r <= 1 then return U.frame(x, y, w, h, t, c, alpha) end
  local to = insets(r)
  local ri = math.max(r - t, 0)
  local ti = ri > 0 and insets(ri) or {}
  local function row(i, yy)
    local so = i < r and to[i] or 0
    if i < t then
      U.rect(x + so, yy, w - 2 * so, 1, c, alpha)
    else
      local j = i - t
      local si = (j < ri) and (ti[j] + t) or t
      U.rect(x + so, yy, si - so, 1, c, alpha)
      U.rect(x + w - si, yy, si - so, 1, c, alpha)
    end
  end
  local zone = math.max(r, t)
  for i = 0, zone - 1 do
    row(i, y + i)
    row(i, y + h - 1 - i)
  end
  U.rect(x, y + zone, t, h - 2 * zone, c, alpha)
  U.rect(x + w - t, y + zone, t, h - 2 * zone, c, alpha)
end

-- text; align = "left" | "center" | "right" relative to x (and width w if given)
function U.text(s, x, y, font, c, align, w, spacing, alpha)
  s = tostring(s)
  setColor(c, alpha)
  G.setFont(font)
  local fw
  if spacing and spacing ~= 0 then
    fw = 0
    for ch in s:gmatch(UTF8_CHAR) do fw = fw + font:getWidth(ch) / SCALE + spacing end
    fw = fw - spacing
  else
    fw = font:getWidth(s) / SCALE
  end
  local tx = x
  if align == "center" then tx = (w and x + (w - fw) / 2) or (x - fw / 2)
  elseif align == "right" then tx = (w and x + w - fw) or (x - fw) end
  tx = math.floor(tx + 0.5)
  if spacing and spacing ~= 0 then
    for ch in s:gmatch(UTF8_CHAR) do
      G.print(ch, tx * SCALE + OX, y * SCALE)
      tx = tx + font:getWidth(ch) / SCALE + spacing
    end
  else
    G.print(s, tx * SCALE + OX, y * SCALE)
  end
  return fw
end

function U.textWidth(s, font, spacing)
  s = tostring(s)
  if spacing and spacing ~= 0 then
    local fw = 0
    for ch in s:gmatch(UTF8_CHAR) do fw = fw + font:getWidth(ch) / SCALE + spacing end
    return fw - spacing
  end
  return font:getWidth(s) / SCALE
end

-- shorten s with an ellipsis so it fits in maxW screen pixels
function U.fit(s, font, maxW)
  s = tostring(s or "")
  if U.textWidth(s, font) <= maxW then return s end
  while #s > 1 and U.textWidth(s .. "…", font) > maxW do s = s:sub(1, -2) end
  return s .. "…"
end

-- image scaled to w x h screen pixels
function U.image(img, x, y, w, h, alpha)
  if not img then return end
  G.setColor(1, 1, 1, alpha or 1)
  local iw, ih = img:getDimensions()
  G.draw(img, x * SCALE + OX, y * SCALE, 0, w * SCALE / iw, (h or w) * SCALE / ih)
end

-- button glyph like (A) or [START]; returns its width
function U.key(label, x, y, h)
  h = h or 18
  local f = U.font("bold", h <= 18 and 12 or 14)
  local tw = U.textWidth(label, f)
  local round = #label == 1
  local w = round and math.max(h, tw + 10) or tw + 12
  U.rrect(x, y, w, h, round and math.floor(h / 2) or 4, U.C.key)
  U.text(label, x, y + math.floor((h - f:getHeight() / SCALE) / 2), f, U.C.text, "center", w)
  return w
end

-- hint bar along the bottom edge: items = { {"A", "Select"}, ... }
function U.hintBar(items, y, h)
  y, h = y or (U.H - 36), h or 36
  U.rect(0, y, U.W, h, U.C.row)
  local f = U.font("regular", 14)
  local x = U.W - 24
  for i = #items, 1, -1 do
    local k, label = items[i][1], items[i][2]
    local lw = U.textWidth(label, f)
    x = x - lw
    U.text(label, x, y + math.floor((h - f:getHeight() / SCALE) / 2), f, U.C.muted)
    local kf = U.font("bold", 12)
    local kw = (#k == 1) and math.max(18, U.textWidth(k, kf) + 10) or (U.textWidth(k, kf) + 12)
    x = x - 6 - kw
    U.key(k, x, y + math.floor((h - 18) / 2), 18)
    x = x - 20
  end
end

function U.reset()
  G.setColor(1, 1, 1, 1)
end

return U
