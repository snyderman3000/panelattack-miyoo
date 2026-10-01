-- Online lobby for the 640x480 screen: one list of players / rooms / modes
-- on the left, challenge actions for the selected player on the right.
-- Navigation and networking stay Panel Attack's own; only drawing changes.

local U = require("miyoo.ui")
local C = U.C
local G = love.graphics
local GameModes = require("common.data.GameModes")
local GraphicsUtil = require("client.src.graphics.graphics_util")
local menus = require("miyoo.menus")

local L = {}

local function lobbyData()
  return GAME.netClient and GAME.netClient.lobbyDataV2
end

local function challenged(tbl, id)
  local t = tbl and tbl[id]
  if not t then return false end
  for _, v in pairs(t) do if v then return true end end
  return false
end

local function rating(player, mode)
  local r = player and player.ratings and player.ratings[mode or GameModes.IDs.TWO_PLAYER_VS]
  return r and tostring(r) or nil
end

local function pill(x, y, w, text, bg, fg)
  U.rrect(x, y, w, 22, 11, bg)
  U.text(text, x, y + 4, U.font("bold", 11), fg, "center", w)
end

-- describe one entry of the lobby list
local function describe(child, data)
  local d = { text = "", kind = "other" }
  if child.lobbyType == "player" and child.player then
    local p = child.player
    d.kind = "player"
    d.text = p.name or "?"
    d.rating = rating(p)
    if data and challenged(data.incomingChallenges, p.publicId) then
      d.status, d.bg, d.fg = "Challenged you", C.greenBg, C.green
    elseif data and challenged(data.outgoingChallenges, p.publicId) then
      d.status, d.bg, d.fg = "Requested", C.amberBg, C.amber
    else
      d.status, d.bg, d.fg = "In lobby", C.greyBg, C.dim
    end
  elseif child.lobbyType == "room" and child.room then
    local room = child.room
    local names = {}
    for i, id in ipairs(room.players or {}) do
      local p = data and data.players and data.players[id]
      names[i] = p and p.name or tostring(id)
    end
    d.kind = "room"
    d.text = table.concat(names, " vs ")
    d.status, d.bg, d.fg = "Watch", C.amberBg, C.amber
  elseif child.label then
    d.text = menus.labelText(child.label)
  elseif child.text then
    d.text = menus.labelText(child)
    d.kind = "message"
  end
  return d
end

local function drawList(self, data)
  local menu = self.lobbyMenu
  if not menu then return end
  local rows = {}
  for i, child in ipairs(menu.children) do
    local d = describe(child, data)
    if d.kind ~= "message" then
      d.index = i
      rows[#rows + 1] = d
    end
  end

  local x, w, top, rowH, gap = 24, 372, 64, 32, 4
  local maxRows = math.floor((440 - top + gap) / (rowH + gap))
  local selRow = 1
  for r, d in ipairs(rows) do if d.index == menu.selectedIndex then selRow = r end end
  local first = 1
  if #rows > maxRows then
    first = math.max(1, math.min(selRow - math.floor(maxRows / 2), #rows - maxRows + 1))
  end

  local fN, fB, fS = U.font("medium", 16), U.font("bold", 16), U.font("regular", 13)
  local y = top
  local lastKind
  local submenuOpen = self.playerSubMenu ~= nil
  for r = first, math.min(#rows, first + maxRows - 1) do
    local d = rows[r]
    if lastKind and (lastKind == "player" or lastKind == "room") and d.kind == "other" then y = y + 6 end
    lastKind = d.kind
    local sel = (d.index == menu.selectedIndex)
    if sel then
      U.rrect(x, y, w, rowH, 6, C.sel)
      U.rect(x, y + 3, 4, rowH - 6, submenuOpen and C.faint or C.p1)
    else
      U.rrect(x, y, w, rowH, 6, C.row)
    end
    local f = sel and fB or fN
    local ty = y + math.floor((rowH - f:getHeight() / 1.5) / 2)
    local textW = w - 28
    if d.status then textW = textW - 104 end
    if d.rating then textW = textW - 48 end
    U.text(U.fit(d.text, f, textW), x + 14, ty, f, sel and { 1, 1, 1, 1 } or C.dim)
    local rx = x + w - 10
    if d.status then
      rx = rx - 96
      pill(rx, y + 5, 96, d.status, d.bg, d.fg)
      rx = rx - 8
    end
    if d.rating then
      U.text(d.rating, rx, y + math.floor((rowH - fS:getHeight() / 1.5) / 2), fS, C.muted, "right")
    end
    y = y + rowH + gap
  end

  if #rows > 0 and not rows[1].kind:match("player") and not rows[1].kind:match("room") then
    -- nobody else here
    U.text(loc("lb_alone"), x, 438, U.font("regular", 13), C.muted)
  end
end

local CHALLENGE_TEXT = {
  [GameModes.IDs.TWO_PLAYER_VS] = { "Challenge VS", "Accept VS", "Cancel VS request" },
  [GameModes.IDs.TWO_PLAYER_TIME_ATTACK] = { "Challenge Time Attack", "Accept Time Attack", "Cancel TA request" },
}

local function drawSide(self, data)
  local x, w = 412, 204
  local sub = self.playerSubMenu
  if sub then
    local p = data and data.players and data.players[sub.playerId]
    U.rrect(x, 64, w, 58, 8, C.card)
    U.text(U.fit(p and p.name or "", U.font("bold", 18), w - 28), x + 14, 72, U.font("bold", 18), C.p2)
    local r = rating(p)
    U.text(r and ("Rating " .. r) or "Unrated", x + 14, 98, U.font("regular", 13), C.muted)
    local y = 132
    for i, child in ipairs(sub.children) do
      local sel = (i == sub.selectedIndex)
      local text
      local t = child.gameModeId and CHALLENGE_TEXT[child.gameModeId]
      local states = child.challengeStates
      if t and states then
        if child.challengeState == states.CHALLENGED then text = t[2]
        elseif child.challengeState == states.PROPOSING then text = t[3]
        else text = t[1] end
      else
        text = child.label and menus.labelText(child.label) or "Back"
      end
      local hot = child.challengeState and states and child.challengeState == states.CHALLENGED
      if sel then
        U.rrect(x, y, w, 36, 6, hot and C.green or C.p1)
        U.text(U.fit(text, U.font("bold", 15), w - 24), x + 12, y + 9, U.font("bold", 15), C.bg)
      else
        U.rrect(x, y, w, 36, 6, C.card)
        U.text(U.fit(text, U.font("medium", 15), w - 24), x + 12, y + 9, U.font("medium", 15), hot and C.green or C.text)
      end
      y = y + 42
    end
  else
    local me = data and data.players and GAME.localPlayer and data.players[GAME.localPlayer.publicId]
    U.rrect(x, 64, w, 58, 8, C.card)
    U.text(U.fit(config.name or "", U.font("bold", 18), w - 28), x + 14, 72, U.font("bold", 18), C.p1)
    local r = rating(me)
    U.text(r and ("You · Rating " .. r) or "You", x + 14, 98, U.font("regular", 13), C.muted)
    local msg = self.lobbyMessage and menus.labelText(self.lobbyMessage) or ""
    local f = U.font("regular", 13)
    local lines, cur = {}, ""
    for word in msg:gmatch("%S+") do
      local try = cur == "" and word or (cur .. " " .. word)
      if U.textWidth(try, f) > w - 8 and cur ~= "" then lines[#lines + 1] = cur; cur = word else cur = try end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    for i, l in ipairs(lines) do U.text(l, x + 4, 136 + (i - 1) * 18, f, C.muted) end
  end
end

local function draw(self)
  G.setColor(C.bg[1], C.bg[2], C.bg[3], 1)
  G.rectangle("fill", 0, 0, 1280, 720)
  local data = lobbyData()

  U.text("Online lobby", 24, 14, U.font("display", 26), C.text)
  local server = os.getenv("PA_SERVER") or "panelattack.com"
  local count = 0
  if data and data.players then for _ in pairs(data.players) do count = count + 1 end end
  local info = data and (server .. " · " .. count .. " online") or ("Connecting to " .. server .. "…")
  U.text(info, U.W - 24, 22, U.font("regular", 14), C.muted, "right")

  if data then
    drawList(self, data)
    drawSide(self, data)
  end

  if self.leaderboard and self.leaderboard.isVisible then
    U.rect(0, 0, U.W, U.H, C.shade)
    GraphicsUtil.applyAlignment(self.uiRoot, self.leaderboard)
    self.leaderboard:draw()
    GraphicsUtil.resetAlignment()
  end

  local hints = self.playerSubMenu and { { "A", "Send" }, { "B", "Close" } } or { { "A", "Select" }, { "B", "Leave" } }
  U.hintBar(hints, 448, 32)
  U.reset()
end

function L.install()
  local Lobby = require("client.src.scenes.Lobby")
  Lobby.draw = draw
end

return L
