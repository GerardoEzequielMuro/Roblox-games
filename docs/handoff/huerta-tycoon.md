# Crop Kingdom (huerta-tycoon): handoff

Todo esto se hizo en un contenedor Linux sin Roblox Studio. **No vi el juego corriendo en ningún momento.** Lo que
sigue está verificado con build, analizador y tests puros; lo visual hay que mirarlo en Studio (ver abajo).

Cuando lo revisé, el juego ya tenía bastante trabajo encima: Lighting completo (Atmosphere, Bloom, ColorCorrection,
SunRays, DOF, Clouds), terreno con materiales, fuente FredokaOne, botones con gloss, stroke y tweens de hover/press,
módulo de audio con IDs en 0 que no hace nada, y guardado en DataStore serializado por jugador con autosave
escalonado. Eso no lo toqué (el punto 4 del backlog ya estaba hecho). Me enfoqué en los íconos, los bugs visuales y
en darle más textura a cultivos y props.

## Qué cambié

**Íconos (pack compartido `Shared/Icons`)**
- `src/client/UI/Theme.luau`: agregué `Theme.EmojiIcon`, que mapea el emoji usado como ícono al nombre del pack
  (🛒→shop, 🔁→rebirth, 💎→gem, 🎁→gift, 🎟️→ticket, ⏰→clock, 📖→book, 👋→invite, 🏆→trophy, 🤖→auto, 💰/💵→cash,
  💲→coin, 🍀/🎲→luck, 👑→crown, ✅→check, ✕→close, ⭐→star, 🌱→sprout, 🔒→lock, ⚡→bolt…).
- `src/client/UI/Components.luau`: helpers nuevos, todos en un solo lugar:
  - `C.icon(parent, emoji, size, props, name?)`: con la imagen subida crea un `ImageLabel` (ScaleType Fit, fondo
    transparente) dentro de un marco del mismo tamaño y posición. Si no hay imagen, llama a `C.label` con los mismos
    argumentos de siempre, así que hoy se ve **exactamente igual**.
  - `C.iconPrefix(emoji)` + `C.addIcon(btn, emoji)`: en botones con texto, la imagen va a la izquierda de la etiqueta
    y se saca el emoji del texto. Sin imagen, el texto queda como estaba.
  - `C.panel`: el ícono del título pasa a ser una imagen si está subida. Nuevo `IconName` opcional (Upgrades usa
    "upgrade" en lugar de "bolt").
  - El botón ✕ de cierre usa el ícono "close" si está subido.
- Lugares donde se aplica: menú lateral (`Panels.luau`), títulos de todos los paneles, moneda del HUD ("coin") y botón
  Auto (`Hud.luau`), íconos de upgrades (`UpgradesPanel.luau`), productos de la tienda (`StorePanel.luau`), modos de
  auto-farm (`AutoPanel.luau`), recompensas diarias (`DailyPanel.luau`) y regalos (`GiftsPanel.luau`).
- No toqué los emojis que forman parte de oraciones traducidas, ni las semillas, mutaciones y clima (no hay ícono
  equivalente en el pack).

**Bugs visuales**
- Paneles en celulares chicos (`src/client/UI/Panels.luau`, `Layout.luau`, nuevo `UiMath.luau`). Antes, un panel de
  700x520 se achicaba para entrar entero en la pantalla, y en un teléfono sus botones de 54 px quedaban en unos
  26 px reales. Ahora el panel nunca baja de la escala que deja los botones en 44 px táctiles (40 con mouse). Si
  así no entra de alto, el panel se hace más corto: los paneles que ya tienen lista scrolleable achican esa lista, y
  el resto (Rebirth, Daily, Codes, Invite, Starter, Auto, Language, Gifts) se envuelve en un `ScrollingFrame`
  vertical con su alto original. En PC y tablets no cambia nada: si el panel entra, se ve igual que antes.
- Carteles flotantes sobre la parcela (`src/client/UI/Tiles.luau`):
  - Las barras de crecimiento solo aparecen en las **6 más cercanas** dentro de 40 studs. Antes había una por cada
    tile plantado (hasta 30), siempre visibles y encimadas. También las hice más chicas (2.8 x 0.42 studs).
  - "READY!" sigue limitado a los 3 más cercanos, ahora con la misma función pura (`UiMath.nearest`).
  - En tu próximo tile a comprar, el precio pintado por el server (`LockGui`) se oculta solo para vos, porque el cartel
    flotante ya muestra lo mismo encima.
- Números "+$" de Harvest All (`src/client/UI/Fx.luau`): antes subían hasta 12 números encimados. Ahora los primeros
  3 salen sueltos y el resto de la ráfaga se suma en un solo número dorado más grande ("+$total", "xN") que se
  actualiza. Las mutaciones y los tamaños Big/Giant siempre muestran su propio número.
- Tamaño del HUD: lo revisé con la cuenta. En 1920x1080 la escala raíz ya estaba topeada en 1, así que el HUD mide
  lo que dice en píxeles de diseño y no se agranda. En celulares el canvas compacto deja los botones de 54 px en
  ≥ 44 px reales (en un 620x330, 45 px). Ahí no cambié números: el bug real de botones < 40 px estaba en los paneles.

**Look 2026**
- `src/server/World/CropVisuals.luau`:
  - El tallo del maíz ya no es un caño: ahora es un huso que se afina hacia la espiga (misma cantidad de partes).
  - El follaje deja de ser SmoothPlastic: arbustos y copas usan Grass, y hojas, chala, pétalos, tallos, guías,
    brotes y brazos de cactus usan Fabric. La fruta mantiene el acabado liso y brillante, y las mutaciones conservan
    su material.
  - Cada tile tiene su verde, ±7% de brillo derivado de la posición, así que siempre se ve igual. Una parcela llena
    ya no parece copiar y pegar.
  - El presupuesto de partes por tile (24) no cambia: no agregué partes.
- `src/server/World/Props.luau`: las partes sin material explícito lo toman de su nombre. Marcos, molduras, vigas,
  postes y aleros van como Wood; sogas, banderines y cintas como Fabric; juncos, guías y camalotes como Grass. Los
  animales, globos y detalles chicos siguen con el acabado cartoon.
- HUD (`Hud.luau`, `Hotbar.luau`, `Components.luau`): sombra suave (`C.dropShadow`, un frame hermano que sigue
  posición, tamaño y visibilidad) y degradé vertical en la tarjeta de stats, la barra de canasta y la hotbar.

**Tests**
- `tests/ui_test.luau` (nuevo, puro), con 11 checks:
  - elección de canvas;
  - escala 1 en 1080p;
  - botones ≥ 44 px en teléfonos;
  - 12 tamaños de panel × 8 pantallas: entra, no se achica bajo el mínimo y queda con alto útil;
  - `nearest`: los N más cercanos, rango y desempates.

## Cómo lo verifiqué
- `rojo build default.project.json`: OK (también `test.project.json` y `showcase.project.json`).
- `luau-lsp analyze … src`: **0 errores**, sin salida fuera de INFO/WARN, igual que antes.
- Tests puros (`luau tests/<x>.luau`):
  - autofarm_test: 28 checks, 0 failures
  - locale_test: 11 languages, 326 keys in en, 3597 checks, 0 failures
  - odds_test: 46 checks, 0 failures
  - p0_test: 47 checks, 0 failures
  - trophies_test: 27 checks, 0 failures
  - ui_test: 11 checks, 0 failures (nuevo)
  - wild_test: 28 checks, 0 failures
  - world_test: 72 checks, 0 failures
- No corrí el playtest de Studio (`tests/AutoTest*.luau`). No hay Studio acá.

## Qué hay que mirar en Studio
1. **Paneles en pantalla chica** (ventana 1050x600, que da un viewport de unos 570x345, y 1400x760): abrí Shop,
   Upgrades, Store, Index, Rebirth, Daily y Starter.
   - El panel tiene que verse grande, no a la mitad.
   - Los botones de comprar tienen que quedar cómodos.
   - Rebirth, Daily y Starter tienen que scrollear vertical sin cortar nada a los costados.
   - El botón ✕ tiene que seguir en la esquina.
   - Las badges de las tarjetas (arriba a la derecha) no tienen que quedar recortadas por el borde del scroll.
2. **Paneles en PC** (1920x1032): tienen que verse idénticos a antes (sin scroll).
3. **Parcela plantada entera (30 tiles)**:
   - que se vean como mucho 6 barras de crecimiento, las más cercanas;
   - que no se encimen;
   - que al caminar vayan cambiando a los tiles cercanos.
4. **Harvest All con la parcela llena**: 3 números sueltos y después un "+$total xN" dorado que va subiendo. Una
   mutación tiene que seguir mostrando su propio número de color.
5. **Próximo tile a comprar**: en tu parcela, un solo cartel con 🔒 y el precio, no dos. En parcelas ajenas sigue
   pintado en el piso.
6. **Cultivos**:
   - el maíz, que el tallo se afine hacia arriba y no parezca un palo;
   - las texturas Grass y Fabric en arbustos, copas y hojas: si Grass se ve muy "ruidoso" de cerca, se cambia en
     `FOLIAGE`, en `CropVisuals.luau`;
   - la variación de verdes entre tiles;
   - las mutaciones (Golden, Frozen, Rainbow), que tienen que verse igual que antes.
7. **Props**: molduras, marcos y postes de granero, casa y puestos con veta de madera, y banderines y sogas con tela.
   Que nada blanco se vea sucio.
8. **HUD**: sombra suave debajo de la tarjeta de stats, la canasta y la hotbar, sin desfasarse cuando cambian de
   tamaño o posición (rotá o redimensioná la ventana).
9. **Íconos**: cuando se suban (`tools/icons/upload_assets.py`), revisá el menú, los títulos de panel, el ✕, la
   moneda del HUD, el botón Auto, las tarjetas de Store y Upgrades y Daily/Gifts. Esa rama (ImageLabel) no se probó
   nunca, porque hoy `Icons.get` devuelve nil y todo cae al emoji.
10. Correr `tests/run.ps1`: el playtest completo tiene que seguir en PASS (budgets de partes de cultivos incluidos).

## Pendiente
- Subir el pack de íconos: hasta entonces todo sigue con emoji.
- Precio del Starter Pack (15 vs 99 R$): no lo toqué, lo decide Gerar.
- El pedido hablaba de "carteles de % / chances sobre las parcelas". En el código no encontré un cartel de % en el
  mundo. Asumí que eran las barras de crecimiento, los "+$" de cosecha y el precio duplicado del tile. Si en Studio
  se sigue viendo otro cartel encimado, hay que sacarle una captura para ubicarlo.
- No agregué sombras a los paneles: el `PopScale` los anima y una sombra hermana no lo seguiría. Habría que meter
  cada panel dentro de un contenedor.
- Sonidos: siguen en 0 en `Config.Sounds`. El módulo está listo y no hace nada sin IDs.
- Los cultivos siguen siendo de partes primitivas. Un salto grande de calidad necesita meshes subidos, y eso no se
  puede hacer sin assets.

## Ronda 2

Sin Studio otra vez: **no vi nada corriendo**. Todo está verificado con build, analizador y tests puros.

### Precios
Ids de productos siguen en 0 (los crea Gerar). Los precios de `Config.GamePasses` / `Config.DevProducts` son `priceHint`: la tienda muestra el precio real de la plataforma (`GetProductInfo`).

| Ítem | Antes | Ahora | Por qué |
|---|---|---|---|
| 2x Cash (pase) | 249 | **349** | refs 300-600 en tycoons, 399 X2 Money |
| 2x Grow Speed (pase, NUEVO) | - | **399** | ref X2 Growth ~467; stackea con VIP (x1.5) |
| Instant Grow (1 planta) (producto, NUEVO) | - | **9** | primera compra impulsiva (Instant Hatch ~9) |
| Cash Vault (NUEVO) | - | **499** | escalera 49/199/499/999 |
| Cash Hoard (NUEVO) | - | **999** | idem, +62% de minutos por R$ vs el chico |
| Instant Grow (todo), Restock 39, Cash Pouch 49, Cash Chest 199, Lucky Pack 99 | igual | igual | ya estaban en rango recomendado |
| Auto Harvest 199, VIP 399, Super Luck 299, Big Basket 99, Sell Anywhere 149 | igual | igual | ya estaban en rango |
| Starter Pack | 15 (tachado 49) | **sin cambios** | lo decide Gerar. La investigación recomienda **29-49 con tachado 149**. Ojo: el tachado de 49 no es un precio real de nada en el juego; si se sube, conviene tachar la suma real de lo que trae o sacar el tachado |
| Season pass premium 399 + skip de tier 49 | - | **no hecho** | es un sistema entero (tiers, XP, UI, 12 idiomas); ver Pendiente |

Detalles de implementación:
- Cash packs: `Config.CashPackMinutes/Floor/CashShare` (`src/shared/Config.luau`), grant en `src/server/Services/Monetization.luau` (un solo camino para los 4 packs). Minutos por R$: 0.20 / 0.30 / 0.32 / 0.33.
- Instant Grow (1): `Garden.instantGrowOne` (`src/server/Services/Garden.luau`) madura el cultivo que más tarda (`Goals.slowest`, pura). Si no había nada creciendo, igual se entrega (cash = 3 min de ritmo, `Config.InstantGrowOneFallbackMinutes`) para no dejar una compra sin grant. Pasa por el mismo `ProcessReceipt` idempotente (PurchaseId guardado + save inmediato).
- 2x Grow Speed: `Session.growthMult` (`src/server/Services/Session.luau`), se carga con `loadPasses` como los otros pases.
- Todo con texto en los 12 idiomas (`src/shared/Locales/*.luau`), emoji en `Theme.ProductEmoji`, y aparece solo en la tienda (`StorePanel` itera Config, ya ocultando ids en 0).
- Ninguno de los nuevos es aleatorio, así que no entran a `Odds.RandomItems`. Lucky Pack y Super Luck siguen detrás de odds + `ArePaidRandomItemsRestricted`.

### Retención
| # | Ítem | Estado | Dónde |
|---|---|---|---|
| 1 | Loop de segundos con feedback | ya estaba | `UI/Fx`, `UI/Juice`, cash count-up en `UI/Hud`, hooks de sonido en `UI/Sound` (IDs en 0) |
| 2 | Próxima meta siempre visible con barra | **agregado** | `src/shared/Goals.luau` (pura) + chip "🎯 ... faltan $X" con barra arriba de la barra de canasta en `src/client/UI/Hud.luau` (`refreshGoal`). Muestra lo más barato que todavía no podés pagar entre tile, semillas, upgrades y rebirth; se oculta mientras aparece "Teleport to Sell" |
| 3 | Metas de sesión y largas | ya estaba | zonas/tiles, rebirth, Index de cultivos x mutación (`IndexPanel`), trofeos, leaderboard global (`Services/Leaderboard`), mutaciones raras |
| 4 | Razones para volver | ya estaba | daily + racha (`DailyPanel`), regalos por tiempo jugado (`GiftsPanel`), crecimiento offline (`Garden.applyOffline`), evento semanal sábado 18 UTC + LuckyHour cada 3 h con reloj (`UI/LiveEvent`), restock cada 5 min visible, Wild Patch por hora, códigos, regalo de grupo |
| 5 | Social | ya estaba (salvo gifting) | anuncio server-wide de hallazgos raros (`Garden.harvest` -> `msg.rareHarvest`, y stock raro en `Shop`), invitar/referido (`Shared/Referral`), leaderboard físico. **Gifting entre jugadores: no agregado** (ver Pendiente) |
| 6 | Primer minuto | **agregado** (parcial) | el tutorial ya guiaba comprar, plantar, cosechar y vender (`UI/Tutorial`); ahora al terminarlo y haber vendido algo hay un regalo de bienvenida (`Config.TutorialGift`: 60 + 3 tomates, `FinishTutorial` en `Garden.luau`). Solo una vez, y skipear sin vender no paga. El HUD sigue igual de minimalista |

### Otros cambios
- `src/shared/Config.luau`: `Color3` cae a un stub si corre fuera de Roblox, para poder testear precios con Luau plano. No cambia nada dentro de Roblox.
- Ronda 1 "Pendiente" en código seguro: no había nada nuevo que fuera solo código (íconos y sonidos necesitan assets, Starter lo decide Gerar, las sombras de paneles son visuales sin poder verlas).
- Regla ética cumplida: nada de urgencia/escasez falsa (el único reloj de oferta es el Starter de 24 h reales por jugador, y el restock/eventos son reales), odds visibles, sin apuestas, sin PvP.

### Cómo lo verifiqué
- `rojo build` de `default`, `test` y `showcase`: OK.
- `luau-lsp analyze ... src`: sin salida (0 errores); también sobre los 2 tests nuevos.
- Tests puros: autofarm 28/0, goals 13/0 (nuevo), locale 11 idiomas 341 claves 3762 checks/0, odds 46/0, p0 47/0, pricing 45/0 (nuevo: precios recomendados, escalera de cash packs, anclas honestas, ids únicos, textos en 12 idiomas, regalo de tutorial y meta inicial), trophies 27/0, ui 11/0, wild 28/0, world 72/0 (todos "failures" = 0).
- No hay carpeta `sim/` en este juego. No corrí el playtest de Studio.

### Qué mirar en Studio
1. Chip de meta sobre la barra de canasta: que no pise el cartel del tutorial ni el botón "Teleport to Sell", en PC y en celular (en celular el chip mide 250 px de ancho y la canasta 300+). Que la barra avance y el texto cambie de meta al comprar.
2. Completar el tutorial vendiendo: llega el regalo de bienvenida con toast. Con "Skip" sin vender no debe llegar.
3. Con ids de prueba: comprar Instant Grow (1) con cultivos creciendo (madura el más lento) y sin nada plantado (paga cash). Comprar 2x Grow Speed y ver el 🌱 del HUD (x2, y x3 con VIP).
4. Tienda: los 12 cards nuevos/viejos ordenados por precio, sin texto cortado en idiomas largos (ru, de, vi).
5. Cash Vault / Hoard: que el monto otorgado sea razonable para un jugador de mitad de juego.

### Pendiente
- Decidir precio del Starter Pack (recomendado 29-49 con tachado honesto).
- Season pass (399 + skip 49): no hecho, es un sistema completo.
- Gifting/trading de semillas entre jugadores: no hecho (requiere selector de jugador, límites anti-alts y reglas de PolicyService si vienen de packs pagos).
- Crear los productos/pases en el Creator Dashboard y pegar los ids: `DoubleGrow`, `InstantGrowOne`, `CashMedium`, `CashHuge` son nuevos.
- Los precios de referencia vienen de fuentes secundarias (ver aviso en el research); confirmar antes de lanzar.

## Ronda 3: ranuras de modelos

**Qué cambié**
- Nueva carpeta `huerta-tycoon/assets/models/` (solo README) mapeada como `ServerStorage.ModelLibrary` en `default`, `test`, `showcase` e `i18naudit` `.project.json`.
- `src/server/World/ModelSlots.luau`: `ModelSlots.spawn(slot, cf, targetSize, parent, fallback, opts)`. Clona `slot` o `slot_1..n` (elegido por posición, sin usar `Props.rng`), borra todo script del clon (con warn), escala con `ScaleTo` para entrar en el tamaño objetivo, apoya la base, ancla, ajusta colisión al primitivo (solid / decor, tronco invisible para árboles) y respeta un tope de partes por ranura (y 6000 en total), si no usa el `fallback`.
- `src/shared/ModelFit.luau`: matemática pura (escala, elegir variante, presupuesto, yaw).
- `Props.luau`: 12 ranuras: `tree`, `bush`, `rock`, `farmhouse`, `barn` (solo el edificio), `fountain`, `carrot_statue`, `tractor` (sin remolque), `lamp`, `bench`, `scarecrow`, `balloon`. Los primitivos quedaron como funciones locales `*Primitive` o dentro del `fallback`; sin modelos el flujo y el stream de `rng` es idéntico. Plataformas, parcelas, puestos y cultivos no se tocaron. El molino no tiene ranura (aspas con CK_Spin).
- Como el mapa se construye en el servidor, no hay variante de cliente.
- Doc para Gerar: `docs/modelos/huerta-tycoon.md`.

**Cómo lo verifiqué**
- `tests/modelslots_test.luau` (1699 checks) y todos los `tests/*_test.luau` pasan con `luau`.
- `luau-lsp analyze` sobre `src`: sin salida.
- `rojo build` de default, test y showcase OK (i18naudit ya apuntaba a rutas `C:/work/...` de Windows y falla en Linux, preexistente). Con la carpeta solo con README, Rojo crea un Folder vacío `ModelLibrary` sin quejas.
- Prueba temporal: un `tree.rbxmx` (Model + Part + Script) en `assets/models` aparece en `ServerStorage.ModelLibrary.tree` del build; archivo borrado.
- No pude probar `ScaleTo`/`GetBoundingBox` en runtime (sin Studio).

**Qué mirar en Studio**
- Con la biblioteca vacía el mapa debe verse igual que antes.
- Soltá un `tree.rbxm` y un `farmhouse.rbxm`: que apoyen en el piso, miren hacia la puerta/plaza (-Z), escalen bien y colisionen como se espera (casa sólida, árbol solo el tronco).
- Fuente y casa pierden el chorro y el humo con modelo. El globo tiene que seguir flotando; los faroles con luz.
- Output: buscar `[ModelSlots]` por scripts borrados o modelos que pasan el tope de partes.

## Ronda 4: UI arreglada con la vista previa

Re-renderizado todo (new+mid pc/phone, cada ventana pc/phone, laptop y tablet): 0 errores de runtime y 0 hallazgos en HUD, laptop y tablet.

**Arreglado**
- `src/client/UI/Tiles.luau` (`makeBillboard`, `updateMarkers`): saqué `BillboardGui.DistanceLowerLimit` (deprecada; se asignaba en Components.luau:21 via `C.new`). No tiene reemplazo directo, así que el "no crecer cuando estás encima" lo hace el código: los carteles de tile ya se achicaban con la cercanía para "READY!"; ahora también los de "buy" y las barras de crecimiento (`k = clamp(dist/26, 0.35, 1)`). Antes: propiedad deprecada x13; ahora: nada.
- `src/client/UI/DailyPanel.luau:96-106, ~147`: el tilde de "reclamado" ya no se dibuja encima del premio (dejaba asomar "Pumpkin"). Ahora ocupa el lugar del nombre del premio, que se oculta al reclamar. Se fueron los `text-overlap`.
- Clima en celular: ya no se sale de la píldora (el texto entra en 2 renglones); el "confirmar" era falso.

**Lo que queda**
- Tienda de Robux "coming soon": esperado, ids en 0 hasta que el dueño cree los productos. No inventé ids.
- `core-overlap` (low/med) en celular dentro de paneles con scroll (Gifts Claim del primer regalo, Language coreano, filas de Shop/Upgrades/Index/Daily): es contenido que puede quedar bajo el joystick según el scroll; se puede scrollear, y el panel no se puede achicar sin perder legibilidad. Lo dejé.
- Barra del SELL "cortada" junto a la mochila: la marqué como artefacto probable, no la toqué.

**Confirmar en Studio**
- Que los carteles de tile se vean bien de cerca y de lejos sin `DistanceLowerLimit` (tamaño mínimo 0.35 del base).
- Tilde de Daily: que el emoji ✅ se vea centrado en la tarjeta en Fredoka real.

## Ronda 5: ritmo de progresión

**Sim** (`huerta-tycoon/sim/pacing_core.luau` motor + `sim/pacing_sim.luau` tabla; `luau sim/pacing_sim.luau`, ~10 s). Usa los módulos reales: `Config`, `Formulas`, `Gifts`, `AutoFarm`, `Odds`, `Trophies`. Jugador gratis y activo: cada ronda cosecha todo, vende, compra la mejor mejora/tile por (ingreso ganado / costo) con repago máx. 25 min, llena tiles con la mejor semilla del stock (reemplaza árboles mucho peores), compra Farmhand, reclama daily, regalo del tutorial y regalos de tiempo (5..60 min) al instante, y rebirth apenas alcanza el costo. Stock de la tienda con restock cada 5 min y fase aleatoria (101 corridas con semilla fija, p10/mediana/p90). Mutaciones y tamaños van como valor esperado.

Para que el sim corra con Luau puro toqué `src/shared/Formulas.luau`: `require(script.Parent.Config)` pasó a `if script then ... else require("./Config")` (en Roblox no cambia nada).

**Test de deriva**: `tests/pacing_test.luau` (34 checks, ~5 s) falla si se salen de ventana: primera cosecha/venta/compra, 3 compras en 3 min, mediana de cada tier hasta el mango, hueco entre tiers, hueco sin novedades, rebirth 1 (30-60 min) y 2, y cola larga (moonmelon, loto, rebirth 3 y 5 en horas).

**Hitos (mediana, p10-p90 entre paréntesis), antes -> después**

| Hito | Antes | Después |
|---|---|---|
| Primer premio visible (daily, +$100) | 6 s | 6 s |
| Primera cosecha / venta | 24 s | 15 s |
| 3 compras (tile/mejora) | 3.1 min | 2.2 min (p90 2.8) |
| Maíz | 104 s | 53 s |
| Arándano | 5.2 min | 4.3 min |
| Calabaza | 10.0 min | 8.6 min |
| Sandía | 15.9 min | 14.9 min |
| Manzano | 22.2 min (p90 39) | 18.5 min (p90 25) |
| Dragonfruit | 32.1 min | 23.0 min |
| Mango | 52.5 min (p90 117) | 31.8 min (p90 65) |
| Starfruit | 106 min | 40.8 min |
| Farmhand Lv1 / Lv2 / Lv3 | 14.5 / 27.6 / 91.8 min | 14.3 / 25.3 / 67.5 min |
| Rebirth 1 | 61.3 min (p90 77) | 45.5 min (36-56) |
| Rebirth 2 / 3 | 2.2 h / 3.8 h | 88 min / 2.4 h |
| Mayor hueco sin nada nuevo (1ra hora) | 10.4 min | 6.1 min (p90 9.8) |
| Moonmelon / Cosmic Lotus (48 h de juego) | 4.3 h / 10.6 h | 3.8 h / 7.8 h |
| Rebirth 6 | 14.8 h | 9.8 h |

**Qué cambié en `Config.luau` y por qué** (precios Robux intactos)
- Hallazgo principal: el cuello era el stock, no la plata. Con 15 tiles, 5 min de stock de maíz/calabaza no alcanzan, y el mango (12% por restock) tardaba ~40 min en aparecer; había pozos de 20+ min.
- Zanahoria: `growTime` 20 -> 10, stock 12-25 -> 20-40 (primera cosecha 15 s, y no se queda sin semillas). Tomate: `growTime` 40 -> 30, stock 6-15 -> 10-20.
- `stockChance`: calabaza 0.55 -> 0.7, sandía 0.45 -> 0.6, manzano 0.3 -> 0.55, dragonfruit 0.22 -> 0.42, mango 0.12 -> 0.36, starfruit 0.08 -> 0.3. Moonmelon y Loto no se tocaron: son la cola larga.
- `TileBaseCost` 100 -> 80: la 3ra compra entra antes del minuto 3.
- `Farmhand` `costGrowth` 12 -> 9 ($5K / $45K / $405K en vez de $5K / $60K / $720K): llena el pozo de min 30-50 con el auto-farm y mejora la calidad de vida antes.
- `RebirthBaseCost` 1M -> 750K (el rebirth 1 caía a ~61 min, fuera de ventana; ahora ~45). Crecimiento x4 igual.
- Comentario de Farmhand en Config actualizado. Ningún test existente dependía de estos valores.

**Verificación**: todos los `tests/*_test.luau` pasan (incluido el nuevo); `rojo build` de default y test OK; `luau-lsp analyze src` sin salida.

**Límites del sim**
- Sin clima, eventos en vivo, Index, trofeos, amigos/premium/grupo ni pases (jugador gratis puro); ignora anuncios recompensados (id 0). El clima daría ~9% más de crecimiento promedio, o sea el juego real es un poco más rápido.
- Jugador activo de corrido: no modela AFK ni offline (el auto-farm casi no pesa acá; en AFK pesa mucho más) ni sesiones cortas con el daily de racha (solo día 1).
- Modelo de ronda: 7 s con viaje a vender, 3 s solo plantar; 4 s de arranque antes de la primera acción. Un jugador real es más lento o más torpe.
- "Primer premio < 10 s" se cumple con el daily (6 s), pero ese botón está en el menú con badge, no se abre solo; la primera cosecha real cae a los ~15 s. Bajar más la zanahoria la rompe por el stock; si se quiere, abrir el Daily solo en la sesión 1 (cambio de UI, no hecho).
- Quedan tails de suerte de stock (p90 del mango ~65 min). Faltan números medidos en Studio: la política de compra es una aproximación.
