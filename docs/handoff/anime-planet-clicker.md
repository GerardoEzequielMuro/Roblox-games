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
