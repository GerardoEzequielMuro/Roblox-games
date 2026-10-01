# Planet Crackers (anime-planet-clicker): handoff

Aviso: nada de esto se vio corriendo. Trabajé en un contenedor Linux sin Roblox Studio. Todo se verificó con build, type checker y tests puros. Lo visual (luces, materiales, íconos) hay que mirarlo en Studio sí o sí.

## Qué cambié

**Revisión de runtime (el juego nunca corrió)**
- Revisé el boot del server (`src/server/Main.server.luau`, el orden de init de los Services), los remotes (`Services/Remotes.luau`) contra cada `WaitForChild`/`Net.event`/`Net.request`/`Kit.request` del cliente, los atributos que se leen contra los que se setean, las claves del snapshot contra lo que lee el cliente, DataStore load/save/lock, entrada y salida de jugadores, spawn, WorldBuilder y el boot del cliente. **No encontré ningún nombre roto**: todos los eventos, requests y atributos coinciden. El único handler sin uso era `CanBuy`, y ahora se usa (ver más abajo).
- `src/server/Services/Data.luau`: si el DataStore responde "sin acceso" (Studio sin *Enable Studio Access to API Services*, o un place sin publicar), deja de reintentar enseguida. Antes el jugador quedaba unos 12 s en "loading" en cada playtest. En ese caso la sesión igual sigue sin guardar, como antes.
- `src/server/Services/Pvp.luau` y `src/server/World/WorldBuilder.luau`: los drones de la arena y las máquinas de cápsulas son `ModelStreamingMode = Atomic`, así que con StreamingEnabled no aparecen a medias.
- Mientras trabajaba, el analyzer detectó un bug mío (un helper que quedaba tapado por una variable local `glow` en la refinería). Lo renombré a `addLight` antes de terminar.

**Retención (planet-wall, sistema por galaxia, zona rara horaria)**: ya estaba todo implementado, no hizo falta código nuevo.
- Gate Planet con HP guardado entre sesiones que bloquea la galaxia siguiente: `Services/Mining.luau` (`syncSpecial`, `unlockNextZone`) y `Config.Zones[n].gateHp`.
- Un sistema multiplicador distinto por galaxia (Relics, Temper, Traits, Overcharge, Constellation): `Config.Systems`.
- Anomaly cada hora UTC (15 min, un break por jugador por ventana) en todas las galaxias: `Formulas.anomaly`, más el reloj en el HUD.
- Sumé 19 tests puros en `tests/unit.luau`: ventana de la anomalía estable y nueva cada hora, la anomalía como jefe, cada gate existe y es más duro que el anterior, los nodos especiales no chocan, y hay un sistema en cada galaxia de la 2 a la 6.

**Íconos**
- `src/client/UI/Theme.luau`: `Theme.ICON_BY_EMOJI` (emoji → nombre en `Shared/Icons`), `Theme.iconImage` y `Theme.glyph`. `glyph` usa `ImageLabel` (ScaleType Fit) cuando `Icons.get` devuelve un id; si no, dibuja el mismo emoji de siempre. Hoy todos los ids están vacíos, así que se ve igual que antes.
- Dónde se usa: los pills de moneda del HUD, el grid del menú, el botón Shop (`UI/Hud.luau`), el medallón de cada ventana (`UI/Windows.luau`) y todos los `Theme.icon` (tiles de Store, Upgrades, Teleport, Quests).

**Look 2026 (sin assets nuevos)**
- `default.project.json`: Lighting `Technology = Future`, más difuso y especular de entorno.
- `src/client/WorldFx.luau`: bloom más fuerte (glow del neon), SunRays suave y color grade con más saturación y contraste. Todo esto se apaga en lite.
- `src/shared/PlanetModel.luau` y `src/client/PlanetField.luau`: la corteza tiene material por galaxia (Sandstone, Slate, Glacier, Basalt, Rock) y por tipo (Aurum Foil, Fury Basalt, Titan Slate, Gate DiamondPlate). El manto de Ember es CrackedLava. Además cada planeta tiene una variación de color (hue, saturación y brillo), así un campo de rocas ya no son todos clones.
- `src/server/World/WorldBuilder.luau`: la estación tiene rim DiamondPlate, casco y postes Metal, y PointLights (sin sombras) en las cápsulas, la refinería, el warp, las estaciones de sistema y los pilones del gate.
- `UI/Hud.luau`: los contadores ahora son pills oscuros con borde del color de la moneda y el ícono sobre un disco con gradiente.

**Cápsulas pagas (policy)**
- Las odds ya se mostraban con `Formulas.odds`, la misma función con la que tira el server (siempre suma 100%), y el server ya leía `PolicyService.ArePaidRandomItemsRestricted` (si falla, se asume restringido).
- `src/client/Purchase.luau`: antes de abrir el prompt de un ítem `random = true`, el cliente ahora pregunta al server (`CanBuy`).
- `UI/CapsulePanel.luau`: si el jugador está restringido, la Quantum Capsule (Robux) no muestra ningún botón de compra. Antes quedaba visible "Open 1".

## Cómo lo verifiqué

- `rojo build default.project.json`: OK (`test.project.json` también buildea).
- `luau-lsp analyze ... src`: 0 errores (igual que el baseline).
- `luau sim/check_config.luau`: `CONFIG OK`.
- `luau sim/economy_sim.luau`: corre, los tiempos no cambiaron (galaxia 6 en unas 5 h, rebirth6 en 6h30).
- `luau tests/locale_check.luau`: `LOCALE CHECKS PASSED` (504/504 claves, 12 idiomas).
- `luau tests/unit.luau`: `UNIT: 156 checks, 0 failures` (antes eran 137).

## Qué hay que mirar en Studio

1. **Performance con Future** en un celular o con Graphics bajo: son unas 36 PointLights en total, y las luces se streamean por zona. Si pesa, volver a `ShadowMap` en `default.project.json` (una línea).
2. **Materiales de los planetas**: fijarse que no queden muy oscuros o ruidosos (sobre todo Glacier en Frost y Foil en Aurum). La tabla está en `PlanetModel.ROCK_MATERIAL` y `KIND_MATERIAL`.
3. **Bloom**: que el neon no queme la imagen (threshold 1.35, intensidad 0.55 en `WorldFx.applyLighting`).
4. **Playtest sin API access**: el jugador tiene que entrar al toque, con el aviso de "no se guarda".
5. **Sonidos**: usan rutas `rbxasset://sounds/...`. Si alguna no existe, en Output aparece un warning, no un error.
6. **HUD**: los pills nuevos en PC y en touch (`ForceTouchLayout`).
7. Correr el playtest automático que ya existe (`test.project.json`, `tests/AutoTest*.luau`). Yo no lo pude correr.

## Pendiente

- Subir los íconos (`tools/icons/upload_assets.py` en la raíz). Cuando `Shared/Icons.luau` tenga ids, el HUD los usa solo. Los chips de auto, los toasts y los botones con texto+emoji siguen con emoji: son strings armados, y pasarlos a imagen es otro laburo.
- Los ids de game passes y productos siguen en 0 ("coming soon").
- Chequear que el nombre "Planet Crackers" esté libre en Roblox.

## Ronda 2

Aviso: igual que en la ronda 1, nada se vio corriendo. Todo verificado con build, type checker y tests puros. Los ids de pases y productos siguen en 0 (los crea el dueño).

### Precios

Todo en `src/shared/Config.luau` (`Config.Passes`, `Config.Products`). Referencia: sección 4.4 y 2.3 de `docs/research/top-juegos-y-precios.md`.

| Ítem | Antes | Ahora | Por qué |
|---|---|---|---|
| Auto Miner | 149 | 175 | PS99 Auto Farm 175 |
| x2 Damage | 199 | 349 | 2x clicks 499-549 |
| x2 Stardust | 249 | 349 | 2x moneda 300-450 |
| VIP | 249 | 299 | mediana del género |
| Lucky (random) | 99 | 249 | PS99 275 |
| Super Lucky (random) | 299 | 699 | PS99 800 |
| Golden Capsules (random) | 349 | 599 | ref. Magic Eggs |
| Pet Slots (+2) | 249 | 249 | ya estaba bien |
| **Pet Slots II (+4, pase nuevo)** | - | 649 | tier 2 recomendado; se suma al +2 |
| **x8 Open (pase nuevo)** | - | 699 | hatch múltiple x8 699-849 |
| Triple Open / Fast Open / Sprint / Instant Sell | 199 / 99 / 49 / 199 | igual | ya estaban bien |
| Crystals 100 / 600 | 49 / 249 | igual | |
| **Crystals 1.400 / 3.200 (nuevos)** | - | 499 / 999 | escalera; el pack grande rinde más por R$ (test lo chequea) |
| Quantum x1 / x3, Luck Boost, Stardust packs | igual | igual | ya tenían odds y PolicyService |
| Starter Pack | 99 (tachado 399 fijo) | 99 (tachado calculado: 223) | el 399 no era un precio real. Ahora `Config.StarterPack.fullPrice` = 150 cristales al precio del pack chico (74) + 1 Quantum Capsule (149), o sea lo que cuesta el mismo contenido en esta tienda. El "-75%" del Store ahora se calcula (-56%) |

Pases nuevos, implementación completa:
- **Pet Slots II** (`PetSlots2`): `Formulas.maxEquip` suma `Config.PetSlots2Pass` (4). Lo otorga el mismo flujo de pases (`Monetization.loadPasses` / `PromptGamePassPurchaseFinished`), no necesita receipt.
- **x8 Open** (`OpenEight`): `Capsules.open` acepta 1/3/8 (`Config.OpenCounts`, `Config.OpenPassByCount`), valida el pase en el server, el Auto Open usa el mayor lote posible (`Formulas.bestOpenCount`). UI: botón Open x8 en `UI/CapsulePanel.luau` (con candado si no lo tenés, abre la compra), y la cinemática achica las cartas para 8 (`UI/CapsuleCinematic.luau`).
- **Crystals Large/Huge**: developer products normales; el `ProcessReceipt` ya era idempotente por PurchaseId y guarda antes de confirmar.
- Locale de todo (12 idiomas, 517/517 claves).

**PvP sin ventajas pagas** (`State.pvpPower`, `Formulas.pvpStats`, `Formulas.topPower`, `Formulas.walkSpeed(s, arena)`):
- Antes el daño en la arena usaba `basePower`, que incluía x2 Damage y VIP (x1.5). Ahora la arena usa `pvpPower`: ignora todos los pases, cuenta solo los mejores N pets de los slots gratis (sin los del pase) y excluye las mascotas exclusivas (las de Quantum Capsule).
- Sprint no cuenta dentro de la arena: `State.inArena` lo setea `Services/Pvp.luau` al entrar/salir/KO y `Progression.applyWalkSpeed` saca el bonus.
- El Store muestra una nota fija (`store.pvp_note`) que lo dice.
- Lo que NO se neutraliza: los pases de suerte y de golden aceleran cómo conseguís mascotas (progresión, no daño directo), y el daño de PvP ya está clampeado a x0.6 a x1.7 (`Config.Pvp`).

### Retención

Casi todo ya estaba (verificado leyendo el código). Checklist:

| # | Punto | Estado |
|---|---|---|
| 1 | Loop de segundos con feedback | Ya estaba (números flotantes, tween, FX en `WorldFx`/`ToolFx`, sonidos) |
| 2 | Próxima meta visible y cercana | Ya estaba (barra gate / rebirth en `UI/Hud.luau`). **Agregado**: si estás entre 25% y 99% de la próxima herramienta, la barra muestra "Next tool: X %" (`hud.goal_tool`), así la meta es siempre algo cercano |
| 3 | Metas de sesión y largas | Ya estaba (gate por galaxia, rebirth, índice de mascotas con %, mastery, Secret 0.001%, leaderboards) |
| 4 | Razones para volver | Ya estaba: racha diaria con display (`Services/Rewards.luau`, `UI/RewardsWindow.luau`), regalos por minutos de sesión, offline (`Services/Offline.luau`), códigos, regalo de grupo (`Config.GroupId`, sigue en 0), Anomaly cada hora con reloj, Meteor Shower / Lucky Nebula cada 3 h, Crystal Weekend. **Agregado**: evento **Star Surge** (x2 Stardust, x1.5 Crystals, 45 min) fijo martes y sábado 18:00 UTC (15:00 Argentina), en todos los servers, con banner y reloj del HUD (`Config.LiveEvents`, `Config.LiveEventDefs`, `UI/Hud.luau`, 12 idiomas). Tests de horario en `tests/unit.luau`. No hay stock rotativo horario: no aplica, acá no hay tienda de semillas (el equivalente es la Anomaly) |
| 5 | Social | Ya estaba: anuncios cross-server de hallazgos raros (`Services/Social.luau`), referidos con premio (`shared/Referral.luau`), leaderboards en el mundo (`Services/Leaderboard.luau`). Regalos entre jugadores: **no agregado** (ver Pendiente) |
| 6 | Primer minuto | Ya estaba (tutorial guiado en `Guide.luau`, primer regalo a los 3 min, HUD mínimo hasta `tutorial >= 6`) |

### Otros cambios

- Política: nada de urgencia falsa. El Starter Pack tiene un reloj real (24 h desde el primer ingreso de cada jugador) y su precio tachado es real. Star Surge es un evento gratis, no una oferta de Robux.
- Odds: la Lucky / Super Lucky siguen mostrando su efecto numérico en la descripción, y las odds del panel de cápsulas ya usaban `s.luck` en vivo. Los ítems `random` siguen pasando por `CanBuy` (PolicyService).
- En los paneles de cápsulas de galaxia saqué el hint de teclado "[E]/[R]" de los botones (no entraban con 4 botones). Los atajos E / R / T siguen andando; no hay atajo para x8.
- `Config.StarterPack.fullPrice` se calcula, así no se desfasa si cambian los precios.

### Cómo lo verifiqué

- `rojo build default.project.json -o /tmp/tools/anime-planet-clicker.rbxlx`: OK.
- `luau-lsp analyze ... src`: sin salida (0 errores).
- `luau tests/unit.luau`: `UNIT: 175 checks, 0 failures` (antes 156; +19 nuevos: precios, escalera de cristales, precio de lista del starter, slots, PvP sin pases, Sprint en arena, top de pets, lotes x1/x3/x8, horario de Star Surge).
- `luau tests/locale_check.luau`: `LOCALE CHECKS PASSED` (517/517 claves, 12 idiomas).
- `luau sim/check_config.luau`: `CONFIG OK`.
- `luau sim/economy_sim.luau`: corre; los tiempos no cambian (zone6 ~5h48, rebirth6 6h30). La sim no usa Robux ni pases, así que no hizo falta tocarla.
- No corrí `tests/AutoTest*.luau` (necesitan Studio).

### Qué mirar en Studio

1. Panel de cápsulas de galaxia: los 4 botones (x1, x3, x8, Auto) entran bien en PC y touch; el x8 con candado abre "coming soon" mientras el id sea 0.
2. Cinemática con x8: 8 cartas en una fila, que no se salgan de la pantalla en celular.
3. Store: ahora hay 14 pases y 10 productos de Robux (más el Starter Pack arriba), más la nota de PvP; que el scroll ande y no se corte.
4. Arena: entrar con Sprint y confirmar que la velocidad baja al cruzar el borde y vuelve al salir; que el daño entre un jugador con x2 Damage y otro sin sea igual.
5. Barra de meta: que el cambio entre "Next tool" y "Break the Gate" no parpadee.
6. Star Surge: probar con `/event StarSurge 5` (admin) para ver banner, reloj y el x2.

### Pendiente

- Crear en Roblox los pases/productos nuevos (PetSlots2, OpenEight, CrystalsLarge, CrystalsHuge) y pegar los ids en `Config` (siguen todos en 0).
- Verificar los precios con la API real antes de lanzar (la research los saca de fuentes secundarias).
- Regalos entre jugadores y trading: no se hicieron (implican riesgo de estafas y de valor real entre cuentas; pensar con calma).
- Leaderboard de poder con nametag de ranking y "robar/atacar base ajena" de la research: no se hicieron, son sistemas nuevos grandes.
- `Config.GroupId` sigue en 0 (el regalo de grupo no se activa hasta cargarlo).

## Ronda 3: ranuras de modelos

### Qué cambié
- Carpeta `assets/models/` (solo README) mapeada como `ServerStorage.ModelLibrary` en los 7 `*.project.json`.
- `src/server/World/ModelSlots.luau`: `spawn(slotName, cf, targetSize, parent, fallback, opts)`. Si hay modelo con ese nombre (o `nombre_1`, `nombre_2`... elegido por posición) lo clona, lo escala para entrar en el tamaño objetivo, lo apoya en el piso, ancla todo, pone colisión según el primitivo, borra todo script (con warn) y respeta tope de 300 partes por modelo y 1200 en total; si no, corre el `fallback()` original.
- `src/shared/ModelFit.luau`: matemática pura (escala, variante, presupuesto).
- `WorldBuilder.luau`: 14 ranuras (`capsule_machine`, `refinery_building`, `workshop_stall`, `warp_gate`, `system_monument`, `gate_pylon`, `arena_pylon`, `arena_cover`, `rock_spire`, `mushroom`, `ice_crystal`, `lava_vent`, `tesla_coil`, `obelisk`). Con la biblioteca vacía el código primitivo corre igual que antes. Cuando un modelo reemplaza una estación, prompts/carteles/luces quedan en partes invisibles (`proxy`). Disco de warp, pads, deck y nodos no se tocaron.
- Doc: `docs/modelos/anime-planet-clicker.md`.

### Cómo lo verifiqué
- `rojo build` de los 7 project files OK con solo el README; con un `.rbxmx` temporal (Model + Script) el build incluye `ServerStorage.ModelLibrary.<slot>` (borrado después).
- `luau-lsp analyze` sin salida; `tests/unit.luau` (186 checks, con los nuevos de `ModelFit`), `locale_check`, `sim/*` pasan.
- No corrí Studio: el camino de clonado/escala (`ScaleTo`, `GetBoundingBox`) no está probado en vivo.

### Qué mirar en Studio
- Soltar un `.rbxm` de prueba (ej. `obelisk.rbxm`) y ver que se apoya en el piso, tamaño y colisión correctos, sin scripts.
- Capsule machine: que el prompt y el cartel sigan funcionando con un modelo (quedan en `Base`/`Dome` invisibles).
- Gate pylon / cover: orientación y que no bloquee el paso de más (colisiona por caja de cada parte).
- Con modelos, las props pierden la animación (flotar/girar); si molesta, agregar un ancla animada.
- Budget de AutoTest (<= 3600 partes del mundo) con varios modelos puestos.

## Ronda 4: UI arreglada con la vista previa

Usé `tools/uipreview` (phone 844x390, pc, laptop, tablet). Antes: 10-15 hallazgos por captura en celular (casi todos `small-touch` y `tiny-text` por la escala 0.55). Ahora: HUD y ventanas en PC, laptop y tablet sin hallazgos; en celular solo quedan `core-overlap` de ventanas modales sobre el joystick (ver "Lo que queda").

**Qué arreglé**
- **Escala táctil** (`src/client/UI/Root.luau:64` `compute`, `:75` `computeFit`, `:105` `Root.mount`): en táctil el HUD se arma para ~940x390 unidades y escala `clamp(min(X/940, Y/390), 0.6, 1.1)` (da ~0.8 en un iPhone apaisado, antes 0.55). Las ventanas y popups (`mount(obj, parent, true)`) calculan su propia escala para entrar enteras en pantalla. PC no cambia (misma fórmula de antes).
- **HUD táctil rearmado** (`Hud.luau`, rama `touch`, desde `:102`): contadores + Shop arriba a la izquierda (terminan arriba del joystick); el menú pasa a una tira horizontal de 10 botones de 64x60 arriba; debajo, nombre de galaxia y objetivo; columna derecha (regalo, ofertas, relojes) arranca bajo la tira y termina arriba del botón de salto; chips de auto de 94x56 y SELL de 56 de alto abajo al centro; los buffs activos pasan a una fila sobre los chips (`Buffs`). Todos los botones quedan >= 44 px reales y los textos >= 11 px. `PvpClient.luau:134` baja el HUD de arena en táctil para no pisar el objetivo.
- **Ventanas táctiles** (`Windows.luau:62-`): alto máximo 372 (header 50, cuerpo 304), escala ~0.8, y `window.bodyW/bodyH` para acomodar el contenido. Todos los botones de ventana miden >= 56 unidades: Pets (barra superior, panel de detalle con scroll), Workshop (pestañas 56, Relics con scroll), Store (tarjetas de 140), Rewards (página con scroll), Quests, Index (pestañas y Claim), Rebirth, Warp, Auto, Settings (3 columnas en ventana de 780), Invite, Capsule (`Kit.luau` `TOUCH_BTN`, `Kit.toggle` de 64), cerrar de popups 56.
- **Badges "!" tapados** (`Hud.luau:187`): los botones del menú tienen ZIndex decreciente (`2 + #MENU - i`), así el badge no queda bajo el vecino (PC y celular).
- **DisplayOrder = 1** en `PlanetUI` (`Root.luau:27`) para que una ventana tape al joystick de Roblox y no al revés (confirmar en Studio).
- **Plurales** (`Locale.luau:70`): si `args.n == 1` y el idioma tiene la clave `<clave>.one`, se usa esa. Agregué `.one` en los 12 idiomas para `upgrade.HitSpeed.desc`, `upgrade.AutoRate.desc`, `upgrade.PetSlots.desc`, `pets.fused_n`, `toast.deleted` (antes "+1 equipped pets", "Deleted 1 pets", "+1 hits per second"). En ru cambié `upgrade.PetSlots.desc` a "Слотов питомцев: +{n}" (sin declinar). `tests/unit.luau` tiene 6 checks nuevos.
- **Etiquetas largas del menú** (se veían a 7 px en celular): de "Wiedergeburt"/"WIEDERGEBURT" a "Rebirth"; tr "Doğuş"; ru "Реборн", "Альбом", "Апгрейд"; vi Teleport "Warp"; th Pets "เพ็ท". Con esto las 12 lenguas dan 0 hallazgos en `mid-phone`.

**Antes / después (celular, mid)**: botones del menú de 31x31 a ~51x48 px; Shop 169x24 a ~157x45; SELL 53x31 a ~75x45; chips 48x19 a ~75x45; etiquetas de 6-8 px a 11-14 px; en ventanas (Pets) botones de 19 px a 45 px y el X de 31 a 45.

**Lo que queda**
- `core-overlap` (med/low) en `mid-phone-{pets,store,rewards,quests,index,settings}`: la parte de abajo a la izquierda de la ventana modal queda sobre el círculo del joystick que dibuja la herramienta. Es modal y el jugador no camina con una ventana abierta; no lo moví más porque la ventana no entra en el área libre.
- `mid-*-capsule.png`: la herramienta cierra el panel enseguida (el auto-cierre por distancia del Capsule Machine, el personaje simulado está lejos). Las PNG de capsule las saqué anulando temporalmente ese chequeo (ya revertido) para ver la ventana. Es un artefacto de la herramienta.
- Los recuadros "3D" de las mascotas son `ViewportFrame` (la herramienta no dibuja 3D).
- En celulares muy chicos (usable < ~650x290) la escala cae a 0.6 y los botones bajan de 44 px.

**Para confirmar en Studio**
- Emulador de celular apaisado: el HUD no pisa el joystick ni el salto; tocar la tira del menú, chips y SELL con el pulgar.
- Que con `DisplayOrder = 1` la ventana quede sobre el joystick y los toques en la ventana no muevan al personaje.
- Buffs activos (fila sobre los chips) y ofertas (Starter Pack + Ad boost + regalo juntos) sin tapar la columna derecha; Rewards/Pets con scroll al dedo.
- Idiomas largos (de, ru, th) en el menú y los chips.

## Ronda 5: ritmo de progresión

Armé `sim/pacing_sim.luau` (modelo en `sim/pacing_model.luau`, reusa el `Config` y `Formulas` reales). Juega un jugador gratis: tutorial con sus premios, daily a los 20 s, regalos de sesión 10 s después de que estén listos, 5 hits/s a mano + Auto Mine gratis desde el segundo 45, dron que vende, compra lo que más rápido se repaga (más Power si acorta el gate), ahorra cristales para el primer slot de pet, rompe el gate cuando le falta menos de 4 min y rebirthea apenas puede. Corre con `luau sim/pacing_sim.luau -a 6 3` (horas, seeds; agregar `tiers`, `events` o `trace` para ver la corrida 1, `nodaily` para la variante sin daily). Test: `luau tests/pacing_test.luau` (21 checks, ~10 s, seeds fijas) falla si un hito se sale de su ventana.

**Hitos (mediana de 3 seeds, con daily, 6 h de sim)**

| Hito | Objetivo | Antes | Después |
|---|---|---|---|
| Primer premio (tutorial) | < 10 s | 2 s | 2 s |
| Primer Stardust vendido | - | 12 s | 12 s |
| Primera compra | < 60 s | 9 s | 9 s |
| Upgrades a los 3 min | >= 3 | 28 | 28 |
| Tiers nuevos en la 1ª hora | 1 cada 5-15 min | 15 | 21 |
| Espera más larga sin tier nuevo (1ª hora) | < 10 min | 31 min (peor seed 34) | ~9 min (peor seed 13) |
| Galaxia 2 | 5-15 min | 4 min 18 | 4 min 18 |
| Galaxia 3 | - | 18 min 32 | 18 min 53 |
| Galaxia 4 | - | 1 h 49 | 36 min |
| Primer rebirth | 30-60 min | 51 min | 39 min |
| Rebirth 2 | - | 1 h 54 | 51 min |
| Galaxia 5 | horas | 2 h 16 | 1 h 46 |
| Galaxia 6 | horas | 2 h 57 | 3 h 21 |
| Rebirth 6 | horas | 3 h 42 | 4 h 58 |

"Antes" es la config vieja corrida en el mismo sim nuevo. El problema de fondo no era el primer minuto (ya cumplía: premio a los 2 s, compra a los 9 s, 28 upgrades a los 3 min por el daily + tutorial) sino los huecos: tras comprar las herramientas de cada galaxia pasaban 25-30 min sin nada nuevo hasta el rebirth/la galaxia siguiente, y todo el tramo galaxias 4-6 quedaba comprimido en ~1 h. El `economy_sim` viejo es más estricto (no modela tutorial, daily ni regalos: galaxia 3 a la 1 h, rebirth 1 a 1 h 52); lo dejé con una nota en el encabezado. Sin daily (caso pesimista): primera compra 9 s, galaxia 3 ~20 min, rebirth 1 ~46 min, espera máxima ~16 min.

**Qué números cambié en `Config.luau` y por qué**
- `Zones[3].gateHp` 4.1e8 -> 2.6e8: ajuste fino (Frost sigue a ~19 min, pero baja la espera de la 1ª hora de ~11 a ~9 min con las otras piezas).
- `Zones[4].gateHp` 5.5e12 -> 1e12: Ember pasa de ~1 h 49 a ~36 min y llena el hueco entre Quake y el primer rebirth (antes: 25-30 min sin nada nuevo).
- `Zones[5].gateHp` 3e16 -> 2.5e16 y `Zones[6].gateHp` 1.5e20 -> 2.5e20: con Ember antes, Storm queda a ~1 h 45 y Void a ~3 h 20 en lugar de amontonarse (antes Storm-Void-rebirth 3 a 5 caían en 40 min); la cola larga queda en horas.
- `RebirthBaseCost` 4e11 -> 1e12 (x400 por rebirth igual que antes): primer rebirth a ~39 min, después de Ember, y el segundo a ~51 min.
- `drill_twin.cost` 1.8e6 -> 1.8e7 y `drill_quake.cost` 3.5e9 -> 5e10: antes se compraban un minuto después de llegar a cada galaxia y dejaban la espera vacía; ahora caen a ~15 y ~26 min y reparten los hitos.
- No toqué precios en Robux, pets, Formulas ni nada de locale.

**Límites del sim**
- Un solo arquetipo de jugador; una partida real varía mucho con la suerte de las cápsulas (el peor seed de 8 tiene huecos de ~25 min; con 5 seeds, 13 min). Los tests usan seeds fijas, así que son deterministas pero no prueban "todas las suertes".
- "Tier nuevo" = primera vez que tiene una herramienta, galaxia, primera cápsula de la galaxia, sistema de galaxia (Relics, Temper, Traits...), slot de pet o rebirth. Comprar Power y abrir cápsulas pasa todo el tiempo y no cuenta.
- El ingreso es un promedio continuo (caminar al refinery, dron, buffs ~+10%); no modela PvP, quests, Index, Anomaly, eventos en vivo, offline, amigos ni fusiones. Esos son extras a favor del jugador real. El daily rinde mucho al principio (5 min de ingreso, ~14k Stardust a los 20 s) y por eso comparé también sin daily.
- Después de ~50 min sólo hay rebirths y pet slots hasta Storm; es la cola larga buscada, pero es lo más flojo de la sesión 1 si alguien juega más de una hora. Rebirth 7 no se alcanza en 24 h de sim.
- No corrí Studio: la sensación real (caminata entre planetas, tiempo de gates) está estimada.

## Ronda 6: contenido para el hueco

Hueco: después de ~50 min sólo había rebirths y pet slots hasta Storm (1 h 46), o sea 25-50 min sin nada nuevo.

### Qué agregué: "Asteroid Fields" (herramientas de campo)
- 11 herramientas nuevas con `field = true` en `Config.Tools`, todas lasers: 5 en Ember Forge (`laser_slag`, `cinder`, `magma`, `ashfall`, `pyre`, entre Ion y Nova) y 6 en Storm Reach (`laser_arc`, `static`, `thunder`, `tempest`, `squall`, `zenith`, entre Quasar y Singularity). Los costos están pensados como sumidero de Stardust durante la espera del gate: cada una cae unos 8-9 min después de la anterior. No hay nada con Robux.
- Primera vez que llegás a cada una: `Config.FieldCrystals` (25) Crystals + toast "Asteroid Field found! +N Crystals" (`toast.field_found`). Si comprás una herramienta posterior (Auto Upgrade, por ejemplo), se acreditan también los campos salteados (`Progression.buyTool`).
- Perfil: `fieldsFound: { [toolId]: true }` (`Data.luau`, default `{}`, `reconcile` lo crea en saves viejos y marca como ya encontrados los campos que el jugador ya pasó, así no hay pago retroactivo; `State.snapshot` lo manda al cliente). Las herramientas se guardan por id, así que los saves viejos siguen bien (quien ya tenía Nova ve los campos de Ember como "ya tenidos").
- UI: en Workshop > Tools las filas de campo llevan un cometa antes del nombre y "💎 +25" mientras no los encontraste (`UpgradesWindow.luau`). Sin ventanas nuevas.
- Locale: 11 nombres + `toast.field_found` en los 12 idiomas (534/534 claves).
- Ajustes de números por el cambio de potencia: `hardness` de Storm 10 -> 15 y Void 12 -> 23 (son índices en `Config.Tools`, `check_config` los valida); `Zones[5].gateHp` 2.5e16 -> 4.5e16; `Zones[6].gateHp` 2.5e20 -> 2e20; `PetSlots.growth` 3 -> 2.4 (slots de 60/144/346 Crystals, el slot 2 llega antes).
- No hizo falta ModelSlots: no hay props nuevos (los lasers usan `ToolModel` por color/índice).

### Hitos antes / después (mediana, con daily)
| Hito | Antes | Después |
|---|---|---|
| Espera máxima sin nada nuevo, primeras 2 h (seed mediana) | ~48 min en run 1 (rebirth 2 a 47 min -> Storm a 1 h 35), y otros 28 min después hasta el slot 2 | ~9 min (peor seed: 9-10 min en 4 de 5 seeds, 18 min en la quinta) |
| Eventos nuevos entre 47 min y 2 h (run 1) | ~8, casi todos pegados en el cluster de Storm | ~17, con un campo cada ~8 min |
| Galaxia 5 | 1 h 46 | 1 h 33 |
| Galaxia 6 | 3 h 21 | 2 h 54 |
| Rebirth 2 / 3 / 4 | 51 min / 1 h 46 / 2 h 17 | 53 min / 1 h 34 / 2 h 54 |
| Rebirth 6 | 4 h 58 | 4 h 31 |
Sin daily (caso pesimista): mediana de espera máxima en 2 h = 18-19 min (antes ~50, sin medir en el sim viejo); el tramo que queda es Quake -> Ember (pre-existente) y la espera de Storm cuando el ingreso es bajo.

### Sim y tests
- `sim/pacing_model.luau`: las herramientas `field` se compran apenas alcanza la plata (es el único sumidero mientras esperás el gate) y pagan sus Crystals; nueva métrica `maxTierGap2h` / `worstTierGap2h`; `pacing_sim.luau` la imprime.
- `tests/pacing_test.luau` (ahora 27 checks): espera máxima <= 12 min (mediana) y <= 20 min (peor seed) en las primeras 2 h, los campos de Ember antes de las 2 h, al menos 7 campos en 2 h, el primero entre rebirth 2 y 75 min; sin daily <= 20 min.
- `tests/unit.luau` (195): la herramienta de `hardness` de cada galaxia no es de campo, 8+ campos con nombre en en, `FieldCrystals` entero. Corregí el check de `incomeZone` que usaba índices fijos.
- Verificado: `rojo build` OK, `luau-lsp analyze` sin salida, `unit`, `locale_check`, `check_config`, `pacing_test` pasan. `economy_sim.luau` corre pero es el viejo y estricto: no sabe de los campos.
- Previews: `docs/previews/anime-planet-clicker/mid-{pc,phone}-upgrades-fields.png` (Workshop scrolleado a las filas de campo; 0 hallazgos). El fixture de la herramienta tiene al jugador en galaxia 3, así que ahí las filas salen con candado "Ember Forge"; para sacar esas fotos escrolleé temporalmente el `CanvasPosition` (ya revertido).

### Qué mirar en Studio
1. Workshop > Tools: 23 filas con scroll; que el cometa y "💎 +25" entren en la fila en celular y que al comprar desaparezca el +25.
2. Comprar un campo: toast de tool + toast de Crystals y que los Crystals suban una sola vez (después de un rebirth, comprarlo de nuevo no paga).
3. Modelo del laser en mano para los tintes nuevos (los índices >= 10 agregan las aletas) y `Hud` "Next tool" con los campos.
4. Sensación real: un campo cada ~8 min depende de los números del sim, que no modela PvP, quests ni offline.

### Límites
- Un campo no tiene geografía propia (no hay sub-zonas en el mapa): es una línea de herramientas dentro de la galaxia. Sub-zonas reales y cápsulas propias son sistemas grandes (modelos, pets, locale) y quedaron fuera.
- Después de ~2 h siguen los huecos de 20-40 min entre Void y el rebirth 6 (cola larga); Void, slot de pets 3 y rebirths son lo único ahí.

## Ronda 7: seguridad

Auditoría de todo lo que el cliente puede disparar (`Request`, `Hit`, `Zap`), compras, DataStore y memoria. Helper nuevo y puro: `src/shared/Security.luau` (validadores, token bucket, guard por acción, forma del payload, sanitizado de perfil, migraciones, backoff). Tests: `tests/security_test.luau` (70 checks, `luau tests/security_test.luau`).

### Vulnerabilidades
| Sev. | Archivo:línea | Cómo se explotaba / fallaba | Arreglo |
|---|---|---|---|
| Alta | `Data.luau:326` (`save`) / `:390` (`release`) | Un solo `UpdateAsync` fallido al salir o al cerrar el server perdía toda la sesión (sin reintentos). | Reintentos con backoff (4 intentos al salir, 2 en autosave), espera de budget con `GetRequestBudgetForRequestType`, un save a la vez por jugador, corte rápido en Studio sin acceso. |
| Alta | `Data.luau:415` (`BindToClose`) | Esperaba solo sus propios saves; los de `PlayerRemoving` en vuelo se cortaban al apagar el server. | Contador `inflight`; espera hasta que no quede ninguno (tope 25 s, deadline de 24 s para los reintentos). |
| Alta | `Monetization.luau:135-200` (`ProcessReceipt`) | Roblox reintenta el mismo `PurchaseId` mientras el primero todavía guarda: el segundo veía el id en memoria y devolvía `PurchaseGranted` sin que estuviera en el DataStore. Con perfil no cargado (sin save) se entregaba y se perdía al salir. | `receiptsInFlight` por PurchaseId (`NotProcessedYet`), el camino "ya otorgado" también guarda antes de confirmar, perfil no persistente => `NotProcessedYet` (salvo Studio). |
| Media | `Social.luau:204` (`ClaimGroupGift`) | `IsInGroupAsync` yieldea: dos llamadas en paralelo pasaban `groupGiftClaimed == false` y daban 2 pets. | `exclusive` en `Remotes.handle` + recheck después del yield. |
| Media | `Monetization.luau:229` (`WatchAd`) | Mismo patrón: el cap diario se chequeaba antes del yield del video y se contaba después; llamadas en paralelo lo salteaban. | `exclusive` + `interval = 2`. |
| Media | `Data.luau:350` | NaN/inf en el perfil (overflow de números enormes) hace que `UpdateAsync` tire error y el jugador nunca guarde. | `Security.sanitize` copia el perfil (NaN -> 0, inf -> 1e300, cycles/funciones fuera) en cada save y en la carga; avisa con `warn`. |
| Media | `Data.luau:276,361` | Un server viejo podía pisar un save de una versión más nueva (rollback de deploy). Sin migraciones. | `Data.VERSION` + `Data.migrations` (`Security.migrate`); un save más nuevo (o ilegible) no se carga ni se sobreescribe. |
| Media | `Mining.luau:355` (`Hit`), `Pvp.luau:369` (`Zap`) | Sin límite al ritmo del evento: un flood de eventos mínimos gasta CPU del server antes del bucket de hits. | Bucket por jugador (Hit 40/s ráfaga 80; Zap 8/s ráfaga 12). El bucket de hits sigue siendo `hitsPerSecond` + `HitBurst` y ahora sigue las mejoras/buffs. |
| Media | `Remotes.luau:91` | Payload sin forma: un `Delete` con un millón de uids, strings enormes, NaN/inf, tablas profundas o con metatable. | `Security.payloadOk` central (1000 nodos, profundidad 4, strings de 200, números finitos, sin metatables/ciclos) antes de llamar a cualquier handler; `Delete` además rechaza más de 300 uids (`Pets.luau:254`). |
| Media | `Leaderboard.luau:93` | `SetAsync` ciego: un server atrasado bajaba el puntaje; `encode` con NaN publicaba basura. | `UpdateAsync` que conserva el mejor valor, solo enteros finitos > 0, no reenvía valores sin cambios, `encode` devuelve 0 si no es finito. |
| Media | `Rewards.luau:141` (`RedeemCode`) | Fuerza bruta de códigos hasta 12/s. | `interval = 1`. |
| Baja | `Data.luau:405` | Autosave de todos los jugadores en el mismo instante. | 0,2 s entre jugadores. |
| Baja | `Progression.luau:277`, `:273`; `Mining.luau:543` | `Teleport`, `Rebirth`, `GetNodes` sin cooldown propio (solo el bucket global). | `interval` 0,5 / 0,5 / 0,2 s. |
| Baja | `Monetization.luau:258` | `PromptGamePassPurchaseFinished` sin chequeo de tipos. | Exige `purchased == true` y id numérico (el evento lo dispara el server, el cliente no lo puede falsificar). |
| Baja | `Monetization.luau:215` (`CanBuy`) | Key de largo arbitrario. | Tope de 40 chars (además del payload central). |

Total corregido: 3 altas, 8 medias, 4 bajas.

### Lo que ya estaba bien (sin cambios)
Hits: posición del personaje del server, zona desbloqueada, rango, bucket por `hitsPerSecond` (el cliente no manda daño ni plata); Auto Mine, drones, respawns y buffs corren en el server; cápsulas validan zona, distancia, cooldown, precio y espacio; todas las compras de moneda son server-side; ProcessReceipt ya guardaba antes de confirmar; los pases se cachean al entrar y se actualizan al comprar; tablas por jugador se limpian en `PlayerRemoving` (Mining, State, Remotes, QuestService, Pvp, ahora también los buckets nuevos y el cache de Leaderboard).

### Qué queda
- Referidos: el tope de por vida (`ReferralLifetimeCap`) limita el abuso, pero alguien con cuentas alt puede cobrar las recompensas hasta ese tope; ligarlo a algo costoso (edad de cuenta) es decisión de diseño.
- Los pases comprados fuera del juego mientras estás conectado no se ven hasta el próximo join (no hay refresco periódico).
- El lock de sesión es de tipo "soft" (TTL 150 s, toma el control en el último intento de carga); un server que cuelga más de 150 s puede ser pisado. `MessagingService`/`/event` solo para `AdminUserIds` (hoy vacío).
- No se probó en Studio real: reintentos y budget de DataStore solo se verificaron por análisis y por el mock del preview (que no tiene DataStore).

### Verificación
`rojo build` OK, `luau-lsp analyze` sin salida, `unit` (195), `locale_check`, `check_config`, `pacing_test` (27) y `security_test` (70) pasan, preview `--state mid --screen pc` sin errores de runtime.

## Ronda 8: primera sesión y game feel

### Recorrido de los primeros 2 minutos
**Antes:** spawn -> HUD mínimo (ya era progresivo) -> pill "Click a planet to mine it! (1/6)" con flecha y beam hacia el planeta -> 6 pasos con recompensa (mine, core, sell, capsule, tool, auto). Sin pantalla de carga (el jugador veía el mundo armándose), sin salida del tutorial salvo Ajustes, y casos donde el paso era imposible de hacer en el momento (vender con cargo vacío, comprar herramienta/cápsula sin Stardust) pero la flecha igual apuntaba a la plataforma. Además `Layout.capsulePosition` podía devolver nil y romper la flecha.
**Después:** pantalla de carga de marca (PLANET CRACKERS + tip + barra) -> mismo HUD mínimo -> pill de objetivo; si el paso no se puede hacer todavía, el pill dice qué falta ("Mine some ore first" / "Mine more Stardust first") y la flecha manda a los planetas -> a los 10 s sin avanzar la flecha rebota más grande y rápido -> a los 25 s aparece el botón "Skip tutorial" debajo del pill (táctil: 56 de alto en diseño) -> cada paso completado tira chispas + micro-temblor, y el último un temblor grande + milestone.

### Qué agregué
- `src/shared/TutorialFlow.luau` (puro): `hint` decide a dónde apunta la flecha según paso/cargo/Stardust/target existente, `skip`/`loud` por tiempo en el paso, `progress`, reloj por paso (se reinicia al cambiar de paso y tras rejoin). El paso sigue guardado en el perfil: al reentrar continúa donde estaba.
- `src/shared/Juice.luau` (puro): easings, roll-up de contadores, amplitud/decay de shake, merge de shakes, presupuesto de partículas, progreso/cierre de la carga.
- `src/client/Feel.luau`: micro-shake de cámara (BindToRenderStep después de la cámara, un solo shake activo, tope de frecuencia) y ráfaga de chispas con UN emisor pooleado (`rbxasset://textures/particles/sparkles_main.dds`, tope 40 vivas, mitad en lite). Se dispara al romper planeta (propio, no Auto Mine), crit, romper el Portal (shake grande + chispas moradas) y pasos del tutorial.
- Ajuste nuevo **Calm mode** (`settings.calm`, toggle en Settings, los 12 idiomas): apaga el shake. Default false; los perfiles viejos lo reciben por `reconcile`.
- `src/client/Loading.luau`: pantalla de carga independiente de todo lo demás (usa solo Shared/Locale, todo en pcall/xpcall). Mínimo 1 s, tope 6 s, destruida a la fuerza a los 9 s; si el resto del cliente falla igual se cierra. Probe desde Main.client: remotes / estado recibido / mundo cargado.
- Textos de tutorial más cortos en en/es; claves nuevas `tutorial.skip`, `tutorial.hint_ore`, `tutorial.hint_dust`, `loading.tip1-4`, `settings.calm`.
- Ya existían y no los toqué: roll-up de contadores del HUD, pops en pills, números flotantes con crit, squash en botones (UIScale), cinemática de cápsula con tarjetas por rareza.
- Tests: +31 checks en `tests/unit.luau` (226 en total). Previews: `docs/previews/anime-planet-clicker/new-{pc,phone}.png` (después), `new-{pc,phone}-loading.png`, y antes en /tmp (mismo HUD sin chip).

### Qué mirar en Studio
- La pantalla de carga: que no tape el spawn más de ~1-2 s y que se desvanezca limpia en celular real.
- Flecha/beam de la guía: que el cambio a "planet" cuando falta cargo/Stardust se sienta natural, y el chip Skip (aparece a los 25 s).
- Shake de cámara con rompe-planetas seguidos (debe verse suave, no marear) y con Calm mode ON (cero shake). Chispas en gama baja/lite.
- No se probó nada en Studio real: el preview no dibuja partículas, cámara ni la flecha 3D.
- Pendiente de diseño: `Skip tutorial` en Ajustes se superpone con el joystick en celular (ya estaba así).

## Ronda 10: arreglos del playtest

- **Bug**: los regalos "minutos desde que entras" (`Config.Gifts`) se guardaban solo en la sesion (`State.giftsClaimed`), asi que salir y volver a entrar los dejaba reclamables otra vez (farmeable).
- **Arreglo**: nuevo modulo puro `src/shared/GiftClock.luau` y campo de perfil `gifts = { day, played, claimed }` (dia UTC, segundos jugados ese dia, indices reclamados). Se reinicia al cambiar el dia UTC; el temporizador continua entre rejoins del mismo dia (`played` se actualiza cada segundo y se guarda con el perfil).
- `State.giftElapsed/gifts` reemplazan a `giftsClaimed`; `ClaimGift` (Rewards) valida contra el perfil y guarda al reclamar. El snapshot sigue enviando `giftsClaimed` (lista) y `sessionElapsed` (ahora = segundos jugados hoy), asi que el cliente no cambia.
- Saves viejos: `Data.reconcile` completa/sanea `gifts` (valores seguros por defecto, NaN/tipos invalidos).
- Test puro nuevo: `tests/gift_clock.luau` (19 checks: rejoin el mismo dia no reclama de nuevo, el tiempo continua, nuevo dia reinicia, medianoche en sesion, saves viejos).
- Verificacion: `rojo build` OK, `luau-lsp analyze` sin salida, tests puros y sims pasan, playtest `new` y `mid` con veredicto OK (el hallazgo desaparecio).
