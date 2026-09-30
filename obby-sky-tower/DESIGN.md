# Sky Tower Obby — design

A 1,000-stage obby: ten towers of 100 stages each, joined by portals. Everything (map, UI, effects)
is generated in code from a fixed seed, so every server has identical towers and there are no
uploaded assets.

## Core loop

1. Spawn in the lobby → walk under the START arch onto checkpoint 0 of tower 1.
2. Clear a stage → land on the next checkpoint pad → **coins + celebration**.
3. Fail → respawn on your last **save pad** (saved in the DataStore; falling 28 studs below it
   teleports you back instead of killing you).
4. Every 10 stages the world changes (colours, materials, sky) and there is a **shop deck** with
   power-ups for coins.
5. Stage 100 → summit of tower 1: Wins +1, badge, +250 coins, the first **gift**, the free
   **Winner's Lounge** and a **portal** to tower 2.
6. Towers 2–10 (stages 101–1000): each has its own sky and palette, a harder curve and a different
   gift on its summit. The portal on each summit leads to the base island of the next tower.
7. **Rebirth** (win panel or the pedestal on the summit of tower 1) → back to stage 0 for a new
   ranked run. Best stage, gifts, coins and wins stay.
8. A summit pays its Win (tower 1) and its coin bonus **once per run** (`profile.runTop`,
   `Rules.summitRewarded`): the teleporter to the world under a summit gives that summit up until
   the next rebirth, so Top Wins can't be farmed with 10-stage climbs.

Boards in the lobby: **Top Wins**, **Fastest Climb** (tower 1, unassisted runs only) and
**Highest Stage** (of the 1,000).

## The jump

Classic Roblox jump, nothing else: **JumpPower 50 (6.37 studs high), WalkSpeed 16, gravity 196.2**
(`Layout.Physics`, `Config.JumpPower`). `tests/layout_test.luau` refuses a JumpPower over 50.
Speed / gravity coils are **off by default** (they are a shop power-up or a pass the player turns on)
and Studio does not pretend you own the passes (`Config.StudioOwnsPasses = false`).

## The towers

- Hexagonal spiral: pad *k* sits on a circle of radius 60 at angle 90° + k·60°, so every stage is
  a 60-stud straight run and the stage six steps higher is on the same side, well overhead.
  A core pillar (one segment per world) fills the middle. Each tower climbs ~1,060 studs.
- Tower *t* stands 2,400 studs further along +X (`Layout.towerOrigin`). Global stage
  `g = (t-1)·100 + slot`.
- **Only what is needed exists.** Tower 1 is always in Workspace; towers 2–10 are built when
  somebody is on the last ten stages of the tower before (or on its summit), and destroyed 75 s
  after nobody needs them (`server/Towers.luau`, `Rules.towersNeeded`). A player never needs more
  than two towers. On top of that the place uses `StreamingEnabled` (min radius 128, target 448),
  so a client holds only its own stretch.
- Worlds: the ten looks (Grassy Hills, Candy Land, Frozen Peaks, Desert Ruins, Lava Caves, Ocean
  Reef, Toxic Factory, Cloud Kingdom, Neon Space, Rainbow Summit) rotate by 3 per tower, and each
  tower has a **mood** (`Shared/TowerStyle`: Sky, Sunset, Midnight, Storm, Crystal, Inferno, Frozen,
  Toxic, Void, Rainbow) that shifts hue / saturation / brightness of every colour and grades the
  sky, so the same world never looks the same twice.

### Difficulty curve

All of it is measured by the test against the real jump physics (air time × WalkSpeed), not
against a rule of thumb.

| Stretch | Share of the physical jump reach a hop may use | Notes |
|---|---|---|
| 1–10 | 42% → 58% | tutorial, hand-picked kinds |
| 11–50 | 60% → 80% | kinds unlock, platforms shrink (5.1 → ~4 studs) |
| 51–100 | → 89% | lasers, wind and mixed stages; rest pads appear |
| 101–1000 | → 91.5%, capped at **93%** (`Layout.MAX_REACH`) | platforms down to 3.2 studs, faster movers / lasers, more kill bricks |

A hop never climbs more than 4.4 studs (`MAX_STEP`, 70% of the jump apex). Measured by the test:
tower 1 uses 45% → 79% of the reach from its first to its last world; towers 2–10 average 78–82%;
the hardest hop of the whole game uses 93.0%.

**Checkpoints get scarcer**: every pad saves up to stage 50; from 51 to 300 every second pad is a
*rest pad* (you can stand on it, it does not save); after 300 only pads ending in 0, 3 and 6 save.
The first pad of every world always saves.

## Obstacle library (17 kinds)

| Kind | What it is | Runtime |
|---|---|---|
| `jumps` | Classic hops over gaps, platforms shrink with difficulty | static |
| `killbricks` | Floor pieces separated by kill strips (+ kill cubes later, never covering a whole platform) | `Kill` tag → Health = 0 |
| `beam` | Long narrow beams | static |
| `conveyor` | Belts pushing you back or sideways, chevrons show the direction | `AssemblyLinearVelocity` on anchored parts |
| `truss` | Walkway → climb a truss → hop to the pad | `TrussPart` |
| `bounce` | Pad launches you up to a high ledge | client sets upward velocity on the local character |
| `disappear` | Platforms fade out after you touch them | server `Touched` + tween |
| `moving` | Platforms sliding sideways or up and down, rails show the travel | one server loop, `BulkMoveTo` |
| `spinner` | Wide platforms with rotating kill bars to jump over | same loop |
| `ice` | Frictionless ice | static |
| `glass` | Glass platforms invisible until you are close | client-side transparency |
| `falling` | Planks shake then drop | server `Touched` + tween |
| `lava` | Staircase over a lava floor that rises on a timer | same loop + backup kill check |
| `wallhop` | Small ledges stuck to a tall wall | static |
| `laser` | A gate with a beam that is on for part of a cycle; posts and a lamp show the timing | same loop; the test checks there is time and room to pass |
| `wind` | A zone that drifts you sideways while you are in the air (at most 60% of WalkSpeed, so you can always steer against it) | client moves the local character |
| `mixed` | Two of the above in one stage | — |

Animated obstacles only run near players: each tower keeps them grouped by stage and the single
server loop touches the stages from 2 behind to 8 ahead of each player (`Obstacles.isAwake`).

## Shops on the route

A wooden deck on the outer side of the first pad of every world (pads 10, 20 … 90 of each tower),
with one pedestal per item: a small model of the item, its name and its price. Walk up and press
the prompt. Everything is validated and applied by the server (`server/Shops.luau`, rules in
`Shared/Powerups.luau`) and saved in the profile, so it survives a rejoin.

| Item | Coins | What it does | Permanent version |
|---|---|---|---|
| Speed Coil | 60 | WalkSpeed 24 for 3 min | pass `SpeedCoil` |
| Gravity Coil | 60 | low gravity for 3 min | pass `GravityCoil` |
| Double Jump | 90 | one extra jump in the air for 5 min | pass `DoubleJump` |
| Shield | 40 | absorbs one kill brick / laser hit (up to 3 charges) | — |
| Coin Magnet | 50 | pulls in nearby coins for 5 min | — |
| Skip Stage | 150 | skips the next stage | product `SkipStage` |
| Pocket Checkpoint | 80 | place a checkpoint where you stand (up to 3 charges) | pass `InfiniteRevives` |

Nothing is random: a pedestal gives exactly what it says. There are no paid random items in the
game (if one is ever added it needs odds in % that add up to 100, no "nothing" outcome and the
`PolicyService.ArePaidRandomItemsRestricted` check; `tests/rules_test.luau` holds that rule).

**Assisted runs are not ranked.** Skips, coils, power-ups, abilities, the glider / cloud and the
teleporter mark the run (`Session.assist`, `Rules.ranked`): the HUD timer turns grey with "not
ranked" and the run does not enter Fastest Climb. Progress, coins and gifts still count.

`tests/layout_test.luau` proves that no deck (nor the head-room over it) is touched by any
platform or hazard of any stage in the ten towers.

## Winner's Lounge (free items)

A terrace beyond the summit room of tower 1, open to everybody who has reached stage 100
(`Shared/Perks.luau`, `server/Lounge.luau`). Everything is free:

- **Teleporter**: to the lobby (keeps your checkpoint) or the start of any world you have already
  reached (a panel lists them).
- **Glider** and **Cloud** (explore mode): fly around the map. Checkpoints do not count while one
  is on, and turning it off returns you to your checkpoint, so they cannot skip stages.
- **Dash** and **Triple Jump** (abilities): they do count for progress, in assisted runs.
- **Skins**: four body glows (gold, cyan, pink, green; rainbow for owners of the stage-700 gift),
  two jump effects, two trails and an aura.

## A gift every 100 stages

Ten fixed gifts, one per summit (`Shared/Gifts.luau`); a plinth next to each portal shows the gift
of that summit, and the HUD names the next one at all times.

| Stage | Gift |
|---|---|
| 100 | Summit Flame trail (+ the lounge) |
| 200 | Cloud Buddy pet |
| 300 | Lucky Charm: ×1.5 coins for ever |
| 400 | Aurora aura |
| 500 | Title "Halfway Legend" |
| 600 | +1 free skip with every daily reward |
| 700 | Rainbow glow skin |
| 800 | Comet trail |
| 900 | Diamond Charm: ×2 coins for ever |
| 1000 | Sky Crown + title "Conqueror of 1000" |

## HUD

Minimal, the way tower games do it (`UI/Hud.luau`, `UI/Progress.luau`, `UI/Cards.luau`):

- **Top centre**: the run timer, big and thin; under it the best time or "not ranked".
- **Right edge**: a thin vertical bar for the tower you are on (ten world-coloured segments,
  bottom = stage 0) with everybody's head next to it. The default player list stays closed.
- **Bottom left**: *Menu* + coins + wins. Menu opens the grid (shop, store, rewards, settings,
  invite, share, group gift, starter pack); a red badge on it means something is waiting.
  Active power-ups show as small chips above it.
- **Bottom centre**: the level bar (stage N of 1,000, a tick on every summit, the tower's name and
  the next gift over it) and, under it, the action buttons: Skip Stage, Skip 10, Checkpoint, Lobby
  (+ Enter Portal / Stop exploring / Dash / Save here when they apply).
- **Offers** (stuck on a stage, notification opt-in) are a slim strip under the timer with the
  options side by side, not a popup.
- **Touch**: the corner block moves under the Roblox buttons (the thumbstick owns the bottom
  left), the actions become a column on the right above the jump button, the level bar sits in
  the free band between thumbstick and jump button.
- The "(Studio test)" skip needs Studio **and** a test flag (`Rules.studioTools`:
  `Config.StudioFreeSkips`, off by default, or the Workspace attribute `StudioTestTools` that only
  `test.project.json` sets). A normal Studio playtest and a published game never show it.
- The rebirth window shows what you lose (red) next to what you keep (green).

## Performance

Budgets are tests (`tests/AutoTest*.luau`, the playtest fails if one is exceeded): parts per
tower ≤ 7,200, lobby ≤ 700, lights ≤ 110, emitters ≤ 110, world GUIs ≤ 560 per tower, animated
obstacles awake per player ≤ 90, server Heartbeat ≤ 20 ms, client parts in the lobby ≤ 5,200,
biggest State push ≤ 2,600 bytes, idle remote traffic ≤ 0.5 events/s, at most two towers per
player in Workspace, client frame ≥ 30 fps (or render CPU ≤ 16 ms when Studio caps the window),
draw calls in the lobby ≤ 2,500.

- One server loop for every mover / spinner / lava / laser, only for stages near a player.
- Cosmetic loops (coins, kill-brick pulse, chevrons, glass) are client-only and only within
  170 studs of the camera.
- HUD: no per-frame layout; text and gradients are rewritten only when the value changes.
- **Lite profile** (`Shared/Quality.luau`): phones / tablets and the graphics slider at 1–3 get no
  bloom / sun rays, no scenery particles or point lights, half of the ambient particles and a
  110-stud cosmetic radius. Obstacle particles (lava embers, wind streaks) stay: they are
  information. PC at normal quality is untouched.
- **Minimum graphics**: what tells the worlds apart is baked into part colours, sky colour and
  shapes, not post-processing (`shotslow.project.json` takes the screenshot tour that way).

## Visual layer

Everything is still built in code with native materials, built-in mesh shapes and the particle
textures that ship with Roblox (`rbxasset://`): no uploaded assets, no sounds.

| What | Where | Notes |
|---|---|---|
| **Sky by height** | `Shared/Ambience.luau` (10 profiles: clock, brightness, ambient, atmosphere, tint, bloom, sun rays, stars) + `client/World/Atmos.luau` | The client samples the camera height ~15 times a second and blends the two neighbouring profiles from 22 studs below a world boundary to 8 above it. Lighting set on a client is local, so every player sees the sky of the world they are in. Meadow afternoon -> pink candy dusk -> cold misty morning -> golden hour -> red cave dusk -> teal reef -> green smog -> bright cloud morning -> starry midnight -> sunrise. |
| **Scenery** | `Shared/DecorPlan.luau` (pure positions) + `server/Scenery.luau` (parts) | Per world: 9 floating set pieces outside the spiral (islands and a windmill, lollipops and cupcakes, icebergs, pyramids and ruins, volcanic rocks, corals and jellyfish, smokestacks and goo tanks, cloud castles, ringed planets and neon cubes, rainbows and crystals), 12 ornaments on the core pillar, and a halo around the tower at each world boundary. Clouds are tinted per world. Every scenery part is anchored with CanCollide / CanTouch / CanQuery off and no shadow; `DecorPlan.clearOfLane` keeps every piece at least 8 studs from the lane. |
| **Core pillar** | `StageGenerator.buildCore` | One segment per world in the world's material (a tree trunk in world 1) with six pilasters. |
| **Platforms** | `Scenery.dressPlatform` | Static platforms get a top layer (turf on dirt, snow on ice, frosting on cake...), a darker underside and, for about a third, a prop hanging below (roots, icicles, drips, crystals...). Only the original slab is solid. |
| **Obstacle read** | `StageGenerator.topIcon` / `moverRails`, `client/World/Juice.luau` | A glyph painted on top: arrows on movers (plus a rail with glowing stops showing the travel), an hourglass on platforms that fade, down arrows on planks that drop, an up arrow on bounce pads. Kill bricks pulse. Moving platforms are lightened so they never look like a kill brick. |
| **Checkpoints** | `StageGenerator.buildPad`, `Juice` | A flag on every pad, a pale inlay + glowing centre dot painted on it, and the stage number floating over the flag pole (clear of the name tag of whoever stands on the pad). Per player: reached pads turn green and raise their flag, the next pad has a light beacon and a breathing ring. |
| **Juice** | `Juice`, `UI/Celebrate` | Checkpoint: two shockwave rings + sparkle burst on the pad + camera FOV kick. World change / win: a coloured ribbon behind the subtitle. Death: red flash, smoke puff, sparks, short camera shake. Respawn: a white ring. Coins burst into sparkles. Lobby balloons bob. |
| **Lobby** | `Scenery.buildLobby` | The floor is a floating island (rock tapering underneath, a sea of clouds), with a plaza around the spawn, lamp posts and flower beds along the path, banners and glowing orbs on the START arch, a marble plinth and a gold-framed title plate on the tower, and two hot-air balloons. |
| **Victory room** | `Scenery.buildVictory` | Glowing floor rim, two giant golden cups, a rainbow over the WINNER sign, four searchlight beams, a cloud bank underneath. |
| **UI** | `UI/Kit`, `UI/Progress`, `UI/Intro` | Buttons: darker 3D lip, hover (grow + white outline), pressed (face slides onto the lip). Panels: drop shadow (hidden where it would not fit on a phone) + a dark veil over the rest of the screen (tap it to close). The progress bar is painted in the ten world colours. A title card plays for ~2.5 s on join. |
| **Effects switch** | Settings -> *Visual effects* (`profile.settings.effects`) | Off: no bloom / sun rays, no shockwaves, flashes or camera kicks, and the scenery's particle emitters and point lights are disabled locally. For slow phones. |

Budgets (checked by the Studio playtest): workspace < 9,000 parts (currently ~5,300), scenery
<= 80 point lights (no shadows) and <= 60 low-rate particle emitters.

## Economy

- Coins: `5 + 2·min(floor(stage/10), 25)` per new stage in the current run, 3 per coin pickup
  (1–2 per stage, once per run), 250 per summit, plus daily / play-time / codes.
  VIP ×1.5, 2x Coins pass ×2, gift charms ×1.5 / ×2 (the best charm counts).
- Coin sinks: the shop decks on the route (40–150 per item), 8 trails (100 → 6,000) and 4 effects
  (400 → 2,500). VIP gets a gold trail; each win unlocks a rebirth trail colour.
- Free skips (daily day 7, play-time 30/60 min, SKYHIGH code, the stage-600 gift) are used before
  the Robux prompt.

## Retention and monetization features (P0)

| Feature | How it works |
|---|---|
| **Stuck? skip offer** | Deaths and fall-catches on the same stage are counted (session only). Every 4th in a row (at most once per 90 s) the server fires `OfferSkip`; the client shows a slim strip under the run timer for 10 s: *Use free skip (xN)* / *Skip free - watch a video* (only if `AdSkip` is set and `AdService` says a rewarded video is available) / *Skip - R$ price*. Ads: `Request("WatchAd", {placement="skip"})`, 6 per UTC day; the reward arrives as a receipt for the `AdSkip` product and skips exactly one stage. |
| **Run timer + Fastest Climb** | A run starts when you leave stage 0 (after joining at 0 or a rebirth) and ends on the summit of tower 1. Any help (skip, coil, power-up, ability, glider / cloud, teleporter), or joining mid-climb, makes it unranked (grey HUD timer, "not ranked"). A ranked win saves `bestRunMs` and writes the `SkyTowerObby_Fastest_v1` OrderedDataStore; a second lobby board shows the 10 fastest (ascending). |
| **Invite + share link** | HUD *Invite* (game invite) and *Share* (`SocialService:PromptLinkSharingAsync`) carry `LaunchData = "ref:<userId>"`. A new player (best < 5) who joins with it gets +1 free skip +50 coins; when they reach stage 5 the inviter is queued in `SkyTowerObby_Referrals_v1` and gets +1 free skip +100 coins per friend (drained on join and every 120 s, lifetime cap 25). |
| **Starter Pack** | While `StarterPack` is set, not bought and within 24 h of the first join: one popup when you reach stage 3, then a pulsing menu button. Grants 3 free skips, the exclusive *Starter Star* trail and 30 min of x2 coins (`boostEndsAt`, survives rejoin). |
| **Name tags** | Billboard over each head: display name ([VIP] in gold), "Stage N · 🏆 W" and a title by wins (Climber, Sky Walker, Cloud Runner, Tower Legend, Sky God). Localized per viewer. |
| **Live events** | `Shared/LiveEvents.luau` + `Config.LiveEvents`: *2x Coins Weekend* (Saturday 00:00 - Sunday 23:59 UTC, doubles every coin grant) and *Skip Sale Hour* (20:00-21:00 UTC daily, a bought skip gives +1 free skip; prices unchanged). HUD pill with countdown, banner when one starts. Admins (`Config.AdminUserIds`) can type `/event <id> <minutes>`; it is broadcast to all servers with MessagingService. |
| **Group gift** | Hidden while `Config.GroupId = 0`. Button prompts the join, then `Request("ClaimGroupGift")` checks membership: +150 coins, +1 free skip, exclusive *Crew* trail, once. |
| **Notification opt-in** | First time you reach stage 10 or win (at most once a week) the server fires `AskNotifications`; if `ExperienceNotificationService:CanPromptOptInAsync()` is true a card asks "Want a ping when 2x Coins Weekend starts?" and calls `PromptOptIn()`. No sending yet. |

### Remotes

- Events (server -> client): `State`, `Notify(msg, kind)`, `Celebrate`, `CoinCollected`, `OpenPanel`, `Win({tower, wins, runMs, newBest, best, gift})`, `Gift({id})`, `TowerEnter({tower})`, `Shield`, `OfferSkip({stage, freeSkips, adAvailableHint})`, `LiveEventUpdate(current, next)`, `AskNotifications`.
- `SetSetting` keys: `speedCoil`, `gravityCoil`, `effects`.
- `Request` actions: `GetState`, `ReturnToCheckpoint`, `GoToLobby`, `Rebirth`, `EnterPortal`, `BuyPower`, `PlacePocket`, `TakePerk`, `SetRoam`, `Travel`, `UseFreeSkip`, `DevSkip` (Studio only), `WatchAd`, `ShareLink`, `ClaimGroupGift`, `ClaimDaily`, `RedeemCode`, `ClaimPlaytime`, `BuyTrail`, `EquipTrail`, `BuyEffect`, `EquipEffect`, `SetSetting`, `SetLanguage`.
- Every message the server sends is a translation key spec `{key, args}` (see Languages below).

### Profile fields added

`lang`, `bestRunMs`, `ads {day, count}`, `referredBy`, `referralPaid`, `referralRewards`, `starterBought`, `boostEndsAt`, `groupGiftClaimed`, `notifAskedAt`, and with the 1,000-stage update (profile v2): `base` (standing on the base island of the next tower), `gifts`, `boosts` (power-up end times), `charges`, `perks`, `pocket`, `runTop` (all back-filled by `reconcile`, no data wipe; coils are switched off once by the migration; `runTop` starts at the last summit under the saved stage).

## Languages

12 languages: en (default), es, pt, fr, de, id, tr, ru, ja, ko, th, vi. `Shared/Locale.luau` + one flat table per language in `Shared/Locales/<code>.luau`. The language is the saved `profile.lang` (Settings -> Language, `Request("SetLanguage")`) or the account locale. The UI re-renders live. The server only sends keys (`Remotes.M(key, args)`); world signs, stalls, prompts, boards and name tags carry `LocKey`/`LocArgs` attributes that each client translates. `tests/locale_test.luau` checks that every language has every key and keeps every `{placeholder}`.

## Anti-exploit basics

- Checkpoints only count in order: at most `Config.MaxStageJump` (3) ahead of your current one,
  your root must be within 14 studs of the pad, and there's a 0.8 s minimum between checkpoints.
  Jumping further ahead needs a purchase (skips go through `ProcessReceipt` on the server).
- All currency changes happen on the server; the client only sends requests through one
  `Request` RemoteFunction with a token-bucket rate limit (8/s, burst 16).
- Coin pickups check distance on the server and are once per run.
- Receipts are idempotent (last 60 receipt ids stored in the profile; saved before granting).
- Dev skip for free only works when `RunService:IsStudio()`.

## Creator Dashboard items to create

Create these, then paste the IDs into `src/shared/Config.luau` (any ID left at 0 stays hidden).

### Developer Products (`Config.Products`)

| Key | Name | Suggested price | Notes |
|---|---|---|---|
| `SkipStage` | Skip Stage | **15 R$** | The main earner. Keep it cheap and impulsive. |
| `Skip10` | Skip 10 Stages | **99 R$** | Anchors the value of the single skip. |
| `Coins500` | 500 Coins | 25 R$ | Optional. |
| `Coins2500` | 2,500 Coins | 99 R$ | Optional. |
| `AdSkip` | Ad Skip | any (not sold) | Reward holder for the rewarded-video skip. Ads need 2,000 monthly unique visitors, ID verification + 2FA and the maturity questionnaire. |
| `StarterPack` | Starter Pack | **59 R$** | 3 free skips + Starter Star trail + 30 min x2 coins; first 24 h only. |

### Game Passes (`Config.Passes`)

| Key | Name | Suggested price | What it does |
|---|---|---|---|
| `SpeedCoil` | Speed Coil | **8 R$** | WalkSpeed 24 (toggle in Settings). The hook: the first purchase, almost free |
| `GravityCoil` | Gravity Coil | **19 R$** | Low gravity jumps (toggle in Settings) |
| `DoubleJump` | Double Jump | **99 R$** | One extra jump in the air, for ever |
| `InfiniteRevives` | Infinite Revives | **139 R$** | Unlimited pocket checkpoints |
| `VIP` | VIP | **199 R$** | [VIP] chat tag, gold trail, +50% coins, 2x daily reward |
| `DoubleCoins` | 2x Coins | **149 R$** | Double coins from every source |

### Badges (`Config.BadgeIds`)

| Key | Badge |
|---|---|
| `Winner` | Beat the first tower (stage 100) |
| `Stage50` | Halfway There (stage 50) — optional |
| `FirstRebirth` | Born Again (first rebirth) — optional |

Price ladder (from the top-obby research, `ROBLOX-INVESTIGACION-2.md`): hook 8 → impulse skip 15 →
starter pack 59 → Skip 10 at 99 → permanent passes 99–199. Runs helped by a pass are not ranked,
so nothing sold touches the Fastest Climb board.

Not built yet (backlog): "troll" tools as products (hammer 199, grapple hook 299, admin panel
1,499) with a server switch and out of the ranking, and a two-player mode.

Game icon/thumbnails are not in this repo (no uploaded assets) — take screenshots in Studio.

### Group

Create a Roblox group for the game and set `Config.GroupId` (0 hides the button).

## Code map

```
src/shared/  Config (all tunables + IDs) · Layout (pure map maths: 10 towers, curve, save pads, shop decks)
             Rules (pure game rules: reach, skips, spawn, towers needed, ranked, HUD skip button)
             Gifts · Powerups · Perks (pure catalogues + purchase rules) · Quality (lite profile rule)
             TowerStyle (palettes + tower moods) · Ambience (sky per height and tower)
             DecorPlan (scenery positions) · Segments (bar gradients)
             Locale + Locales/* · RunTime · Referral · LiveEvents
src/server/  init.server (bootstrap) · Data (profiles v2, session lock) · Remotes (router + rate limit)
             Session (leaderstats, coins, help flags, State push) · Towers (build / release on demand)
             StageGenerator (lobby + one tower, 1 builder per kind) · Scenery (set pieces, shops,
             portals, lounge, base islands, dressing) · Obstacles (one loop, awake window, coins)
             Checkpoints (progress, save / rest pads, skips, summits, portals, rebirth, fall catch)
             Shops (power-ups) · Lounge (free perks, explore mode, teleporter)
             Monetization (passes, ProcessReceipt) · Rewards (daily, codes, play time)
             Leaderboard (Top Wins, Fastest Climb, Highest Stage) · Cosmetics (trails, effects, coils,
             pet / crown / glow) · Referrals · Events (live events, /event) · Nametags
src/client/  init.client (bootstrap, lite profile) · Net · Lang · UI/{Kit, Hud, Progress, Toast,
             Celebrate, Cards, Prompts, EventBar, StarterPanel, ShopPanel, StorePanel, RewardsPanel,
             SettingsPanel, WinPanel, TravelPanel, Intro} · World/{LocalFx, Atmos, Juice, Weather,
             ChatTags, WorldText}
tests/       layout_test / rules_test / visual_test / locale_test / p0_test (luau.exe)
             AutoTest*.luau (Studio playtest, test.project.json)
             Shots (38-view camera tour; shots / shotslow projects) · UiShots · LangShots
```
