-- Installs Miyoo replacements for the LÖVE modules that need a window/GPU.
-- Must be required before any Panel Attack code.

local ffi = require("ffi")
local M = require("miyoo.m2d")
local G = require("miyoo.graphics")

local SCREEN_W, SCREEN_H = 640, 480
local noop = function() end

G._init(SCREEN_W, SCREEN_H)
love.graphics = G
package.loaded["love.graphics"] = G

---------------------------------------------------------------------------
-- love.window
---------------------------------------------------------------------------
local W = {}
local title = "Panel Attack"
local modeFlags = { fullscreen = true, fullscreentype = "desktop", vsync = 1, msaa = 0, stencil = true, depth = 0,
  resizable = false, borderless = true, centered = true, display = 1, minwidth = 1, minheight = 1, highdpi = false,
  refreshrate = 60, x = 0, y = 0, usedpiscale = false }
function W.getMode() return SCREEN_W, SCREEN_H, modeFlags end
function W.setMode() return true end
function W.updateMode() return true end
function W.getDesktopDimensions() return SCREEN_W, SCREEN_H end
function W.getPosition() return 0, 0, 1 end
function W.setPosition() end
function W.isMaximized() return false end
function W.isMinimized() return false end
function W.maximize() end
function W.minimize() end
function W.restore() end
function W.getFullscreen() return true, "desktop" end
function W.setFullscreen() return true end
function W.getFullscreenModes() return { { width = SCREEN_W, height = SCREEN_H } } end
function W.setTitle(t) title = t end
function W.getTitle() return title end
function W.setIcon() return true end
function W.getIcon() return nil end
function W.showMessageBox(t, msg) print("[messagebox] " .. tostring(t) .. ": " .. tostring(msg)); return 1 end
function W.requestAttention() end
function W.isOpen() return true end
function W.close() end
function W.hasFocus() return true end
function W.hasMouseFocus() return false end
function W.isVisible() return true end
function W.getDisplayCount() return 1 end
function W.getDisplayName() return "Miyoo Mini Plus" end
function W.getDisplayOrientation() return "landscape" end
function W.getDPIScale() return 1 end
function W.toPixels(v, v2) if v2 then return v, v2 end return v end
function W.fromPixels(v, v2) if v2 then return v, v2 end return v end
function W.setVSync() end
function W.getVSync() return 1 end
function W.getSafeArea() return 0, 0, SCREEN_W, SCREEN_H end
function W.isDisplaySleepEnabled() return false end
function W.setDisplaySleepEnabled() end
love.window = W
package.loaded["love.window"] = W

---------------------------------------------------------------------------
-- love.mouse / love.touch / love.joystick
---------------------------------------------------------------------------
local Mouse = {}
function Mouse.getPosition() return 0, 0 end
function Mouse.getX() return 0 end
function Mouse.getY() return 0 end
function Mouse.isDown() return false end
function Mouse.setVisible() end
function Mouse.isVisible() return false end
function Mouse.setGrabbed() end
function Mouse.isGrabbed() return false end
function Mouse.setRelativeMode() end
function Mouse.getRelativeMode() return false end
function Mouse.setCursor() end
function Mouse.getCursor() return nil end
function Mouse.isCursorSupported() return false end
function Mouse.getSystemCursor() return nil end
function Mouse.newCursor() return nil end
function Mouse.setPosition() end
love.mouse = Mouse
package.loaded["love.mouse"] = Mouse

love.touch = { getTouches = function() return {} end, getPosition = function() return 0, 0 end,
  getPressure = function() return 0 end }
package.loaded["love.touch"] = love.touch

love.joystick = {
  getJoysticks = function() return {} end,
  getJoystickCount = function() return 0 end,
  loadGamepadMappings = noop,
  saveGamepadMappings = function() return "" end,
  setGamepadMapping = function() return false end,
  getGamepadMappingString = function() return nil end,
}
package.loaded["love.joystick"] = love.joystick

---------------------------------------------------------------------------
-- love.keyboard + Miyoo buttons -> keys
---------------------------------------------------------------------------
-- evdev code -> LÖVE key, matching Panel Attack's default keyboard config 1:
-- Up/Down/Left/Right = arrows, Swap1 = z, Swap2 = x, TauntUp = y, TauntDown = u,
-- Raise1 = c, Raise2 = v, Start = return
local KEYMAP = {
  [103] = "up", [108] = "down", [105] = "left", [106] = "right",
  [57] = "z",         -- A
  [29] = "x",         -- B
  [42] = "y",         -- X
  [56] = "u",         -- Y
  [18] = "c",         -- L1
  [20] = "v",         -- R1
  [15] = "c",         -- L2
  [14] = "v",         -- R2
  [28] = "return",    -- Start
  [97] = "escape",    -- Select
  [1] = "escape",     -- Menu
}
local CODE_START, CODE_SELECT, CODE_MENU = 28, 97, 1
local BUTTON_NAME = { [103] = "up", [108] = "down", [105] = "left", [106] = "right", [57] = "a", [29] = "b",
  [42] = "x", [56] = "y", [18] = "l", [20] = "r", [15] = "l2", [14] = "r2", [28] = "start", [97] = "select", [1] = "menu" }

local down = {}
local K = {}
function K.isDown(...)
  for i = 1, select("#", ...) do
    if down[select(i, ...)] then return true end
  end
  return false
end
K.isScancodeDown = K.isDown
local OSK = require("miyoo.osk")
function K.setTextInput(on) if on then OSK.open() else OSK.close() end end
function K.hasTextInput() return OSK.active end
function K.setKeyRepeat() end
function K.hasKeyRepeat() return false end
function K.getScancodeFromKey(k) return k end
function K.getKeyFromScancode(k) return k end
function K.hasScreenKeyboard() return false end
function K.isModifierActive() return false end
love.keyboard = K
package.loaded["love.keyboard"] = K

local code, value = ffi.new("int[1]"), ffi.new("int[1]")
local codeDown = {}
local function pollButtons()
  OSK.flush()
  while M.m2d_poll_key(code, value) == 1 do
    local c, v = code[0], value[0]
    local key = KEYMAP[c]
    if OSK.active and (v == 1 or (v == 2 and c >= 103 and c <= 108)) then
      -- the on-screen keyboard gets the buttons while a text field is focused
      codeDown[c] = true
      if BUTTON_NAME[c] then OSK.button(BUTTON_NAME[c]) end
    elseif OSK.active and v == 0 and not (key and down[key]) then
      codeDown[c] = false
    elseif v ~= 2 then -- ignore autorepeat, the game does its own
      codeDown[c] = (v == 1)
      -- Select + Start or Menu + Start quits
      if v == 1 and c == CODE_START and (codeDown[CODE_SELECT] or codeDown[CODE_MENU]) then
        love.event.push("quit")
      end
      if key then
        if v == 1 then
          if not down[key] then
            down[key] = true
            love.event.push("keypressed", key, key, false)
          end
        else
          if down[key] then
            down[key] = nil
            love.event.push("keyreleased", key, key)
          end
        end
      end
    end
  end
end

-- hook event pumping so button presses arrive as normal LÖVE key events
local realPump = love.event.pump
love.event.pump = function(...)
  realPump(...)
  pollButtons()
end

---------------------------------------------------------------------------
-- love.audio / love.sound: real OpenAL audio when a device opens, else silent stubs
---------------------------------------------------------------------------
-- The Miyoo has no ALSA; OnionOS exposes sound through OSS (/dev/dsp) when
-- libpadsp.so is preloaded (launch.sh). OpenAL Soft's OSS backend uses that.
-- PA_NOSOUND=1 forces the silent stubs.
local function tryRealAudio()
  if os.getenv("PA_NOSOUND") then return false, "PA_NOSOUND set" end
  local ok, snd = pcall(require, "love.sound")
  if not ok then return false, "love.sound: " .. tostring(snd) end
  local ok2, aud = pcall(require, "love.audio")
  if not ok2 then return false, "love.audio: " .. tostring(aud) end
  love.sound, love.audio = snd, aud
  -- LÖVE silently falls back to a "null" device when OpenAL can't open one
  local okDev, dev = pcall(function() return aud.getPlaybackDevice and aud.getPlaybackDevice() end)
  return true, okDev and tostring(dev) or "?"
end

local function installSilentAudio()
  -- Sources are userdata (the game checks type(x) == "userdata")
  local Source = {}
  local srcState = setmetatable({}, { __mode = "k" })
  local function makeSource(stype)
    local u = newproxy(true)
    local mt = getmetatable(u)
    mt.__index = Source
    mt.__tostring = function() return "Source" end
    srcState[u] = { volume = 1, looping = false, stype = stype or "static", pitch = 1 }
    return u
  end
  local function newSource(_, stype) return makeSource(stype) end
  -- pretend playback state so the game doesn't keep restarting music
  function Source:play() srcState[self].playing = true; return true end
  function Source:stop() srcState[self].playing = false end
  function Source:pause() srcState[self].playing = false end
  function Source:resume() srcState[self].playing = true end
  function Source:isPlaying() return srcState[self].playing == true end
  function Source:isPaused() return false end
  function Source:isStopped() return not srcState[self].playing end
  function Source:setVolume(v) srcState[self].volume = v end
  function Source:getVolume() return srcState[self].volume end
  function Source:setLooping(l) srcState[self].looping = l end
  function Source:isLooping() return srcState[self].looping end
  function Source:setPitch(p) srcState[self].pitch = p end
  function Source:getPitch() return srcState[self].pitch end
  function Source:seek() end
  function Source:tell() return 0 end
  function Source:getDuration() return 0 end
  function Source:clone() return makeSource(srcState[self].stype) end
  function Source:getType() return srcState[self].stype end
  function Source:queue() return true end
  function Source:getFreeBufferCount() return 0 end
  function Source:getChannelCount() return 2 end
  function Source:setPosition() end
  function Source:setRelative() end
  function Source:setAttenuationDistances() end
  function Source:release() return true end
  function Source:typeOf(t) return t == "Source" or t == "Object" end
  function Source:type() return "Source" end
  function Source:setFilter() end
  function Source:setEffect() end

  local A = {}
  A.newSource = newSource
  A.newQueueableSource = function() return makeSource("queue") end
  A.play = noop
  A.stop = noop
  A.pause = function() return {} end
  A.resume = noop
  local masterVolume = 1
  A.setVolume = function(v) masterVolume = v end
  A.getVolume = function() return masterVolume end
  A.getActiveSourceCount = function() return 0 end
  A.setPosition = noop
  A.setOrientation = noop
  A.setDistanceModel = noop
  A.getSourceCount = function() return 0 end
  A.isEffectsSupported = function() return false end
  A.setMixWithSystem = function() return false end
  love.audio = A
  package.loaded["love.audio"] = A

  local Decoder = {}
  Decoder.__index = Decoder
  function Decoder:decode() return nil end
  function Decoder:getDuration() return 0 end
  function Decoder:seek() end
  function Decoder:getChannelCount() return 2 end
  function Decoder:getSampleRate() return 44100 end
  function Decoder:getBitDepth() return 16 end
  function Decoder:clone() return setmetatable({}, Decoder) end
  function Decoder:release() return true end
  function Decoder:typeOf(t) return t == "Decoder" or t == "Object" end
  local SoundData = {}
  SoundData.__index = SoundData
  function SoundData:getDuration() return 0 end
  function SoundData:getSampleCount() return 0 end
  function SoundData:getSampleRate() return 44100 end
  function SoundData:getBitDepth() return 16 end
  function SoundData:getChannelCount() return 2 end
  function SoundData:getSample() return 0 end
  function SoundData:setSample() end
  function SoundData:getSize() return 0 end
  function SoundData:release() return true end
  function SoundData:typeOf(t) return t == "SoundData" or t == "Object" end
  love.sound = {
    newDecoder = function() return setmetatable({}, Decoder) end,
    newSoundData = function() return setmetatable({}, SoundData) end,
  }
  package.loaded["love.sound"] = love.sound

end

local realAudio, audioInfo = tryRealAudio()
if realAudio then
  print("[audio] OpenAL playback device: " .. audioInfo)
else
  print("[audio] silent: " .. audioInfo)
  installSilentAudio()
end
G_AUDIO_ACTIVE = realAudio

---------------------------------------------------------------------------
-- love.system bits that need a window
---------------------------------------------------------------------------
if love.system then
  love.system.getClipboardText = function() return "" end
  love.system.setClipboardText = noop
  love.system.openURL = function() return false end
  love.system.vibrate = noop
end

-- the default error screen needs love.event.wait (pumps + our buttons)
if love.event and love.event.wait then
  local realWait = love.event.wait
  love.event.wait = function()
    love.timer.sleep(0.05)
    love.event.pump()
    for n, a, b, c, d, e, f in love.event.poll() do return n, a, b, c, d, e, f end
  end
end

return true
