# Tap Pets Simulator — Design

## Core loop

1. **Tap** anywhere (mouse or touch) to earn **Taps**. One tap is worth
   `(1 + sum of equipped pets' power) × multipliers`.
2. **Hatch eggs** with Taps. Better pets add more power, so every tap is worth more.
3. **Unlock the next zone** through its gate. Each zone has stronger eggs.
4. **Rebirth** when you hit the cost: your Taps reset, you keep pets, zones, gems and upgrades,
   and you get +50% on every tap forever, plus **Gems**.
5. Spend **Gems** on permanent upgrades (Tap Power, Luck, Pet Slots, Walk Speed).
6. Fill the **Index**: finishing a zone's page gives Gems and +10% Taps forever.

The pull to come back: a daily streak, timed gifts, rare-hatch announcements, crafting Golden
and Rainbow pets, the 1-in-100,000 Secret pet, leaderboards, and a friend boost.

## Tap value

```
tapValue = (BaseTap + Σ equipped pet power)
         × (1 + 0.25 × TapPower level)
         × (1 + 0.5 × rebirths)
         × 2   (Double Taps pass)
         × 1.5 (VIP pass)
         × (1 + min(0.5, 0.1 × friends in server))
         × (1 + 0.1 × completed index zones)
```

* Pet power × tier: Normal ×1, Golden ×3 (craft 5 Normal), Rainbow ×8 (craft 5 Golden).
* Hatches come out Golden 1% of the time (10% with Magic Eggs).
* Exclusive and Secret pets have no fixed power. They scale with the strongest regular pet in
  the owner's best zone: Sparkle Cat ×1.5, Crystal Unicorn ×2.5, Celestial Dragon ×5,
  Shadow Dragon ×10. That keeps Robux pets relevant for the whole game without being
  overpowered on day one.

### Anti-exploit

* Currency only changes on the server. Clients send a tap **count** every 0.25 s and the
  server clamps it with a token bucket: 12 taps/s plus a 6-tap burst. An autoclicker can't
  beat a fast human.
* Auto Tap runs on the server (see "Auto toggles").
* Hatching checks, on the server: the egg exists, it isn't the Robux egg, you own its zone,
  you're within 16 studs of it, the 2.4 s cooldown has passed, you have the Taps and you have
  inventory room.
* Every Request call is rate limited (12/s sustained, burst 30). Payloads are type-checked.
* Anyone found inside a zone they don't own (noclip, teleport) is sent back every second.
  Gate barriers collide on the server; they only open on the client of a player who owns
  that zone.

## Auto toggles

Four chips in the HUD (green = ON, grey = OFF). The client only flips a saved switch
(`SetAuto` / `SetAutoHatch`, rate limited like every request); the server loops do the work at
the server's pace, so they keep running while the player is AFK and no remote is spammed.

| Chip | Free | Faster with | Notes |
|---|---|---|---|
| Auto Tap | 1 tap/s **while idle** (no manual tap for 2 s) | "Auto Tap" gem upgrade: +1/s per level (max 3, idle only). Auto Tap pass: +5/s, always | The idle rate equals the offline rate, and the best free idle rate (4/s) stays below an active player (6/s), so the economy curve of an active player is unchanged |
| Auto Hatch | x1 every 4.5 s at the egg you stand next to | Auto Hatch pass: every 2.4 s, x3 with the x3 pass | Started from the egg panel. Stops (with a message) when the inventory is full. Session only: it is tied to a place |
| Auto Equip | Re-runs Equip Best after every hatch and craft | — | Saved |
| Auto Rebirth | Rebirths as soon as it is affordable | Auto Rebirth pass: opens it after the first rebirth instead of the third | Free after 3 manual rebirths (`Config.AutoRebirthMinRebirths`). Saved |

## HUD and first minute

Laid out like the top simulators (`docs/ROBLOX-HUD-GUIA.md`): objective with a progress bar
at the top centre; rebirth line, Gems and Taps as bars and the menu grid on the left; a dock at
the bottom centre with Rewards, the big TAP button (the value of one tap under it) and Pets
(badge = how many you own); gift timer, event, boosts, offers and the four auto chips on the
right. On phones the left block and the right column move to the top and the dock sits between
the thumbstick and the jump button.

The objective (`client/Guide.luau`) always names the next step and shows how far along it is:
earn Taps for the first egg → hatch it → hatch 5 → next zone (or rebirth, whichever is cheaper).
When the step is a place (first egg, a gate you can afford) a beam of light runs from the player
to it. Clicking the objective opens the matching window.

The HUD grows with the player (`shared/HudUnlock.luau`, pure, checked by `tests/policy_hud.luau`).
A new player sees only Rewards · TAP · Pets and the Store, plus a wobbling "Tap anywhere" hint
over the TAP button until the first 60 taps. The rest pops in when it becomes useful: first egg →
Upgrades, Quests, Auto Tap chip; 3 eggs → Index, Codes & Language, Auto Hatch / Auto Equip;
5 eggs → Teleport; 10 eggs → Invite; zone 3 or an affordable rebirth → Rebirth; the first
rebirth → Auto Rebirth. Having reached zone 2 or rebirthed opens everything. Only counters
that never go down are used, and the HUD keeps whatever it has shown, so a rebirth never hides
a button.

Icons come from the shared pack (`shared/Icons.luau`, images in `assets/icons` at the repo
root). While an icon has no uploaded id, `Theme.setIcon` / `Theme.icon` / `Theme.lead` show the
same emoji as before; once `tools/icons/upload_assets.py` writes the ids, the menu, dock, pills,
auto chips, window medallions, store/reward/quest/upgrade icons switch to images by themselves.

## Traits

Any pet can carry a trait grade that multiplies that pet's power. Rolling costs 1 **Trait Die**
and always gives a grade (it replaces the old one):

| Grade | Power | Chance |
|---|---|---|
| D | x1.05 | 45% |
| C | x1.10 | 30% |
| B | x1.20 | 17% |
| A | x1.35 | 7% |
| S | x1.60 | 1% |

Trait Dice are only earned by playing - 2 to start, 3 per rebirth, 1 per daily quest, 3 for the
quest bonus, 5 per completed index page - and are **never sold**, so a trait roll is not a paid
random item. The odds are still shown on the pet panel before rolling. Crafting makes a new pet,
so the trait is not carried over.

## Pet Park

Behind the spawn plaza: 12 plots along an aisle, one per player (Teleport → My Pet Park).
The owner's equipped pets stand on the six pedestals, the sign carries their name, and the
chest holds what the pets collected while the player was away: the same offline earnings as
before (tap value × 1/s, 8 h cap, 12 h with VIP), now something you walk up to and open. The
join popup still offers "Claim" and the rewarded video. Nothing new is earned in the park, so
the economy is unchanged. Statues are drawn by each client, only for plots near the camera.

## Paid random items (Roblox rules, 26/05/2026)

Eggs cost Taps and Taps can be bought with Robux, so every egg counts as a paid random item.

* The egg panel shows **every outcome as a numeric percentage, adding up to exactly 100**
  (`Formulas.displayOdds`, largest-remainder rounding to 0.0001%), before anything is spent,
  and it is rebuilt whenever luck changes (upgrades, passes, Super Luck, Lucky Hour). The
  Golden chance is on the same panel.
* The Robux offers that hatch the Magic Egg (Magic Egg x1 / x3 cards in the store, the Starter
  Pack card) print the same numeric odds, plus the Golden chance, **on the card, before the
  purchase prompt** (`Formulas.productEgg`, `Purchase.oddsText`). The Magic Egg's entries are all
  Rare+, so luck cannot change its odds (checked in `tests/policy_hud.luau`). Luck items (Lucky,
  VIP, Super Lucky, Super Luck) and the Magic Eggs pass show what they change with the player's own numbers
  ("Luck x1.10 → x1.60", "Golden 1% → 10%"); the full odds after luck are on every egg panel.
* No outcome is "nothing": every hatch gives a pet, and a full inventory is refused before paying.
* `PolicyService:GetPolicyInfoForPlayerAsync` → `ArePaidRandomItemsRestricted`. For those players
  (and until the lookup answers) the game does not sell: Magic Eggs, the Starter Pack (it contains
  an egg), Super Luck, Taps packs (so Taps are not purchasable and the world eggs stop being
  "paid"), and the Lucky / Super Lucky / Magic Eggs / VIP passes (paid luck modifiers). Gems and the utility
  passes stay. `Config.PaidRandomProductKinds` / `Config.PaidRandomPasses`.
  The Robux-only Magic Egg in spawn is hidden from them too: its prompt and sign are switched
  off on their client (`EggPanel`), so it can't even be opened.
* There is no trading, so `IsPaidItemTradingAllowed` does not apply yet.

## Performance budget

Measured and enforced by the playtest (`[TEST] PERF` line + `budget:` checks).

* Pets are client-only: the server replicates one string per player (`EquippedPets`) and never
  moves a part. One RenderStepped loop animates every pet; other players' pets are capped per
  player, culled by distance and updated every other frame when far (`client/Quality.luau`).
* Taps are batched (one remote every 0.25 s) and clamped on the server; currency updates go
  out at most twice a second and quest progress once every 2 s.
* Instance streaming is on (`StreamingTargetRadius` 512): zones load as you reach them. Eggs,
  gates and animated props stream as whole models; each zone's horizon is always loaded.
* Decorations are anchored and never collide, touch, answer raycasts or cast shadows.
* Floating numbers, rings, sparks and counter tokens are pooled. The inventory only builds the
  3D icons of the rows on screen.
* Autosave is staggered: one player per second at most, inside the DataStore budget.
* **Lite profile** (phones, or graphics slider ≤ 3): half the particles, no pet lights or trails,
  4 pets per other player, no real-time shadows or post-processing. The look does not depend on
  those: colours and shapes are baked into the parts, big props have painted contact shadows,
  rare pets keep their geometric aura and orbs.

## Luck

`luck = 1 + 0.10 × Luck level (+0.5 Lucky pass) (+1.5 Super Lucky pass) (+0.1 VIP)`, ×2
while the Super Luck boost is active. Luck multiplies the weight of every **Rare and above** entry in an egg, and then
the odds are renormalised. The egg panel always shows the odds after luck.

## Economy curve (tuned by simulation)

Average free player: taps 6 times per second and buys no passes. Claims the in-session
gifts. Hatches only eggs that repay themselves within 150 s. Equips the best pets and crafts
automatically. Buys gates as soon as it can. Rebirths when affordable, unless a gate is less
than 5 min away. Spends gems on the cheapest useful upgrade.

`sim/economy_sim.luau` (20 seeds, 6 h):

| Milestone | Target | Simulated average |
|---|---|---|
| Zone 2 Candy Land (27K) | ~5 min | **4 m 48 s** |
| Zone 3 Frost Peak (2.6M) | — | **35 m 37 s** |
| First rebirth (63M) | ~1 h | **1 h 02 m** |
| Zone 4 Lava Caves (420M) | — | **1 h 46 m** |
| Zone 5 Cosmic Void (6B) | 3–4 h | **3 h 29 m** |

Run `../huerta-tycoon/tools/luau.exe sim/economy_sim.luau -a tune` to re-fit the gate costs,
egg prices (kept in proportion to their zone's gate) and the first rebirth cost to these
targets after changing pets or multipliers. `sim/set_config.py key=value ...` writes numbers
back into Config.

| Item | Cost |
|---|---|
| Rebirth n | 63M × 8ⁿ Taps → +50% taps, 30 + 15n Gems |
| Tap Power | 10 × 1.45ˡᵛ Gems (max 25) |
| Luck | 20 × 1.55ˡᵛ Gems (max 15) |
| Pet Slots | 60 × 3ˡᵛ Gems (max 3) |
| Walk Speed | 8 × 1.8ˡᵛ Gems (max 5) |
| Auto Tap | 25 × 2.2ˡᵛ Gems (max 3): +1 auto tap/s while idle |

## Eggs and pets

9 eggs (8 bought with Taps across the 5 zones, plus the Robux-only Magic Egg in spawn) and
39 pets. Every world egg also holds the **Secret Shadow Dragon at 1 in 100,000**. Every
Legendary, Mythic or Secret hatch is announced to the whole server.

**Basic Egg** — Spawn Meadow — 200 Taps

| Pet | Rarity | Chance | Power (+taps/tap) |
|---|---|---|---|
| Dog | Common | 60% | 1 |
| Cat | Uncommon | 30% | 2 |
| Bunny | Rare | 9% | 4 |
| Bear | Epic | 1% | 9 |
| Shadow Dragon | Secret | 1 in 100,000 | 10x best pet of your top zone |

**Spotted Egg** — Spawn Meadow — 3K Taps

| Pet | Rarity | Chance | Power (+taps/tap) |
|---|---|---|---|
| Piggy | Common | 55% | 5 |
| Chick | Uncommon | 32% | 9 |
| Fox | Rare | 11% | 18 |
| Owl | Epic | 2.4% | 40 |
| Unicorn | Legendary | 0.1% | 120 |
| Shadow Dragon | Secret | 1 in 100,000 | 10x best pet of your top zone |

**Candy Egg** — Candy Land — 16K Taps

| Pet | Rarity | Chance | Power (+taps/tap) |
|---|---|---|---|
| Gummy Bear | Common | 58% | 22 |
| Lollipup | Uncommon | 30% | 40 |
| Cupcake Cat | Rare | 10% | 80 |
| Candy Dragon | Epic | 2% | 170 |
| Shadow Dragon | Secret | 1 in 100,000 | 10x best pet of your top zone |

**Sprinkle Egg** — Candy Land — 140K Taps

| Pet | Rarity | Chance | Power (+taps/tap) |
|---|---|---|---|
| Donut Dog | Common | 60% | 60 |
| Marshmallow Bunny | Uncommon | 33% | 110 |
| Cotton Candy Fox | Epic | 6.9% | 330 |
| Jelly Phoenix | Legendary | 0.1% | 900 |
| Shadow Dragon | Secret | 1 in 100,000 | 10x best pet of your top zone |

**Frost Egg** — Frost Peak — 260K Taps

| Pet | Rarity | Chance | Power (+taps/tap) |
|---|---|---|---|
| Penguin | Common | 60% | 260 |
| Snow Fox | Uncommon | 30% | 480 |
| Polar Bear | Rare | 8.5% | 950 |
| Ice Wolf | Epic | 1.5% | 2K |
| Shadow Dragon | Secret | 1 in 100,000 | 10x best pet of your top zone |

**Glacier Egg** — Frost Peak — 2.1M Taps

| Pet | Rarity | Chance | Power (+taps/tap) |
|---|---|---|---|
| Arctic Owl | Uncommon | 62% | 1.3K |
| Yeti | Rare | 30% | 2.6K |
| Frost Phoenix | Epic | 7.9% | 5.4K |
| Ice Dragon | Legendary | 0.099% | 15K |
| Shadow Dragon | Secret | 1 in 100,000 | 10x best pet of your top zone |

**Magma Egg** — Lava Caves — 12M Taps

| Pet | Rarity | Chance | Power (+taps/tap) |
|---|---|---|---|
| Lava Pup | Uncommon | 60% | 7K |
| Ember Cat | Rare | 30% | 14K |
| Magma Golem | Epic | 9.4% | 30K |
| Fire Dragon | Legendary | 0.58% | 80K |
| Hellhound | Mythic | 0.019% | 250K |
| Shadow Dragon | Secret | 1 in 100,000 | 10x best pet of your top zone |

**Cosmic Egg** — Cosmic Void — 180M Taps

| Pet | Rarity | Chance | Power (+taps/tap) |
|---|---|---|---|
| Moon Cat | Uncommon | 60% | 110K |
| Star Bunny | Rare | 30% | 220K |
| Alien Pup | Epic | 9.4% | 480K |
| Nebula Owl | Legendary | 0.58% | 1.3M |
| Galaxy Dragon | Mythic | 0.019% | 4.2M |
| Shadow Dragon | Secret | 1 in 100,000 | 10x best pet of your top zone |

**Magic Egg** — Spawn (Robux only) — Robux

| Pet | Rarity | Chance | Power (+taps/tap) |
|---|---|---|---|
| Sparkle Cat | Legendary | 70% | 1.5x best pet of your top zone |
| Crystal Unicorn | Mythic | 29% | 2.5x best pet of your top zone |
| Celestial Dragon | Mythic | 1% | 5x best pet of your top zone |

## Retention

| Feature | Details |
|---|---|
| Daily streak | 7-day cycle, claim every 20 h, the streak breaks after 48 h. Day 7 = a Magic Egg. The Rewards window shows the running streak ("Streak: N days") |
| Timed gifts | 8 gifts at 45 s / 5 / 10 / 20 / 30 / 40 / 50 / 60 min into the session (taps, gems, luck, a Magic Egg at 60 min). The 45 s one (1 min of Taps) pays the first egg inside the first minute |
| Codes | `RELEASE` (50 gems), `TAPTAP` (10 min of taps), `LUCKY` (15 min Super Luck), `PETS` (25 gems) |
| Index | % discovered overall and per zone; each completed zone gives 50/100/200/400/800 gems and +10% taps forever |
| Leaderboards | Global Total Taps and Rebirths boards in spawn (OrderedDataStore, refreshed every 60 s) |
| Friend boost | +10% taps for each friend in the server, max +50% |
| Offline earnings | Pets collect `tap value × 1/s` while you're away, up to 8 h (12 h with VIP), from 5 min away. A popup on join claims it (x2 with a rewarded video when ads are live). Unclaimed Taps are kept |
| Daily quests | 3 per UTC day from a pool of 6 (hatch N eggs, tap N times, craft a Golden, spend N gems, play N minutes, hatch an Epic+). Targets scale with your best zone; 20–60 gems each, a Magic Egg for all 3 |
| Live events | **Lucky Hour**: 15 min every 3 h (UTC), x2 luck. **Golden Weekend**: Saturday + Sunday UTC, x2 Golden chance. Both stack with Super Luck; the egg panel odds include them. When no event is running the HUD pill counts down to the next Lucky Hour (real UTC schedule). Admins (`Config.AdminUserIds`) can start one on every server with `/event <LuckyHour\|GoldenWeekend> <1-60 minutes>` |
| Rare hatches | Legendary+ hatches are announced to the server; Mythic, Secret and Rainbow hatches to every server (MessagingService, max 1 publish / 2 s per server, shown one every 4 s) |
| Invite friends | Game invites and share links carry `ref:<userId>`. The friend gets 50 gems on their first join; after they play 10 minutes the inviter gets a Magic Egg (max 25 in a lifetime) |
| Group gift | Joining the group (`Config.GroupId`) gives the exclusive **Group Pup** (x1.2 of the best pet of your top zone), once |
| Notifications | After the first Legendary+ hatch or first rebirth (at most weekly) the game offers the Roblox notification opt-in |

## Languages

English, Spanish, Portuguese (BR), French, German, Indonesian, Turkish, Russian, Japanese, Korean,
Thai and Vietnamese. The language follows the Roblox account locale; players can change it in
**Codes & Language** and the choice is saved. Every UI string, world sign and server message
goes through `Shared/Locale` (`Locales/<code>.luau`); the server only sends keys, so rare-hatch
announcements are shown in each player's own language.

"Minutes of Taps" rewards pay out your current tap value × 6 taps/s × minutes, so they stay
useful at every stage.

## Creator Dashboard items to create

Create these under **Creator Dashboard → your experience → Monetization**, then paste each
ID into `src/shared/Config.luau` (`Config.Passes[*].id` / `Config.Products[*].id`). An item
with ID `0` stays hidden in the store, and its buttons say "coming soon".

### Game passes

| Key | Name | Suggested price (R$) | Effect |
|---|---|---|---|
| AutoTap | Auto Tap | 149 | +5 auto taps/s, also while you tap (the free Auto Tap is 1/s, idle only) |
| TripleHatch | x3 Hatch | 199 | Hatch 3 eggs at once |
| OctoHatch | x8 Hatch | 699 | Hatch 8 eggs at once; includes x3 (owning it marks x3 as owned) |
| AutoHatch | Auto Hatch | 249 | Fast Auto Hatch: every 2.4 s instead of 4.5 s, at the biggest size owned (x8 / x3) that you can pay for |
| AutoRebirth | Auto Rebirth | 199 | Auto Rebirth from the first rebirth (free players get it after 3) |
| Lucky | Lucky | 249 | +50% luck (paid random modifier: hidden for restricted players) |
| SuperLucky | Super Lucky | 699 | +150% luck, stacks with Lucky (paid random modifier) |
| VIP | VIP | 299 | ×1.5 taps, +10% luck, VIP tag |
| PetSlots | +3 Pet Slots | 249 | Equip 3 more pets |
| PetSlots2 | +6 Pet Slots | 649 | Equip 6 more pets, stacks with +3 |
| Storage | +50 Storage | 99 | Inventory 150 → 200 |
| DoubleTaps | Double Taps | 449 | ×2 taps |
| MagicEggs | Magic Eggs | 599 | Golden hatch chance goes from 1% to 10% |

### Developer products

**Also create** (they stay hidden while their ID is 0):

| Where in Config | Name | Suggested price (R$) | Grants |
|---|---|---|---|
| `Config.Products` `StarterPack` | Starter Pack | 99 | 1 Magic Egg + 150 gems + 30 min Super Luck. Offered for the first 24 h (popup after the 3rd hatch, then a HUD button); shown as -75% of 399 |
| `Config.AdProducts.AdBoost` | Rewarded video: x2 Taps | (ad) | x2 taps for 15 min |
| `Config.AdProducts.AdOffline` | Rewarded video: double offline | (ad) | Doubles the offline Taps being claimed (10 min of taps if none are pending) |

Rewarded videos need ads eligibility (2,000 monthly unique visitors, ID + 2FA, maturity
questionnaire). Max 5 videos per player per day. Also create the **Roblox group** and put its ID
in `Config.GroupId`.

| Key | Name | Suggested price (R$) | Grants |
|---|---|---|---|
| TapsSmall | Pile of Taps | 49 | 30 min of your current tap income |
| TapsMedium | Bag of Taps | 199 | 3 h of tap income |
| TapsLarge | Vault of Taps | 599 | 12 h of tap income |
| GemsSmall | 100 Gems | 49 | 100 gems |
| GemsMedium | 600 Gems | 249 | 600 gems (+18% per Robux vs the 49 pack) |
| GemsLarge | 1,400 Gems | 499 | 1,400 gems (+37%) |
| GemsHuge | 3,200 Gems | 999 | 3,200 gems (+57%) |
| SuperLuck | Super Luck (15 min) | 99 | ×2 luck for 15 min (stacks) |
| MagicEgg1 | Magic Egg | 149 | 1 exclusive Magic Egg hatch |
| MagicEgg3 | 3 Magic Eggs | 399 | 3 exclusive Magic Egg hatches |

`ProcessReceipt` is idempotent. Every granted `PurchaseId` is stored in the profile (the last
60) and saved to the DataStore before the game returns `PurchaseGranted`. A retried receipt
never grants twice. If the save fails, the game returns `NotProcessedYet` and Roblox retries.

### Also set up

* A **thumbnail and icon**. Write the description around "tap, hatch, collect".
* **Badges** (optional; not wired up): first hatch, first Legendary, each zone.
