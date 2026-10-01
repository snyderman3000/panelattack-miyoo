-- love.graphics replacement for the Miyoo Mini Plus, drawing with mini2d on the CPU.
--
-- Model: every texture (Image/Canvas) has a logical size (what the game sees)
-- and a pixel surface. Images and canvases are stored at RENDER_SCALE of their
-- logical size (0.5 by default) because Panel Attack draws everything into a
-- 1280x720 canvas that ends up as 640x360 on the Miyoo screen. That keeps memory
-- low and makes most blits 1:1.
--
-- Deliberate simplifications: rotation and shear are ignored, shaders are no-ops,
-- stencils only support rectangles (turned into a clip rect), filtering is always
-- nearest, texture wrapping is not supported.

local ffi = require("ffi")
local bit = require("bit")
local utf8 = require("utf8")
local M = require("miyoo.m2d")

local floor, max, min = math.floor, math.max, math.min
local NOTINT = 0xffffffff

local G = {}
if os.getenv("PA_TEXLIST") then G._imageLog = {} end
-- "fill" (default): Panel Attack's 16:9 screen is scaled to the full 480 px
-- height and the sides are cropped to 4:3. "fit": letterboxed at half size.
local SCREEN_MODE = os.getenv("PA_SCREEN_MODE") or "fill"
local RENDER_SCALE = tonumber(os.getenv("PA_RENDER_SCALE") or (SCREEN_MODE == "fill" and tostring(2 / 3) or "0.5"))
G.RENDER_SCALE = RENDER_SCALE

local screenW, screenH = 640, 480
local back -- back buffer surface
local stats = { drawcalls = 0, images = 0, canvases = 0, fonts = 0, texturememory = 0, drawcallsbatched = 0,
  canvasswitches = 0, shaderswitches = 0 }

---------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------
local screenTarget = { scale = 1, isScreen = true, ox = 0, oy = 0 } -- surf filled in at init
local target = screenTarget
local tsx, tsy, ttx, tty = 1, 1, 0, 0 -- transform: logical -> target logical
local tstack = {}
local cr, cg, cb, ca = 1, 1, 1, 1
local tint = NOTINT        -- premultiplied tint for textures
local fillColor = 0xffffffff -- premultiplied fill colour
local blend = 1
local blendName, alphaModeName = "alpha", "alphamultiply"
local lineWidth = 1
local curFont
local bgr, bgg, bgb, bga = 0, 0, 0, 1
local scissor = nil        -- {x,y,w,h} in target logical units
local stencilRect = nil    -- pixel rect captured by stencil()
local stencilActive = false
local capturingStencil = false
local shader = nil
local defaultFilterMin, defaultFilterMag = "linear", "linear"

local function premulColor(r, g, b, a)
  if a < 0 then a = 0 elseif a > 1 then a = 1 end
  if r < 0 then r = 0 elseif r > 1 then r = 1 end
  if g < 0 then g = 0 elseif g > 1 then g = 1 end
  if b < 0 then b = 0 elseif b > 1 then b = 1 end
  local A = floor(a * 255 + 0.5)
  local R = floor(r * a * 255 + 0.5)
  local Gc = floor(g * a * 255 + 0.5)
  local B = floor(b * a * 255 + 0.5)
  return A * 16777216 + R * 65536 + Gc * 256 + B
end

local function updateColor()
  fillColor = premulColor(cr, cg, cb, ca)
  if cr == 1 and cg == 1 and cb == 1 and ca == 1 then
    tint = NOTINT
  else
    tint = fillColor
  end
end

-- apply scissor/stencil as a pixel clip rect on the current target
local function applyClip()
  local x0, y0, x1, y1
  if scissor then
    local s, ox, oy = target.scale, target.ox, target.oy
    x0, y0 = floor(scissor[1] * s - ox + 0.5), floor(scissor[2] * s - oy + 0.5)
    x1, y1 = floor((scissor[1] + scissor[3]) * s - ox + 0.5), floor((scissor[2] + scissor[4]) * s - oy + 0.5)
  end
  if stencilActive and stencilRect then
    if x0 then
      x0, y0 = max(x0, stencilRect[1]), max(y0, stencilRect[2])
      x1, y1 = min(x1, stencilRect[3]), min(y1, stencilRect[4])
    else
      x0, y0, x1, y1 = stencilRect[1], stencilRect[2], stencilRect[3], stencilRect[4]
    end
  end
  if x0 then
    M.m2d_set_clip(x0, y0, max(0, x1 - x0), max(0, y1 - y0))
  else
    M.m2d_reset_clip()
  end
end

-- logical point -> target pixel
local function toPixel(x, y)
  local s = target.scale
  return (ttx + tsx * x) * s - target.ox, (tty + tsy * y) * s - target.oy
end

-- pixel rect from two logical corners (handles negative scales -> flip flags)
local function pixelRect(x0, y0, x1, y1)
  local s, ox, oy = target.scale, target.ox, target.oy
  local px0 = floor((ttx + tsx * x0) * s - ox + 0.5)
  local py0 = floor((tty + tsy * y0) * s - oy + 0.5)
  local px1 = floor((ttx + tsx * x1) * s - ox + 0.5)
  local py1 = floor((tty + tsy * y1) * s - oy + 0.5)
  local flip = 0
  if px1 < px0 then px0, px1 = px1, px0; flip = flip + 1 end
  if py1 < py0 then py0, py1 = py1, py0; flip = flip + 2 end
  return px0, py0, px1 - px0, py1 - py0, flip
end

-- Lazy clear of the game canvas: Panel Attack clears it every frame and then
-- usually covers it completely with an opaque stage background, so the clear
-- is only performed if something else gets drawn first.
local pendingClear = nil
local function flushClear()
  if pendingClear and G._screenView then
    M.m2d_clear(G._screenView.surf, pendingClear, 0)
  end
  pendingClear = nil
end
local function prepTarget()
  if pendingClear and target.canvas == G._screenView then flushClear() end
end

---------------------------------------------------------------------------
-- object helpers
---------------------------------------------------------------------------
local function makeType(name, parents)
  local mt = {}
  mt.__index = mt
  mt.__typeName = name
  local types = { [name] = true, Object = true }
  for _, p in ipairs(parents or {}) do types[p] = true end
  function mt:typeOf(t) return types[t] == true end
  function mt:type() return name end
  function mt:release() return true end
  return mt
end

local function surfaceFinalizer(s)
  M.m2d_surface_free(s)
end

local function newSurface(w, h)
  local s = M.m2d_surface_new(w, h)
  assert(s ~= nil, "out of memory allocating " .. w .. "x" .. h .. " surface")
  stats.texturememory = stats.texturememory + w * h * 4
  return ffi.gc(s, function(p)
    stats.texturememory = stats.texturememory - p.w * p.h * 4
    surfaceFinalizer(p)
  end)
end

---------------------------------------------------------------------------
-- Texture (Image / Canvas)
---------------------------------------------------------------------------
local Texture = makeType("Texture", { "Drawable" })

local Image = makeType("Image", { "Texture", "Drawable" })
local Canvas = makeType("Canvas", { "Texture", "Drawable" })

local function textureMethods(T)
  function T:getDimensions() return self.lw, self.lh end
  function T:getWidth() return self.lw end
  function T:getHeight() return self.lh end
  function T:getPixelDimensions() return self.surf.w, self.surf.h end
  function T:getPixelWidth() return self.surf.w end
  function T:getPixelHeight() return self.surf.h end
  function T:getDPIScale() return self.dpiscale end
  function T:setFilter(a, b) self.filterMin, self.filterMag = a, b or a end
  function T:getFilter() return self.filterMin or "linear", self.filterMag or "linear", 1 end
  function T:setWrap(h, v) self.wrapH, self.wrapV = h, v or h end
  function T:getWrap() return self.wrapH or "clamp", self.wrapV or "clamp" end
  function T:getMipmapCount() return 1 end
  function T:getFormat() return "rgba8" end
  function T:getTextureType() return "2d" end
  function T:isReadable() return true end
  function T:setMipmapFilter() end
  function T:getMipmapFilter() return nil end
  function T:getDepth() return 1 end
  function T:getLayerCount() return 1 end
  function T:isCanvas() return self.__isCanvas == true end
  function T:getMSAA() return 1 end
end
textureMethods(Image)
textureMethods(Canvas)

local function makeTexture(mt, lw, lh, dpiscale, surf)
  local t = setmetatable({}, mt)
  t.lw, t.lh = lw, lh
  t.dpiscale = dpiscale or 1
  t.surf = surf
  t.filterMin, t.filterMag = defaultFilterMin, defaultFilterMag
  return t
end

-- ImageData proxy used for canvas readback (canvas:newImageData / readbackTexture)
local SurfaceData = makeType("ImageData", { "Data" })
function SurfaceData:getDimensions() return self.lw, self.lh end
function SurfaceData:getWidth() return self.lw end
function SurfaceData:getHeight() return self.lh end
function SurfaceData:encode() return nil end
function SurfaceData:getFormat() return "rgba8" end

local function detectDPI(path)
  if type(path) ~= "string" then return 1 end
  local s = path:match("@(%d+%.?%d*)x%.[%a]+$")
  return tonumber(s) or 1
end

function G.newImage(src, settings)
  settings = settings or {}
  local dpiscale = settings.dpiscale
  if type(src) == "table" and getmetatable(src) == SurfaceData then
    -- canvas snapshot: share the pixels
    local img = makeTexture(Image, src.lw, src.lh, dpiscale or src.dpiscale, src.surf)
    stats.images = stats.images + 1
    return img
  end
  local imageData
  if type(src) == "string" then
    dpiscale = dpiscale or detectDPI(src)
    imageData = love.image.newImageData(src)
  elseif type(src) == "userdata" and src.typeOf and src:typeOf("ImageData") then
    imageData = src
  elseif type(src) == "userdata" and src.typeOf and (src:typeOf("FileData") or src:typeOf("File")) then
    dpiscale = dpiscale or detectDPI(src.getFilename and src:getFilename() or nil)
    imageData = love.image.newImageData(src)
  else
    error("newImage: unsupported source " .. tostring(src))
  end
  dpiscale = dpiscale or 1
  local pw, ph = imageData:getDimensions()
  local lw, lh = pw / dpiscale, ph / dpiscale
  local sw = max(1, floor(lw * RENDER_SCALE + 0.5))
  local sh = max(1, floor(lh * RENDER_SCALE + 0.5))
  local surf = newSurface(sw, sh)
  M.m2d_surface_upload_rgba(surf, ffi.cast("const uint8_t*", imageData:getFFIPointer()), pw, ph)
  if imageData ~= src then imageData:release() end
  stats.images = stats.images + 1
  local img = makeTexture(Image, lw, lh, dpiscale, surf)
  if type(src) == "string" then img.debugName = src end
  if G._imageLog then G._imageLog[#G._imageLog + 1] = { name = img.debugName or "?", bytes = sw * sh * 4, w = sw, h = sh } end
  img.opaque = M.m2d_surface_is_opaque(surf) == 1
  if not img.opaque then M.m2d_surface_build_spans(surf) end
  return img
end

function Image:replacePixels(imageData)
  local pw, ph = imageData:getDimensions()
  M.m2d_surface_upload_rgba(self.surf, ffi.cast("const uint8_t*", imageData:getFFIPointer()), pw, ph)
  self.opaque = M.m2d_surface_is_opaque(self.surf) == 1
  if not self.opaque then M.m2d_surface_build_spans(self.surf) end
  self.scaled, self.noScaleCache = nil, nil
end

function G.newCanvas(w, h, settings)
  if type(h) == "table" then settings, h = h, nil end
  settings = settings or {}
  w = w or screenW
  h = h or screenH
  local sw = max(1, floor(w * RENDER_SCALE + 0.5))
  local sh = max(1, floor(h * RENDER_SCALE + 0.5))
  if w == 1280 and h == 720 and sw >= screenW and sh <= screenH then
    -- Panel Attack's global 1280x720 canvas: alias it straight into the back
    -- buffer so presenting it needs no copy. Wider than the screen -> crop the
    -- sides (fill mode); shorter -> letterbox.
    local vy = floor((screenH - sh) / 2)
    local vh = min(sh, screenH)
    local view = ffi.gc(M.m2d_surface_view(back, 0, vy, screenW, vh), M.m2d_surface_view_free)
    local c = makeTexture(Canvas, w, h, settings.dpiscale or 1, view)
    c.__isCanvas = true
    c.scale = RENDER_SCALE
    c.ox = (w * RENDER_SCALE - screenW) / 2 -- cropped pixels on the left
    c.oy = 0
    c.screenView = { 0, vy, screenW, vh }
    G._screenView = c
    stats.canvases = stats.canvases + 1
    return c
  end
  local c = makeTexture(Canvas, w, h, settings.dpiscale or 1, newSurface(sw, sh))
  c.__isCanvas = true
  c.scale = sw / w
  c.ox, c.oy = 0, 0
  stats.canvases = stats.canvases + 1
  return c
end

function Canvas:renderTo(fn, ...)
  local prev = target
  G.setCanvas(self)
  fn(...)
  if prev.isScreen then G.setCanvas() else G.setCanvas(prev.canvas) end
end

function Canvas:newImageData()
  local d = setmetatable({ lw = self.lw, lh = self.lh, dpiscale = self.dpiscale }, SurfaceData)
  d.surf = newSurface(self.surf.w, self.surf.h)
  M.m2d_surface_copy(d.surf, self.surf)
  return d
end

function G.readbackTexture(tex)
  return tex:newImageData()
end
Image.newImageData = Canvas.newImageData

---------------------------------------------------------------------------
-- Quad
---------------------------------------------------------------------------
local Quad = makeType("Quad")
function G.newQuad(x, y, w, h, sw, sh)
  if type(sw) == "table" then sw, sh = sw:getDimensions() end
  return setmetatable({ x = x, y = y, w = w, h = h, sw = sw, sh = sh }, Quad)
end
function Quad:getViewport() return self.x, self.y, self.w, self.h end
function Quad:setViewport(x, y, w, h, sw, sh)
  self.x, self.y, self.w, self.h = x, y, w, h
  if sw then self.sw, self.sh = sw, sh end
end
function Quad:getTextureDimensions() return self.sw, self.sh end
function Quad:setLayer() end
function Quad:getLayer() return 1 end

---------------------------------------------------------------------------
-- drawing textures
---------------------------------------------------------------------------
local function drawTexture(tex, q, x, y, r, sx, sy, ox, oy)
  x = x or 0; y = y or 0
  sx = sx or 1; sy = sy or sx
  ox = ox or 0; oy = oy or 0
  local surf = tex.surf
  local qx, qy, qw, qh
  local spx, spy, spw, sph
  if q then
    qx, qy, qw, qh = q.x, q.y, q.w, q.h
    local fx, fy = surf.w / q.sw, surf.h / q.sh
    spx, spy = floor(qx * fx + 0.5), floor(qy * fy + 0.5)
    spw, sph = max(1, floor((qx + qw) * fx + 0.5) - spx), max(1, floor((qy + qh) * fy + 0.5) - spy)
  else
    qw, qh = tex.lw, tex.lh
    spx, spy, spw, sph = 0, 0, surf.w, surf.h
  end
  local lx0 = x - ox * sx
  local ly0 = y - oy * sy
  local dx, dy, dw, dh, flip = pixelRect(lx0, ly0, lx0 + qw * sx, ly0 + qh * sy)
  if dw <= 0 or dh <= 0 then return end

  if tex.screenView and target.isScreen then
    return -- the game canvas already lives in the back buffer
  end

  local b = blend
  if tex.opaque and b == 1 and tint == NOTINT then b = 0 end

  -- off-by-one from rounding: draw 1:1 instead of rescaling
  if dw ~= spw and (dw - spw == 1 or spw - dw == 1) then dw = spw end
  if dh ~= sph and (dh - sph == 1 or sph - dh == 1) then dh = sph end

  -- scaled draws of static images: blit from a cached pre-scaled copy instead
  if (dw ~= spw or dh ~= sph) and not tex.__isCanvas and not tex.noScaleCache then
    local kx, ky = dw / spw, dh / sph
    if kx > 0.05 and kx < 8 and ky > 0.05 and ky < 8 then
      local key = floor(kx * 512 + 0.5) * 65536 + floor(ky * 512 + 0.5)
      local cache = tex.scaled
      if not cache then cache = { n = 0 }; tex.scaled = cache end
      local sc = cache[key]
      if not sc then
        if cache.n >= 6 then
          tex.noScaleCache = true -- animated scaling: stop caching this texture
        else
          local nw, nh = max(1, floor(surf.w * kx + 0.5)), max(1, floor(surf.h * ky + 0.5))
          sc = newSurface(nw, nh)
          stats.scalecache = (stats.scalecache or 0) + nw * nh * 4
          if G._imageLog then print(string.format("[cache] %s %dx%d -> %dx%d", tostring(tex.debugName), surf.w, surf.h, nw, nh)) end
          M.m2d_surface_resample(sc, surf)
          M.m2d_surface_build_spans(sc)
          cache[key] = sc
          cache.n = cache.n + 1
        end
      end
      if sc then
        surf = sc
        spx, spy = floor(spx * kx + 0.5), floor(spy * ky + 0.5)
        spw, sph = dw, dh
        if spx + spw > sc.w then spx = max(0, sc.w - spw) end
        if spy + sph > sc.h then spy = max(0, sc.h - sph) end
      end
    end
  end

  if pendingClear and target.canvas == G._screenView then
    local ts = target.surf
    if b == 0 and not scissor and not stencilActive and dx <= 0 and dy <= 0 and dx + dw >= ts.w and dy + dh >= ts.h then
      pendingClear = nil -- fully covered by an opaque image: skip the clear
    else
      flushClear()
    end
  end
  stats.drawcalls = stats.drawcalls + 1
  if G._traceAll then
    G._traceAll[#G._traceAll + 1] = string.format("%s|%d|%d", tostring(tex.debugName or (tex.__isCanvas and "canvas") or "?"), dw * dh, b)
  end
  if G._traceBig and dw * dh > 8000 then
    print(string.format("[big] %dx%d at %d,%d blend %d tint %s opaque %s canvas %s src %s", dw, dh, dx, dy, b,
      tint == NOTINT and "-" or string.format("%08x", tint), tostring(tex.opaque), tostring(tex.__isCanvas), tostring(tex.debugName)))
  end
  M.m2d_blit(surf, spx, spy, spw, sph, target.surf, dx, dy, dw, dh, tint, b, flip)
end

---------------------------------------------------------------------------
-- Fonts
---------------------------------------------------------------------------
local Font = makeType("Font")
local PAGE = 256

local defaultFontCache = {}

function G.newFont(a, b, c, d)
  -- newFont(size) | newFont(size, hinting, dpiscale) | newFont(path, size, hinting, dpiscale)
  local path, size, hinting, dpiscale
  if type(a) == "number" or a == nil then
    size, hinting, dpiscale = a or 12, b, c
  else
    path, size, hinting, dpiscale = a, b or 12, c, d
  end
  local px = max(5, floor(size * RENDER_SCALE + 0.5))
  local ok, rast
  if path then
    ok, rast = pcall(love.font.newRasterizer, path, px, hinting or "normal")
    if not ok then
      print("font load failed, using default: " .. tostring(path) .. " " .. tostring(rast))
      rast = love.font.newRasterizer(px, hinting or "normal")
    end
  else
    rast = love.font.newRasterizer(px, hinting or "normal")
  end
  local f = setmetatable({}, Font)
  f.rast = rast
  f.size = size
  f.px = px
  f.fs = px / size          -- pixels per logical unit
  f.dpiscale = dpiscale or 1
  f.glyphs = {}
  f.pages = {}
  f.penX, f.penY, f.rowH = PAGE, PAGE, 0 -- forces new page on first glyph
  f.lineHeight = 1
  f.height = rast:getHeight() / f.fs
  f.ascent = rast:getAscent() / f.fs
  f.descent = rast:getDescent() / f.fs
  f.baseline = f.ascent
  f.fallbacks = {}
  f.widthCache, f.widthCacheN = {}, 0
  f.wrapCache, f.wrapCacheN = {}, 0
  stats.fonts = stats.fonts + 1
  return f
end

function G.setNewFont(...)
  local f = G.newFont(...)
  G.setFont(f)
  return f
end

local function newPage(f)
  local p = newSurface(PAGE, PAGE)
  f.pages[#f.pages + 1] = p
  f.penX, f.penY, f.rowH = 0, 0, 0
  return p
end

local function getGlyph(f, cp)
  local g = f.glyphs[cp]
  if g then return g end
  local rast = f.rast
  if not rast:hasGlyphs(cp) then
    for _, fb in ipairs(f.fallbacks) do
      if fb.rast:hasGlyphs(cp) then rast = fb.rast; break end
    end
  end
  local ok, gd = pcall(rast.getGlyphData, rast, cp)
  if not ok then
    g = { w = 0, h = 0, adv = f.px * 0.5 }
    f.glyphs[cp] = g
    return g
  end
  local gw, gh = gd:getDimensions()
  local bx, by = gd:getBearing()
  g = { w = gw, h = gh, bx = bx, by = by, adv = gd:getAdvance() }
  if gw > 0 and gh > 0 then
    if gw > PAGE or gh > PAGE then gw, gh = min(gw, PAGE), min(gh, PAGE) end
    if f.penX + gw > PAGE then
      f.penX = 0; f.penY = f.penY + f.rowH + 1; f.rowH = 0
    end
    if #f.pages == 0 or f.penY + gh > PAGE then newPage(f) end
    local page = f.pages[#f.pages]
    M.m2d_surface_upload_la8(page, ffi.cast("const uint8_t*", gd:getFFIPointer()), f.penX, f.penY, gw, gh)
    g.page, g.x, g.y = page, f.penX, f.penY
    f.penX = f.penX + gw + 1
    f.rowH = max(f.rowH, gh)
  end
  gd:release()
  f.glyphs[cp] = g
  return g
end

local byte = string.byte
local function asciiIter(s, i)
  i = i + 1
  local b = byte(s, i)
  if b then return i, b end
end
local function codepoints(s)
  if not s:find("[\128-\255]") then return asciiIter, s, 0 end
  if utf8.len(s) then return utf8.codes(s) end
  -- invalid utf8: fall back to bytes
  local i = 0
  return function()
    i = i + 1
    if i <= #s then return i, s:byte(i) end
  end
end

function Font:getWidth(s)
  s = tostring(s)
  local wc = self.widthCache
  local cached = wc[s]
  if cached then return cached end
  if self.widthCacheN > 1024 then wc = {}; self.widthCache = wc; self.widthCacheN = 0 end
  local w, best = 0, 0
  for _, cp in codepoints(s) do
    if cp == 10 then
      best = max(best, w); w = 0
    else
      w = w + getGlyph(self, cp).adv
    end
  end
  local result = max(best, w) / self.fs
  wc[s] = result
  self.widthCacheN = self.widthCacheN + 1
  return result
end
function Font:getHeight() return self.height end
function Font:getLineHeight() return self.lineHeight end
function Font:setLineHeight(h) self.lineHeight = h end
function Font:getAscent() return self.ascent end
function Font:getDescent() return self.descent end
function Font:getBaseline() return self.baseline end
function Font:getDPIScale() return self.dpiscale end
function Font:setFilter() end
function Font:getFilter() return "linear", "linear", 1 end
function Font:hasGlyphs(...) return self.rast:hasGlyphs(...) end
function Font:getKerning() return 0 end
function Font:setFallbacks(...) self.fallbacks = { ... } end

-- greedy word wrap; returns maxWidth, lines (cached per text+limit)
local function wrapUncached(self, text, limit)
  if type(text) == "table" then
    local parts = {}
    for i = 2, #text, 2 do parts[#parts + 1] = tostring(text[i]) end
    text = table.concat(parts)
  end
  text = tostring(text)
  local lines, maxW = {}, 0
  for para in (text .. "\n"):gmatch("(.-)\r?\n") do
    local line, lineW = "", 0
    local spaceW = self:getWidth(" ")
    for word, spaces in para:gmatch("(%S*)(%s*)") do
      if word == "" and spaces == "" then break end
      local wordW = self:getWidth(word)
      if line ~= "" and lineW + wordW > limit then
        lines[#lines + 1] = line
        maxW = max(maxW, lineW)
        line, lineW = "", 0
      end
      -- break over-long words by characters
      if wordW > limit and line == "" then
        local chunk, chunkW = "", 0
        for _, cp in codepoints(word) do
          local ch = utf8.char(cp)
          local cw = self:getWidth(ch)
          if chunkW + cw > limit and chunk ~= "" then
            lines[#lines + 1] = chunk
            maxW = max(maxW, chunkW)
            chunk, chunkW = "", 0
          end
          chunk, chunkW = chunk .. ch, chunkW + cw
        end
        line, lineW = chunk, chunkW
      else
        line, lineW = line .. word, lineW + wordW
      end
      if spaces ~= "" then
        local sw = #spaces * spaceW
        line, lineW = line .. spaces, lineW + sw
      end
    end
    -- trailing spaces don't count for width
    local trimmed = line:gsub("%s+$", "")
    lineW = self:getWidth(trimmed)
    lines[#lines + 1] = trimmed
    maxW = max(maxW, lineW)
  end
  return maxW, lines
end

function Font:getWrap(text, limit)
  if type(text) ~= "string" then return wrapUncached(self, text, limit) end
  local key = text .. "\0" .. limit
  local c = self.wrapCache[key]
  if not c then
    if self.wrapCacheN > 256 then self.wrapCache = {}; self.wrapCacheN = 0 end
    local w, lines = wrapUncached(self, text, limit)
    c = { w, lines }
    self.wrapCache[key] = c
    self.wrapCacheN = self.wrapCacheN + 1
  end
  -- callers may modify the returned table, so hand out a copy
  local lines = {}
  for i = 1, #c[2] do lines[i] = c[2][i] end
  return c[1], lines
end

-- flatten coloured text {c1, s1, c2, s2, ...} into segments
local function segments(text)
  if type(text) ~= "table" then return { { nil, tostring(text) } } end
  local segs = {}
  for i = 1, #text, 2 do
    local c, s = text[i], text[i + 1]
    if type(c) == "string" or type(c) == "number" then
      segs[#segs + 1] = { nil, tostring(c) }
      if s then segs[#segs + 1] = { nil, tostring(s) } end
    else
      segs[#segs + 1] = { c, tostring(s or "") }
    end
  end
  return segs
end

local function drawGlyphRun(f, s, pen, baseY, x, y, sx, sy, ox, oy, colorTint)
  prepTarget()
  local fs = f.fs
  local tsurf = target.surf
  for _, cp in codepoints(s) do
    local g = getGlyph(f, cp)
    if g.page then
      local lx = x + ((pen + g.bx) / fs - ox) * sx
      local ly = y + ((baseY - g.by) / fs - oy) * sy
      local dx, dy, dw, dh, flip = pixelRect(lx, ly, lx + g.w / fs * sx, ly + g.h / fs * sy)
      if dw > 0 and dh > 0 then
        M.m2d_blit(g.page, g.x, g.y, g.w, g.h, tsurf, dx, dy, dw, dh, colorTint, blend, flip)
      end
    end
    pen = pen + g.adv
  end
  return pen
end

local function tintFor(c)
  if not c then return tint end
  local r, g, b, a = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
  return premulColor(r * cr, g * cg, b * cb, a * ca)
end

-- draw lines of (possibly coloured) text; align within limit (logical)
local function drawText(f, text, x, y, limit, align, sx, sy, ox, oy)
  f = f or curFont
  sx = sx or 1; sy = sy or sx
  ox = ox or 0; oy = oy or 0
  stats.drawcalls = stats.drawcalls + 1
  local fs = f.fs
  local lineStep = f.height * f.lineHeight * fs -- in font pixels
  local ascentPx = f.ascent * fs
  local segs = segments(text)

  if not limit then
    -- simple print: honour newlines, colours per segment
    local pen, lineNo = 0, 0
    for _, seg in ipairs(segs) do
      local ct = tintFor(seg[1])
      local first = true
      for part in (seg[2] .. "\n"):gmatch("(.-)\n") do
        if not first then lineNo = lineNo + 1; pen = 0 end
        first = false
        pen = drawGlyphRun(f, part, pen, lineNo * lineStep + ascentPx, x, y, sx, sy, ox, oy, ct)
      end
    end
    return
  end

  -- printf: wrap the plain text, colour by the first segment's colour
  local plain = {}
  for _, seg in ipairs(segs) do plain[#plain + 1] = seg[2] end
  local _, lines = f:getWrap(table.concat(plain), limit)
  local ct = tintFor(segs[1] and segs[1][1])
  for i, line in ipairs(lines) do
    local w = f:getWidth(line)
    local offset = 0
    if align == "center" then offset = (limit - w) / 2
    elseif align == "right" then offset = limit - w end
    drawGlyphRun(f, line, offset * fs, (i - 1) * lineStep + ascentPx, x, y, sx, sy, ox, oy, ct)
  end
end

function G.print(text, x, y, r, sx, sy, ox, oy)
  if type(x) == "table" then x, y, r, sx, sy, ox, oy = 0, 0, 0, 1, 1, 0, 0 end
  drawText(curFont, text, x or 0, y or 0, nil, nil, sx, sy, ox, oy)
end

function G.printf(text, x, y, limit, align, r, sx, sy, ox, oy)
  if type(x) == "table" then error("printf with transform not supported") end
  drawText(curFont, text, x or 0, y or 0, limit or 1e9, align or "left", sx, sy, ox, oy)
end

---------------------------------------------------------------------------
-- Text objects
---------------------------------------------------------------------------
local Text = makeType("Text", { "Drawable", "TextBatch" })
function G.newText(font, text)
  local t = setmetatable({ font = font or curFont, items = {} }, Text)
  if text then t:set(text) end
  return t
end
G.newTextBatch = G.newText
function Text:set(text) self.items = { { text = text, x = 0, y = 0 } } end
function Text:setf(text, limit, align) self.items = { { text = text, x = 0, y = 0, limit = limit, align = align } } end
function Text:add(text, x, y) self.items[#self.items + 1] = { text = text, x = x or 0, y = y or 0 }; return #self.items end
function Text:addf(text, limit, align, x, y)
  self.items[#self.items + 1] = { text = text, x = x or 0, y = y or 0, limit = limit, align = align }
  return #self.items
end
function Text:clear() self.items = {} end
function Text:setFont(f) self.font = f end
function Text:getFont() return self.font end
function Text:getDimensions(index)
  local w, h = 0, 0
  for i, it in ipairs(self.items) do
    if not index or index == i then
      local iw, lines
      if it.limit then
        iw, lines = self.font:getWrap(it.text, it.limit)
        if it.align == "center" or it.align == "right" then iw = it.limit end
      else
        local plain = it.text
        if type(plain) == "table" then
          local p = {}
          for j = 2, #plain, 2 do p[#p + 1] = tostring(plain[j]) end
          plain = table.concat(p)
        end
        plain = tostring(plain)
        iw = self.font:getWidth(plain)
        local n = 1
        for _ in plain:gmatch("\n") do n = n + 1 end
        lines = {}
        for k = 1, n do lines[k] = true end
      end
      w = max(w, it.x + iw)
      h = max(h, it.y + #lines * self.font:getHeight() * self.font:getLineHeight())
    end
  end
  return w, h
end
function Text:getWidth(i) return (self:getDimensions(i)) end
function Text:getHeight(i) local _, h = self:getDimensions(i); return h end

local function drawTextObject(t, x, y, r, sx, sy, ox, oy)
  x = x or 0; y = y or 0
  sx = sx or 1; sy = sy or sx
  ox = ox or 0; oy = oy or 0
  for _, it in ipairs(t.items) do
    drawText(t.font, it.text, x + (it.x - ox) * sx, y + (it.y - oy) * sy, it.limit, it.align, sx, sy, 0, 0)
  end
end

---------------------------------------------------------------------------
-- SpriteBatch
---------------------------------------------------------------------------
local SpriteBatch = makeType("SpriteBatch", { "Drawable" })
function G.newSpriteBatch(texture, size, usage)
  return setmetatable({ texture = texture, items = {}, n = 0 }, SpriteBatch)
end
function SpriteBatch:add(q, x, y, r, sx, sy, ox, oy)
  if type(q) ~= "table" or getmetatable(q) ~= Quad then
    q, x, y, r, sx, sy, ox, oy = nil, q, x, y, r, sx, sy, ox
  end
  self.n = self.n + 1
  local it = self.items[self.n]
  if not it then it = {}; self.items[self.n] = it end
  -- like LÖVE, take a copy of the quad's viewport now: callers reuse one quad
  -- object and change its viewport between adds
  if q then
    local cq = it.cq
    if not cq then cq = setmetatable({}, Quad); it.cq = cq end
    cq.x, cq.y, cq.w, cq.h, cq.sw, cq.sh = q.x, q.y, q.w, q.h, q.sw, q.sh
    q = cq
  end
  it.q, it.x, it.y, it.sx, it.sy, it.ox, it.oy = q, x or 0, y or 0, sx or 1, sy or sx or 1, ox or 0, oy or 0
  it.tint = tint ~= NOTINT and tint or nil
  return self.n
end
function SpriteBatch:set(id, ...)
  local n = self.n
  self.n = id - 1
  self:add(...)
  self.n = max(n, id)
end
function SpriteBatch:clear() self.n = 0 end
function SpriteBatch:flush() end
function SpriteBatch:setColor() end
function SpriteBatch:getCount() return self.n end
function SpriteBatch:getBufferSize() return max(self.n, 1000) end
function SpriteBatch:getTexture() return self.texture end
function SpriteBatch:setTexture(t) self.texture = t end
function SpriteBatch:setDrawRange() end

local function drawSpriteBatch(b, x, y, r, sx, sy, ox, oy)
  G.push()
  G.translate(x or 0, y or 0)
  if sx then G.scale(sx, sy or sx) end
  if ox then G.translate(-ox, -(oy or 0)) end
  local tex = b.texture
  for i = 1, b.n do
    local it = b.items[i]
    drawTexture(tex, it.q, it.x, it.y, 0, it.sx, it.sy, it.ox, it.oy)
  end
  G.pop()
end

---------------------------------------------------------------------------
-- draw dispatch
---------------------------------------------------------------------------
function G.draw(d, a, ...)
  if d == nil then return end
  local mt = getmetatable(d)
  if mt == Image or mt == Canvas then
    if type(a) == "table" and getmetatable(a) == Quad then
      drawTexture(d, a, ...)
    else
      drawTexture(d, nil, a, ...)
    end
  elseif mt == Text then
    drawTextObject(d, a, ...)
  elseif mt == SpriteBatch then
    drawSpriteBatch(d, a, ...)
  end
end
G.drawLayer = function() end
G.drawInstanced = function() end

---------------------------------------------------------------------------
-- primitives
---------------------------------------------------------------------------
local function lineWidthPx()
  return max(1, floor(lineWidth * math.abs(tsx) * target.scale + 0.5))
end

function G.rectangle(mode, x, y, w, h)
  local dx, dy, dw, dh = pixelRect(x, y, x + w, y + h)
  if capturingStencil then
    stencilRect = { dx, dy, dx + dw, dy + dh }
    return
  end
  if mode == "fill" and pendingClear and target.canvas == G._screenView and ca >= 1
    and not scissor and not stencilActive then
    local ts = target.surf
    if dx <= 0 and dy <= 0 and dx + dw >= ts.w and dy + dh >= ts.h then
      pendingClear = fillColor -- an opaque full-screen fill is just a clear in another colour
      return
    end
  end
  prepTarget()
  stats.drawcalls = stats.drawcalls + 1
  local surf = target.surf
  if mode == "fill" then
    M.m2d_fill(surf, dx, dy, dw, dh, fillColor, blend)
  else
    local lw = lineWidthPx()
    local half = floor(lw / 2)
    dx, dy = dx - half, dy - half
    dw, dh = dw + lw, dh + lw
    M.m2d_fill(surf, dx, dy, dw, lw, fillColor, blend)
    M.m2d_fill(surf, dx, dy + dh - lw, dw, lw, fillColor, blend)
    M.m2d_fill(surf, dx, dy + lw, lw, dh - 2 * lw, fillColor, blend)
    M.m2d_fill(surf, dx + dw - lw, dy + lw, lw, dh - 2 * lw, fillColor, blend)
  end
end

function G.line(...)
  local pts = { ... }
  if type(pts[1]) == "table" then pts = pts[1] end
  local lw = lineWidthPx()
  stats.drawcalls = stats.drawcalls + 1
  prepTarget()
  for i = 1, #pts - 3, 2 do
    local x0, y0 = toPixel(pts[i], pts[i + 1])
    local x1, y1 = toPixel(pts[i + 2], pts[i + 3])
    M.m2d_line(target.surf, floor(x0 + 0.5), floor(y0 + 0.5), floor(x1 + 0.5), floor(y1 + 0.5), lw, fillColor, blend)
  end
end

function G.circle(mode, x, y, r)
  local px, py = toPixel(x, y)
  local pr = floor(r * math.abs(tsx) * target.scale + 0.5)
  stats.drawcalls = stats.drawcalls + 1
  prepTarget()
  M.m2d_circle(target.surf, floor(px + 0.5), floor(py + 0.5), pr, fillColor, blend, mode == "fill" and 1 or 0, lineWidthPx())
end

function G.ellipse(mode, x, y, rx, ry) G.circle(mode, x, y, (rx + (ry or rx)) / 2) end
function G.arc() end
function G.points() end

function G.polygon(mode, ...)
  -- approximate with the bounding box outline / fill
  local pts = { ... }
  if type(pts[1]) == "table" then pts = pts[1] end
  if mode == "line" then
    local closed = {}
    for i = 1, #pts do closed[i] = pts[i] end
    closed[#closed + 1], closed[#closed + 2] = pts[1], pts[2]
    G.line(closed)
    return
  end
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for i = 1, #pts - 1, 2 do
    x0, x1 = min(x0, pts[i]), max(x1, pts[i])
    y0, y1 = min(y0, pts[i + 1]), max(y1, pts[i + 1])
  end
  if x0 < x1 then G.rectangle("fill", x0, y0, x1 - x0, y1 - y0) end
end

---------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------
function G.setColor(r, g, b, a)
  if type(r) == "table" then r, g, b, a = r[1], r[2], r[3], r[4] end
  cr, cg, cb, ca = r or 1, g or 1, b or 1, a or 1
  updateColor()
end
function G.getColor() return cr, cg, cb, ca end

function G.setBackgroundColor(r, g, b, a)
  if type(r) == "table" then r, g, b, a = r[1], r[2], r[3], r[4] end
  bgr, bgg, bgb, bga = r or 0, g or 0, b or 0, a or 1
end
function G.getBackgroundColor() return bgr, bgg, bgb, bga end

function G.setBlendMode(mode, alphamode)
  blendName, alphaModeName = mode or "alpha", alphamode or "alphamultiply"
  if mode == "add" then blend = 2
  elseif mode == "replace" or mode == "none" then blend = 0
  else blend = 1 end
end
function G.getBlendMode() return blendName, alphaModeName end

function G.setLineWidth(w) lineWidth = w or 1 end
function G.getLineWidth() return lineWidth end
function G.setLineStyle() end
function G.getLineStyle() return "smooth" end
function G.setLineJoin() end
function G.getLineJoin() return "miter" end
function G.setPointSize() end
function G.getPointSize() return 1 end

function G.setFont(f) if f then curFont = f end end
function G.getFont()
  if not curFont then curFont = G.newFont(12) end
  return curFont
end

function G.setDefaultFilter(a, b) defaultFilterMin, defaultFilterMag = a, b or a end
function G.getDefaultFilter() return defaultFilterMin, defaultFilterMag, 1 end
function G.setColorMask() end
function G.getColorMask() return true, true, true, true end
function G.setWireframe() end
function G.isWireframe() return false end
function G.setDepthMode() end
function G.setMeshCullMode() end
function G.setFrontFaceWinding() end

-- shaders: accepted and ignored
local Shader = makeType("Shader")
function Shader:send() end
function Shader:sendColor() end
function Shader:hasUniform() return false end
function Shader:getWarnings() return "" end
function G.newShader() return setmetatable({}, Shader) end
function G.setShader(s) shader = s end
function G.getShader() return shader end
function G.validateShader() return true end

-- scissor (target logical coordinates)
function G.setScissor(x, y, w, h)
  if x then scissor = { x, y, w, h } else scissor = nil end
  applyClip()
end
function G.intersectScissor(x, y, w, h)
  if not scissor then return G.setScissor(x, y, w, h) end
  local x0, y0 = max(scissor[1], x), max(scissor[2], y)
  local x1 = min(scissor[1] + scissor[3], x + w)
  local y1 = min(scissor[2] + scissor[4], y + h)
  G.setScissor(x0, y0, max(0, x1 - x0), max(0, y1 - y0))
end
function G.getScissor()
  if scissor then return scissor[1], scissor[2], scissor[3], scissor[4] end
end

-- stencil: only rectangles, turned into a clip rect
function G.stencil(fn, action, value, keep)
  capturingStencil = true
  stencilRect = nil
  local ok, err = pcall(fn)
  capturingStencil = false
  if not ok then error(err) end
  applyClip()
end
function G.setStencilTest(compare, value)
  stencilActive = compare ~= nil
  applyClip()
end
function G.getStencilTest() return stencilActive and "greater" or "always", 0 end
function G.setStencilMode(mode, value)
  if mode == "draw" then capturingStencil = true; stencilRect = nil
  elseif mode == "test" then capturingStencil = false; stencilActive = true
  else capturingStencil = false; stencilActive = false end
  applyClip()
end

-- render targets
function G.setCanvas(c, ...)
  if type(c) == "table" and getmetatable(c) ~= Canvas then c = c[1] end
  if c then
    target = { surf = c.surf, scale = c.scale, canvas = c, ox = c.ox or 0, oy = c.oy or 0 }
  else
    target = screenTarget
  end
  stats.canvasswitches = stats.canvasswitches + 1
  applyClip()
end
function G.getCanvas()
  if target.isScreen then return nil end
  return target.canvas
end

function G.clear(r, g, b, a, ...)
  if type(r) == "table" then r, g, b, a = r[1], r[2], r[3], r[4] end
  local color
  if r == nil then
    color = 0
  else
    color = premulColor(r, g or 0, b or 0, a or 1)
  end
  local view = G._screenView
  if target.isScreen and view and not scissor then
    -- only the letterbox bands; the game canvas clears its own area
    local v = view.screenView
    M.m2d_fill(target.surf, 0, 0, screenW, v[2], color, 0)
    M.m2d_fill(target.surf, 0, v[2] + v[4], screenW, screenH - v[2] - v[4], color, 0)
    return
  end
  if target.canvas and target.canvas == view and not scissor then
    pendingClear = color
    return
  end
  prepTarget()
  M.m2d_clear(target.surf, color, 1)
end
function G.discard() end

-- transforms (rotation / shear ignored)
function G.push(kind)
  local s = { tsx, tsy, ttx, tty }
  if kind == "all" then
    s.all = true
    s.color = { cr, cg, cb, ca }
    s.blend = { blendName, alphaModeName }
    s.font = curFont
    s.lineWidth = lineWidth
    s.scissor = scissor
    s.target = target
    s.shader = shader
    s.stencilActive = stencilActive
  end
  tstack[#tstack + 1] = s
end
function G.pop()
  local s = tstack[#tstack]
  if not s then return end
  tstack[#tstack] = nil
  tsx, tsy, ttx, tty = s[1], s[2], s[3], s[4]
  if s.all then
    cr, cg, cb, ca = s.color[1], s.color[2], s.color[3], s.color[4]
    updateColor()
    G.setBlendMode(s.blend[1], s.blend[2])
    curFont = s.font
    lineWidth = s.lineWidth
    scissor = s.scissor
    target = s.target
    shader = s.shader
    stencilActive = s.stencilActive
    applyClip()
  end
end
function G.origin() tsx, tsy, ttx, tty = 1, 1, 0, 0 end
function G.translate(x, y)
  ttx = ttx + tsx * (x or 0)
  tty = tty + tsy * (y or 0)
end
function G.scale(sx, sy)
  sx = sx or 1
  sy = sy or sx
  tsx, tsy = tsx * sx, tsy * sy
end
function G.rotate() end
function G.shear() end
function G.transformPoint(x, y) return ttx + tsx * x, tty + tsy * y end
function G.inverseTransformPoint(x, y) return (x - ttx) / tsx, (y - tty) / tsy end
function G.applyTransform() end
function G.replaceTransform() end

function G.reset()
  G.origin()
  G.setColor(1, 1, 1, 1)
  G.setBlendMode("alpha")
  lineWidth = 1
  scissor = nil
  stencilActive = false
  shader = nil
  target = screenTarget
  bgr, bgg, bgb, bga = 0, 0, 0, 1
  applyClip()
end

---------------------------------------------------------------------------
-- queries / misc
---------------------------------------------------------------------------
function G.getWidth() return screenW end
function G.getHeight() return screenH end
function G.getDimensions() return screenW, screenH end
function G.getPixelWidth() return screenW end
function G.getPixelHeight() return screenH end
function G.getPixelDimensions() return screenW, screenH end
function G.getDPIScale() return 1 end
function G.isActive() return true end
function G.isCreated() return true end
function G.isGammaCorrect() return false end
function G.getRendererInfo() return "mini2d", "1.0", "SigmaStar", "Miyoo Mini Plus (CPU)" end
function G.getStats() return stats end
function G.getSystemLimits()
  return { texturesize = 4096, multicanvas = 1, canvasmsaa = 1, pointsize = 1, texturelayers = 1, volumetexturesize = 1,
    cubetexturesize = 1, anisotropy = 1 }
end
function G.getSupported()
  return { clampzero = false, lighten = false, multicanvasformats = false, glsl3 = false, instancing = false,
    fullnpot = true, pixelshaderhighp = false, shaderderivatives = false }
end
function G.getCanvasFormats() return { normal = true, rgba8 = true } end
function G.getImageFormats() return { rgba8 = true } end
function G.getTextureTypes() return { ["2d"] = true } end
function G.captureScreenshot() end
function G.flushBatch() end
function G.getStackDepth() return #tstack end

local OSK
function G.present()
  OSK = OSK or require("miyoo.osk")
  flushClear()
  if OSK.active then OSK.draw(G) end
  M.m2d_present()
  stats.drawcalls = 0
  stats.canvasswitches = 0
end

-- expose internals for the input/boot code
G._types = { Image = Image, Canvas = Canvas, Quad = Quad, Font = Font, Text = Text, SpriteBatch = SpriteBatch }

function G._init(w, h)
  screenW, screenH = w, h
  local rc = M.m2d_init(w, h)
  if rc ~= 0 then error("mini2d init failed: " .. rc) end
  back = M.m2d_backbuffer()
  screenTarget.surf = back
  G.reset()
end

return G
