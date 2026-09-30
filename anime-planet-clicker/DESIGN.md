# Planet Crackers — Design

**Title:** Planet Crackers (visible title suggestion: `[NEW] Planet Crackers ⛏️`).
Alternatives if the name is taken or too close to another game: **Cosmo Miners**, **Core Breakers**.
Everything is original: names, pets, planets, galaxies, tools. No third-party characters, logos
or assets. (I could not check the Roblox catalogue for a game with the same name from here; do
that before publishing.)

## What it is

A space mining simulator. You click (or let Auto Mine click) mini planets floating over a
station. Each planet has three layers — crust, mantle, core — and breaking a layer drops ore into
your cargo hold. Ore becomes **Stardust** when it is sold at the Refinery. Stardust buys tools,
upgrades and capsules with pets that mine with you. A **Gate Planet** with a lot of HP blocks the
way to the next galaxy, and every galaxy opens a new way to get stronger.

## Core loop

1. **Mine**: click / tap a planet (hold to keep hitting). Damage per hit is your Mining Power.
2. **Layers**: crust 25% of the HP, mantle 35%, core 40%. Every broken layer = ore in the hold
   (the core counts double). Breaking the core also gives the planet's buff, materials, Crystals
   (some kinds) and Mastery progress. The planet respawns 5 s later as a new random kind.
3. **Sell**: walk onto the Refinery pad (instant, **+20%**) or let the Cargo Drone fly the hold
   (7 s trip; mining stops if the hold fills up again before it is back).
4. **Spend** Stardust: better tool, Power / Cargo / speed upgrades, capsules (pets).
5. **Gate**: hit the Gate Planet at the far end of the galaxy. Its HP is saved between
   sessions; when it breaks, the next galaxy is yours.
6. **Rebirth**: resets Stardust, the tool, the cargo and Power levels; keeps galaxies, pets,
   Crystals, materials, every other upgrade and Mastery. +50% damage and +50% Stardust each time.

### Three caps that take turns

| Cap | What stops you | What fixes it |
|---|---|---|
| Hardness | Each galaxy needs its own tool tier; a weaker tool does 25% damage ("Too hard!") | Buy the galaxy's first tool at the Workshop |
| Cargo | The hold is full; the drone is away | Cargo upgrade, sell by hand (+20%), Star Drone, Instant Sell pass |
| Gate | The Gate Planet's HP | Raw power: tool, Power levels, pets, the galaxy's system, rebirth |

### One new system per galaxy

| # | Galaxy | Opens | How it works |
|---|---|---|---|
| 1 | Dawn Belt | Tools + pets | 12 tools (picks, drills, lasers); capsules |
| 2 | Verdant Nebula | **Relics** | 10 Spores per roll. One relic per stat (damage, speed, luck, Stardust, Crystals), 6 grades (+5% … +100%). A better grade replaces the relic; anything else is Relic Dust, and 8 dust raise the grade |
| 3 | Frost Halo | **Temper** | Cryo Cores buy +10% damage per level (60 levels). Survives rebirths |
| 4 | Ember Forge | **Traits** | 8 Embers roll a Trait on a pet (x1.1 … x5). The pet keeps the better one; a roll that is not better refunds 3 Embers |
| 5 | Storm Reach | **Overcharge** | Hits fill a meter (80 hits); full meter = damage x1.5, up to x4.5 with Capacitor. It drops after 2.5 s without hitting |
| 6 | Void Crown | **Constellation** | Void Essence buys the strongest permanent boosts (+40% damage per level, +20% Stardust, luck, faster drone, +1 pet slot) |

Materials (Spores, Cryo Cores, Embers, Volt Cells, Void Essence) only drop from planets of their
galaxy and cannot be bought.

### Planet kinds

| Kind | Spawn weight | HP | Value | Buff when the core breaks | Mastery (permanent) |
|---|---|---|---|---|---|
| Rock | 56 | x1 | x1 | — | damage |
| Fury | 10 | x1.4 | x1.2 | Damage x1.5, 45 s | damage |
| Zephyr | 10 | x1.2 | x1.2 | Speed +35% (walk and hits/s), 45 s | speed |
| Clover | 8 | x1.3 | x1.2 | Luck x2, 60 s | luck |
| Aurum | 10 | x1.6 | x2 | Stardust x2, 45 s | Stardust |
| Prism | 6 | x2 | x1.5 | Crystals + 3 materials | Crystals |
| Titan (one per galaxy) | — | x120 | x1.6 | Random buff (double length), Crystals, 15 materials; respawns in 75 s | damage |
| Anomaly (hourly) | — | x12 | x4 | Every buff (x4 length), Crystals, 40 materials | Crystals |
| Gate | — | own HP | — | Unlocks the next galaxy | — |

Luck multiplies the weight of every kind except Rock (capped at x3). Planets on the outer ring are
**Dense**: x10 HP and ore, x2 materials, so a galaxy stays useful as you grow.
**Mastery**: 5 / 25 / 100 / 400 / 1,500 / 5,000 planets of a kind = +3% of its stat per level and
5 / 10 / 20 / 40 / 80 / 160 Crystals.
**Anomaly**: up for the first 15 minutes of every UTC hour in every galaxy, one break per player
per window. The HUD always shows the countdown.

## Damage and income

```
hit damage = tool power
           x 1.06 ^ Power level            (Stardust, resets on rebirth)
           x (1 + 0.1 x Temper)            (Frost Halo)
           x (1 + sum of equipped pet power)
           x (1 + 0.5 x rebirths)
           x (1 + Mastery damage + Relic damage)
           x (1 + 0.4 x Star of Power)     (Void Crown)
           x (1 + 0.1 x index pages done)
           x (1 + friends in the server x 0.1, max 0.5)
           x Overcharge (1 .. 1.5 + 0.25 x Capacitor)
           x 2 (x2 Damage pass) x 1.5 (VIP) x 1.5 (Fury buff)
           x 0.25 if the tool is below the galaxy's hardness
crit: 4% (+2% per Crit level), x3
ore value = layer HP x galaxy value x planet value
          x (1 + 0.1 x Magnet) x (1 + 0.5 x rebirths) x (1 + Mastery + Relic) x (1 + 0.2 x Star of Fortune)
          x 2 (pass) x 1.1 (Roblox Plus / Premium) x 2 (Aurum buff) x 2 (Meteor Shower)
```

Pet power x tier: Normal x1, Golden x3 (fuse 5), Prism x8 (fuse 5 Golden). Capsule pets come out
Golden 1% of the time (10% with the pass). Exclusive pets (Quantum Capsule, Starter Pack, group
gift, Secret) scale with the best regular pet of the owner's top galaxy (x1.2 … x10), so they
stay relevant.

### Anti-exploit

* Currency, HP, damage, drops and PvP results only change on the server.
* Clients send `(node, hit count)` batches every 0.2 s. The server clamps them with a token
  bucket at the player's hits-per-second stat (6/s base, burst 5) and checks that the character
  is within range of that planet and that the galaxy is owned.
* Auto Mine, Auto Sell, Auto Open, Auto Upgrade and Auto Rebirth run in **one server loop**
  (4 ticks/s); the client cannot speed them up and they work AFK.
* Capsules: galaxy owned, distance to the machine, cooldown, price, inventory room.
* Every `Request` is rate limited (12/s, burst 30) and type-checked.
* Standing in a galaxy you do not own sends you back within a second.
* Planets are per player (nobody can steal yours) and are drawn by the client only.

## Autos (first-class system)

| Auto | Free | Faster / better |
|---|---|---|
| Mine | 2 hits/s on the nearest planet in range, retargets by itself, works AFK | Auto Rate upgrade (+0.5/s per level, 8 levels, Crystals); Auto Miner pass x3 and +18 studs of reach |
| Sell | The drone sells a full hold (on by default) | Star Drone (faster), Instant Sell pass |
| Open | Keeps opening the chosen capsule while you stay in its galaxy | Fast Open pass (0.9 s instead of 2.2 s), x3 Open pass |
| Best | Re-equips the strongest pets after every open / fuse | — |
| Fuse | Fuses 5 of a kind into Golden / Prism as soon as possible | — |
| Delete | Deletes new Common / Uncommon / Rare pets on open (never a Golden, never a first-time pet) | — |
| Upgrade | Buys the best affordable tool and Power levels | — |
| Rebirth | Rebirths the moment it is affordable | — |

Five chips on the HUD (MINE, SELL, OPEN, BEST, REBIRTH) show ON / OFF at a glance; the Auto
window has all of them with one line each.

## Economy (simulation)

`sim/pacing_sim.luau` (`luau sim/pacing_sim.luau -a 6 3`) plays a free player: tutorial rewards,
daily reward and in-session gifts, 5 manual hits/s + free Auto Mine, drone selling, buys whatever
pays back fastest, attacks a Gate when it would fall in under 4 min, rebirths as soon as it can.
It prints the first-minute beats, the tier timeline and the dead stretches; `tests/pacing_test.luau`
fails when a milestone leaves its window. Median of 3 seeds:

| Milestone | Time |
|---|---|
| First reward / first purchase | 2 s / 9 s |
| Galaxy 2 (Verdant Nebula) | ~4 min |
| Galaxy 3 (Frost Halo) | ~19 min |
| Galaxy 4 (Ember Forge) | ~36 min |
| First rebirth | ~40 min |
| Galaxy 5 (Storm Reach) | ~1 h 45 |
| Galaxy 6 (Void Crown) | ~3 h 20 |
| Rebirth 6 | ~5 h (rebirth 7 is days away) |

`sim/economy_sim.luau` is the stricter long-run view (no tutorial, daily or gifts): its galaxy
times are later.

`../huerta-tycoon/tools/luau.exe sim/economy_sim.luau -a tune` re-fits planet HP, gate HP, tool
and capsule prices after changing pets or multipliers (prices are "planets' worth": capsule = 4,
first tool = 10, second tool = 110 rock planets of their galaxy). The late game is sensitive to
the rebirth cost; re-check with `-a 14 6` after any change.

| Item | Cost |
|---|---|
| Rebirth n | 4e11 x 400^n Stardust → +50% damage and Stardust, 40 + 20n Crystals |
| Power | 60 x 1.18^level Stardust, x1.06 damage per level (max 400) |
| Cargo | 200 x 1.9^level, +12 space (max 20) |
| Mining Speed | 500 x 2.6^level, +0.5 hits/s (max 12) |
| Walk Speed | 350 x 2.4^level, +1.5 (max 8) |
| Range | 1,500 x 3.2^level, +2 studs (max 6) |
| Luck / Magnet / Crit / Auto Rate / Pet Slots | Crystals (20 x 1.5^l, 15 x 1.45^l, 25 x 1.5^l, 30 x 1.7^l, 60 x 3^l) |

## Pets and capsules

7 capsules (one per galaxy + the Robux-only Quantum Capsule) and 35 pets. Every galaxy capsule
also holds the **Secret Galaxy Guardian at 0.001%**. The panel shows every outcome with its
percentage; the list always adds up to exactly 100%, and it is recomputed with the player's
luck (the same function the server rolls with: `Formulas.odds`).

| Capsule | Price | Pets (base chance) |
|---|---|---|
| Dawn | 120 | Pebble Pup 55% · Dust Bunny 30% · Comet Cat 12% · Rover Bot 2.9% · Solar Fox 0.099% · Secret 0.001% |
| Verdant | 66K | Moss Slime 55% · Spore Moth 30% · Vine Lizard 12% · Nebula Owl 2.9% · Emerald Stag 0.099% · Secret 0.001% |
| Frost | 130M | Ice Mite 55% · Snow Seal 30% · Glacier Cub 12% · Aurora Wisp 2.9% · Frost Wyrm 0.099% · Secret 0.001% |
| Ember | 1.5T | Cinder Newt 58% · Magma Crab 30% · Ash Hound 11% · Forge Golem 0.98% · Inferno Drake 0.019% · Secret 0.001% |
| Storm | 6.6Qa | Spark Mite 58% · Thunder Ram 30% · Cloud Ray 11% · Volt Drone 0.98% · Tempest Griffin 0.019% · Secret 0.001% |
| Void | 93Qi | Void Jelly 58% · Rift Bat 30% · Star Eater 11% · Quasar Sphinx 0.98% · Null Dragon 0.019% · Secret 0.001% |
| Quantum (Robux / rewards) | — | Photon Pixie 70% · Warp Tiger 29% · Celestial Titan 1% |

Luck multiplies the weight of every Rare-or-better pet before renormalising.

## PvP — the Meteor Arena

* A separate station. **Everything outside the red ring is a safe zone**, including the arena's
  own lobby ring and every galaxy. Mining never hurts anybody.
* Inside the ring you zap rivals with your tool (click them). Arena HP is its own bar (100):
  nobody really dies. A knockout sends you back to the lobby ring with full HP; you lose nothing.
* Damage = 14 x (attacker power / defender power)^0.2, clamped to x0.6 … x1.7. The strongest
  player in the game needs at least 5 hits on a day-one player; a day-one player needs at most
  13 hits on anyone.
* **Spawn protection**: 4 s after entering. **Rookie Shield**: with under 10 minutes of play
  time players cannot damage you until you attack one.
* Two **sparring drones** patrol the arena, so there is always something to fight.
* Rewards are paid by the system, never by the loser: 10 arena points + 45 s of your mining
  income for a player, 3 points + 12 s for a drone. Arena points feed the Arena Champions board
  and a daily quest.

## Retention

| Feature | Details |
|---|---|
| Tutorial (first minute) | 6 steps with a beam and an arrow to the objective, one instruction at the top, a reward per step: mine → crack a core → sell → open a capsule → buy a tool → switch Auto Mine on. The menu starts with 3 buttons and grows as steps are done |
| Daily streak | 7-day strip, claim every 20 h, breaks after 48 h. Day 7 = a Quantum Capsule |
| Play-time gifts | 8 gifts at 3 / 7 / 12 / 18 / 25 / 35 / 45 / 60 min (first one inside the 10-minute Creator Rewards window) |
| Codes | `LAUNCH` (50 Crystals), `CRACK` (10 min of mining), `LUCKY` (15 min luck), `PLANETS` (10 min x2 Stardust), `TITAN` (25 Crystals) |
| Daily quests | 3 per UTC day from a pool of 9; all three = a Quantum Capsule |
| Index | Pets by galaxy with silhouettes and chances; a finished page = Crystals + 10% damage forever. Planet page = Mastery |
| Anomaly | Hourly planet with a clock on the HUD |
| Live events | Meteor Shower (x2 Stardust, 15 min every 3 h), Lucky Nebula (x2 luck, 15 min every 3 h), Crystal Weekend (x2 Crystals, Sat + Sun UTC). Admins: `/event <name> <minutes>` on every server |
| Offline mining | Pets keep mining while you are away: 10% of your active income, up to 6 h (12 h VIP) |
| Leaderboards | Top Miners, Top Rebirths (Dawn Belt plaza) and Arena Champions (arena lobby) |
| Announcements | Legendary+ pets to the server, Mythic / Secret / Prism to every server, Gate breaks to the server |
| Invite | Game invite and share link carry `ref:<userId>`: the friend gets 50 Crystals, the inviter a Quantum Capsule after the friend plays 10 minutes (25 lifetime) |
| Group gift | Joining the group gives the Crew Beacon pet |
| Starter Pack | First 24 h: 150 Crystals + 30 min x2 Stardust + the Photon Pixie pet |
| Notifications | Opt-in prompt after the first Legendary pet or the first rebirth (at most weekly) |

## Languages

English, Spanish, Portuguese (BR), French, German, Indonesian, Turkish, Russian, Japanese, Korean,
Thai, Vietnamese. 504 keys each. The language follows the Roblox account locale; players can
change it in Settings. The server only sends translation keys.

## Looks at graphics quality 1

Nothing important depends on shadows, glow, particles or post effects:
* planets are layered geometry with relief (craters, continents, spikes, crystals, belts, rings,
  moons) and baked colours;
* the sky is a painted rig that follows the camera (inside-out dome, horizon bands, star parts,
  nebula blobs, far planets); in the lite profile it shrinks to 185 studs so it sits inside the
  short draw distance;
* lasers and the tutorial arrow are parts; chunks and damage numbers come from pools;
* the lite profile (phones, graphics slider ≤ 3, or the Settings switch) drops craters, extra
  debris, pet sparkles and post effects.

## Policy

### Paid random items (capsules)

Source: <https://create.roblox.com/docs/production/monetization/paid-random-items> and the
Community Standards (<https://about.roblox.com/community-standards>), read on 2026-09-30.

* "you must indicate all possible outcomes and the actual numerical odds" → the capsule panel
  lists every pet with a percentage **before** you pay, and the list sums to exactly 100%.
  `Formulas.odds` is the single source for both the panel and the server's roll; a playtest rolls
  60,000 times and compares.
* A luck boost changes the odds → the panel recomputes with the player's current luck.
* "Paying Robux to buy gems or spin tickets that are spent at a prize wheel" counts → Stardust
  can be bought with Robux, so capsules are treated as paid random items.
* No outcome is "just lose": every open gives a pet.
* `PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted` → for those players
  the game hides and refuses everything marked `random = true` in Config: the Stardust bundles,
  the Quantum Capsule products, Luck Boost and the three chance passes (Lucky, Super Lucky,
  Golden Capsules). They keep the free path: capsules bought with Stardust they mined. If the
  lookup fails the player is treated as restricted.
* The **Starter Pack has fixed contents** (no random item, no luck), so it is not a paid random item.
* Relics and Traits are random but are paid with materials that cannot be bought; their odds
  are shown anyway.
* There is no trading, so `IsPaidItemTradingAllowed` does not apply.

### Gambling

"we prohibit both simulated and actual gambling activities on the platform. No real money,
Robux, or in-game items of value may be exchanged in connection with any gambling activities."
(Community Standards). The game has no wagering: nothing is staked, PvP rewards are paid by the
system and the loser loses nothing, there are no wheels or slot-style mechanics.

### Intellectual property

Original setting and names. Do not add characters, music or logos from any anime, film or
other Roblox game: a valid takedown removes the whole experience.

## Creator Dashboard items to create

Create these under **Creator Dashboard → the experience → Monetization**, then paste each ID into
`src/shared/Config.luau`. An item with ID `0` stays hidden / "coming soon".

### Game passes (`Config.Passes`)

| Key | Name | Price (R$) | Effect |
|---|---|---|---|
| AutoMiner | Auto Miner | 149 | Auto Mine x3 faster, +18 studs of reach |
| DoubleDamage | x2 Damage | 199 | Every hit does double damage |
| DoubleStardust | x2 Stardust | 249 | Ore sells for double |
| VIP | VIP | 249 | x1.5 damage, +50% cargo, 12 h offline mining |
| InstantSell | Instant Sell | 199 | Ore is paid as you mine, no cargo limit |
| PetSlots | +2 Pet Slots | 249 | Equip 2 more pets |
| TripleOpen | x3 Open | 199 | Open 3 capsules at once |
| FastOpen | Fast Open | 99 | Capsule cooldown 2.2 s → 0.9 s |
| Sprint | Sprint | 49 | +6 walk speed |
| Lucky* | Lucky | 99 | +50% luck |
| SuperLucky* | Super Lucky | 299 | +100% luck |
| GoldenCapsules* | Golden Capsules | 349 | Golden chance 1% → 10% |

### Developer products (`Config.Products`)

| Key | Name | Price (R$) | Grants |
|---|---|---|---|
| StardustSmall* | Stardust Pouch | 49 | 30 min of your mining income |
| StardustMedium* | Stardust Crate | 199 | 3 h of income |
| StardustLarge* | Stardust Vault | 599 | 12 h of income |
| CrystalsSmall | 100 Crystals | 49 | 100 Crystals |
| CrystalsMedium | 600 Crystals | 249 | 600 Crystals |
| LuckBoost* | Luck Boost | 99 | x2 luck for 30 min |
| QuantumCapsule1* | Quantum Capsule | 149 | 1 exclusive pet |
| QuantumCapsule3* | 3 Quantum Capsules | 399 | 3 exclusive pets |
| StarterPack | Starter Pack | 99 (shown as -75% of 399) | 150 Crystals + 30 min x2 Stardust + Photon Pixie. First 24 h only |
| `Config.AdProducts.AdBoost` | Rewarded video: x2 Stardust | (ad) | x2 Stardust for 15 min |
| `Config.AdProducts.AdOffline` | Rewarded video: double offline | (ad) | Doubles the offline Stardust being collected |

\* paid random item under Roblox's policy: hidden where `ArePaidRandomItemsRestricted`.

`ProcessReceipt` is idempotent: every granted `PurchaseId` is stored in the profile (the last 60)
and saved before the game answers `PurchaseGranted`.

Also set: `Config.GroupId` (group gift) and `Config.AdminUserIds` (`/event`).

## Not built (ideas for later)

* A personal base that shows off rare finds and earns offline (what Anime Dice and Steal An Egg do).
* Trading (would need `IsPaidItemTradingAllowed`).
* Weekly leaderboard with prizes, clans.
* Gifting passes to friends (mirror products).
