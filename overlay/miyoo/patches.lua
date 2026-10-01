-- Runtime tweaks to Panel Attack for the Miyoo Mini Plus. Applied after the
-- game's modules are loaded and before love.load runs.

local CustomRun = require("client.src.CustomRun")
local GraphicsUtil = require("client.src.graphics.graphics_util")
local FileUtils = require("client.src.FileUtils")

-- 1) Frame pacing: present() already waits for the display's vertical blank,
--    so the game's own sleep would only add delay.
if not os.getenv("PA_HOST_TEST") then
  CustomRun.sleep = function()
    CustomRun.runMetrics.previousSleepEnd = love.timer.getTime()
    CustomRun.runMetrics.sleepDuration = 0
  end
end

-- 2) Images: prefer the smallest (@1x) version of each asset. We draw at half
--    resolution anyway, so decoding @2x/@3x files only costs time and memory.
local scales = { 1, 2, 3 }
function GraphicsUtil.loadImageFromSupportedExtensions(pathAndName)
  for _, extension in ipairs(FileUtils.SUPPORTED_IMAGE_FORMATS) do
    for _, scale in ipairs(scales) do
      local image = GraphicsUtil.privateLoadImageWithExtensionAndScale(pathAndName, extension, scale)
      if image then return image end
    end
  end
  return nil
end


-- 3) One controller: give it to player 1 straight away instead of asking the
--    player to "hold a button on the device you want to use".
do
  local InputDeviceOverlay = require("client.src.scenes.components.InputDeviceOverlay")
  local inputManager = require("client.src.inputManager")
  local original = InputDeviceOverlay.openInputDeviceOverlayIfNeeded
  InputDeviceOverlay.openInputDeviceOverlayIfNeeded = function(self)
    if not self.active and #self.players == 1 and not self.players[1]:hasInputConfiguration() then
      local config = inputManager.inputConfigurations[1]
      if config and not config.claimed then
        self.players[1]:restrictInputs(config)
        if self.updatePlayerSlots and self.playerSlots then pcall(self.updatePlayerSlots, self) end
        return
      end
    end
    return original(self)
  end
end

-- 4) Lighter match graphics: the darkened character portrait behind each board
--    costs a large blend + fill per board every frame. Off unless PA_PORTRAITS=1.
if not os.getenv("PA_PORTRAITS") then
  local ClientStack = require("client.src.ClientStack")
  ClientStack.drawCharacter = function() end
end

-- 4b) Handheld UI: match layout, menus, character select, lobby
do
  require("miyoo.hud").install()
  require("miyoo.menus").install()
  require("miyoo.charselect").install()
  require("miyoo.lobby").install()
end

-- 4c) Sound: Panel Attack's default volumes (50% master x 50% music/SFX) are
--     very quiet on the handheld's small speaker. Raise them once; after that
--     the player's own settings are kept (marker file in the save folder).
if G_AUDIO_ACTIVE and not love.filesystem.getInfo("miyoo_volume_v1") then
  config.master_volume = 100
  config.SFX_volume = 80
  config.music_volume = 60
  pcall(write_conf_file)
  love.filesystem.write("miyoo_volume_v1", "1")
end

-- 4d) Release builds: the FPS counter was on by default in the test builds;
--     switch it off once (it stays available in Options > General), and keep
--     Panel Attack's log to warnings and errors unless PA_DEBUG is set.
if not love.filesystem.getInfo("miyoo_fps_off_v1") then
  config.show_fps = false
  pcall(write_conf_file)
  love.filesystem.write("miyoo_fps_off_v1", "1")
end
if not os.getenv("PA_DEBUG") then
  local logger = require("common.lib.logger")
  logger.setLogLevel(logger.levels.WARN)
end

-- 5) Optional frame-time log (PA_PROFILE=1): average update/draw/present per 5 s
if os.getenv("PA_PROFILE") then
  local inner = CustomRun.innerRun
  local acc = { n = 0, u = 0, d = 0, p = 0, maxFrame = 0 }
  local last = love.timer.getTime()
  local frameStart = love.timer.getTime()
  love.runInternal = function()
    local r1, r2 = inner()
    local m = CustomRun.runMetrics
    local now = love.timer.getTime()
    acc.n = acc.n + 1
    acc.u = acc.u + m.updateDuration
    acc.d = acc.d + m.drawDuration
    acc.p = acc.p + m.presentDuration
    acc.maxFrame = math.max(acc.maxFrame, m.updateDuration + m.drawDuration)
    if os.getenv("PA_TRACE_ALL") then
      local scene2 = GAME and GAME.navigationStack and GAME.navigationStack.scenes
      scene2 = scene2 and scene2[#scene2] and scene2[#scene2].name
      if scene2 == "GameBase" then
        traceCounter = (traceCounter or 0) + 1
        if traceCounter == 300 and not love.graphics._traceDone then love.graphics._traceAll = {} end
        if traceCounter == 301 and love.graphics._traceAll and not love.graphics._traceDone then
          local agg = {}
          for _, l in ipairs(love.graphics._traceAll) do
            local name, px, b = l:match("(.*)|(%d+)|(%d+)")
            local short = name:gsub("^.*/assets/", "")
            local k = short .. " b" .. b
            local e = agg[k] or { n = 0, px = 0 }
            e.n, e.px = e.n + 1, e.px + tonumber(px)
            agg[k] = e
          end
          local list = {}
          for k, e in pairs(agg) do list[#list + 1] = { k, e.n, e.px } end
          table.sort(list, function(a, b) return a[3] > b[3] end)
          for i = 1, math.min(40, #list) do print(string.format("[draw] %4d calls %7d px  %s", list[i][2], list[i][3], list[i][1])) end
          love.graphics._traceAll = nil
          love.graphics._traceDone = true
        end
      end
    end
    if os.getenv("PA_TRACE_BIG") then
      love.graphics._traceBig = (acc.n == 100)
    end
    if now - last >= 5 then
      local scene = GAME and GAME.navigationStack and GAME.navigationStack.scenes
      scene = scene and scene[#scene] and scene[#scene].name or "?"
      print(string.format("[perf] %-16s fps %5.1f | update %5.2f ms | draw %5.2f ms | present %5.2f ms | worst u+d %5.1f ms | lua %.1f MB",
        scene, acc.n / (now - last), acc.u / acc.n * 1000, acc.d / acc.n * 1000, acc.p / acc.n * 1000,
        acc.maxFrame * 1000, collectgarbage("count") / 1024))
      if os.getenv("PA_FULLGC") then collectgarbage("collect"); collectgarbage("collect") end
      print(string.format("[perf]   lua after gc %.1f MB | textures %.1f MB", collectgarbage("count") / 1024,
        love.graphics.getStats().texturememory / 1048576))
      if love.graphics._imageLog and not love.graphics._imageLogShown and scene == "EndlessGame" then
        love.graphics._imageLogShown = true
        local list = love.graphics._imageLog
        local byDir = {}
        for _, e in ipairs(list) do
          local dir = e.name:match("^(.*)/[^/]*$") or e.name
          byDir[dir] = (byDir[dir] or 0) + e.bytes
        end
        local dirs = {}
        for d, b in pairs(byDir) do dirs[#dirs + 1] = { d, b } end
        table.sort(dirs, function(a, b) return a[2] > b[2] end)
        for i = 1, math.min(25, #dirs) do print(string.format("[tex] %6.2f MB  %s", dirs[i][2] / 1048576, dirs[i][1])) end
      end
      local ffi = require("ffi")
      local st = ffi.new("double[8]")
      require("miyoo.m2d").m2d_stats(st)
      local n = acc.n
      print(string.format("[perf]   per frame: blits %d (copy %dk px, alpha %dk px, generic %dk px, scaled %dk px) fills %d (%dk px) clear %dk px",
        st[0] / n, st[1] / n / 1000, st[2] / n / 1000, st[3] / n / 1000, st[7] / n / 1000, st[6] / n, st[4] / n / 1000, st[5] / n / 1000))
      acc = { n = 0, u = 0, d = 0, p = 0, maxFrame = 0 }
      last = now
    end
    return r1, r2
  end
end


-- LuaJIT sampling profiler for development (PA_JITPROF=<outfile>)
if os.getenv("PA_JITPROF") then
  local ok, jp = pcall(require, "jit.p")
  if ok then
    local started = false
    local inner = love.runInternal
    local frames = 0
    love.runInternal = function()
      frames = frames + 1
      local scene = GAME and GAME.navigationStack and GAME.navigationStack.scenes
      scene = scene and scene[#scene] and scene[#scene].name
      if not started and scene == "GameBase" then
        frames = 0
        jp.start(os.getenv("PA_JITMODE") or "Fi1", os.getenv("PA_JITPROF"))
        started = true
      elseif started and frames == 1200 then
        jp.stop()
        started = "done"
      end
      return inner()
    end
  end
end

return true
