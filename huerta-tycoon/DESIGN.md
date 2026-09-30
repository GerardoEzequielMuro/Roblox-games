# Crop Kingdom — design & client/server contract

Roblox garden tycoon. Loop: buy seeds (shop restocks every 5 min, rare seeds are scarce) → plant on your plot tiles →
they grow in real time (also offline) → harvest (chance of mutations worth 2x–40x, boosted by weather events) →
basket fills → sell → buy better seeds, more tiles, upgrades → rebirth for a permanent cash multiplier.

Why it retains: variable-ratio rewards (mutations, rare restocks), timers that bring players back (restock, weather,
offline growth, daily streak), visible progression (plot filling up with bigger plants), social flex (global board).

## Project layout (Rojo)
- `src/shared` → `ReplicatedStorage.Shared` — `Config`, `Format`, `Formulas`
- `src/server` → `ServerScriptService.Server` — `Main.server.luau`, `Services/*`, `World/*`
- `src/client` → `StarterPlayer.StarterPlayerScripts.Client` — `Main.client.luau`, `UI/*`

## Remotes (created by server in `ReplicatedStorage.Remotes`)
RemoteEvents server→client:
- `StateUpdate(state: State)` — full player snapshot, sent on every change (throttled ~0.2 s)
- `StockUpdate(stock: {[seedId]: number}, nextRestockAt: number)` — personal seed stock (remaining units)
- `WeatherUpdate(weatherId: string?, endsAt: number, nextAt: number)` — `weatherId` nil = clear sky
- `Notify(text: string, kind: "info"|"success"|"error"|"rare")`
- `HarvestFx(position: Vector3, seedId: string, mutation: string?, value: number)`
- `LiveEventUpdate(current: {id, endsAt}?, next: {id, startsAt}?)` — on change and to each player on join
- `AskNotifications()` — happy moment (first Golden+ harvest / first rebirth, max once per 7 days): client may show the opt-in card

RemoteFunction client→server: `Request(action: string, payload: table?) -> (ok: boolean, message: string?)`
Actions:
| action | payload | effect |
|---|---|---|
| `Hello` | – | returns `(true, nil, {state, stock, nextRestockAt, weather={id,endsAt,nextAt}})` (3rd return value) |
| `BuySeed` | `{seedId, amount?}` | buy from personal stock |
| `Plant` | `{tile, seedId}` | plant on own unlocked empty tile |
| `PlantAll` | `{seedId}` | fill every empty unlocked tile with that seed while you have seeds |
| `Harvest` | `{tile}` | harvest a ripe tile into basket |
| `HarvestAll` | – | harvest every ripe tile (until basket full) |
| `Shovel` | `{tile}` | destroy the crop on a tile |
| `SellAll` | – | sell basket (needs Sell Anywhere pass or be within `Config.SellRadius` of `Workspace.Hub.SellStand`) |
| `BuyTile` | – | unlock next tile |
| `BuyUpgrade` | `{id}` | id from `Config.Upgrades` |
| `Rebirth` | – | |
| `ClaimDaily` | – | |
| `RedeemCode` | `{code}` | |
| `FinishTutorial` | – | marks `state.tutorialDone` |
| `SetLanguage` | `{lang}` | saves the UI language (one of `Locale.Languages`) |
| `ClaimGift` | `{index}` | session play-time gift (`Config.PlaytimeGifts`), valid once `minutes` have passed this session |
| `ClaimIndex` | `{seedId}` | claim a completed Index row (Normal + every mutation found): cash + permanent `IndexRowBonus` |
| `ShareLink` | – | server prompts `SocialService:PromptLinkSharingAsync` with `LaunchData = "ref:<userId>"` |
| `ClaimGroupGift` | – | one-time `Config.GroupJoinGift` after joining `Config.GroupId` |
| `WatchAd` | `{placement="restock"}` | rewarded video (daily cap `AdDailyCap`); the restock arrives via `ProcessReceipt` of `AdRestock` |
| `SetAuto` | `{mode="harvest"\|"plant"\|"sell", on: boolean}` | flips an auto-farm switch (rejected while that mode is locked) |
| `SetAutoSeed` | `{seedId}` | seed the auto-planter uses (the client sends the hotbar selection) |

`Hello` also takes `{lang}` (the client's auto-detected language) and returns `liveEvent = {current, next}`.
Every message returned by a Request and every `Notify` text is already translated into that player's language.

Robux purchases are prompted directly by the client with `MarketplaceService:PromptGamePassPurchase` /
`PromptProductPurchase` using ids from `Config.GamePasses` / `Config.DevProducts` (skip entries with id 0).

## State (sent in StateUpdate)
```lua
{
  cash: number, totalEarned: number, rebirths: number,
  tilesOwned: number, tileCost: number,
  upgrades: {GrowSpeed=n, CropValue=n, Luck=n, Backpack=n},
  upgradeCosts: {GrowSpeed=n, ...},          -- cost of next level (nil if maxed)
  seeds: {[seedId]: count},
  backpack: { {seedId, mutation (string|nil), count, value} },  -- value = total sell value of the stack
  backpackCount: number, backpackCap: number, backpackValue: number,
  passes: {[passKey]: boolean},
  mult: {cash: number, growth: number, luck: number},
  rebirthCost: number,
  daily: {streak: number, canClaim: boolean, nextAt: number},
  plotIndex: number,                           -- which Workspace.Plots.Plot_<n> is yours
  tutorialDone: boolean,
  earnRate: number,                            -- $ per minute recently (for display)
  lang: string,                                -- effective UI language
  sessionStart: number,                        -- os.time() the session began (play-time gifts)
  gifts: { {minutes, ready: boolean, claimed: boolean} },
  boosts: { growth: {mult, endsAt}?, cash: {mult, endsAt}? },  -- timed boosts, already folded into mult
  index: {[seedId]: {found: n, total: n, claimed: boolean, variants: {string}}},
  indexBonus: number,                          -- permanent cash bonus from claimed Index rows (0.02 = +2%)
  starter: {available: boolean, endsAt: number},  -- Starter Pack offer (needs a product id)
  groupGift: {available: boolean, member: boolean},
  adsLeft: number,                             -- rewarded-video restocks left today
  referralRewards: number,
  auto: { level, pass, allowed={harvest,plant,sell}, wanted={...}, on={...}, seed, interval, batch },  -- auto-farm status
  policy: { paidRandom: boolean },             -- false where Roblox restricts paid random items (and until known)
}
```

## Auto-farm
- Rules in `Shared/AutoFarm` (pure, `tests/autofarm_test.luau`), numbers in `Config.AutoFarm`, work in `Services/AutoFarm`.
- Unlock: the **Farmhand** upgrade (in-game cash, kept through rebirths): Lv1 auto-harvest, Lv2 auto-plant, Lv3 auto-sell.
  The **Auto Harvest** pass unlocks all three at full speed (1 s, 30 tiles).
- The server does the work in ONE loop (1 Hz) and paces each player (`interval` seconds, `batch` tiles per round), so it
  keeps running while the player is AFK and a client can't speed it up. Switches are saved in `profile.auto`.
- Auto-sell sells a FULL basket from anywhere. Auto-plant uses the seed selected in the hotbar.

## Chances (paid random items)
- `Shared/Odds` is the single source for every random outcome: the server rolls with it (`Rewards.luckySeed`,
  `Garden.rollMutation`) and the client shows it in the **Chances** panel (Index panel button, and the "%" button on
  the Lucky Seed Pack / Super Luck cards). Percentages always add up to 100 (`tests/odds_test.luau` + 30k-roll checks
  in the playtest).
- `PolicyService.ArePaidRandomItemsRestricted` → `state.policy.paidRandom`; the store hides the Lucky Seed Pack and the
  Super Luck pass where restricted (and until the policy call answers).
- The Starter Pack has fixed contents (no Lucky Pack inside), so it is not a paid random item.

## Crop sizes + trophy shelf
- `Shared/Trophies` (pure, `tests/trophies_test.luau`): a crop ripens Normal / Big (8%, x1.5) / Giant (2%, x3). Basket
  keys are `seed|mutation` or `seed|mutation|size` (old saves keep working).
- Each plot has 3 pedestals outside the fence, right of the gate. `Exhibit {key}` moves one Big / Giant / mutated crop
  from the basket to a pedestal (`profile.trophies`); `Unexhibit {slot}` takes it back. Every trophy adds luck while it
  stays there (size 5% / 15% + mutation 2–25%), multiplied into `Session.luckMult`. State: `trophies`, `trophyLuck`,
  and `backpack[i].key/size`.

## Audio
- One client module, `UI/Sound`; IDs in `Config.Sounds` (all 0 = silent, nothing is created). Hooks already wired:
  button click, harvest / rare harvest, sell, error toast, confetti fanfare, background music.

## HUD layout (from ROBLOX-HUD-GUIA.md)
- Top-center: 3 teleports (Seeds / Garden / Sell). Left: stats card + menu. Right: Harvest All / Plant All / Auto.
  Bottom-center: basket + hotbar. Bottom-right (PC): weather chip + event / Wild Patch pill.
- `Layout.designFor`: regular canvas 1100x540 (PC) or 1000x480 (touch); **compact** 740x365 when a 54 px button would
  fall under 40 px (44 on touch). Compact folds the menu behind a "More" button and moves the weather chip to the
  left column. Crops closer than 10 studs to the camera turn see-through (`Ambience`).

## Wild Patch
- Rules in `Shared/Wild` (pure, `tests/wild_test.luau`): every hour (UTC clock, same on every server) six rare seeds
  regrow on the patch next to the giant pumpkins. Each player may pick each node once per cycle (free).
- `Services/Wild` builds the ripe plants on `Workspace.WildPatch.WildNode_<i>` (ProximityPrompt, 24-stud server check),
  saves picks in `profile.wild = {cycle, claimed}` and announces the regrow. State: `wild = {nextAt, left, claimed}`.
- Client `UI/WildPatch`: hides the plants you already picked (for you only), runs the sign clock; the HUD pill
  alternates "next event" with the Wild Patch line.
- `state.rev`: snapshots are numbered; the client ignores one older than what it has (a `Hello` reply could land
  after a newer `StateUpdate` and leave the HUD stale).

## World + performance
- `Shared/WorldLayout` (pure, `tests/world_test.luau`): plot ring, entrance gap, owner sign beside the gate, landmarks.
- `World/Props` builds everything from Parts. Flat terrain features are painted into voxels (`Props.paint`): filling
  shapes changes the ground height (a full voxel renders 2 studs above its top).
- Client cosmetics live in `UI/Ambience` (spin/bob/float/rainbow/crop pop, pollen), `UI/Juice` (coins, confetti) and
  `UI/Fx`; `UI/Perf` picks the **lite** profile (phones, graphics level 1-3): fewer particles, no pops, ornaments removed
  locally. The playtest prints `PERF` lines and enforces budgets (parts, crop parts, remote traffic, snapshot size...).

## i18n
- `Shared/Locale` + `Shared/Locales/<code>` (en, es, pt, fr, de, id, tr, ru, ja, ko, th, vi); `en` is the source of truth.
- Server: handlers return `Locale.ref(key, args)`; `Remotes` translates replies/notifications per recipient
  (`Session.lang`: saved choice > client-detected > `Player.LocaleId`). World text is tagged with `Locale.stamp`
  (`LocKey`/`LocArgs` attributes) and re-rendered on each client by `UI/WorldText`.
- Client: `UI/I18n` (`t`, `L`, `set`, `setLang`); switching re-renders live. `tests/locale_test.luau` checks keys/placeholders.

## Live events
- Schedule in `Config.LiveEvents` (weekly UTC + recurring), effects in `Config.LiveEventDefs`; pure math in `Shared/LiveEvents`.
- `Services/Events` ticks every second: forces the event weather (`Weather.force`/`unforce`), multiplies mutation
  chance and growth, and for the Harvest Festival restocks everyone with at least one Mythic+ seed.
- Admins (`Config.AdminUserIds`) type `/event <id> <minutes>` (≤ 60) → MessagingService topic `CK_LiveEvent` → all servers.

## Referrals
- Invite / share link carry `LaunchData = "ref:<inviterId>"` (`Shared/Referral`). A new player (< 10 min played) joining
  with it gets `ReferralInviteeGift`; after they play 10 min the inviter gets `ReferralInviterGift` through the
  `CropKingdom_Referrals_v1` DataStore (drained on join and every 120 s, max `ReferralMaxRewards`).
```

## World contract
- `Workspace.Plots.Plot_<n>` (Model) attributes `OwnerId` (number, 0 = free), `OwnerName`.
  - `Tiles` folder → Parts `Tile_<i>` (i = 1..30) with attributes `TileIndex`, `Unlocked`, `HasCrop`, `Ripe`, `SeedId`, `Progress` (0..1).
  - `Spawn` Part (teleport target for "My Garden").
- `Workspace.Hub` → `SellStand`, `SeedShop`, `UpgradeShop`, `RobuxShop` Parts, each with a `ProximityPrompt` named `Prompt`.
  Client opens the matching UI when SeedShop/UpgradeShop/RobuxShop prompt triggers; server sells on SellStand.
- Tiles unlock in order: next purchasable tile is `tilesOwned + 1`.
