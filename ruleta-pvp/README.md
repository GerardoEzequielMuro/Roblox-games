# Spin Showdown

An elimination party game for Roblox, built entirely in code as a [Rojo](https://rojo.space)
project: 2 to 8 players around a wheel of effects, last one standing wins. No Studio-authored
parts and no uploaded assets: the lobby, the tables, the wheels, the bots and the UI are
generated at runtime. Sounds are the built-in `rbxasset://` ones only.

Nothing is wagered and nothing sold changes a match. Read "Policy" in `DESIGN.md` before
touching rewards or the shop.

## Open in Studio

**The prebuilt place (no Rojo needed):** open `SpinShowdown.rbxlx` (File → Open from File)
and press **Play**. The server builds the world when it starts and bots fill the tables, so
one player is enough to play.

**Live-sync while editing:**

```
../huerta-tycoon/tools/rojo.exe serve default.project.json
```

Rebuild the place file after changes:

```
../huerta-tycoon/tools/rojo.exe build default.project.json -o SpinShowdown.rbxlx
```

## Publish

See `LANZAMIENTO.md` for the full checklist. Short version:

1. **File → Publish to Roblox As…** and create a new experience.
2. **Game Settings → Security → Enable Studio Access to API Services = ON** (DataStores).
3. Create the passes and products listed in `DESIGN.md`, paste their IDs into
   `src/shared/Config.luau`, rebuild, publish again. Items with ID 0 cannot be bought.
4. Set max players to 16 and make the experience public.

## Project layout

```
default.project.json         src/shared → ReplicatedStorage.Shared
                             src/server → ServerScriptService.Server
                             src/client → StarterPlayer.StarterPlayerScripts.Client
src/shared/
  Config.luau                all content and numbers (pure data)
  MatchCore.luau             the match as a pure state machine (no Roblox APIs, no clocks)
  BotBrain.luau              what a bot does on its turn (pure)
  Rng.luau                   seeded PRNG (the server seeds it; the client never sees the seed)
  Progression.luau           levels, leagues, seasons, match rewards (pure)
  Layout.luau                where tables, seats and wheels are (server and client)
  BotModel.luau              the bots' bodies
  Quests, LiveEvents, Referral, Format, Locale, Locales/ (12 languages)
src/server/
  Main.server.luau           bootstrap + player lifecycle
  World/LobbyBuilder.luau    lobby island, Power Core, boards, 6 stages, lighting
  Services/Data.luau         DataStore profiles (session lock, reconcile, autosave, BindToClose)
  Services/Remotes.luau      Request router + rate limit, server→client events
  Services/State.luau        the only place coins / xp / trophies change; snapshot replication
  Services/Tables.luau       seating, countdowns, bots, private tables, duels, auto-queue
  Services/MatchRunner.luau  runs one match: timers, RNG, requests → core → event playback
  Services/MatchRewards.luau pays by placement
  Services/Cosmetics, Rewards, QuestService, Monetization, Leaderboard, LiveEventService,
           Social (referrals, group), CoreService (lobby clicker + auto charge)
src/client/
  Main.client.luau, Net, Lang, Prefs (lite profile), Audio, CoreClient, WorldText
  Arena/TableViews.luau      every table on this client: wheel, desks, screens, spotlights
  Arena/Wheel.luau           the wheel (wedges welded to a hub), skins, pointer, highlight
  Arena/Director.luau        match events → camera, light, sound, effects, HUD
  Arena/Cam.luau             scripted shots, shake, FOV punches, free orbit for spectators
  Arena/Mood.luau            "lights down": UI veil first, Lighting as an extra; heartbeat
  Arena/Fx.luau              pooled bolts, rings, shards, confetti, floating text
  Arena/Finishers.luau       8 elimination finishers
  Arena/Avatars.luau         reactions, emote bubbles, titles, auras
  UI/                        Theme, Root (scaling), Windows, Toasts, Hud (lobby), MatchHud,
                             MenuWindows (Play, Shop, Locker, Rewards, Quests, Ranking,
                             Invite, Settings), Popups (duel challenge, coach lines)
tests/
  unit_core.luau             rules, full bot matches, RNG, progression, policy (luau.exe)
  locale_check.luau          keys, placeholders and banned vocabulary in 12 languages
  check_keys.py              every key the code uses exists in en.luau
  AutoTest*.luau             the Studio playtest (test.project.json)
  Showcase*.luau             staged scenes for screenshots (showcase*.project.json)
```

## Tests

Outside Studio:

```
../huerta-tycoon/tools/luau.exe tests/unit_core.luau
../huerta-tycoon/tools/luau.exe tests/locale_check.luau
python tests/check_keys.py
```

Analyzer:

```
../huerta-tycoon/tools/rojo.exe sourcemap default.project.json -o sourcemap.json
../huerta-tycoon/tools/luau-lsp.exe analyze --definitions=../huerta-tycoon/tools/globalTypes.d.luau --sourcemap=sourcemap.json src
```

Studio playtest (opens Studio on the second monitor through the shared runner; it waits
for the lock if another game is testing):

```
powershell -ExecutionPolicy Bypass -File ../huerta-tycoon/tools/studio_run.ps1 -ProjectDir . -Project test.project.json -TimeoutSec 700
```

It plays full matches in every mode through the real remotes (a pilot takes the player's
turns), a second human leaving mid-match, the player walking away mid-match, spectating, a
private duel at watchable speed (suspense checks), auto-queue / auto-play, the Power Core,
cosmetics, rewards, quests, codes, receipts, events, season rollover, all 12 languages, the
part budgets and the lite profile. It prints `[TEST] PASS/FAIL` lines and a summary.

Screenshots (`-Sizes` needs the `&` call form from PowerShell):

```
& ..\huerta-tycoon\tools\studio_run.ps1 -ProjectDir . -Project showcase.project.json -TimeoutSec 500 -ShotPrefix rul1 -Sizes "1920x1032","1400x760","1100x620", ...
```

Each resize restages a scene; `ShowcaseSizes` (workspace attribute in the project file) says
how many captures each scene gets. `showcase_low.project.json` forces the lowest graphics
and the lite profile; `showcase_touch.project.json` the phone layout.

Test-only switches (workspace attributes): `ForceLite`, `ForceTouchLayout`, `ForceLanguage`.
`Config.StudioGrantAllPasses = true` grants every pass inside Studio.

## Controls

- Walk to a table and use its prompt, or press **PLAY**.
- On your turn: click a target, optionally a card, then **SPIN**; **BRAKE** (or Space) stops
  the wheel.
- Tap the Power Core in the middle of the lobby between matches.
