# Ki Warriors

Anime training-and-fighting game for Roblox, built entirely in code as a [Rojo](https://rojo.space)
project. No Studio-authored parts and no uploaded assets: the planets, enemies, auras, effects
and UI are generated at runtime. Sounds are built-in `rbxasset://` content only.

All names are original (see `DESIGN.md` and `src/shared/Names.luau`). Do not add names,
characters or designs from an existing anime, manga or game.

## Open in Studio

**Option A: the prebuilt place (no Rojo needed)**

1. Open `KiWarriors.rbxlx` in Roblox Studio (File → Open from File).
2. Press **Play**. The server builds the world when it starts.

**Option B: live-sync while editing**

```
../huerta-tycoon/tools/rojo.exe serve default.project.json
```

Rebuild the place file after changes:

```
../huerta-tycoon/tools/rojo.exe build default.project.json -o KiWarriors.rbxlx
```

## Controls

| Action | PC | Touch |
|---|---|---|
| Punch (= one training rep of the selected stat) | Left mouse (hold to repeat) | Punch button |
| Ki blast | Q | Blast |
| Charged beam | hold R, release | hold Beam |
| Block | hold F | hold Block |
| Dash (short teleport, invulnerable) | E | Dash |
| Charge ki (aura) | hold C | hold Charge |
| Transform / revert | G | Form |
| Fly | Space in the air, or H. Space = up, Ctrl = down, Shift = boost. Double Space = land | Fly, then the jump button = up, extra buttons = down / boost |
| Techniques | Z / X / V | extra buttons |
| Training focus | 1–5 or click a stat | tap a stat |
| Auto Train | T or the HUD toggle | HUD toggle |
| Warp gate / altar | B | prompt |

## Project layout

```
src/shared/
  Config.luau        all content and numbers (pure data)
  Names.luau         every visible proper name, by key (one file to rename anything)
  Formulas.luau      economy and combat math (pure; used by tests)
  Locale.luau, Locales/   translations; Locale.t(lang, key, args)
  Format.luau, Referral.luau
src/server/
  Main.server.luau   bootstrap + player lifecycle
  World/WorldBuilder.luau   planets, zones, camps, boss arenas, coliseum, altar, boards
  Services/Data      DataStore profiles (session lock, reconcile, autosave)
  Services/Remotes   Request router + rate limit, Act (combat input) event
  Services/State     derived stats, currencies, replication
  Services/Fighters  combatant registry + the single damage pipeline (PvE, PvP rules)
  Services/Combat    melee combo, blasts (projectile loop), beam, block, dash, charge, forms, techniques
  Services/Training  reps (manual bucket + auto), zones, weights, movement stats
  Services/Npcs      enemies: one 10 Hz AI loop, bosses with telegraphed patterns
  Services/Auto      server-driven auto-charge and auto-fight
  Services/Progression   planets, techniques, upgrades, races, rebirth
src/client/
  Fx (pool, shake, hit-stop, quality), CombatFx (projectiles, beams, hits, numbers),
  CharFx (auras, form looks, procedural poses, tags), NpcRender (enemy models),
  Flight, Controls, WorldFx (sky per planet, animated props, localized signs),
  UI/ (Theme, Root, Hud, TouchControls, Toasts, Windows)
tests/
  AutoTest.server.luau + AutoTestClient.client.luau   gameplay playtest (test.project.json)
  Showcase*.luau                                       posed scenes for screenshots
```

## Tests

Studio playtests go through the shared runner (opens Studio on the second monitor, with a lock):

```
powershell -ExecutionPolicy Bypass -File ../huerta-tycoon/tools/studio_run.ps1 -ProjectDir . -Project test.project.json -TimeoutSec 480
```

Screenshots (call it with `&` from PowerShell so the `-Sizes` array arrives):

```
& ../huerta-tycoon/tools/studio_run.ps1 -ProjectDir . -Project showcase.project.json -Sizes "1920x1032","1920x1031",... -ShotPrefix kiw1
```

`showcase_low.project.json` previews minimum graphics (no shadows, post-processing, atmosphere,
lights or particles) and `showcase_touch.project.json` the phone layout.

## Verify

```
../huerta-tycoon/tools/rojo.exe sourcemap default.project.json -o sourcemap.json
../huerta-tycoon/tools/luau-lsp.exe analyze --definitions=../huerta-tycoon/tools/globalTypes.d.luau --sourcemap=sourcemap.json src
```

## Publish

See `LANZAMIENTO.md`.
