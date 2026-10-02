-- Handheld styling for Panel Attack's menus: flat backgrounds, bigger
-- Rubik text, rounded list rows, and a custom title / main menu screen.

local U = require("miyoo.ui")
local C = U.C
local G = love.graphics

local GraphicsUtil = require("client.src.graphics.graphics_util")
local Theme = require("client.src.mods.Theme")
local ui = require("client.src.ui")

local M = {}

-- base UI text: 13 px on screen (Panel Attack's default is 8 px here)
local BASE_FONT = "miyoo/fonts/Rubik-500.ttf"
local FONT_SCALE = 1.625

---------------------------------------------------------------------------
-- flat backgrounds instead of the 2560x1440 theme pictures
---------------------------------------------------------------------------
local Flat = {}
Flat.__index = Flat
function Flat.new(color) return setmetatable({ color = color }, Flat) end
function Flat:update() end
function Flat:draw()
  local c = self.color
  G.setColor(c[1], c[2], c[3], 1)
  G.rectangle("fill", 0, 0, 1280, 720)
  G.setColor(1, 1, 1, 1)
end
M.Flat = Flat

local function loadMenuGraphics(self)
  self.images.bg_main = Flat.new(C.bg)
  self:loadFont()
  self.images.bg_title = Flat.new(C.bg)
  self.images.bg_select_screen = Flat.new(C.bg)
  self.images.bg_readme = Flat.new(C.bg)
  self.images.IMG_bug = self:load_theme_img("bug")
  self.images.edit = self:load_theme_img("edit")
  self.images.hint = self:load_theme_img("hint")
  self.images.complete = self:load_theme_img("complete")
  self.images.partial = self:load_theme_img("partial")
end

---------------------------------------------------------------------------
-- label text helper
---------------------------------------------------------------------------
local function labelText(label)
  if not label then return "" end
  if label.translate == false then return tostring(label.text or "") end
  local ok, s = pcall(loc, label.text, unpack(label.replacementTable or {}))
  return ok and s or tostring(label.text or "")
end
M.labelText = labelText

---------------------------------------------------------------------------
-- widget skins (drawn in the element's own coordinates)
---------------------------------------------------------------------------
local K = 1 / 1.5 -- canvas units -> screen pixels

local function skinMenuItem(self)
  U.inElement()
  local x, y, w, h = self.x * K, self.y * K, self.width * K, self.height * K
  if self.selected then
    U.rrect(x, y, w, h, 6, C.sel)
    U.rect(x, y + 3, 4, h - 6, C.p1)
  else
    U.rrect(x, y, w, h, 6, C.row)
  end
  U.onScreen()
  U.reset()
end

local function skinButton(self)
  if self.parent and self.parent.TYPE == "MenuItem" then return end
  U.inElement()
  local x, y, w, h = self.x * K, self.y * K, self.width * K, self.height * K
  U.rrect(x, y, w, h, 6, self.currentlyPressed and C.sel or C.card)
  U.onScreen()
  U.reset()
end

-- uniform row widths and a comfortable minimum height for list menus
local MIN_ROW = 42 -- canvas units (28 px)
local function wrapLayout(layout)
  return function(self)
    local items = self.menuItems
    if items and #items > 0 then
      local maxW = 0
      for _, it in ipairs(items) do maxW = math.max(maxW, it.width) end
      maxW = math.max(maxW, 330)
      for _, it in ipairs(items) do
        if it.height < MIN_ROW then it.height = MIN_ROW end
        it.width = maxW
        if it.textButton and #it.children == 1 then
          it.textButton.width = maxW - 2 * ui.MenuItem.PADDING
          it.textButton.height = it.height - 2 * ui.MenuItem.PADDING
        end
      end
    end
    return layout(self)
  end
end

---------------------------------------------------------------------------
-- logo block: six panels and the wordmark
---------------------------------------------------------------------------
local function drawPanelIcon(color, x, y, size)
  local p = panels and panels[config.panels]
  if p and p.drawPanelFrame then
    G.setColor(1, 1, 1, 1)
    p:drawPanelFrame(color, "normal", U.cx(x), U.cy(y), size * 1.5)
  else
    U.rrect(x, y, size, size, 4, C.card)
  end
end

local function drawLogo(x, y, center)
  local size, gap = 40, 4
  local gridW = 3 * size + 2 * gap
  local gx = center and math.floor(x - gridW / 2) or x
  for i = 0, 5 do
    drawPanelIcon(i + 1, gx + (i % 3) * (size + gap), y + math.floor(i / 3) * (size + gap), size)
  end
  local f = U.font("display", 52)
  local ty = y + 2 * size + gap + 14
  local align = center and "center" or "left"
  U.text("PANEL", x, ty, f, C.text, align, nil, 1)
  U.text("ATTACK", x, ty + 50, f, C.text, align, nil, 1)
  return ty + 50 + 58
end

local function versionString()
  local v = os.getenv("PA_VERSION")
  return "Miyoo Mini Plus" .. (v and v ~= "" and (" · " .. v) or "")
end

---------------------------------------------------------------------------
-- title screen
---------------------------------------------------------------------------
local function titleDraw(self)
  Flat.draw({ color = C.bg })
  local bottom = drawLogo(U.W / 2, 70, true)
  local a = ((math.sin(5 * love.timer.getTime()) / 2 + .5) ^ .5) / 2 + .5
  U.text(loc("continue_button"), U.W / 2, bottom + 40, U.font("medium", 18), C.text, "center", nil, nil, a)
  U.text("Unofficial port · not affiliated with the Panel Attack team", U.W / 2, 426, U.font("regular", 12), C.muted, "center")
  U.text(versionString(), U.W / 2, 450, U.font("regular", 12), C.faint, "center")
  U.reset()
end

---------------------------------------------------------------------------
-- main menu
---------------------------------------------------------------------------
local MAIN_NAMES = {
  mm_1_endless = { "Endless", "1P" },
  mm_1_puzzle = { "Puzzles" },
  mm_1_time = { "Time Attack", "1P" },
  mm_1_vs = { "Vs Yourself", "1P" },
  mm_1_training = { "Training" },
  mm_1_challenge_mode = { "Challenge", "vs CPU" },
  mm_2_vs_online = { "Online", "panelattack.com" },
  mm_replay_browser = { "Replays" },
  mm_configure = { "Controls" },
  mm_set_name = { "Set Name" },
  mm_options = { "Options" },
  mm_quit = { "Quit" },
}

local function mainMenuDraw(self)
  Flat.draw({ color = C.bg })
  local bottom = drawLogo(32, 96, false)
  U.text("UNOFFICIAL PORT", 32, bottom + 6, U.font("bold", 13), C.amber, nil, nil, 1)
  U.text("Not affiliated with or supported", 32, bottom + 26, U.font("regular", 12), C.muted)
  U.text("by the Panel Attack team", 32, bottom + 42, U.font("regular", 12), C.muted)
  U.text(versionString(), 32, 400, U.font("regular", 13), C.muted)

  local name = config.name and config.name ~= "" and config.name or "No name set"
  U.text(U.fit(name, U.font("regular", 14), 280), U.W - 24, 10, U.font("regular", 14), C.muted, "right")

  local menu = self.menu
  local items = menu and menu.menuItems or {}
  local english = (config.language_code or "EN") == "EN"
  local x, w = 330, 286
  local rowH, gap, top = 29, 3, 38
  local maxRows = math.floor((436 - top + gap) / (rowH + gap))
  local first = 1
  if #items > maxRows then
    first = math.max(1, math.min(menu.selectedIndex - math.floor(maxRows / 2), #items - maxRows + 1))
  end
  local fN, fB, fS = U.font("medium", 17), U.font("bold", 17), U.font("regular", 12)
  for i = first, math.min(#items, first + maxRows - 1) do
    local it = items[i]
    local label = it.textButton and it.textButton.label
    local key = label and label.text
    local names = english and key and MAIN_NAMES[key]
    local text = names and names[1] or labelText(label)
    local sub = names and names[2]
    if key == "mm_2_vs_online" and os.getenv("PA_SERVER") then sub = os.getenv("PA_SERVER") end
    local y = top + (i - first) * (rowH + gap)
    local sel = (i == menu.selectedIndex)
    if sel then
      U.rrect(x, y, w, rowH, 6, C.sel)
      U.rect(x, y + 3, 4, rowH - 6, C.p1)
    end
    local f = sel and fB or fN
    U.text(text, x + 16, y + math.floor((rowH - f:getHeight() / 1.5) / 2), f, sel and { 1, 1, 1, 1 } or C.dim)
    if sub then U.text(sub, x + w - 14, y + math.floor((rowH - fS:getHeight() / 1.5) / 2), fS, C.muted, "right") end
  end
  U.hintBar({ { "A", "Select" }, { "B", "Back" } })
  U.reset()
end

---------------------------------------------------------------------------
function M.install()
  -- fonts
  -- Panel Attack sizes all UI text relative to a 12-unit global font, which is
  -- 8 px here. Keep its numbers but render every size 1.6x larger in Rubik.
  local setGlobalFont = GraphicsUtil.setGlobalFont
  GraphicsUtil.setGlobalFont = function(path, size, dpiScale)
    if path and (path:find("jp%.ttf") or path:find("th%.otf")) then
      return setGlobalFont(path, size, dpiScale)
    end
    return setGlobalFont(BASE_FONT, 12, dpiScale)
  end
  GraphicsUtil.getGlobalFontWithSize = function(fontSize)
    local f = GraphicsUtil.fontCache[fontSize]
    if not f then
      f = love.graphics.newFont(GraphicsUtil.fontFile or BASE_FONT, fontSize * FONT_SCALE, "normal", GraphicsUtil.fontDpiScale)
      GraphicsUtil.fontCache[fontSize] = f
    end
    return f
  end
  GraphicsUtil.fontFile = BASE_FONT
  GraphicsUtil.fontSize = 12
  GraphicsUtil.fontCache = {}
  ui.MenuItem.PADDING = 12
  GraphicsUtil.drawClearText = function(text, x, y, ox, oy)
    G.setColor(C.text[1], C.text[2], C.text[3], 1)
    G.draw(text, x, y, 0, 1, 1, ox, oy)
    G.setColor(1, 1, 1, 1)
  end

  Theme.loadMenuGraphics = loadMenuGraphics

  ui.MenuItem.drawSelf = skinMenuItem
  ui.Button.drawSelf = skinButton
  ui.Menu.layout = wrapLayout(ui.Menu.layout)

  local TitleScreen = require("client.src.scenes.TitleScreen")
  TitleScreen.draw = titleDraw

  local MainMenu = require("client.src.scenes.MainMenu")
  local create = MainMenu.createMainMenu
  MainMenu.createMainMenu = function(self)
    local menu = create(self)
    for i = #menu.menuItems, 1, -1 do
      local it = menu.menuItems[i]
      local key = it.textButton and it.textButton.label and it.textButton.label.text
      if key == "mm_2_vs_local" then menu:removeMenuItem(it.id) end
      -- Online play is off unless online.cfg says "online = on" (launch.sh exports PA_ONLINE)
      if key == "mm_2_vs_online" and os.getenv("PA_ONLINE") ~= "on" then menu:removeMenuItem(it.id) end
    end
    return menu
  end
  MainMenu.draw = mainMenuDraw
end

return M
