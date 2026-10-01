-- Character select / mode setup screens (Endless, Time Attack, Vs Yourself,
-- online ready-up): same grid and controls as Panel Attack, restyled with
-- rounded cards, a player-coloured cursor, cleaner character tiles and a
-- hint bar.

local U = require("miyoo.ui")
local C = U.C
local G = love.graphics
local ui = require("client.src.ui")

local CS = {}
local K = 1 / 1.5

local function playerColor(player)
  return (player and player.playerNumber == 2) and C.p2 or C.p1
end

-- cards behind the grid's boxed elements instead of white outlines
local function gridElementSkin(self)
  if not self.drawBorders then return end
  U.inElement()
  U.rrect(self.x * K, self.y * K, self.width * K, self.height * K, 8, C.card)
  U.onScreen()
  U.reset()
end

-- a rounded frame in the player's colour around the selected element
local function cursorSkin(self)
  if not self.target then return end
  self.drawClock = self.drawClock + 1
  if self.rapidBlinking then
    local pn = self.player.playerNumber or 1
    if (math.floor(self.drawClock / self.blinkFrequency) + pn) % 2 + 1 ~= pn then return end
  end
  local element = self:getElementAt(self.selectedGridPos.y, self.selectedGridPos.x)
  local top = self.target:getElementAt(self.selectedGridPos.y, self.selectedGridPos.x)
  if not element or not top then return end
  local unit, margin = self.target.unitSize, self.target.unitMargin
  local x, y
  if element == top then
    x = (element.gridOriginX - 1) * unit
    y = (element.gridOriginY - 1) * unit
  else
    x = (top.gridOriginX + element.gridOriginX - 2) * unit
    y = (top.gridOriginY + element.gridOriginY - 2) * unit
  end
  local w, h = element.width + margin * 2, element.height + margin * 2
  local inset = margin * 0.5
  U.inElement()
  local pulse = 0.75 + 0.25 * math.sin(love.timer.getTime() * 6)
  U.rframe(math.floor((x + inset) * K), math.floor((y + inset) * K), math.floor((w - 2 * inset) * K), math.floor((h - 2 * inset) * K), 9, 3, playerColor(self.player), pulse)
  U.onScreen()
  U.reset()
end

-- selection wrappers: accent outline when focused, no gold box
local function wrapperSkin(self)
  if self.hasFocus then
    U.inElement()
    U.rframe(self.x * K, self.y * K, self.width * K, self.height * K, 8, 2, C.p1)
    U.onScreen()
    U.reset()
  end
end

-- character tiles: name along the bottom on a dark strip, no flag / stage /
-- panel badges (they are tiny here and cost a texture each)
local function simplifyCharacterButtons(buttons)
  for _, b in ipairs(buttons) do
    for _, key in ipairs({ "flag", "stageIcon", "panelIcon" }) do
      if b[key] then b[key]:detach(); b[key] = nil end
    end
    if b.label then
      b.label.vAlign = "bottom"
      b.label:setFillColors(0.05, 0.07, 0.12, 0.78)
    end
  end
  return buttons
end

local function drawSelf(self)
  self.backgroundImg:draw()
  self:customDraw()
end

local function hints(self)
  local items = { { "A", "Select" }, { "B", "Back" } }
  if self.ui and self.ui.characterGrid and self.ui.characterGrid.totalPages and self.ui.characterGrid.totalPages > 1 then
    table.insert(items, 2, { "L/R", "Page" })
  end
  U.hintBar(items, 448, 32)
  U.reset()
end

-- online / 2P ready-up: two player cards across the top instead of the
-- tiny portrait + stats boxes, ranked status in the hint bar
local function playerCard2p(player, i, x, y, w, h)
  local color = (i == 2) and C.p2 or C.p1
  U.rrect(x, y, w, h, 8, C.card)
  local ch = player.settings and characters and characters[player.settings.characterId]
  local icon = ch and ch.images and ch.images.icon
  if icon then
    U.image(icon, x + 6, y + 5, h - 10, h - 10)
  else
    U.rrect(x + 6, y + 5, h - 10, h - 10, 6, C.row)
    U.text("?", x + 6, y + 12, U.font("display", 30), C.muted, "center", h - 10)
  end
  local tx = x + h + 4
  local fName = U.font("bold", 17)
  U.text(U.fit(player.name or "", fName, w - h - 100), tx, y + 9, fName, color)
  local wins = 0
  pcall(function() wins = player:getWinCountForDisplay() end)
  local r = tonumber(player.rating)
  local line = (r and (r .. " · ") or "") .. "Wins " .. tostring(wins)
  U.text(line, tx, y + 34, U.font("regular", 13), C.muted)
  local ready = player.settings and player.settings.wantsReady
  local pw = 74
  U.rrect(x + w - pw - 10, y + math.floor(h / 2) - 11, pw, 22, 11, ready and C.greenBg or C.greyBg)
  U.text(ready and "READY" or "Picking", x + w - pw - 10, y + math.floor(h / 2) - 7, U.font("bold", 11), ready and C.green or C.dim, "center", pw)
end

local function draw2pOverlay(self)
  if not self.players or #self.players < 2 then return end
  for i = 1, 2 do
    local p = self.players[i]
    if p then playerCard2p(p, i, 20 + (i - 1) * 304, 42, 296, 62) end
  end
  local rs = self.uiRoot and self.uiRoot.rankedStatus
  if rs and rs.rankedLabel then
    local menus = require("miyoo.menus")
    local status = menus.labelText(rs.rankedLabel)
    local comment = rs.commentLabel and menus.labelText(rs.commentLabel) or ""
    U.text(status:upper(), 20, 456, U.font("bold", 12), (self.battleRoom and self.battleRoom.ranked) and C.green or C.muted, "left", nil, 1)
    local sw = U.textWidth(status:upper(), U.font("bold", 12), 1)
    if comment ~= "" then
      U.text(U.fit(comment, U.font("regular", 12), 400 - sw), 20 + sw + 10, 456, U.font("regular", 12), C.faint)
    end
  end
  U.reset()
end

function CS.install()
  require("client.src.ui.GridElement").drawSelf = gridElementSkin
  ui.GridCursor.drawSelf = cursorSkin
  ui.MultiPlayerSelectionWrapper.drawSelf = wrapperSkin

  -- smaller titles on the setting boxes so they don't collide with content
  local StackPanel = require("client.src.ui.StackPanel")
  ui.MultiPlayerSelectionWrapper.setTitle = function(self, string)
    self.title = ui.Label({ text = string, fontSize = 10 })
    self.title.hAlign = "center"
    if self.alignment == "top" or self.alignment == "bottom" then
      self.title.vAlign = self.alignment
      StackPanel.insertElementAtIndex(self, self.title, 1)
    else
      self.title.vAlign = "top"
      self:addChild(self.title)
    end
  end

  -- stage names under the thumbnails: small, so two fit side by side
  local GraphicsUtil = require("client.src.graphics.graphics_util")
  local StageCarousel = require("client.src.ui.StageCarousel")
  local createPassenger = StageCarousel.createPassenger
  StageCarousel.createPassenger = function(self, id, image, text)
    local p = createPassenger(self, id, image, text)
    local l = p.label
    if l then
      l.fontSize = 8
      local s = l.translate and loc(l.text, unpack(l.replacementTable or {})) or l.text
      l.drawable = GraphicsUtil.newText(GraphicsUtil.getGlobalFontWithSize(8), s)
      l:refreshFormatting()
    end
    return p
  end

  local CharacterSelect = require("client.src.scenes.CharacterSelect")
  -- one built-in controller: no "change input device" button
  CharacterSelect.setChangeInputButtonVisibleIfNeeded = function(self)
    self:setChangeInputButtonVisibility(false)
  end
  local load = CharacterSelect.load
  CharacterSelect.load = function(self, ...)
    local r = load(self, ...)
    self:setChangeInputButtonVisibility(false)
    return r
  end
  local get = CharacterSelect.getCharacterButtons
  CharacterSelect.getCharacterButtons = function(self)
    return simplifyCharacterButtons(get(self))
  end
  local draw = CharacterSelect.draw
  CharacterSelect.draw = function(self)
    draw(self)
    hints(self)
  end
  CharacterSelect.drawSelf = drawSelf

  local CS2 = require("client.src.scenes.CharacterSelect2p")
  local customLoad = CS2.customLoad
  CS2.customLoad = function(self, ...)
    local r = customLoad(self, ...)
    for i = 1, 2 do
      if self.ui.characterIcons and self.ui.characterIcons[i] then self.ui.characterIcons[i]:setVisibility(false) end
      if self.ui.playerInfos and self.ui.playerInfos[i] then self.ui.playerInfos[i]:setVisibility(false) end
    end
    if self.uiRoot.rankedStatus then self.uiRoot.rankedStatus:setVisibility(false) end
    return r
  end
  CS2.draw = function(self)
    CharacterSelect.draw(self)
    draw2pOverlay(self)
  end
end

return CS
