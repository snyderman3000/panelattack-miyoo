#!/usr/bin/env python3
"""Source edits applied to a fresh copy of Panel Attack for the Miyoo port.
Each patch is an exact string replacement; the build fails if a patch no longer
applies (e.g. after updating Panel Attack), so nothing silently drifts."""
import sys, os

GAME = sys.argv[1]

PATCHES = [
    # Music: starting a stream in a thread needs the real love.audio; the Miyoo
    # build has its own audio layer, so start sources directly.
    ("client/src/music/Music.lua",
     '''local musicThread = love.thread.newThread("client/src/music/PlayMusicThread.lua")''',
     '''local musicThread = nil -- miyoo: no playback thread'''),
    ("client/src/music/Music.lua",
     '''local function playSource(source)
  if musicThread:isRunning() then
    musicThread:wait()
  end
  musicThread:start(source)
end''',
     '''local function playSource(source)
  source:play()
end'''),
    ("client/src/music/Music.lua",
     '''not musicThread:isRunning()''',
     '''true'''),
    # First-run defaults for the handheld: English, skip the Discord invite
    # screen (links can't be opened), show the fps counter.
    ("client/src/config.lua",
     "    language_code                 = nil,",
     '    language_code                 = "EN",'),
    ("client/src/config.lua",
     "    discordCommunityShown         = false,",
     "    discordCommunityShown         = true,"),
    ("client/src/config.lua",
     "    show_fps                      = false,",
     "    show_fps                      = true,"),
    # Memory: Stack.lua preallocates ~44,000 rollback tables (~35 MB) at startup
    # to smooth garbage collection on PCs. The Miyoo has ~100 MB of RAM in total,
    # so allocate them on demand instead (only online matches need them).
    ("common/engine/Stack.lua",
     "for i = 1, (15 * 6) * MAX_LAG * 2 do",
     "for i = 1, 0 do -- miyoo: no preallocation"),
    # Main menu: no "Fullscreen" entry on the handheld
    ("client/src/scenes/MainMenu.lua",
     '''    ui.MenuItem.createButtonMenuItem("mm_fullscreen", {"\\n(Alt+Enter)"}, nil, function()
      GAME.theme:playValidationSfx()
      GAME:toggleFullscreen()
    end),
''',
     ""),
    # Server address can be overridden (PA_SERVER / PA_SERVER_PORT) for testing
    ("client/src/scenes/MainMenu.lua",
     '''switchToScene(Lobby({serverIp = "panelattack.com"}))''',
     '''if not config.name or config.name == "" then switchToScene(SetNameMenu()) else switchToScene(Lobby({serverIp = os.getenv("PA_SERVER") or "panelattack.com", serverPort = tonumber(os.getenv("PA_SERVER_PORT") or "")})) end'''),
]

failed = False
for rel, old, new in PATCHES:
    p = os.path.join(GAME, rel)
    s = open(p, encoding="utf-8").read()
    n = s.count(old)
    if n != 1:
        print("PATCH FAILED (%d matches): %s :: %s" % (n, rel, old.splitlines()[0]))
        failed = True
        continue
    s = s.replace(old, new)
    open(p, "w", encoding="utf-8").write(s)
print("patches: %d applied%s" % (len(PATCHES), ", SOME FAILED" if failed else ""))
sys.exit(1 if failed else 0)
