# Brief: make a Roblox game work great on phone, tablet and PC + real playtest

The user is gaming on the PRIMARY monitor. Rules:
- NEVER launch Roblox Studio (or any window) directly. Only through the runner below, which opens Studio on the
  SECOND monitor, gives focus back to the user, serializes runs with a lock, and closes Studio at the end.
- Other agents use the same runner; if it waits on the lock, that's normal.

## Tools (all in C:/work/_Personal/proyectos/huerta-tycoon/tools)
- `rojo.exe`, `luau-lsp.exe` + `globalTypes.d.luau` (analyzer), `luau.exe`.
- Runner: `powershell -File C:/work/_Personal/proyectos/huerta-tycoon/tools/studio_run.ps1 -ProjectDir <game dir> -Project <x.project.json> [-Sizes "1920x1032","1400x760","1050x600"] [-ShotPrefix name] [-TimeoutSec 300]`
  It builds the project, opens it, a local plugin starts a real playtest (needs `ServerStorage.__AutoTest` BoolValue in the project),
  and prints every Output line containing `[TEST]` plus errors (`CreatorError`, stack traces). The test ends when a server script calls
  `game:GetService("StudioTestService"):EndTest(value)`.
  With `-Sizes` it resizes the Studio window 14 s after the playtest starts, waiting 7 s per size, and saves screenshots to
  `C:\work\_Personal\media\roblox-shots\<prefix>-<size>.png` — LOOK at them with the Read tool (they're images).
  Window 1050x600 gives a ~570x345 game viewport (smaller than any phone: worst case), 1400x760 ≈ 920x505 (phone landscape/small tablet), 1920x1032 ≈ 1436x777 (PC).
- UI audit: `python C:/work/_Personal/proyectos/huerta-tycoon/tools/uiaudit/make_project.py <game dir>` writes `<game dir>/uiaudit.project.json`
  (the game + an audit LocalScript that prints, per viewport size: offscreen elements, buttons with min side < 40 px, text overflow,
  + a server script that ends the test after 75 s). Run it with the runner and `-Sizes`.
- Client-set attributes do NOT replicate to the server; for test signalling client→server use a RemoteEvent.

## Definition of done (mobile/tablet/PC)
1. Main ScreenGui(s) use `ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets` (or position below the Roblox topbar) so nothing collides with
   the Roblox menu/chat buttons at the top-left, and nothing sits offscreen at any of the 3 sizes.
2. On touch devices (UserInputService.TouchEnabled and not KeyboardEnabled) the Roblox thumbstick (bottom-left ~35% x 40%) and jump button
   (bottom-right ~ 25% x 35%) zones stay free of your buttons. You can't emulate touch in this runner, so make the layout logic explicit
   (e.g. a `isTouch` branch that moves bottom-corner buttons up/inward) and reason about it; test the non-touch path visually.
3. Tappable buttons ≥ 44 px on their short side at the ~920x505 viewport; the 570x345 case may be tighter but must not overlap or clip.
4. The default Roblox PlayerList must not cover your buttons on small screens (hide it with StarterGui:SetCoreGuiEnabled(PlayerList,false)
   when viewport width < 1000, or keep your right-side UI below it).
5. No overlapping panels/HUD elements at any size; text readable (TextScaled with UITextSizeConstraint min ~12 or explicit sizes).
6. Looks polished at PC size too (don't blow things up).
7. Analyzer: 0 errors. Commit in the game repo with a clear message.

## Gameplay playtest (real, in Studio)
Write/keep `tests/` harness in the game repo (see C:/work/_Personal/proyectos/huerta-tycoon/tests + test.project.json as the reference pattern):
a server script that waits for the player, exercises the core loop through the real remotes from a client LocalScript, prints
`[TEST] PASS/FAIL ...` lines and calls EndTest. Must include "no server errors" and "no client errors" checks (LogService.MessageOut).
Fix every real bug found. Iterate until everything passes.

Report back (short): what you changed, final audit numbers per size, playtest PASS/FAIL counts, screenshot paths, anything still unverified.
