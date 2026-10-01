-- Miyoo Mini Plus conf: same setup as Panel Attack's conf.lua, but without the
-- window/GPU/audio modules (replaced by miyoo/shim.lua).
require("client.src.config")
require("client.src.developer")

function love.conf(t)
  love.filesystem.setIdentity("Panel Attack")
  readConfigFile(config)

  t.appendidentity = false
  t.version = "11.5"
  t.console = false
  t.externalstorage = true
  t.gammacorrect = false
  t.accelerometerjoystick = false

  t.window = nil
  t.modules.window = false
  t.modules.graphics = false
  t.modules.audio = false
  t.modules.sound = false
  t.modules.joystick = false
  t.modules.keyboard = false
  t.modules.mouse = false
  t.modules.touch = false
  t.modules.video = false
  t.modules.physics = false

  t.modules.event = true
  t.modules.image = true
  t.modules.font = true
  t.modules.math = true
  t.modules.system = true
  t.modules.thread = true
  t.modules.timer = true
  t.modules.data = true
end
