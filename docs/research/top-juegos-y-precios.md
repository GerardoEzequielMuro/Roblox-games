# Top juegos de Roblox y precios reales (research 2026-09-30)

## 0. Cómo leer esto (importante)

- **No pude consultar las APIs públicas de Roblox.** `games.roblox.com` y `apis.roblox.com` devuelven 403 en el proxy de egreso de este entorno (política de red, no un error). WebFetch también está bloqueado para rolimons, romonitorstats, rblxdb, wikipedia, etc. **Lo único que funcionó fue WebSearch**, así que todos los datos "verificados" vienen de **fuentes secundarias** (wikis de fans, rolimons, guías, DevForum y blogs), leídas a través de los resúmenes del buscador el 2026-09-30.
- Etiquetas:
  - **[V]** = dato que aparece en una fuente citada (URL abajo). Es secundario: no lo contrasté contra la API. Puede estar desactualizado o cambiar por **precios regionales** (hoy vienen activados por defecto, ver §3).
  - **[I]** = inferencia o recomendación mía.
- Para confirmar los precios exactos antes de lanzar: desde una máquina con acceso, `GET https://games.roblox.com/v1/games/{universeId}/game-passes?limit=100&sortOrder=Asc` (universeIds: Steal An Egg 10563114921; los otros se sacan con `https://apis.roblox.com/universes/v1/places/{placeId}/universe`; placeIds útiles: PS99 8737899170, Steal a Brainrot 109983668079237, Tower of Hell 1962086868, Keyboard Escape 95082159892680, 99 Nights 79546208627805, Tap Simulator 75992362647444, Clicker Simulator 7560156054, Epic Minigames 277751860, AFS Endless 130247632398296, Dragon Soul 8246874626).

---

## 1. Top ~10 por jugadores concurrentes

**Snapshot [V]**: rblxdb "Most Played Right Now (September 2026)", visto vía buscador el 2026-09-30 (hora del snapshot desconocida). https://rblxdb.com/charts/most-played

| # | Experiencia | CCU | Género | ¿Cerca de nuestros juegos? |
|---|---|---|---|---|
| 1 | Steal An Egg and Collect Rare Pets | 2,351,191 | robar/huevos/mascotas (tycoon-sim) | pet-tap, huerta, planet |
| 2 | Brookhaven RP | 366,365 | roleplay | no |
| 3 | Blox Fruits | 351,546 | anime RPG/PvP | ki-warriors |
| 4 | Murder Mystery 2 | 201,913 | party/eliminación | ruleta-pvp |
| 5 | [X10] +1 Speed Keyboard Escape (Candy & Chocolate) | 193,864 | obby incremental | obby-sky-tower |
| 6 | RIVALS | 183,618 | PvP shooter | ruleta-pvp (duelos) |
| 7 | 99 Nights in the Forest | 172,254 | survival coop | no directo |
| 8 | Adopt Me! | 132,034 | mascotas/trading | pet-tap |
| 9 | Jujutsu Shenanigans | 101,323 | anime battlegrounds | ki-warriors |
| 10 | Fish It! | 99,543 | sim/colección | huerta (loop idle) |

Otros datos [V]: pico histórico de Steal An Egg **14,272,591 el 2026-09-19** según RoVitals (https://rovitals.com/game/107778070777162); otra fuente reporta 13,790,561 el 2026-09-26 (livecounts.nl, vía buscador). El juego se creó el **2026-07-25** y en ~2 meses pasó a Brookhaven y Blox Fruits (https://www.player.one/robloxs-steal-egg-beating-some-platforms-biggest-games-164086). Grow a Garden sigue activo (update "Fall Market 2026" del 2026-09-19, https://deltiasgaming.com/grow-a-garden-fall-market-2026-update-patch-notes-roblox). Revenue estimado [V, estimación de terceros]: RIVALS y Blox Fruits lideran con ~US$8-15M/mes (https://rowatcher.com/news/the-10-highest-earning-roblox-games-in-2026-and-what-they-mean-for-the-platform).

### Qué hace que funcionen (géneros cercanos)

| Juego | Core loop | Primer minuto | Social | Cadencia / eventos | Stock limitado / trading / otros |
|---|---|---|---|---|---|
| **Steal An Egg** [V] | comprar huevo → incuba → mascota genera plata → mejorar → **robar huevos de otros** | loop entendible en segundos, correr en cinta para ganar velocidad | robar/defender = interacción forzada con otros | nuevo, updates rápidos | micro-skips: *Instant Hatch ~9 R$*, *Grow All ~160 R$* |
| **Steal a Brainrot** [V] | coleccionar/defender/robar 150+ personajes que dan ingreso pasivo | cinta transportadora con unidades para comprar al toque | robo PvP, bases | **Admin Abuse martes 18:00 ET y sábados 15:00 ET** (30-45 min, spawns exclusivos en todos los servers); update semanal sábados; collabs | Lucky Blocks en tienda Robux (random → odds), 14 tipos, varios solo en eventos |
| **Grow a Garden** [V] | plantar → esperar → cosechar → vender → mejores semillas; mutaciones | plantás en 10 s | jardines visibles, robo de cultivos con Robux, regalos | **update semanal sábados 10:00 EST**; eventos temáticos | **stock de semillas/gear rota cada 5 min, huevos cada 30 min, mercader cada 2 h**; season pass; trading |
| **Pet Simulator 99** [V] | tap/farm → monedas → huevos → mascotas → nuevas zonas | tapear y romper cosas ya | trading, booths, clanes | updates grandes + eventos | Huge pets (ultra raros), exclusive shop, Forever Pack |
| **Blox Fruits** [V] | nivelar, frutas (poderes), jefes, PvP | combate simple | tripulaciones, trading de frutas | updates grandes espaciados | **stock de frutas rotativo**, frutas permanentes por Robux, fruit notifier |
| **Jujutsu Shenanigans** [V] | battlegrounds 1vN con movesets de anime | pegar ya, sin grind | **private servers gratis** con comandos; emotes para lucirse | updates frecuentes + códigos | **free-to-play sin pay-to-win**; monetiza cosmético (emotes, kill sound, outfits) |
| **+1 Speed Keyboard Escape** [V] | cada paso suma velocidad → llegás más lejos (obby incremental) | caminar = progresar | servers de 22 | ganó premio RIA 2026 | treadmills y trails multiplicadores por Robux |
| **RIVALS** [V] | duelos cortos 1v1 a 5v5 | partida en segundos | ranking, clips | **temporadas con battle pass de 70 tiers** | llaves/cajas cosméticas, bundles |
| **Anime Vanguards / Defenders** [V] | tower defense con unidades gacha | summon inicial | trading (en AD los pases son tradeables) | battle pass por temporada | banners limitados, shiny hunter |
| **Tower of Hell** [V] | torre random que cambia cada ~8 min, sin checkpoints | subir ya | todos en la misma torre = competencia visible | mutadores/eventos | coils y efectos baratos |

**Patrones comunes [I]:** (1) loop entendible en <30 s y sin tutorial largo; (2) algo que ver de otros jugadores (robar, comparar, lucir); (3) **cita fija semanal** (update + evento con hora fija); (4) escasez con reloj (restock cada 5 min, stock rotativo, spawns de evento); (5) muchas compras chicas de "saltear espera" además de pases grandes; (6) en PvP, monetización cosmética y cero pay-to-win.

---

## 2. Precios reales

### 2.1 Tablas por juego [V salvo que diga lo contrario]

**Pet Simulator 99** (https://pet-simulator.fandom.com/wiki/Gamepasses_(Pet_Simulator_99), https://pet-simulator.fandom.com/wiki/Exclusive_Shop_(Pet_Simulator_99))
| Ítem | Tipo | R$ |
|---|---|---|
| Auto Farm | pass | 175 |
| Lucky (+200% luck en huevos) | pass | 275 |
| +15 Pets equipadas | pass | 375 |
| VIP | pass | 400 |
| +15 Eggs (hatch múltiple) | pass | 625 |
| Ultra Lucky (+500%) | pass | 800 |
| Magic Eggs (golden/rainbow) | pass | 1,200 |
| Super Drops | pass | 2,400 |
| Huge Hunter | pass | 3,250 |
| Packs de diamantes (ya retirados) | product | 125 / 450 / 1,600 / 4,500 |
| Forever Pack (escalera infinita) | product | 50 → 2,400 |

**Tap Simulator (Cursor Makers)** (https://www.rolimons.com/game/75992362647444, vía buscador)
| Ítem | R$ |
|---|---|
| Auto Rebirth | 199 |
| +2 Pet Equips | 249 |
| Faster Hatching | 295 |
| Golden Auto Craft | 599 |
| Unlimited Rebirths | 699 |
| Super Luck | 749 |
| +4 Pet Equips | 749 |
| x8 Hatch | 849 |
| Secret Hunter | 1,799 |

**Tapping Simulator (Zood)**: +20 storage 199, +3 equips 299, 2x Taps 599, +6 equips 600, +40 mega storage 799. **Clicker Simulator**: Auto Rebirth 299, Auto Clicker 399, x2 Clicks 549. **Anime Clicker Sim**: 2x Clicks 499. **Tapping Inc**: Auto Tap 99. (rolimons, vía buscador)

**Steal An Egg** (https://stealanegg.net/game-passes/, https://bo3.gg/games/articles/steal-an-egg-gamepasses-guide)
| Ítem | Tipo | R$ |
|---|---|---|
| Instant Hatch (1 huevo) | product | ~9 |
| Grow All Eggs | product | ~160 |
| X2 Money | pass | 399 |
| X2 Growth Speed | pass | 467 |

**Steal a Brainrot** (https://stealabrainrot.fandom.com/wiki/Gamepasses_and_Dev_Products) — **fuentes contradictorias**: VIP 199 o 499; 2x Money 119 o 299; Admin Panel 1,999 o 9,999. No lo pude resolver sin la API.

**Grow a Garden** (https://www.sportskeeda.com/roblox-news/grow-a-garden-season-pass-4-guide-all-rewards-premium-price, https://growagarden.fandom.com/wiki/Limited_Time_Shop)
| Ítem | Tipo | R$ |
|---|---|---|
| Forever Pack (escalón) | product | 37 → 175 |
| 100 Sheckles | product | 49 |
| Skip 1 nivel del Season Pass | product | 49 |
| Super Seed x1 / x3 / x10 | product | 199 / 575 / 1,699 |
| Season Pass Premium | product | 749 |
| Season Pass completo | product | 1,699 |

**Blox Fruits** (https://blox-fruitvalues.com/blox-fruits-gamepass/, https://bloxguidesgg.com/games/blox-fruits/values)
| Ítem | R$ |
|---|---|
| Fast Boats | 375 |
| +1 Fruit Storage | 400 |
| 2x Money | 450 |
| 2x Mastery | 450 |
| Dark Blade | 1,200 |
| Fruit Notifier | 2,200 |

**Anime Fighting Simulator: Endless** (https://afs-endless.fandom.com/wiki/Store): x2 Speed 99, x2 Agility 99, x2 Chikara 249, x2 Yen 249, VIP 299, bundle 2x monedas 549, No Limit 749.

**Dragon Soul (anime estilo DB)** (https://dragon-soul-rblx.fandom.com/wiki/Gamepasses): Chest Luck 25, Fast Travel 39, Color Picker 49, Flying Nimbus 79, Instant Transmission 149, Demon's Mark 249, Drops Luck 249, Dragon Radar 299, Soul Vanity 349, Brave Bundle 499, Time Chamber 899, bundles 899-1,399, Great Ape 9,999. **DBZ Final Stand**: Time Chamber 1,000.

**Jujutsu Shenanigans** (https://jujutsu-shenanigans.fandom.com/wiki/Gamepasses): Kill Sound 100, More Build Saves 125, More Emote Slots 150, Awakening Outfits 175, Early Access 300; todo ~950 R$. Private servers **gratis**.

**Anime Vanguards** (https://animevanguards.fandom.com/wiki/Store): Extra Unit Storage (+50) 149, VIP 299, Display All Units 599, Premium Pass 799, Shiny Hunter 1,299, Battlepass Bundle 4,999. **Anime Defenders** (https://animedefenders.fandom.com/wiki/In-Game_Store): Booth Space 99, VIP 299, 3x Speed 799, Shiny Hunter 1,299.

**RIVALS** (https://robloxrivals.miraheze.org/wiki/Season_Pass_&_Prime_Season_Pass, https://deltiasgaming.com/roblox-all-rivals-season-3-pass-rewards/): Prime (battle pass) 599, Contraband bundle 999, Prop bundle 824; tiers salteables con Robux.

**Tower of Hell** (https://www.rolimons.com/gamepass/12362005 y búsqueda): Effects 25, Gravity Coil 65, Fusion Coil 139, Double Coins 195, Bootleg Speed Coil 199, Summer pack 349, VIP 699.

**+1 Speed Keyboard Escape** (https://speedkeyboardvalues.com/blog/best-gamepasses.html, https://allthings.how/all-items-in-1-speed-keyboard-escape-rarities-speed-bonuses-and-prices/): treadmills 69 / 299 / 749 / 1,599; trails 35 / 75 / 175 / 199 / 249 / 295 / 1,099; cosméticos 49 → 689; private server 20.

**Epic Minigames** (party) (https://typical-games.fandom.com/wiki/Gamepasses): Second Effect 99, Starter Pack 99, Illumina 149, x4 Controller Chance 249, Double Coins 299, Play Rewards Plus 299, Party Premium 349, VIP 499, Private Server Powers 899.

**Dress to Impress** (https://www.sportskeeda.com/roblox-news/dress-impress-gamepasses-all-passes-price-details): Custom Makeup 349, VIP 799 (o 399 mensual).

**99 Nights in the Forest** (https://99-nights-in-the-forest.fandom.com/wiki/Diamonds): 20💎 99, 100💎 400, 250💎 900, 700💎 2,500 (bonus por volumen ≈ +0% / +24% / +38% / +39%). Único pass: Decorator 199.

**Obbies, skip stage** (DevForum, https://devforum.roblox.com/t/how-much-should-skip-stage-cost/1613444, https://devforum.roblox.com/t/whats-the-best-price-for-a-skip-stage-devproduct/3364893): rango real 20-79 R$ por stage; lo más citado 25-49; algunos usan precio por dificultad (35 early / 45 late).

**Tycoons genéricos** (https://mall-tycoon-roblox.fandom.com/wiki/Gamepasses, DevForum): 2x Cash 300-600, Auto Collect 150-350, VIP 250-800.

### 2.2 Robux ↔ USD [V]

- **Compra**: 400 R$ = US$4.99 y 800 R$ = US$9.99 (~80 R$/US$ ≈ **US$0.0125 por R$**); 10,000 R$ = US$99.99 (~100 R$/US$). https://rowatcher.com/news/robux-prices-bundles-2026-guide
- **Creador**: te quedás con el **70%** de cada pass/product.
- **DevEx**: **US$0.0038/R$** para Robux ganados desde 2025-09-05 (antes 0.0035). **US$0.0054/R$** para gasto de jugadores **18+ de EE.UU. con age check, en juegos R15**, desde **2026-06-08**. https://en.help.roblox.com/hc/en-us/articles/13061189551124 , https://backyarddrunkard.com/game-news/roblox-devex-rate-increase-june-2026/
- **Cuenta rápida [I]**: un pass de 99 R$ → 69 R$ netos → ~US$0.26 (0.37 si es 18+ US). Un pass de 399 R$ → 279 R$ → ~US$1.06.
- **Roblox Plus** (reemplaza Premium desde **2026-04-30**, US$4.99/mes): 10% de descuento en compras con Robux (20% tras 3 meses), **Roblox absorbe el descuento** (el creador cobra igual), **private servers gratis**, sin bonus de Robux. API `PromptRobloxSubscriptionPurchase`; hasta 750 R$ por suscriptor nuevo atraído. https://www.tubefilter.com/2026/04/13/roblox-plus-creator-payouts/ → vender private servers ya no rinde [I].

### 2.3 Guía de precios por tipo de ítem [I, derivada de las tablas]

| Ítem | Rango observado [V] | Recomendado [I] |
|---|---|---|
| Primera compra impulsiva | 9 (Instant Hatch), 20-25 (skip, efectos), 37 (Forever Pack) | **9-25 R$**, consumible y útil ya (saltear 1 espera/1 stage) |
| Starter pack (solo 24 h, precio tachado) | 99 (Epic Minigames) | **49-99 R$** con un valor de referencia 3-4x |
| 2x moneda principal | 119-600 (mediana ~300-450) | **249-399** (sim/tycoon); 199 en juegos chicos |
| Auto-farm / auto-tap / auto-collect | 99-399 | **149-199** (el pass más vendido del género) |
| VIP | 199-799 (mediana ~299-400) | **299-399** |
| +equip / +storage | +2 equips 249, +3 299, +15 375, +4/+6 600-749; storage 99-199 | **+3 slots 249-299**, **+6 649-749**, **storage 99-149** |
| Luck | 249 (drops) - 275 (Lucky) - 749/800 (super/ultra) | **Lucky 249-275, Super Lucky 699-799** |
| Hatch múltiple | x3 ~199, x8 849, +15 eggs 625 | **x3 199, x8 699-849** |
| Pass "whale" (hunter) | 1,299-3,250 | **1,299-1,799** (solo con base grande de jugadores) |
| Velocidad del juego (2x/3x speed) | 99 (x2 stat) - 799 (3x speed TD) | 99-249 |
| Escalera de moneda | 49/199/... ; 99/400/900/2,500 | **49 / 99 / 249 / 499 / 999** con **+0 / +10 / +25 / +40 / +60 %** de bonus |
| Skip stage (obby) | 20-79 | **19-29** (1 stage), **x10 ~149-199** |
| Coils obby | 65 (gravity) - 199 (speed) ; Fusion 139 | **Gravity 65-79, Speed 99-149, Fusion 139-199** |
| Battle pass premium | 599 (RIVALS), 749 (GaG), 799 (AV) | **299-499** para juego chico; skip de tier 49 |
| Cosméticos (aura/trail/emote/kill sound) | 25 (efecto) - 100-175 (JJS) - 689 (legendario) | **49-149 comunes, 199-399 premium, 499+ limitados de evento** |

---

## 3. Políticas vigentes en 2026 [V]

1. **Paid random items** (cualquier compra con Robux, o con moneda comprada con Robux, que da un resultado al azar): **odds numéricas en % de cada resultado antes de comprar, sumando 100%**; los ítems que modifican odds (luck boosts, pity, rate-up) deben mostrar su efecto numérico y **las odds mostradas se actualizan en vivo** cuando están activos; reglas específicas para **trading** de ítems random pagos. Actualizado en **junio 2026** por la ley coreana y aplicado **globalmente**. https://devforum.roblox.com/t/clarifying-requirements-for-paid-random-items/4654622 , https://create.roblox.com/docs/production/monetization/paid-random-items , https://www.techtimes.com/articles/319148/20260626/koreas-loot-box-rules-push-roblox-disclose-item-odds-worldwide.htm
2. **`PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted`**: obligatorio. Si da `true`, ocultar/reemplazar/bloquear la compra random. **Brasil**: desde el 17 de marzo (el resumen no aclara el año; probablemente 2026) bloqueado para menores de 18; desde el 31 de marzo, también para adultos sin verificación de edad. Relevante para público latino y en portugués.
3. **Apuestas**: **simulated gambling prohibido** aunque la moneda no se compre con Robux (fichas virtuales, apuestas simuladas). No se puede ganar ni perder Robux, dinero real ni ítems tradeables/con valor. Minijuegos de azar "sin stakes" (sin moneda de ningún tipo) son aceptables. https://devforum.roblox.com/t/clarification-on-robloxs-simulated-gambling-guidelines/3631931 , https://about.roblox.com/community-standards
4. **Regional pricing**: passes desde abril 2025, developer products desde octubre 2025; **desde 2026-03-30 todos los passes quedan en precio regional por defecto** (opt-out por pass). Los precios regionales van del 30% al 100% del precio base. https://devforum.roblox.com/t/enabling-regional-prices-for-all-passes-to-grow-your-global-audience/4471199 , https://create.roblox.com/docs/production/monetization/regional-pricing
5. **Pisos/techos**: no encontré cambios en 2026 (el mínimo para un pass sigue siendo 1 R$ según docs/guías). Una guía menciona que desde **2026-05-30 se deshabilitaron ventas de passes entre juegos (cross-game)**; es una sola fuente, a confirmar. https://generalistprogrammer.com/tutorials/roblox-game-pass-pricing-guide
6. **Edad**: age check obligatorio para el chat, con rollout global desde enero 2026. Cuentas **Roblox Kids (5-8)** y **Roblox Select (9-15)** desde el 13 de abril (globales en junio 2026): Kids solo ve juegos Minimal/Mild; Select hasta Moderate. Para aparecer ahí, el dev tiene que tener **ID verificado + 2FA + suscripción o fee reembolsable**; se excluyen juegos con hangout social o dibujo libre. Los padres pueden poner el límite de gasto en $0. https://create.roblox.com/docs/production/publishing/kids-and-select , https://techcrunch.com/2026/04/13/roblox-introduces-kids-and-select-accounts-for-age-appropriate-access-to-games-and-chat/

**Implicancias [I]:** completar bien el cuestionario de madurez (apuntar a Mild para entrar en Select); toda caja/huevo/cápsula paga y todo pass de suerte → UI de odds + chequeo de PolicyService; en ruleta-pvp, nada de apuestas.

---

## 4. Recomendaciones por juego [I, salvo las referencias]

"Actual" = precio que tiene hoy el `Config.luau` del repo.

### 4.1 huerta-tycoon — Crop Kingdom (ref: Grow a Garden, Steal An Egg, tycoons)

| Ítem | Tipo | Actual | Recomendado | Por qué |
|---|---|---|---|---|
| Starter Pack (24 h) | product | 15 (tachado 49) | **29-49** (tachado 149) | 15 deja plata sobre la mesa; el impulso lo cubre el ítem de 9 R$ |
| Instant Grow 1 planta | product (nuevo) | — | **9** | copia Instant Hatch ~9 de Steal An Egg: primera compra |
| Instant Grow (todo) | product | 79 | **79-129** | "Grow All" ~160 en Steal An Egg |
| Restock Shop | product | 39 | **39** | combina con el restock cada 5 min tipo GaG |
| Cash Pouch / Chest | product | 49 / 199 | 49 / 199 / **499 / 999** | completar la escalera con bonus +40/+60% |
| Lucky Seed Pack | product (random) | 99 | 99 | **odds visibles + PolicyService** |
| 2x Cash | pass | 249 | **349** | refs 399 (X2 Money) y 300-600 en tycoons |
| 2x Grow Speed | pass (nuevo) | — | **399** | ref X2 Growth 467 |
| Auto Harvest | pass | 199 | 199 | auto-collect 150-350 |
| VIP | pass | 399 | 399 | rango típico |
| Super Luck (mutaciones) | pass | 299 | 299 | modifica odds → mostrar % con y sin el pass |
| Big Basket / Sell Anywhere | pass | 99 / 149 | 99 / 149 | ok |
| Season pass premium | product (nuevo) | — | **399** + skip de tier 49 | GaG 749; más barato por ser juego chico |

Top 5 para copiar: (1) **restock visible con cuenta regresiva** (semillas cada 5 min, raras cada 30 min, mercader cada 2 h); (2) **update semanal sábado a hora fija** + evento "admin" de 30 min con semillas exclusivas; (3) jardines de otros visibles con leaderboard de valor del jardín; (4) mutaciones raras anunciadas en el chat del server; (5) regalos y trading de semillas/mascotas (con reglas de PolicyService si vienen de packs pagos).

### 4.2 obby-sky-tower (1000 niveles) (ref: Tower of Hell, Keyboard Escape, DevForum)

| Ítem | Tipo | Actual | Recomendado | Por qué |
|---|---|---|---|---|
| Skip Stage | product | sin precio | **19** (niveles 1-300) / **29** (301-1000) | rango real 20-79; con 1000 niveles conviene barato y repetido |
| Skip x10 | product | sin precio | **149** | ~25-50% de descuento contra comprar de a uno |
| Double Jump 5 min | product | — | **9** | primera compra impulsiva |
| Starter Pack | product | 59 sugerido | **59** (tachado 169) | ok |
| Coins 500 / 2500 | product | sin precio | **49 / 199** + 499 | escalera |
| Speed Coil | pass | 8 sugerido | **79-99** | ToH Bootleg Speed 199. No encontré evidencia de coils a 8 R$; 8 R$ para un pass permanente es muy barato [I] |
| Gravity Coil | pass | sin precio | **65-79** | ToH 65 |
| Fusion (speed+gravity) | pass (nuevo) | — | **139** | ToH 139 |
| Infinite Revives | pass | 139 sugerido | **149-199** | ahorra mucho skip; no canibalizar |
| 2x Coins | pass | sin precio | **195** | ToH 195 |
| VIP | pass | sin precio | **299** | ToH 699 es de un juego enorme |
| Trails/auras premium | pass/product | coins | 49-199 por Robux además de coins | Keyboard Escape cobra cosméticos de 49 a 689 |

Top 5 para copiar: (1) progreso visible en la torre (altura/stage de todos en pantalla, como ToH); (2) sensación incremental: cada X stages, speed/trail nuevo (Keyboard Escape); (3) mutadores/evento semanal con torre especial por tiempo limitado; (4) leaderboard global de stage + badges cada 50/100; (5) códigos y recompensa por unirse al grupo (trail "Crew", ya existe) anunciados en cada update.

### 4.3 pet-tap-simulator (ref: PS99, Tap Simulator, Tapping Simulator, Clicker Sim)

| Ítem | Tipo | Actual | Recomendado | Por qué |
|---|---|---|---|---|
| Auto Tap | pass | 149 | 149 | Tapping Inc 99, Clicker Sim 399, PS99 Auto Farm 175 |
| Double Taps | pass | 399 | **449** | 2x Clicks 499-599 |
| x3 Hatch | pass | 199 | 199 | ok |
| x8 Hatch | pass (nuevo) | — | **699** | Tap Sim 849, PS99 +15 eggs 625 |
| Auto Hatch | pass | 249 | 249 | ok |
| Auto Rebirth | pass (nuevo) | — | **199** | Tap Sim 199, Clicker 299 |
| Lucky | pass | 199 | **249** | PS99 275 |
| Super Lucky | pass (nuevo) | — | **699** | PS99 Ultra 800, Tap Sim 749 |
| Magic Eggs | pass | 349 | **599** | PS99 1,200; hoy está regalado |
| +3 Pet Slots | pass | 299 | **249**, y +6 a **649** | escalera de 2 pasos (Tap Sim 249/749) |
| +Storage | pass (nuevo) | — | **99** | Tapping Sim 199, AD 99 |
| Secret/Huge Hunter | pass (nuevo) | — | **1,299** | PS99 3,250, Tap Sim 1,799; techo para "whales" |
| VIP | pass | 299 | 299 | ok |
| Gems 100 / 600 | product | 49 / 249 | 49 / 249 / **499 (1,400) / 999 (3,200)** | escalera con bonus creciente |
| Magic Egg x1 / x3 | product (random) | 149 / 399 | 149 / 399 | odds + PolicyService (ya marcado) |
| Starter Pack | product | 99 | 99 (tachado 399) | ok |

Top 5 para copiar: (1) **mascotas "Huge"/secretas ultra raras con anuncio a todo el server** (PS99); (2) **trading + booths** para lucir; (3) huevos de evento por tiempo limitado con fecha fin visible; (4) Forever Pack (escalera de recompensas con primer escalón barato ~37-50 R$); (5) zonas nuevas en cada update semanal + códigos.

### 4.4 anime-planet-clicker — Planet Crackers (ref: PS99, Clicker Sim, Steal An Egg por el PvP)

| Ítem | Tipo | Actual | Recomendado | Por qué |
|---|---|---|---|---|
| Auto Miner | pass | 149 | **175** | PS99 Auto Farm 175 |
| Double Damage | pass | 199 | **349** | 2x clicks 499-549; 2x core |
| Double Stardust | pass | 249 | **349** | 2x moneda 300-450 |
| VIP | pass | 249 | **299** | mediana |
| Pet Slots | pass | 249 | 249 (+ tier 2 a 649) | ok |
| Triple Open / Fast Open | pass | 199 / 99 | 199 / 99 | ok; agregar x8 Open a **699** |
| Lucky / Super Lucky | pass (random) | 99 / 299 | **249 / 699** | PS99 275/800; hoy muy baratos |
| Golden Capsules | pass (random) | 349 | **599** | ref Magic Eggs 1,200 |
| Sprint | pass | 49 | 49 | buen pass de entrada |
| Crystals 100 / 600 | product | 49 / 249 | + **499 / 999** | escalera |
| Quantum Capsule x1 / x3 | product (random) | 149 / 399 | 149 / 399 | odds + PolicyService |
| Starter Pack | product | 99 (tachado 399) | 99 | ok |
| PvP | — | — | **sin ventajas pagas en el PvP** (o normalizar stats en la arena) | el modelo de JJS/RIVALS evita el rechazo por pay-to-win |

Top 5 para copiar: (1) interacción obligatoria con otros (robar o atacar planeta/base ajena con defensa, como Steal An Egg / Brainrot); (2) **eventos "admin" con hora fija 2 veces por semana** y cápsulas exclusivas; (3) cápsulas limitadas de evento con odds visibles y pity; (4) leaderboard de poder + nametag de ranking; (5) trading de mascotas.

### 4.5 ki-warriors (ref: AFS Endless, Dragon Soul, JJS, Blox Fruits)

| Ítem | Tipo | Actual | Recomendado | Por qué |
|---|---|---|---|---|
| Fast Flight | pass | 99 | **79** | Nimbus 79, Fast Travel 39 |
| 2x Training | pass | 349 | **249** | x2 Chikara 249 |
| 2x Sparks | pass | 199 | **249** | x2 Yen 249 |
| Bundle 2x (training + sparks) | pass (nuevo) | — | **449-549** | AFS bundle 549 |
| Turbo Auto | pass | 249 | 249 | ok |
| Ki Mastery | pass | 199 | 199 | análogo a x2 Mastery (450 en BF) |
| Lucky Aura | pass | 249 | 249 | Drops Luck 249; si afecta drops pagos, mostrar odds |
| Relic Radar | pass | 149 | **299** | Dragon Radar 299; Fruit Notifier 2,200 |
| VIP | pass | 399 | **299** | AFS/AV/AD 299 |
| Cámara de entrenamiento (tiempo x2 en sala especial) | pass (nuevo) | — | **499-899** | Time Chamber 899-1,000 |
| Auras / transformaciones cosméticas | pass (nuevo) | — | **149-399**; de evento 499+ | Outfits JJS 175, bundles DS 499-1,399 |
| Emote slots / kill sound | pass (nuevo) | — | **99-149** | JJS 100-150 |
| Sparks / Gems ladder | product | 49→399 / 49→699 | ok (bonus +24/+48/+84% y +14/+31/+52%) | subir el bonus de Gems 2 a ~+20% |
| Starter Pack | product | 99 | 99 | ok |

Top 5 para copiar: (1) **battlegrounds sin pay-to-win** (monetizar entrenamiento y cosmética, no daño en PvP); (2) **private servers gratis con comandos** (JJS; además Plus ya los da gratis); (3) movesets/transformaciones nuevas en cada update + códigos; (4) jefes/raids con drops y stock rotativo de técnicas (como las frutas de BF); (5) auras/emotes para lucirse y ranking visible.

### 4.6 ruleta-pvp (ref: Epic Minigames, MM2, RIVALS)

| Ítem | Tipo | Actual | Recomendado | Por qué |
|---|---|---|---|---|
| VIP | pass | 299 | 299 | Epic Minigames 499 |
| Double Coins | pass | 149 | **199-249** | EM 299 |
| Legend Skins / Finisher Pack | pass | 199 / 149 | 199 / 149 | cosmético puro |
| Emote Pack | pass | 79 | 79-99 | EM Second Effect 99 |
| Kill/elimination sound | pass (nuevo) | — | **99** | JJS 100 |
| Auto Charge | pass | 99 | 99 | verificar que no dé ventaja en la partida |
| Season pass premium | product (nuevo) | — | **399** (skip tier 29-49) | RIVALS 599 |
| Coins 49 / 99 / 249 / 499 | product | ok | ok (bonus +24 / +48 / +77%) | buena escalera; agregar **999 → ~40,000** |
| Starter Pack | product | 49 (tachado 199) | 49-99 | EM 99 |
| Server Party | product | 25 | 25 | buen impulso social |
| **Prohibido** | — | — | nada de apuestas con coins, pagar por "girar" o por cambiar odds de la ruleta, ni "x4 chance" tipo EM | política de simulated gambling; la ruleta no debe tener stakes (ya está `affectsMatch=false`) |

Top 5 para copiar: (1) rondas de ≤2 min y re-cola instantánea (RIVALS/MM2); (2) **roles/modos rotativos** (Epic Minigames) para que cada ronda sea distinta; (3) season pass con cosméticos de eliminación/finisher; (4) momentos para clip (slow-mo de la eliminación, confeti del ganador); (5) leaderboard semanal de wins y rachas + evento de fin de semana con modo especial.

---

## Fuentes principales

- Top CCU: https://rblxdb.com/charts/most-played · https://rovitals.com/game/107778070777162 · https://www.player.one/robloxs-steal-egg-beating-some-platforms-biggest-games-164086 · https://rowatcher.com/news/the-10-highest-earning-roblox-games-in-2026-and-what-they-mean-for-the-platform
- Eventos/cadencia: https://www.pcgamesn.com/grow-a-garden/update-schedule · https://gagcalculatorvalue.com/stock · https://www.eldorado.gg/blog/steal-a-brainrot-en/steal-a-brainrot-admin-abuse-schedule-explained/ · https://freetoplayer.com/jujutsu-shenanigans/
- Precios: URLs en cada tabla de §2.1.
- Economía: https://rowatcher.com/news/robux-prices-bundles-2026-guide · https://en.help.roblox.com/hc/en-us/articles/13061189551124 · https://www.tubefilter.com/2026/04/13/roblox-plus-creator-payouts/
- Políticas: https://devforum.roblox.com/t/clarifying-requirements-for-paid-random-items/4654622 · https://create.roblox.com/docs/production/monetization/paid-random-items · https://devforum.roblox.com/t/enabling-regional-prices-for-all-passes-to-grow-your-global-audience/4471199 · https://create.roblox.com/docs/production/publishing/kids-and-select · https://devforum.roblox.com/t/clarification-on-robloxs-simulated-gambling-guidelines/3631931
