# Spin Showdown: design

Working title: **Spin Showdown**. Alternatives: **Wheel of Splat**, **Last Spin Standing**.
No brands, and on purpose no "roulette" in the name (see Policy).

An elimination party game for 2 to 8 players standing at podiums around a wheel of effects.
On your turn you pick a target, may play one card, spin, and brake the wheel yourself. The
wheel says what happens. Last one standing wins. Matches run 3 to 5 minutes.

## 1. Policy (read this before changing anything that touches rewards or the shop)

### What Roblox says

Community Standards, "Gambling" (read 30/09/2026; the page shows no date):

> "Except where prohibited by local law or regulation, we allow unplayable gambling content,
> such as references to gambling and related imagery. However, we prohibit both simulated
> and actual gambling activities on the platform. No real money, Robux, or in-game items of
> value may be exchanged in connection with any gambling activities."

Source: https://about.roblox.com/community-standards

The 2023 announcement that introduced the rule, as quoted on the DevForum: "Any experience
that has simulated gambling (i.e., playing with virtual chips, simulated betting) will no
longer be allowed" and "Games of luck or chance that are not casino or gambling based will
still be allowed, such as bingo or arcade style games."
Source: https://devforum.roblox.com/t/are-roulettes-the-casino-ones-allowed-on-roblox/3229821
(a DevForum answer quoting the announcement; I could not open the original post).

Paid Random Items (Creator docs, and the 26/05/2026 clarification): anything bought with
Robux, or with a currency that Robux can buy, that gives a random result must show every
outcome with its numerical odds adding up to 100% before the purchase, no outcome may be
"you just lose", and `PolicyService` (`ArePaidRandomItemsRestricted`) must be respected.
Sources: https://create.roblox.com/docs/production/monetization/paid-random-items ·
https://devforum.roblox.com/t/clarifying-requirements-for-paid-random-items/4654622

The in-house research (`C:\work\_Personal\docs\ROBLOX-INVESTIGACION-2.md`, section 7) reads
this the same way and lists a dozen live elimination games built on chance (BUCKSHOT since
01/2024, maturity "Mild"). That reading is an inference from the text, not a statement from
Roblox.

### How this design complies

| Rule | What the game does | Where it is enforced |
|---|---|---|
| No wagering | Spinning is free. Nothing is staked before or during a match: no coins, no items, no streaks | `MatchCore` has no notion of currency |
| The prize is paid by the system | Rewards depend on placement only (`Progression.matchRewards`) | `MatchRewards.pay` |
| The loser loses nothing they had | Trophies never go down inside a season; coins, XP and items never go down | `State.addTrophies` only adds; unit test "rewards never negative" |
| No casino look | It is a game-show spinner with effect icons (zap, shield, heal). No numbers, no red/black, no chips, no felt, no ball | `LobbyBuilder`, `Wheel` |
| No casino words | No "bet", "casino", "jackpot", "chips", "roulette", "lottery" in any of the 12 languages | `tests/locale_check.luau` (banned-word list) |
| No pay-to-win | Every pass and product has `affectsMatch = false`; cards are dealt free inside the match and are never sold | `tests/unit_core.luau` and the Studio playtest assert it |
| No paid random items | The shop sells fixed things: passes, coin packs, a Starter Pack with listed contents, a server party. No crates, no spins for sale, no luck boosts | `Config.Products` kinds are `coins`, `starter`, `party` only (asserted) |
| Cartoon violence only | Bolts, hammers, slime, UFOs. No firearms, no blood | `Finishers` |

Grey areas I chose the safe side on:

- **Ranked points that go down.** Every ranked game does it, but "the loser loses nothing"
  is the cleanest line, so trophies only go up and the season reset does the levelling.
- **Daily "lucky wheel" rewards.** Common in the genre; left out. The daily reward is a
  fixed 7-day calendar.
- **The word "roulette".** Spanish-speaking players will call it a ruleta anyway. The game
  never does: it is "the wheel" everywhere.
- **Skin crates.** BUCKSHOT sells them. Not here.

If paid random items are ever added, they need: odds on screen that add up to 100%, no
empty outcome, `PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted`
honoured, and tests for all three.

## 2. A match

```
lobby → sit at a table → countdown (bots fill) → intro
  → turn: decide (card? target) → spin → brake → landing → effects → next turn
  → round changes (modifiers) → sudden death when 2 are left → winner → rewards
```

**Skill, not only luck.** The wheel spins at 7 slots per second. You press BRAKE; from that
angle the wheel travels 1.25 turns plus a server-rolled jitter of ±1.25 slots. Perfect
timing lands the slot you aimed at about 40% of the time (random is 8%). Measured in
`tests/unit_core.luau`.

**Server authority.** `MatchCore` (pure Luau, no clocks, no Roblox APIs) is the state
machine. `MatchRunner` owns the timers and the RNG, turns requests and bot decisions into
core actions and plays the resulting events back. The client is told where the wheel stops
only once the brake is final, and only animates it.

### Wheel slots

| Slot | Effect |
|---|---|
| ⚡ Zap | Target loses 1 life |
| 💥 Double Zap | Target loses 2 |
| 🔁 Backfire | The spinner loses 1 |
| 🛡️ Shield | Blocks the next hit of any size |
| 💚 Heal | +1 life (cap: starting lives + 1) |
| 🧲 Steal | Target −1, spinner +1 |
| 🔄 Reverse | Turn order flips; draw a card |
| 🎯 Wild | A random living player (the spinner too) loses 1 |
| 💀 Doom | Target is out. Always sits between two Backfires |
| 🃏 Card | Draw a card (duel wheel) |
| 🔀 Swap | Trade lives with the target (chaos) |
| ☄️ Meteor | Everyone else loses 1 (chaos) |
| 🎁 Gift | Everyone draws a card (chaos) |
| 🚑 Rescue | The last eliminated teammate returns with 1 life (teams) |

### Cards (dealt free at the start; one per turn, before spinning)

| Card | Effect |
|---|---|
| 🔮 Oracle | During this spin you see where the wheel would stop if you braked now |
| ⏭️ Skip | End the turn without spinning |
| 👉 Pass | Another player takes this spin, risk included |
| 🛡️ Shield | +1 shield |
| ✖️ Double | This spin counts double, Backfire too |
| 🧲 Magnet | Take a random card from another player |

### Modes

| Mode | Players | Lives | Cards | Wheel | Twist |
|---|---|---|---|---|---|
| Classic | 2–8 (bots fill to 5) | 3 | 2 | 12 slots | A modifier every 3rd round |
| Chaos | 2–8 (fill to 6) | 3 | 3 | 14 slots | A modifier every round from round 2 |
| Teams | 2–8 (fill to 6) | 3 | 2 | 12 slots with Rescue | Two teams, alternating seats |
| Duel | 2 | 5 | 2 | 12 slots with Card | By challenge or private table |

Round modifiers: Turbo (faster wheel), Blackout (slots shuffled and hidden until it lands),
Overcharge (hits +1), Fragile (shields do not block), Gift (everyone draws).

Sudden death: when two players are left (or at a turn limit) the wheel loses its heals, the
rig turns red and every 6 turns all hits get +1. Hard stop at 150 turns (most lives wins).
Averages over 6,960 simulated bot matches: Classic 14.8 turns, Chaos 13.6, Teams 12.0,
Duel 5.6; longest 48.

Leaving mid-match: the leaver is eliminated with cause "left" and the match goes on. If it
was their spin the turn moves on; if they were the target another target is picked. A
forfeit pays nothing and costs nothing. If no human is left the match stops.

## 3. Suspense (the point of the game)

Built so it works on graphics level 1: the base is camera, timing, part colours, Beams and
a UI veil. Lighting and post-processing are extras.

| Beat | What happens |
|---|---|
| Turn | Camera pushes in on whoever is up, spotlight beam on their podium, their chip grows |
| Aim | Red laser from spinner to target, target's podium and spotlight turn red |
| Spin | Camera goes over the pointer, veil at 55%, heartbeat starts, a tick per slot |
| Brake | Camera pushes in and the FOV narrows as the wheel slows; veil to 95%; heartbeat speeds up while the ticks slow down; everyone trembles; live readout of the slot under the pointer |
| Near miss | If it stops within 14% of a boundary the banner says which slot it almost was |
| Landing | Slot lights up and the rest goes dark; on Doom the screen goes black for a beat first; banner slams, camera punches in |
| Hit | Tight close-up on the target, bolt from the wheel, flinch, red flash if it is you |
| Elimination | The attacker's finisher (hammer, rocket, slime, freeze, UFO, black hole, lightning, confetti) |
| Sudden death | Black beat, red vignette, the whole rig turns red, two-shot of the survivors |
| Winner | Orbit around the winner, confetti, the result panel |

Audio: `Config.Audio` holds the ids. Only the sounds that ship with every Roblox client are
wired (ticks, impacts); music ids are 0 until the owner adds audio he has rights to.

## 4. Matchmaking

- 6 tables in one server (16 players suggested): Classic ×2, Chaos, Teams, and 2 flex
  tables for private games and duels.
- Sit with the prompt at a table or through PLAY. A countdown starts with the first human
  (4 s for a brand-new player, 12 s otherwise) and bots fill the empty seats.
- Private table: 4-letter code, host picks mode and bots on/off and starts.
- Duel: challenge a player in the server; 20 s to answer.
- Spectate any running table: per-player camera or free orbit. Eliminated players watch
  from behind their podium.
- Comfort toggles: **Auto-queue** (stay seated for the next match) and **Auto-play** (the
  server takes your turns with a random target and a random brake; two idle turns in a row
  switch it on by themselves so an AFK player never stalls a table; the Auto-play button then
  reads ON and pressing it hands the turns back, `MatchFlow`). Neither changes odds.

## 5. Lobby activity: the Power Core

A clicker in the middle of the lobby for the time between matches. 25 taps fill a charge,
a charge pays 1 coin. Server side: 8 taps/s cap with a token bucket, only within 26 studs
and not while seated. **Auto Charge** unlocks at level 5 (or with its pass): 3 taps/s (5 with
VIP). That is about 430 coins an hour; a Classic match of a few minutes pays 20 to 120, so
playing stays the better way to earn. 200 lifetime charges unlock the Core aura.

## 6. Progression

- **Coins**: from matches, quests, daily, gifts, levels, the Core. They only buy cosmetics.
- **XP and level** (1–100): `100 + 40·(level−1)` XP per level; each level pays coins and
  some unlock cosmetics.
- **Trophies and leagues**: Bronze 0, Silver 100, Gold 250, Platinum 500, Diamond 900,
  Champion 1500. Seasons are calendar months: at rollover the league pays coins and half
  the trophies carry over.
- **Streak**: +10% coins per consecutive win, up to +50%.
- **Match rewards** (Classic, 6 players): 1st 120 coins / 110 XP / 26 trophies, last 20 / 30
  / 1. Teams and Duel: win 80 / 80 / 18, lose 30 / 35 / 3. A table with only bots gives
  half the trophies.
- **Cosmetics** (65): 13 wheel skins, 7 table skins, 8 finishers, 14 emotes, 15 titles, 8
  auras. Rarity colours follow the genre (grey, blue, purple, gold).
- **Daily**: fixed 7-day calendar. **Session gifts** at 5/10/15/25/40/60 minutes.
- **Quests**: 3 per UTC day from a pool of 10, plus a bonus for all three.
- **Codes**: `SHOWDOWN` 500 coins, `WELCOME` 250 coins, `SPIN` Early Bird title.
- **Events**: Double XP for 20 min every 3 h (UTC); Chaos Weekend (x2 coins in Chaos);
  admins can start one with `/event <id> <minutes>`, shared across servers.
- **Boards**: all-time wins, season trophies, wins this week.
- **Invite**: the invited player gets 300 coins, the inviter 500 once the friend finishes a
  match (25 rewards lifetime).

## 7. Shop

IDs are 0 until they are created in the Creator Dashboard; items with id 0 cannot be bought.

| Pass | R$ | What it gives |
|---|---|---|
| VIP | 299 | x1.5 coins and XP, gold wheel, gold aura, VIP title, faster Auto Charge |
| Double Coins | 149 | x2 coins from matches |
| Legend Skins | 199 | 3 wheel skins + 2 table skins |
| Finisher Pack | 149 | UFO, black hole, lightning |
| Emote Pack | 79 | 6 emotes and 8 emote slots |
| Auto Charge | 99 | Auto Charge from level 1 |

| Product | R$ | What it gives |
|---|---|---|
| Coin bag / sack / vault / mountain | 49 / 99 / 249 / 499 | 1,000 / 2,500 / 7,500 / 18,000 coins |
| Starter Pack (first 24 h) | 49 | 1,500 coins + Arcade wheel + Confetti finisher + Founder title |
| Server party | 25 | 50 coins for everyone in the server and confetti |

Prices follow the party-game ladder in `ROBLOX-HUD-GUIA.md` (impulse 25–99, core 99–299).

## 8. Performance budgets (asserted by the playtest)

- Server parts ≤ 2,600. Client-made parts ≤ 900 (≤ 520 in the lite profile).
- One loop per system: all wheels in one RenderStepped, all effects in one Heartbeat.
- Effects are pooled (96 parts, 40 in lite; 8 floating texts; 2 particle emitters, sparks and smoke, built-in textures).
- Lite profile (phones, graphics 1–3, or the setting): half the wheel parts, no particles,
  no Lighting tweens.

## 9. Backlog

- Season pass, daily rotating store, a "play with a friend" quest (from the HUD guide).
- A draft mode (pick one of three random effects) in the spirit of Ball VS Ball.
- Real audio, an icon and thumbnails (need the owner: uploaded assets).
- Table skins recolour your own podium only; their own geometry would be better.
