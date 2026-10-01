-- In-match layout for the 640x480 screen ("Layout A" from the mockups).
--   2 players: boards at the outer edges, a centre column with the clock,
--              player cards, chain calls and stop-time bars.
--   1 player:  board on the left, big score and stats on the right.
-- Boards keep Panel Attack's own 32 px panels; only what is around them changes.

local U = require("miyoo.ui")
local C = U.C
local G = love.graphics

local ClientStack = require("client.src.ClientStack")
local ClientMatch = require("client.src.ClientMatch")
local GameBase = require("client.src.scenes.GameBase")
local MatchRules = require("common.data.MatchRules")
local GameModes = require("common.data.GameModes")

local HUD = {}

-- board frame positions (screen px); a frame is 208 x 408 (104 x 204 at gfxScale 3)
local FRAME_W, FRAME_H = 208, 408
local POS = {
  two = { { x = 16, y = 48 }, { x = 416, y = 48 } },
  one = { x = 40, y = 36 },
}

local function playerColor(stack)
  return (stack.renderIndex == 2) and C.p2 or C.p1
end

---------------------------------------------------------------------------
-- board placement
---------------------------------------------------------------------------
local function renderedStacks(match)
  local list = {}
  for _, s in ipairs(match.stacks) do
    if s.player or s.engine.healthEngine then list[#list + 1] = s end
  end
  return list
end

local originalMoveStacks = ClientMatch.moveStacks
function ClientMatch:moveStacks()
  originalMoveStacks(self)
  local count = #self.stacks
  for _, stack in ipairs(self.stacks) do
    local p
    if count == 1 then
      p = POS.one
    else
      p = POS.two[stack.renderIndex or 1] or POS.two[1]
    end
    stack:moveToPosition(U.cx(p.x), U.cy(p.y))
  end
  self.miyooLayout = (count == 1) and "one" or "two"
end

-- plain board: dark fill behind the panels and a coloured outline
-- (replaces the character portrait and the themed frame image)
ClientStack.drawCharacter = function(self)
  G.setColor(C.board[1], C.board[2], C.board[3], 1)
  G.rectangle("fill", 0, 0, self:canvasWidth(), self:canvasHeight())
  G.setColor(1, 1, 1, 1)
end

-- no themed "floor" bar under the stack; the incoming row shows through instead
ClientStack.drawWall = function() end

ClientStack.drawFrame = function(self)
  local c = playerColor(self)
  G.setColor(c[1], c[2], c[3], 1)
  local w, h, t = self:canvasWidth(), self:canvasHeight(), 3 * 1.5
  G.rectangle("fill", 0, 0, w, t)
  G.rectangle("fill", 0, h - t, w, t)
  G.rectangle("fill", 0, t, t, h - 2 * t)
  G.rectangle("fill", w - t, t, t, h - 2 * t)
  G.setColor(1, 1, 1, 1)
end

-- the clock and match type are drawn by the HUD below
ClientMatch.drawTimer = function() end
ClientMatch.drawMatchType = function() end

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function matchClock(match)
  local frames = 0
  local stack = match.stacks[1]
  if stack and tonumber(stack.engine.stopWatch) then frames = stack.engine.stopWatch end
  if match.engine.timeLimit then
    frames = math.max(0, match.engine.timeLimit - frames)
  end
  local s = frames_to_time_string(frames, match.engine.ended)
  return s
end

local function winCount(stack)
  local ok, n = pcall(stack.player.getWinCountForDisplay, stack.player)
  return ok and n or 0
end

local function maxChain(stack)
  local data = stack.analytic and stack.analytic.data
  local m = 0
  if data and data.reached_chains then
    for k in pairs(data.reached_chains) do if k > m then m = k end end
  end
  return m
end

-- stop / shake / health state, normalised 0..1 for the side bars
local barState = setmetatable({}, { __mode = "k" })
local function multibar(stack, x, y, w, h)
  local e = stack.engine
  U.rect(x, y, w, h, C.row)
  local st = barState[stack]
  if not st then st = { stop = 0, pre = 0 }; barState[stack] = st end
  local stop, pre, shake = e.stop_time or 0, e.pre_stop_time or 0, e.shake_time or 0
  if stop == 0 then st.stop = 0 elseif stop > st.stop then st.stop = stop end
  if pre == 0 then st.pre = 0 elseif pre > st.pre then st.pre = pre end

  if e.health and e.levelData and e.levelData.maxHealth and stack.engine.healthEngine then
    local f = math.max(0, math.min(1, e.health / e.levelData.maxHealth))
    local fh = math.floor(h * f + 0.5)
    U.rect(x, y + h - fh, w, fh, C.green)
  end

  if e.peak_shake_time and e.peak_shake_time > 0 and shake > 0 and shake >= pre + stop then
    local fh = math.floor(h * math.min(1, shake / e.peak_shake_time) + 0.5)
    U.rect(x, y + h - fh, w, fh, C.red)
  else
    local bottom = y + h
    if st.stop > 0 and stop > 0 then
      local fh = math.floor(h * math.min(1, stop / st.stop) + 0.5)
      U.rect(x, bottom - fh, w, fh, playerColor(stack))
      bottom = bottom - fh
    end
    if st.pre > 0 and pre > 0 then
      local fh = math.floor((bottom - y) * math.min(1, pre / st.pre) + 0.5)
      U.rect(x, bottom - fh, w, fh, C.text)
    end
  end
end

local function chainCall(stack, cx, y, size, alignLeft)
  local n = stack.engine.chain_counter or 0
  if n < 2 then return false end
  local fBig = U.font("display", size)
  local fLbl = U.font("bold", math.floor(size * 0.38))
  local num = n .. "×"
  local wNum = U.textWidth(num, fBig)
  local wLbl = U.textWidth("CHAIN", fLbl, 2)
  if alignLeft then
    U.text(num, cx, y, fBig, playerColor(stack))
    U.text("CHAIN", cx + wNum + 10, y + size * 0.5, fLbl, C.text, "left", nil, 2)
  else
    U.text(num, cx, y, fBig, playerColor(stack), "center")
    U.text("CHAIN", cx, y + size + 2, fLbl, C.text, "center", nil, 2)
  end
  return true
end

local function playerCard(stack, x, y, w)
  local h = 58
  U.rrect(x, y, w, h, 7, C.card)
  local fName, fSmall = U.font("bold", 16), U.font("regular", 13)
  local rating = stack.player and tonumber(stack.player.rating)
  local ratingW = rating and U.textWidth(rating, fSmall) + 8 or 0
  local name = U.fit(stack.player and stack.player.name or "", fName, w - 20 - ratingW)
  U.text(name, x + 10, y + 7, fName, playerColor(stack))
  if rating then U.text(rating, x + w - 10, y + 10, fSmall, C.muted, "right") end
  local fVal = U.font("bold", 13)
  local lw = U.text("Wins ", x + 10, y + 33, fSmall, C.dim)
  U.text(winCount(stack), x + 10 + lw, y + 33, fVal, C.text)
  if stack.level then
    local vw = U.textWidth(stack.level, fVal)
    U.text(stack.level, x + w - 10, y + 33, fVal, C.text, "right")
    U.text("Lv ", x + w - 10 - vw, y + 33, fSmall, C.dim, "right")
  end
end

local MODE_NAMES = {
  EndlessGame = "ENDLESS",
  TimeAttackGame = "TIME ATTACK",
  VsSelfGame = "VS YOURSELF",
  ReplayGame = "REPLAY",
}

---------------------------------------------------------------------------
-- two-player HUD
---------------------------------------------------------------------------
local function drawTwo(scene, match)
  local stacks = renderedStacks(match)
  local colX, colW = 224, 192
  local mid = colX + colW / 2

  local clock = matchClock(match)
  local fClock = U.font("display", 40)
  if U.textWidth(clock, fClock) > colW - 12 then
    U.text(clock, mid, 12, U.font("display", 30), C.text, "center")
  else
    U.text(clock, mid, 4, fClock, C.text, "center")
  end
  local label
  if match.stackInteraction == GameModes.StackInteractions.VERSUS or (match.replay and match.replay.metadata.gameModeName == "VS") then
    label = match.ranked and "RANKED" or "CASUAL"
  else
    label = MODE_NAMES[scene.name] or ""
  end
  U.text(label, mid, 52, U.font("bold", 12), C.muted, "center", nil, 2)

  local cardX, cardW = 240, 160
  local y = 76
  for i = 1, 2 do
    local s
    for _, st in ipairs(stacks) do if st.renderIndex == i then s = st end end
    if s and s.player then
      playerCard(s, cardX, y, cardW)
      y = y + 66
    end
  end

  -- chain calls
  local cy = 222
  for i = 1, 2 do
    for _, st in ipairs(stacks) do
      if st.renderIndex == i and chainCall(st, mid, cy, 40) then cy = cy + 68 end
    end
  end

  -- stop-time bars along the inner edge of each board
  for _, st in ipairs(stacks) do
    local bx = (st.renderIndex == 2) and 406 or 228
    multibar(st, bx, 56, 6, 392)
  end

  -- speeds along the bottom of the column
  local fS, fV = U.font("regular", 13), U.font("bold", 13)
  for _, st in ipairs(stacks) do
    if st.player then
      local sp = tostring(st.engine.speed or "")
      if st.renderIndex == 2 then
        local vw = U.textWidth(sp, fV)
        U.text(sp, cardX + cardW, 436, fV, C.text, "right")
        U.text("Speed ", cardX + cardW - vw, 436, fS, C.muted, "right")
      else
        local lw = U.text("Speed ", cardX, 436, fS, C.muted)
        U.text(sp, cardX + lw, 436, fV, C.text)
      end
    end
  end

  if GAME.battleRoom and GAME.battleRoom.spectatorString and GAME.battleRoom.spectatorString ~= "" then
    U.text(U.fit(GAME.battleRoom.spectatorString:gsub("\n", " "), U.font("regular", 11), colW), mid, 458, U.font("regular", 11), C.faint, "center")
  end
end

---------------------------------------------------------------------------
-- one-player HUD
---------------------------------------------------------------------------
local function statBox(x, y, w, label, value)
  U.rrect(x, y, w, 62, 7, C.card)
  U.text(label, x + 10, y + 9, U.font("bold", 11), C.muted, "left", nil, 1)
  U.text(value, x + 10, y + 24, U.font("display", 26), C.text)
end

local function drawOne(scene, match)
  local stack = renderedStacks(match)[1]
  if not stack then return end
  local e = stack.engine
  local x, w = 288, 328

  local mode = MODE_NAMES[scene.name] or ""
  if stack.level and mode ~= "" then mode = mode .. " · LEVEL " .. stack.level end
  U.text(mode, x, 40, U.font("bold", 12), C.muted, "left", nil, 2)

  local swaps = e.stackOverConditions and e.stackOverConditions[MatchRules.StackOverConditions.SWAPS]
  if swaps then
    U.text(tostring(swaps - e.swapCount), x, 58, U.font("display", 60), playerColor(stack))
    U.text("MOVES LEFT", x, 128, U.font("regular", 14), C.muted)
  else
    U.text(tostring(e.score or 0), x, 58, U.font("display", 60), playerColor(stack))
    U.text("SCORE", x, 128, U.font("regular", 14), C.muted)
  end

  local bw = math.floor((w - 20) / 3)
  statBox(x, 160, bw, "TIME", matchClock(match))
  statBox(x + bw + 10, 160, bw, "SPEED", tostring(e.speed or ""))
  local mc = maxChain(stack)
  statBox(x + 2 * (bw + 10), 160, bw, "MAX CHAIN", mc >= 2 and (mc .. "×") or "–")

  chainCall(stack, x, 248, 52, true)

  multibar(stack, 256, 44, 6, 392)

  -- controls
  local y, f = 436, U.font("regular", 13)
  local kx = x
  kx = kx + U.key("A", kx, y) + 6
  kx = kx + U.text("Swap", kx, y + 1, f, C.muted) + 18
  kx = kx + U.key("R", kx, y) + 6
  kx = kx + U.text("Raise", kx, y + 1, f, C.muted) + 18
  kx = kx + U.key("START", kx, y) + 6
  U.text("Pause", kx, y + 1, f, C.muted)
end

---------------------------------------------------------------------------
-- hooks into the game scenes
---------------------------------------------------------------------------
function HUD.draw(scene)
  local match = scene.match
  if not match or match.isPaused then return end
  if match.miyooLayout == "one" then drawOne(scene, match) else drawTwo(scene, match) end
  U.reset()
end

function HUD.background()
  G.setColor(C.bg[1], C.bg[2], C.bg[3], 1)
  G.rectangle("fill", 0, 0, 1280, 720)
  G.setColor(1, 1, 1, 1)
end

function HUD.endText(scene)
  local match = scene.match
  if not match or not match.ended then return end
  local msg = scene.text or ""
  local x, w, y
  if match.miyooLayout == "one" then x, w, y = 288, 328, 330 else x, w, y = 232, 176, 300 end
  local fT = U.font("bold", 18)
  local lines = {}
  -- wrap the message to the card width
  local cur = ""
  for word in msg:gmatch("%S+") do
    local try = (cur == "") and word or (cur .. " " .. word)
    if U.textWidth(try, fT) > w - 24 and cur ~= "" then lines[#lines + 1] = cur; cur = word else cur = try end
  end
  if cur ~= "" then lines[#lines + 1] = cur end
  local h = 24 + #lines * 24 + 28
  U.rrect(x, y, w, h, 8, C.sel)
  U.rect(x, y, 4, h, C.p1)
  for i, l in ipairs(lines) do U.text(l, x + w / 2, y + 12 + (i - 1) * 24, fT, C.text, "center") end
  local f = U.font("regular", 13)
  local tw = U.textWidth("Continue", f)
  local kx = math.floor(x + (w - (18 + 6 + tw)) / 2)
  U.key("A", kx, y + h - 30)
  U.text("Continue", kx + 24, y + h - 29, f, C.muted)
  U.reset()
end

function HUD.pause(match)
  U.rect(0, 0, U.W, U.H, C.shade)
  -- the Resume / Back menu itself is drawn by the scene's UI on top
  U.text("PAUSED", U.W / 2, 110, U.font("display", 48), C.text, "center")
  U.reset()
end

-- FPS readout (Options > show FPS): small, bottom-left, out of the way
local function drawFPS(game)
  if not (game.config.show_fps) then return end
  local s = love.timer.getFPS() .. " fps"
  local scene = game.navigationStack and game.navigationStack.scenes
  scene = scene and scene[#scene]
  local match = scene and scene.match
  if match and match.stacks and #match.stacks > 1 then
    local lag = 0
    for _, st in ipairs(match.stacks) do lag = math.max(lag, st.engine.framesBehind or 0) end
    s = s .. " · lag " .. lag
  end
  U.text(s, 4, 464, U.font("regular", 11), C.faint)
  U.reset()
end

-- stages: only the thumbnail is needed (match backgrounds are flat now), so
-- skip decoding the full-screen background picture
local function stageGraphicsInit(self, full, yields)
  local GraphicsUtil = require("client.src.graphics.graphics_util")
  self.images.thumbnail = GraphicsUtil.loadImageFromSupportedExtensions(self.path .. "/thumbnail")
  if not self.images.thumbnail and not self:isBundle() then
    local def = themes[config.theme] and themes[config.theme].defaultStage
    self.images.thumbnail = def and def.images.thumbnail
  end
  if full then
    HUD.blank = HUD.blank or G.newImage(love.image.newImageData(1, 1))
    self.images.background = HUD.blank
  end
  if yields then coroutine.yield() end
end

function HUD.install()
  require("client.src.mods.Stage").graphics_init = stageGraphicsInit
  local Game = require("client.src.Game")
  Game.drawFPS = drawFPS
  local render = ClientMatch.render
  ClientMatch.render = function(self)
    local fps = config.show_fps
    config.show_fps = false
    render(self)
    config.show_fps = fps
  end
  GameBase.draw = (function(draw)
    return function(self)
      local fps = config.show_fps
      config.show_fps = false
      draw(self)
      config.show_fps = fps
    end
  end)(GameBase.draw)
  GameBase.drawHUD = HUD.draw
  GameBase.drawBackground = HUD.background
  GameBase.drawForegroundOverlay = function() end
  GameBase.drawEndGameText = HUD.endText
  ClientMatch.draw_pause = HUD.pause
  local ok, ReplayGame = pcall(require, "client.src.scenes.ReplayGame")
  if ok then ReplayGame.drawHUD = HUD.draw end
end

return HUD
