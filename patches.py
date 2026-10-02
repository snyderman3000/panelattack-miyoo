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
    # Crash reports: never send them to the Panel Attack server. This port is
    # modified, so its crashes are ours to fix, not the Panel Attack team's.
    ("pa_main.lua",
     '''    if GAME.updater and not DEBUG_ENABLED and not os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") then
      GAME.netClient:sendErrorReport(errorData, consts.SERVER_LOCATION, 49569)
    end
''',
     '''    -- miyoo: crash reports are never sent to the Panel Attack server
'''),
    ("pa_main.lua",
     '''"Error: Please share your crash.log with the developers to get help with this!\\n"''',
     '''"Error: this is the UNOFFICIAL Miyoo Mini Plus port of Panel Attack.\\nPlease report this crash at github.com/snyderman3000/panelattack-miyoo/issues\\n(attach Roms/PORTS/Games/PanelAttack/log.txt), NOT to the Panel Attack team.\\n"'''),
]

MARK ="-- Modified for the Miyoo Mini Plus port (https://github.com/snyderman3000/panelattack-miyoo); see MODIFIED.txt\n"

failed = False
changed = []
for rel, old, new in PATCHES:
    p = os.path.join(GAME, rel)
    s = open(p, encoding="utf-8").read()
    n = s.count(old)
    if n != 1:
        print("PATCH FAILED (%d matches): %s :: %s" % (n, rel, old.splitlines()[0]))
        failed = True
        continue
    s = s.replace(old, new)
    if not s.startswith(MARK):
        s = MARK + s
    if rel not in changed:
        changed.append(rel)
    open(p, "w", encoding="utf-8").write(s)
# zlib license, clause 2: altered versions must be plainly marked as such
with open(os.path.join(GAME, "MODIFIED.txt"), "w", encoding="utf-8") as f:
    f.write("""This is a MODIFIED version of Panel Attack, not the original software.

It is an unofficial port to the Miyoo Mini Plus (OnionOS), made by
snyderman3000 with Claude (Anthropic) and not affiliated with the Panel Attack
team. Original game: https://github.com/panel-attack/panel-game
Port source and the full list of changes: https://github.com/snyderman3000/panelattack-miyoo

These changes may have introduced bugs that the original game does not have.
Report every problem with this port at
https://github.com/snyderman3000/panelattack-miyoo/issues, never to the Panel
Attack team. This port never sends crash reports to the Panel Attack server.

Changes compared with the original source:
- main.lua was renamed to pa_main.lua; a new main.lua and conf.lua start the
  Miyoo layer first.
- Added: miyoo/ (renderer bindings, graphics/input/audio replacements,
  handheld UI, on-screen keyboard, runtime patches) and the fonts in miyoo/fonts.
- Crash reports are not sent to the Panel Attack server, and the crash
  screen points to this port's issue tracker.
- Online play is off unless online.cfg turns it on.
- Edited (each file is marked at the top):
""")
    for rel in changed:
        f.write("    " + rel + "\n")
    f.write("""- Removed to save memory: the Simple and Sharp panel sets, the theme's
  background pictures and overlay, the stage background pictures, and tests.
- Sound: the theme's menu and game sound effects (licensed to official Panel
  Attack releases only) and the default chain sound are replaced with new
  public-domain sounds made for this port; character voice clips are trimmed
  to at most three variants each; all audio is re-encoded to mono.

Panel Attack's license (zlib) and asset credits are in COPYING and COPYING-ASSETS.
""")

print("patches: %d applied%s" % (len(PATCHES), ", SOME FAILED" if failed else ""))
sys.exit(1 if failed else 0)
