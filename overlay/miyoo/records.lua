-- Records for the Miyoo port: best scores for every Endless / Time Attack
-- setting (Panel Attack itself only keeps Classic-style ones), best Vs CPU
-- (challenge mode) times, and a Records screen that also shows Panel
-- Attack's own Vs Yourself records and lifetime stats (analytics.json).
--
-- Saved in the game's save folder as miyoo_records.json; Panel Attack's own
-- files (scores.json, analytics.json) are only read, never changed.

local U = require("miyoo.ui")
local C = U.C
local G = love.graphics

local class = require("common.lib.class")
local Scene = require("client.src.scenes.Scene")
local input = require("client.src.inputManager")
local LevelPresets = require("common.data.LevelPresets")

local M = {}
local FILE = "miyoo_records.json"
local VERSION = 1

---------------------------------------------------------------------------
-- storage
---------------------------------------------------------------------------
local data

local function blank()
  return {
    version = VERSION,
    endless = { classic = {}, modern = {} },
    timeAttack = { classic = {}, modern = {} },
    challenge = {},
  }
end

function M.load()
  if data then return data end
  data = blank()
  local ok, content = pcall(love.filesystem.read, FILE)
  if ok and content then
    local value = json.decode(content)
    if type(value) == "table" then
      for _, mode in ipairs({ "endless", "timeAttack" }) do
        if type(value[mode]) == "table" then
          data[mode].classic = type(value[mode].classic) == "table" and value[mode].classic or {}
          data[mode].modern = type(value[mode].modern) == "table" and value[mode].modern or {}
        end
      end
      if type(value.challenge) == "table" then data.challenge = value.challenge end
    end
  end
  return data
end

function M.save()
  if not data then return end
  local ok, encoded = pcall(json.encode, data)
  if not ok then return end
  love.filesystem.write(FILE, encoded)
end

local function maxKey(t)
  local m = 0
  if type(t) ~= "table" then return 0 end
  for k, v in pairs(t) do
    local n = tonumber(k)
    if n and (tonumber(v) or 0) > 0 and n > m then m = n end
  end
  return m
end

-- one finished Endless / Time Attack game
function M.recordScoreGame(mode, stack)
  if not stack or not stack.engine then return end
  local style, key
  if stack.difficulty then
    style, key = "classic", tostring(stack.difficulty)
  elseif stack.level then
    style, key = "modern", tostring(stack.level)
  else
    return
  end
  local d = M.load()
  local score = stack.engine.score or 0
  local a = stack.analytic and stack.analytic.data or {}
  local chain, combo = maxKey(a.reached_chains), maxKey(a.used_combos)
  local r = d[mode][style][key] or { best = 0, last = 0, games = 0, bestChain = 0, bestCombo = 0 }
  r.last = score
  r.games = (r.games or 0) + 1
  if score > (r.best or 0) then r.best = score end
  if chain > (r.bestChain or 0) then r.bestChain = chain end
  if combo > (r.bestCombo or 0) then r.bestCombo = combo end
  d[mode][style][key] = r
  M.save()
end

-- a completed challenge mode run (all stages beaten)
function M.recordChallenge(cm)
  if not cm or not cm.challengeComplete or not cm.difficulty then return end
  local d = M.load()
  local key = tostring(cm.difficulty)
  local r = d.challenge[key] or { clears = 0 }
  local total = cm.expendedTime or 0
  local splits = {}
  for i, stage in ipairs(cm.stages or {}) do splits[i] = stage.expendedTime or 0 end
  r.clears = (r.clears or 0) + 1
  if not r.bestTime or total < r.bestTime then
    r.bestTime = total
    r.bestContinues = cm.continues or 0
    r.bestSplits = splits
  end
  if not r.fewestContinues or (cm.continues or 0) < r.fewestContinues then
    r.fewestContinues = cm.continues or 0
  end
  r.bestStage = type(r.bestStage) == "table" and r.bestStage or {}
  for i, t in ipairs(splits) do
    local old = tonumber(r.bestStage[i]) or tonumber(r.bestStage[tostring(i)])
    if t > 0 and (not old or t < old) then r.bestStage[i] = t end
  end
  r.lastTime = total
  d.challenge[key] = r
  M.save()
end

---------------------------------------------------------------------------
-- hooks into Panel Attack's game scenes
---------------------------------------------------------------------------
function M.install()
  M.load()
  local EndlessGame = require("client.src.scenes.EndlessGame")
  local endlessEnded = EndlessGame.onMatchEnded
  EndlessGame.onMatchEnded = function(self, match)
    endlessEnded(self, match)
    pcall(M.recordScoreGame, "endless", match.players[1].stack)
  end

  local TimeAttackGame = require("client.src.scenes.TimeAttackGame")
  local taEnded = TimeAttackGame.onMatchEnded
  TimeAttackGame.onMatchEnded = function(self, match)
    taEnded(self, match)
    pcall(M.recordScoreGame, "timeAttack", match.players[1].stack)
  end

  local Game1pChallenge = require("client.src.scenes.Game1pChallenge")
  local nextScene = Game1pChallenge.startNextScene
  Game1pChallenge.startNextScene = function(self, ...)
    if GAME.battleRoom and GAME.battleRoom.challengeComplete then
      pcall(M.recordChallenge, GAME.battleRoom)
    end
    return nextScene(self, ...)
  end
end

---------------------------------------------------------------------------
-- Records screen
---------------------------------------------------------------------------
local CLASSIC_NAMES = { "Easy", "Normal", "Hard", "EX" }
local TABS = { "Endless", "Time Attack", "Vs CPU", "Vs Yourself", "Lifetime" }

local function fmtScore(n)
  n = tonumber(n) or 0
  if n <= 0 then return "–" end
  local s = tostring(math.floor(n))
  return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local function fmtTime(frames)
  frames = tonumber(frames)
  if not frames or frames <= 0 then return "–" end
  return frames_to_time_string(frames, true)
end

local function fmtChain(n)
  n = tonumber(n) or 0
  return n >= 2 and ("x" .. n) or "–"
end

local function challengeName(i)
  local ok, s = pcall(loc, "challenge_difficulty_" .. i)
  if ok and s and s ~= "" and not s:find("challenge_difficulty") then return s end
  return "Level " .. i
end

local function readAnalytics()
  local ok, content = pcall(love.filesystem.read, "analytics.json")
  if not ok or not content then return nil end
  local value = json.decode(content)
  return type(value) == "table" and type(value.overall) == "table" and value.overall or nil
end

local function sumPairs(t)
  local list = {}
  if type(t) ~= "table" then return list end
  for k, v in pairs(t) do
    local n, c = tonumber(k), tonumber(v)
    if n and c and c > 0 then list[#list + 1] = { n, c } end
  end
  table.sort(list, function(a, b) return a[1] < b[1] end)
  return list
end

local RecordsScene = class(function(self, sceneParams)
  self.keepMusic = true
  self.tab = 1
  self.sel = 1      -- selected Vs CPU difficulty
  self.scroll = 0
  self.rec = M.load()
  self.analytics = readAnalytics()
end, Scene)
RecordsScene.name = "RecordsScene"
M.RecordsScene = RecordsScene

local function pressed(key)
  return input:isPressedWithRepeat(key)
end

function RecordsScene:updateSelf(dt)
  if input.isDown["MenuEsc"] or input.isDown["MenuBack"] then
    GAME.theme:playCancelSfx()
    GAME.navigationStack:pop()
    return
  end
  local dTab = 0
  if pressed("MenuLeft") or pressed("MenuPrevPage") then dTab = -1 end
  if pressed("MenuRight") or pressed("MenuNextPage") then dTab = 1 end
  if dTab ~= 0 then
    self.tab = (self.tab - 1 + dTab) % #TABS + 1
    self.scroll = 0
    GAME.theme:playMoveSfx()
  end
  local dRow = 0
  if pressed("MenuUp") then dRow = -1 end
  if pressed("MenuDown") then dRow = 1 end
  if dRow ~= 0 then
    if TABS[self.tab] == "Vs CPU" then
      local n = 8
      pcall(function() n = require("client.src.ChallengeMode").numDifficulties end)
      self.sel = math.max(1, math.min(n, self.sel + dRow))
    else
      self.scroll = math.max(0, math.min(self.maxScroll or 0, self.scroll + dRow))
    end
    GAME.theme:playMoveSfx()
  end
end

-- table helpers ------------------------------------------------------------
local ROW_H = 20
local TOP = 90
local BOTTOM = 440

local function header(cols, y)
  local f = U.font("bold", 11)
  for _, c in ipairs(cols) do
    U.text(c[1]:upper(), c[2], y, f, C.faint, c[3], nil, 1)
  end
end

local function sectionTitle(text, y, note)
  U.text(text, 24, y, U.font("bold", 14), C.text)
  if note then U.text(note, U.W - 24, y + 2, U.font("regular", 11), C.faint, "right") end
end

function RecordsScene:drawRows(rows, cols, y)
  -- rows: list of { cells..., highlight = bool } or { section = "title", note = "" }
  local visible = math.floor((BOTTOM - y) / ROW_H)
  self.maxScroll = math.max(0, #rows - visible)
  local fN, fB = U.font("regular", 14), U.font("medium", 14)
  local first = self.scroll + 1
  for i = first, math.min(#rows, first + visible - 1) do
    local r = rows[i]
    local ry = y + (i - first) * ROW_H
    if r.section then
      sectionTitle(r.section, ry + 2, r.note)
      if r.cols then header(r.cols, ry + 4) end
    else
      if (i % 2) == 0 then U.rect(16, ry, U.W - 32, ROW_H, C.row) end
      for j, c in ipairs(cols) do
        local v = r[j]
        local col = (j == 1) and C.dim or ((v == "–") and C.faint or C.text)
        if r.newBest and j == 2 then col = C.green end
        U.text(v, c[2], ry + 3, j == 2 and fB or fN, col, c[3])
      end
    end
  end
  if self.maxScroll > 0 then
    local f = U.font("regular", 11)
    if self.scroll > 0 then U.text("more above", U.W - 24, TOP - 16, f, C.faint, "right") end
    if self.scroll < self.maxScroll then U.text("more below", U.W - 24, BOTTOM + 2, f, C.faint, "right") end
  end
end

-- tabs ---------------------------------------------------------------------
function RecordsScene:scoreTab(mode, gameScores)
  local cols = { { "Setting", 32, nil }, { "Best", 300, "right" }, { "Last", 400, "right" },
    { "Best chain", 500, "right" }, { "Games", 600, "right" } }
  local rows = {}
  local rec = self.rec[mode]
  rows[#rows + 1] = { section = "Classic" }
  for i = 1, LevelPresets.classicPresetCount do
    local r = rec.classic[tostring(i)] or {}
    -- Panel Attack's own Classic records count too (games played before this screen existed)
    local best, last = r.best or 0, r.last
    if gameScores then
      local ok, b = pcall(gameScores.record, GAME.scores, i)
      if ok and tonumber(b) and b > best then best = b end
      if last == nil then
        local ok2, l = pcall(gameScores.last, GAME.scores, i)
        if ok2 then last = l end
      end
    end
    rows[#rows + 1] = { CLASSIC_NAMES[i] or ("Difficulty " .. i), fmtScore(best), fmtScore(last),
      fmtChain(r.bestChain), r.games and tostring(r.games) or "–" }
  end
  rows[#rows + 1] = { section = "Modern" }
  for i = 1, LevelPresets.modernPresetCount do
    local r = rec.modern[tostring(i)] or {}
    rows[#rows + 1] = { "Level " .. i, fmtScore(r.best), fmtScore(r.last), fmtChain(r.bestChain),
      r.games and tostring(r.games) or "–" }
  end
  header(cols, TOP - 22)
  self:drawRows(rows, cols, TOP)
end

function RecordsScene:challengeTab()
  self.maxScroll = 0
  local CM = require("client.src.ChallengeMode")
  local n = CM.numDifficulties or 8
  -- left: one row per difficulty
  local fN, fB = U.font("regular", 14), U.font("medium", 14)
  local cols = { { "Difficulty", 32, nil }, { "Best time", 252, "right" }, { "Clears", 318, "right" } }
  header(cols, TOP - 22)
  for i = 1, n do
    local r = self.rec.challenge[tostring(i)] or {}
    local y = TOP + (i - 1) * 30
    local sel = i == self.sel
    if sel then
      U.rrect(16, y - 2, 316, 28, 6, C.sel)
      U.rect(16, y + 2, 4, 20, C.p1)
    end
    U.text(U.fit(challengeName(i), sel and fB or fN, 150), 32, y + 4, sel and fB or fN, sel and C.text or C.dim)
    local t = fmtTime(r.bestTime)
    U.text(t, 252, y + 4, fB, t == "–" and C.faint or C.text, "right")
    U.text(r.clears and tostring(r.clears) or "–", 318, y + 4, fN, r.clears and C.text or C.faint, "right")
  end

  -- right: the selected difficulty's best run
  local x, w = 348, U.W - 348 - 16
  U.rrect(x, TOP - 18, w, BOTTOM - TOP + 18, 8, C.card)
  local r = self.rec.challenge[tostring(self.sel)] or {}
  U.text(U.fit(challengeName(self.sel), U.font("bold", 15), w - 24), x + 12, TOP - 8, U.font("bold", 15), C.text)
  if not r.bestTime then
    U.text("Not beaten yet.", x + 12, TOP + 22, U.font("regular", 13), C.muted)
    U.text("Beat every stage to set a time.", x + 12, TOP + 40, U.font("regular", 12), C.faint)
    return
  end
  local f = U.font("regular", 12)
  U.text(("Best %s  ·  %d continue%s"):format(fmtTime(r.bestTime), r.bestContinues or 0,
    (r.bestContinues == 1) and "" or "s"), x + 12, TOP + 14, f, C.muted)
  local hf = U.font("bold", 10)
  local yy = TOP + 36
  U.text("STAGE", x + 12, yy, hf, C.faint, nil, nil, 1)
  U.text("BEST RUN", x + 160, yy, hf, C.faint, "right", nil, 1)
  U.text("BEST EVER", x + w - 12, yy, hf, C.faint, "right", nil, 1)
  yy = yy + 16
  local splits = r.bestSplits or {}
  local bestStage = r.bestStage or {}
  local rowH = math.min(20, math.floor((BOTTOM - 26 - yy) / math.max(1, #splits)))
  for i, t in ipairs(splits) do
    local be = tonumber(bestStage[i]) or tonumber(bestStage[tostring(i)])
    local y = yy + (i - 1) * rowH
    U.text(tostring(i), x + 12, y, f, C.dim)
    U.text(fmtTime(t), x + 160, y, f, C.text, "right")
    U.text(fmtTime(be), x + w - 12, y, f, (be and be < t) and C.green or C.text, "right")
  end
  local fy = BOTTOM - 22
  U.text(("Fewest continues %d  ·  Last clear %s"):format(r.fewestContinues or 0, fmtTime(r.lastTime)),
    x + 12, fy, U.font("regular", 11), C.faint)
end

function RecordsScene:vsSelfTab()
  local cols = { { "Level", 32, nil }, { "Best", 360, "right" }, { "Last", 480, "right" } }
  local rows = { { section = "Garbage lines sent", note = "Vs Yourself, Modern levels" } }
  local s = GAME.scores
  for i = 1, LevelPresets.modernPresetCount do
    local best, last = 0, 0
    if s then
      pcall(function() best = s:recordVsScoreForLevel(i) or 0; last = s:lastVsScoreForLevel(i) or 0 end)
    end
    rows[#rows + 1] = { "Level " .. i, fmtScore(best), fmtScore(last) }
  end
  header(cols, TOP - 22)
  self:drawRows(rows, cols, TOP)
end

function RecordsScene:lifetimeTab()
  self.maxScroll = 0
  local a = self.analytics
  if not a then
    U.text("No stats yet.", 24, TOP, U.font("regular", 15), C.muted)
    U.text("Stats are saved after each game while Options > General > Enable analytics is on.", 24, TOP + 22,
      U.font("regular", 12), C.faint)
    return
  end
  local chains, combos = sumPairs(a.reached_chains), sumPairs(a.used_combos)
  local bigChain = chains[#chains] and chains[#chains][1] or 0
  local bigCombo = combos[#combos] and combos[#combos][1] or 0
  -- big numbers
  local tiles = {
    { "Biggest chain", bigChain >= 2 and ("x" .. bigChain) or "–" },
    { "Biggest combo", bigCombo >= 4 and tostring(bigCombo) or "–" },
    { "Panels cleared", fmtScore(a.destroyed_panels) },
    { "Garbage sent", fmtScore(a.sent_garbage_lines) },
  }
  local tw = (U.W - 32 - 3 * 10) / 4
  for i, t in ipairs(tiles) do
    local x = 16 + (i - 1) * (tw + 10)
    U.rrect(x, TOP - 18, tw, 62, 8, C.card)
    U.text(t[1]:upper(), x + 10, TOP - 10, U.font("bold", 10), C.faint, nil, nil, 1)
    U.text(t[2], x + 10, TOP + 8, U.font("display", 24), C.text)
  end
  U.text(("Swaps %s  ·  Cursor moves %s"):format(fmtScore(a.swap_count), fmtScore(a.move_count)), 24, TOP + 54,
    U.font("regular", 12), C.faint)

  -- chain and combo counts
  local y0 = TOP + 80
  local function counts(title, list, x, prefix, minKey)
    U.text(title, x, y0, U.font("bold", 14), C.text)
    local f = U.font("regular", 13)
    local y, shown = y0 + 24, 0
    for _, p in ipairs(list) do
      if p[1] >= minKey then
        if y > BOTTOM - 16 then break end
        if shown % 2 == 1 then U.rect(x - 8, y - 2, 280, 20, C.row) end
        U.text(prefix .. p[1], x, y, f, C.dim)
        U.text(fmtScore(p[2]), x + 260, y, f, C.text, "right")
        y, shown = y + 20, shown + 1
      end
    end
    if shown == 0 then U.text("None yet", x, y, f, C.faint) end
  end
  counts("Chains", chains, 32, "x", 2)
  counts("Combos", combos, 344, "", 4)
end

function RecordsScene:draw()
  G.setColor(C.bg[1], C.bg[2], C.bg[3], 1)
  G.rectangle("fill", 0, 0, 1280, 720)
  U.onScreen()
  U.text("RECORDS", 24, 14, U.font("display", 24), C.text)
  -- tab strip
  local f, fs = U.font("medium", 14), U.font("bold", 14)
  local x = 160
  for i, name in ipairs(TABS) do
    local sel = i == self.tab
    local tw = U.textWidth(name, sel and fs or f)
    if sel then U.rrect(x - 8, 16, tw + 16, 24, 12, C.sel) end
    U.text(name, x, 20, sel and fs or f, sel and C.text or C.muted)
    x = x + tw + 22
  end
  local name = TABS[self.tab]
  if name == "Endless" then
    self:scoreTab("endless", { record = GAME.scores and GAME.scores.recordEndlessForLevel, last = GAME.scores and GAME.scores.lastEndlessForLevel })
  elseif name == "Time Attack" then
    self:scoreTab("timeAttack", { record = GAME.scores and GAME.scores.recordTimeAttack1PForLevel, last = GAME.scores and GAME.scores.lastTimeAttack1PForLevel })
  elseif name == "Vs CPU" then
    self:challengeTab()
  elseif name == "Vs Yourself" then
    self:vsSelfTab()
  else
    self:lifetimeTab()
  end
  local hints = { { "L/R", "Mode" } }
  if name == "Vs CPU" then hints[#hints + 1] = { "UP/DOWN", "Difficulty" }
  elseif (self.maxScroll or 0) > 0 then hints[#hints + 1] = { "UP/DOWN", "Scroll" } end
  hints[#hints + 1] = { "B", "Back" }
  U.hintBar(hints)
  U.reset()
end

return M
