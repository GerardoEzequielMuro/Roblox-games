# Tap Pets Simulator

A clicker and egg-hatching pet simulator for Roblox, built entirely in code as a
[Rojo](https://rojo.space) project. There are no Studio-authored parts and no uploaded
assets: the map, the pets, the eggs and the UI are all generated at runtime. Textures and
sounds are built-in `rbxasset://` content only.

## Open in Studio

**Option A: the prebuilt place (no Rojo needed)**

1. Open `TapPetsSimulator.rbxlx` in Roblox Studio (File → Open from File).
2. Press **Play**. The server builds the world when it starts.

**Option B: live-sync while editing**

```
../huerta-tycoon/tools/rojo.exe serve default.project.json
```

Then, in Studio, open the Rojo plugin and click **Connect**.

Rebuild the place file after changes:

```
../huerta-tycoon/tools/rojo.exe build default.project.json -o TapPetsSimulator.rbxlx
```

## Publish

1. In Studio: **File → Publish to Roblox As…** and create a new experience.
2. **Game Settings → Security → Enable Studio Access to API Services = ON**. DataStores need
   this, so progress, leaderboards and receipts don't save without it (the game still runs,
   and warns the player that it can't save).
3. Game Settings → Monetization: create the game passes and developer products listed in
   `DESIGN.md`. Paste their IDs into `src/shared/Config.luau`, rebuild, and publish again.
   Items with ID 0 stay hidden.
4. Set the experience to **Public** in the Creator Dashboard.

To test paid features in Studio without real IDs, set `Config.StudioGrantAllPasses = true`.
It only works inside Studio.

## Project layout

```
default.project.json         src/shared → ReplicatedStorage.Shared
                             src/server → ServerScriptService.Server
                             src/client → StarterPlayer.StarterPlayerScripts.Client
src/shared/
  Config.luau                all content and numbers (pure data, no Roblox APIs)
  Formulas.luau              economy math (pure; also loaded by the simulation)
  Format.luau, Palette.luau  number formatting, Color3/material helpers
  Icons.luau                 shared icon pack ids (empty until uploaded: the UI falls back to emoji)
  HudUnlock.luau             which HUD buttons a player sees (the HUD grows with progress)
  PetModel.luau              PetModel.build(petId, tier, opts): procedural pets. Three rigs (quadruped,
                             cube, upright) and a species family per pet (face, ears, tail, wings);
                             rarity aura / orbs / trail in the world, `lite` builds for icons
  Locale.luau, Locales/      translations (12 languages): Locale.t(lang, key, args), resolve()
  LiveEvents.luau            Lucky Hour / Golden Weekend schedule + admin override
  Quests.luau                daily quest picks (same 3 for everyone per UTC day)
  Referral.luau              "ref:<userId>" launch data
src/server/
  Main.server.luau           bootstrap + player lifecycle
  World/WorldBuilder.luau    5 zones (border, props, 2 landmarks, lamps, horizon each), gates, egg
                             pedestals, spawn plaza, boards, lighting, sky and clouds
  Services/Data.luau         DataStore profiles (session lock, reconcile, autosave, BindToClose)
  Services/Remotes.luau      Request router + rate limit, server→client events
  Services/State.luau        derived stats, currency helpers, state replication
  Services/Tapping.luau      tap batches (token-bucket cap), Auto Tap, timers
  Services/Eggs.luau         validated hatching, luck, golden rolls, broadcasts, auto hatch
  Services/Pets.luau         inventory: equip / best / lock / delete / craft
  Services/Progression.luau  gates, teleport, anti-trespass, rebirth, gem upgrades
  Services/Rewards.luau      daily streak, gifts, codes, index rewards, friend boost
  Services/Monetization.luau passes + idempotent ProcessReceipt
  Services/Leaderboard.luau  leaderstats + global boards
  Services/LiveEventService  schedule, /event admin command, cross-server override
  Services/QuestService      daily quests, progress hooks, claims
  Services/Offline.luau      offline earnings on join + ClaimOffline
  Services/Social.luau       cross-server rare hatches, referrals, share link, group gift, notification ask
  Services/Auto.luau         Auto Tap / Auto Equip / Auto Rebirth switches (server does the work)
  Services/Plots.luau        Pet Park plots: assign on join, chest pays the offline earnings
  Services/Hooks.luau        tiny event bus (hatched, taps, crafted, gems spent, rebirth, second)
src/client/
  Main.client.luau, Net.luau, Purchase.luau, Lang.luau (client language + live re-render),
  WorldText.luau (localizes signs/prompts), LiveEventClient.luau, Ads.luau
  Guide.luau                 next objective (pure) + the beam of light to the egg / gate
  ParkFx.luau                Pet Park: owners' pets on the pedestals, sign, chest label
  Quality.luau               device / graphics profile ("lite" on phones or graphics <= 3)
  Tapper.luau                tap anywhere, batching; pooled feedback (+N pop, ring, sparks, token
                             flying into the counter, combo counter with milestones)
  PetFollow.luau             renders everyone's pets: hop / hover, face the way they walk, wings,
                             tails and ears move, blob shadows, hop on every tap
  WorldFx.luau               eggs, gate opening, per-zone sky (clock, Atmosphere, clouds, colour
                             grade, weather particles), "TpsAnim" props, zone banner
  UI/                        Theme, Root (scaling), Windows, Hud, Toasts, EggPanel,
                             HatchCinematic, PetIcon, PetsWindow, ProgressWindows
                             (Upgrades/Rebirth/Teleport/Codes & Language), StoreWindow,
                             RewardsWindow, IndexWindow, QuestsWindow, InviteWindow, Popups
sim/
  economy_sim.luau           economy simulation + auto-tuner (luau.exe)
  check_config.luau          config sanity checks
  odds_table.luau            prints the odds tables used in DESIGN.md
  set_config.py              writes tuned numbers back into Config.luau
```

## Tests

```
../huerta-tycoon/tools/luau.exe tests/unit_p0.luau        # live events, offline, referral, quests
../huerta-tycoon/tools/luau.exe tests/locale_check.luau   # every key + placeholder in every language
../huerta-tycoon/tools/luau.exe tests/policy_hud.luau     # paid random items flags/odds, progressive HUD
```

Studio playtests (they open Studio on the second monitor through the shared runner):

```
powershell -ExecutionPolicy Bypass -File ../huerta-tycoon/tools/studio_run.ps1 -ProjectDir . -Project test.project.json
```

`test.project.json` adds `tests/AutoTest*.luau` (gameplay through the real remotes, P0 features,
auto toggles, paid-random-item rules, languages, a performance measurement with budgets, no
server/client errors). `showcase_low.project.json` takes the screenshots with everything that
minimum graphics drops switched off; `showcase2` / `showcase_touch` cover every window. `showcase.project.json` poses scenes for screenshots
(`-Sizes`). Set the workspace attribute `ForceTouchLayout` to preview the phone layout on PC.

## Verify

```
../huerta-tycoon/tools/rojo.exe sourcemap default.project.json -o sourcemap.json
../huerta-tycoon/tools/luau-lsp.exe analyze --definitions=../huerta-tycoon/tools/globalTypes.d.luau --sourcemap=sourcemap.json src
../huerta-tycoon/tools/luau.exe sim/check_config.luau
../huerta-tycoon/tools/luau.exe sim/economy_sim.luau -a 20 6
```

## Controls

* Tap or click anywhere: earn Taps.
* Walk up to an egg and press **E** (or tap the prompt) to open it. **E** again = hatch x1,
  **R** = x3, **T** = toggle auto hatch.
* Walk up to a gate and use its prompt to unlock the next zone. After that, use the Teleport menu.
