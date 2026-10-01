# Handoff: Sky Tower Obby (obby-sky-tower)

Sesión en la nube, sin Studio. **No vi nada corriendo**: todo lo que sigue está verificado con build, chequeo de tipos y tests puros, no jugando. No commiteé.

## Qué cambié

### Bugs reales del rediseño de 1000 niveles

- **El botón "Lobby" del teletransportador te borraba el progreso.** `Travel` con destino 0 guardaba `stage = 0`: alguien en el nivel 850 que tocaba "Lobby" volvía al 0 (y se guardaba). Ahora va al lobby y **conserva el checkpoint**.
  `src/server/Lounge.luau`, `src/server/Checkpoints.luau` (`travel` rechaza el 0 y manda al lobby).
- **Se podían farmear Wins y el bonus de cumbre.** Con el teletransportador ibas al mundo 91-100, subías 10 niveles y te daba Win +1 y 250 monedas. Podías repetirlo sin límite, con rebirth en el medio, e inflar el ranking de Top Wins. Ahora cada cumbre paga **una vez por run**: campo nuevo `profile.runTop`, regla pura `Rules.summitRewarded`. El rebirth lo resetea. Teletransportarte debajo de una cumbre renuncia a esa cumbre hasta el próximo rebirth. Los regalos siguen siendo una vez en la vida, igual que antes.
  `src/shared/Rules.luau`, `src/server/Checkpoints.luau`, `src/server/Data.luau`.
- **Migración de saves viejos:** si falta `runTop`, se completa con la última cumbre por debajo del nivel guardado (`Rules.runTopFromStage`). No se borra nada. También agregué una defensa por si `settings` viene corrupto.
  `src/server/Data.luau`.
- **Un portal viejo podía mandarte para atrás.** Pasar volando con el planeador/nube, o subir la torre 1 a pie desde el lobby, y rozar el portal de la cumbre 100 te dejaba en el nivel 100 aunque estuvieras en el 850. Ahora el portal **por contacto** se ignora en modo explorar o si tu checkpoint está más arriba (`Rules.portalTouchAllowed`). El prompt y el botón del HUD siguen andando.
- **Ranking "Fastest Climb":** un power-up comprado y ya vencido antes de arrancar desde el nivel 0 marcaba la run como asistida para siempre. Ahora, al salir del 0, solo cuenta lo que sigue activo. `src/server/Checkpoints.luau`.

### Problemas conocidos

- **Botones de prueba de Studio ("SALTAR NIVEL (prueba Studio)").** Ahora necesitan **Studio Y un flag**:
  - `Config.StudioFreeSkips` ahora es `false` por defecto.
  - El atributo de Workspace `StudioTestTools` solo lo pone `test.project.json`.
  - El server lo decide (`Session.studioTools` → `Rules.studioTools`) y el cliente además chequea su propio `RunService:IsStudio()`.
  - Un playtest normal en Studio ya se ve como el juego publicado, y el publicado nunca los muestra.
  - Archivos: `src/shared/Config.luau`, `src/shared/Rules.luau`, `src/server/Session.luau`, `src/server/Checkpoints.luau`, `src/client/UI/Hud.luau`, `src/client/UI/Prompts.luau`, `test.project.json`.
- **Personaje "desarmado" en el spawn del lobby.** No lo pude reproducir. Arreglé la causa más probable que encontré en el código:
  - Las piezas soldadas al personaje (mascota nube del regalo 200, corona del 1000) se soldaban a Head/Torso **antes** de que terminara de cargar el avatar. Si la apariencia reemplazaba esas partes, las piezas quedaban sueltas y se caían.
  - Ahora se espera `CharacterAppearanceLoaded` (máximo 8 s) y se re-aplican si cambia Head/Torso.
  - Las piezas se sueldan antes de meterlas en el personaje.
  - Los avatares altos (HipHeight grande) se levantan para no aparecer con los pies dentro del pad o del spawn.
  - Archivos: `src/server/init.server.luau`, `src/server/Cosmetics.luau`, `src/server/Checkpoints.luau` (`teleport`).

### Íconos

- `Kit.icon(parent, emoji, ...)` en `src/client/UI/Kit.luau` es el único lugar donde se dibujan íconos:
  - Si el emoji tiene ícono en el pack **y** ese ícono tiene id, sale un `ImageLabel` con `ScaleType Fit`.
  - Si no, sale el emoji exactamente como hoy.
  - `Kit.coin` usa el ícono `coin` cuando exista.
- El mapa emoji → ícono está en `Icons.GLYPHS` / `Icons.forGlyph`, en `src/shared/Icons.luau`, fuera del bloque que genera el script de subida.
- Lo usan los botones del menú, el contador de wins, los chips de power-ups y la tienda de Robux (`Hud.luau`, `StorePanel.luau`).
- Hoy todos los ids están vacíos, así que **no cambia nada visible** hasta subir los íconos.

### Look

- Materiales por mundo en `Scenery.dressPlatform` (`src/server/Scenery.luau`):
  - Toxic Factory: tapa de metal.
  - Cloud Kingdom: plataformas de mármol.
  - Neon Space: losas de pizarra oscura con la tapa en Neon (antes toda la losa era Neon).
  - No agregué partes.
- HUD: las pastillas "glass" tienen un brillo en degradé en vez de relleno plano (`Hud.luau`).
- Los kill bricks ya eran Neon rojo con pulso y la iluminación por altura ya existía. No los toqué: ForceField en un peligro me pareció riesgoso para la lectura sin poder verlo.

### Docs y tests

- `DESIGN.md` actualizado (runTop, teletransportador, flag de Studio).
- `tests/rules_test.luau` tiene +33 checks (cumbres una vez por run, migración, portal por contacto, flag de Studio).
- `tests/icons_test.luau` es nuevo.
- `tests/AutoTestClient.client.luau` tiene un check nuevo: "Lobby" del teletransportador conserva el checkpoint.

## Cómo lo verifiqué

Desde `obby-sky-tower/`, con `PATH=/tmp/tools:$PATH`:

- `rojo build default.project.json` → OK. `rojo build test.project.json` → OK.
- `luau-lsp analyze ... src` → **0 errores** (igual que al empezar).
- Tests puros:

| Test | Checks | Resultado |
|---|---|---|
| layout_test | 144843 (incluye alcance físico del salto) | 0 fallas |
| rules_test | 3569 (antes 3536) | 0 fallas |
| visual_test | 12942 | 0 fallas |
| locale_test | 9780 | 0 fallas |
| p0_test | 48 | 0 fallas |
| icons_test (nuevo) | 82 | 0 fallas |

No toqué salto ni dificultad: JumpPower 50 y la curva quedaron como los dejó el rediseño.

## Qué hay que mirar en Studio

1. **Personaje en el lobby:** darle Play con tu avatar, y también con uno alto/Rthro. ¿Sigue "desarmado"?
   - Si sigue, sacá captura del Explorer del personaje (qué partes hay sueltas) para saber si viene de otro lado.
   - Con el regalo 200 o 1000 (usá el test project): ¿la nube y la corona quedan pegadas?
2. **Playtest normal:** no tiene que aparecer ningún botón "(prueba Studio)". Con `test.project.json` sí.
3. **Teletransportador del Lounge → "Lobby":** te lleva al lobby y "Volver al checkpoint" te devuelve donde estabas.
4. **Cumbre 100:** subí limpio y verificá Win +1. Después teletransportate al mundo 10 (nivel 90) y subí a 100: **no** tiene que sumar Win. Hacé rebirth y subí de 0 a 100: sí suma.
5. **Mundos 7, 8 y 9 (niveles 61-90):** ¿se leen bien las plataformas con los materiales nuevos? Neon Space con tapas Neon puede encandilar con bloom. Si molesta, sacá la línea `[9]` de `CAPS` en `Scenery.luau`.
6. **AutoTest completo** (`test.project.json`): no lo pude correr. Ahí están los presupuestos de partes por torre (≤ 7200), luces, fps, etc. **El conteo real de partes en torres altas no está medido.**

## Pendiente

- **Subir los íconos** (`tools/icons/upload_assets.py`). Hasta entonces el HUD sigue con emojis.
- **No medí partes ni rendimiento de las torres 2-10** sin Studio. Lo cubre el AutoTest.
- **Crear los productos/pases/badges** y pegar los IDs en `Config.luau`. Con IDs en 0, Skip no se vende.
- **Detalles menores que no toqué:**
  - El evento `Win` de la torre 1 igual se dispara en una cumbre que ya no paga. Muestra el panel con el mismo total de wins.
  - Las monedas por nivel se vuelven a pagar al re-subir después de teletransportarte y reconectar. Es lo mismo que pasa con rebirth.
- `SkyTowerObby.rbxlx`, dentro de la carpeta del juego, es un build viejo. No lo regeneré.

## Ronda 2

Sigue sin haber Studio: **no vi nada corriendo**. No commiteé. La carpeta estaba limpia al empezar (el intento anterior no dejó ediciones).

### Precios

Los precios reales se cargan en el Dashboard (el juego los lee con `GetProductInfo`); el `Config` solo guarda los IDs. Por eso la lista vive en `src/shared/Pricing.luau` (`Config.Prices`), con test, y es la fuente de los números del DESIGN.md y del ancla del Starter Pack. Research: sección 4.2 + 2.3.

| Ítem | Antes (sugerido) | Ahora | Por qué |
|---|---|---|---|
| Skip Stage (niveles 1-300) | 15 | **19** | Rango real 20-79; barato y repetible con 1000 niveles. |
| Skip Stage (301-1000), producto nuevo `SkipStageHigh` | no existía | **29** | Recomendación por banda de nivel. Mismo grant. |
| Skip x10 | 99 | **149** | Con 19/29 por unidad, 99 regalaba el skip. Ahora ahorra ~25-50%. |
| Double Jump 5 min, producto nuevo `DoubleJump5` | no existía | **9** | Primera compra impulsiva (9-25). |
| Coins 500 / 2.500 | 25 / 99 | **49 / 199** | Escalera de la guía 2.3. |
| Coins 7.000, producto nuevo `Coins7000` | no existía | **499** | Escalón alto: 10,2 / 12,6 / 14,0 monedas por R$. |
| Starter Pack | 59 (tachado 169) | **59** (tachado 144, "-59%") | Ver abajo. |
| Speed Coil | 8 | **99** | 8 R$ permanente era demasiado barato (ToH: 199). |
| Gravity Coil | 19 | **69** | ToH 65. |
| Fusion, pase nuevo `Fusion` | no existía | **139** | ToH 139. Da las dos bobinas (separadas 168). |
| Double Jump pase | 99 | **99** | Sin recomendación en la research: lo dejé. |
| Infinite Revives | 139 | **179** | Rango 149-199; ahorra muchos skips, no lo canibalizo. |
| 2x Coins | 149 | **195** | ToH 195. |
| VIP | 199 | **299** | Rango 299-399 del género. |

Starter Pack y honestidad del tachado: a 19 R$ el skip, 3 skips valían 57 < 59, así que el pack ya no tenía valor real. Ahora trae **5 skips + 500 monedas** + trail Starter Star + 30 min de monedas x2. El "precio tachado" es **lo que cuestan esas partes sueltas a precio de lista** (5x19 + 49 = 144) y el "-59%" se calcula (`Pricing.starterValue`, `Pricing.discountPct`); antes el "-70%" estaba fijo en los 12 idiomas y con el ancla 169 era falso. El trail y el boost son un extra que no cuento. La ventana de 24 h es real por jugador (desde el primer join), no un reloj falso.

Cómo se implementó:
- **Bandas de skip:** `Pricing.skipKey/skipProductId`. HUD (`src/client/UI/Hud.luau`), tarjeta "¿Trabado?" (`Prompts.luau`) y tienda (`StorePanel.luau`) ofrecen el producto de la banda del nivel actual; si falta el ID de una banda se usa el de la otra. El grant es el mismo (`Monetization.grantSkip`). Un exploiter podría pedir el producto barato en un nivel alto: paga 19 en vez de 29 por lo mismo, riesgo aceptado (no puedo rechazar una compra ya cobrada).
- **DoubleJump5:** `src/server/Monetization.luau`, suma 5 min a `boosts.doublejump` (tope `Powerups.MAX_TIMED`), marca la run como asistida. Se oculta en la tienda si ya tenés el pase.
- **Coins7000 / packs:** los 3 packs salen de `Pricing.CoinPacks`, un solo handler.
- **Fusion:** `Session.hasPass` devuelve true para SpeedCoil y GravityCoil si tenés Fusion; toggles y cosméticos no cambian. Tienda la muestra como "tuya" si tenés Fusion o las dos bobinas.
- Recibos: siguen siendo idempotentes (`profile.purchases`, guardado antes de dar). Product IDs siguen en 0 (los crea Gerar). Locales: 9 claves nuevas en los 12 idiomas + `starter.items`, `msg.starter_thanks` y `starter.discount` reescritas.
- Sin autoclick por diseño. Todo lo comprado deja la run fuera del ranking Fastest Climb (ya estaba: monedas no la afectan; coils/double jump/skip marcan `help`).
- No agregué trails/auras por Robux: los cosméticos se compran con monedas y agregar un segundo camino de pago implicaba UI nueva que no puedo probar. Queda en Pendiente.

### Retención

| # | Ítem | Estado | Dónde |
|---|---|---|---|
| 1 | Loop de segundos con feedback | Ya estaba | `Celebrate.luau`, `Juice.luau`, evento `CoinCollected`: +monedas, celebración por nivel, FX. |
| 2 | Próximo objetivo visible | Ya estaba | `Progress.luau`: barra 1000 niveles, torre, "próximo regalo en el nivel N"; botón Skip. |
| 3 | Metas de sesión y largas | Ya estaba | Cumbres cada 100 + regalos por torre (`Gifts.luau`), rebirth/Wins, rankings Top Wins / Fastest / Highest Stage (`Leaderboard.luau`). Sin índice de colección %: **no agregado** (ver Pendiente). |
| 4 | Razones para volver | Ya estaba | Daily con racha (`Rewards.luau`, `RewardsPanel.luau`: "Día N de racha"), regalos por tiempo con barras, códigos, regalo de grupo, eventos con reloj (`Events.luau`, `LiveEvents.luau`: finde x2 sábado-domingo UTC + Skip Sale Hour 20:00 UTC diario; ojo: es un bonus de +1 skip, no baja el precio). Offline progress: no aplica a un obby. Stock rotativo: no aplica. |
| 4b | Primer regalo dentro del primer minuto | **Agregado** | `Config.PlaytimeRewards`: nuevo tramo de 1 min (20 monedas). El badge rojo del botón Regalos ya se enciende solo. |
| 5 | Anuncio server-wide de hitos raros | **Agregado** | Cumbre ganada a pie y cobrada por primera vez en la run avisa a los demás jugadores del server (`Rules.announceKind`, `Checkpoints.luau`, claves `msg.announce_summit/top`). Skips, teletransportes y repetidas no anuncian. |
| 5b | Invitar / referido, leaderboards en el mundo | Ya estaba | `Referrals.luau`, botones Invite/Share, tableros del lobby. |
| 5c | Regalar ítems | No aplica | No hay ítems tradeables; regalar Robux-items trae riesgo de políticas y abuso. |
| 6 | Primer minuto | Ya estaba + 4b | Intro de 2,5 s, nivel 1 paga monedas al toque, HUD mínimo; ahora además el regalo del minuto 1. |

### Política (C)

Nada vendido es aleatorio (no hay cajas ni huevos), así que no hay odds que mostrar ni `ArePaidRandomItemsRestricted` que chequear. Sin apuestas. Sin PvP. Sin escasez falsa: la única oferta con reloj es el Starter Pack, cuya ventana es real y cuyo tachado ahora es verificable.

### Otros cambios

- `DESIGN.md`: tablas de Dashboard con los precios nuevos, fila "Summit shout-out", mapa de código con `Pricing`.
- `tests/AutoTest.server.luau`: dos checks de Studio (cada ítem de `Pricing` tiene slot de ID en `Config`; el ancla del Starter coincide con `Pricing`).

### Cómo lo verifiqué

Desde `obby-sky-tower/`, con `PATH=/tmp/tools:$PATH`:
- `rojo build default.project.json` y `rojo build test.project.json`: OK.
- `luau-lsp analyze ... src`: sin salida (0 errores).
- Tests puros: `icons_test` 82/0 fallas, `layout_test` 144843/0, `locale_test` 10164/0 (324 claves, 12 idiomas), `p0_test` 48/0, `rules_test` 3631/0 (antes 3569; +announceKind), `visual_test` 12942/0, **`pricing_test` nuevo 71/0** (lista de precios, escalera de monedas, bandas de skip con fallback, ancla y % del Starter).
- No hay carpeta `sim/` en este juego. AutoTest de Studio: **no corrido**.

### Qué mirar en Studio

1. Con los IDs en 0 la tienda y el Starter siguen ocultos (igual que antes). Probá con IDs de prueba: Skip debe mostrar 19 hasta el nivel 300 y 29 desde el 300 (banda según `at + 1`).
2. Starter Pack: panel con "R$ 144" tachado y "-59%", texto con 5 skips + 500 monedas; al comprar llegan las 500.
3. Comprar Fusion: toggles de Speed y Gravity activos sin comprar cada uno.
4. Double Jump 5 min: da el salto extra, al re-comprar suma tiempo, la run pasa a "no rankeada".
5. Panel de Regalos: ahora 5 columnas; chequear que no se corte el texto de "💰 30 +1 skip" en celulares.
6. Anuncio: con dos jugadores, que uno llegue a la cumbre 100 a pie: el otro ve el toast.
7. Correr el AutoTest (`test.project.json`).

### Pendiente

- Crear productos/pases en el Dashboard con los precios de la tabla y pegar IDs en `Config.luau` (incluye los nuevos: `SkipStageHigh`, `DoubleJump5`, `Coins7000`, pase `Fusion`). Precios regionales van activados por defecto.
- Cosméticos (trails/auras) por Robux 49-199: no hecho (necesita UI y grants nuevos).
- Índice de colección % (trails/efectos/regalos) y progreso "te faltan X" en números: no hecho.
- Anuncios entre servers (MessagingService) y racha visible en el HUD: hoy el anuncio es solo del server actual.
- Del Pendiente de ronda 1 (íconos, productos, medir partes en torres altas) no toqué nada: no son código seguro sin Studio. Los "detalles menores" los dejé: el evento `Win` en cumbre ya cobrada abre un panel útil (portal/rebirth), y repagar monedas por nivel tras teletransportarse es el mismo caso que el rebirth.

## Ronda 3: ranuras de modelos

Sesión en la nube, sin Studio: **no vi nada corriendo**.

### Qué cambié

- Nueva carpeta `obby-sky-tower/assets/models/` (solo README, en español). Está mapeada como `ServerStorage.ModelLibrary` en `default.project.json` y en los otros 5 `*.project.json` (test, shots, shotslow, uishots, i18nshots).
- `src/server/World/ModelSlots.luau`: `ModelSlots.spawn(slot, cf, targetSize, parent, fallback, opts)`. Si hay `slot.rbxm` (o `slot_1`, `slot_2`...) en la biblioteca, lo clona, **borra todos los scripts** (con warning), lo escala parejo al tamaño objetivo, lo apoya con la base en `cf`, lo ancla, sin colisión/touch/query/sombra (igual que `Scenery.deco`). Si no hay, o se pasa del tope de partes (por ranura y 2000 en total), corre `fallback()` tal cual estaba.
- `src/shared/ModelFit.luau`: matemática pura (escala que entra en la caja, variante por posición, topes). Test: `tests/modelfit_test.luau` (13140 checks, 0 fallas).
- `src/server/Scenery.luau`: 14 ranuras cableadas, el código primitivo quedó adentro de los fallbacks sin cambios: `island`, `tree`, `pine`, `windmill`, `cupcake`, `snowman`, `pyramid`, `cloud`, `rock`, `bush`, `lamp_post`, `balloon`, `trophy`, `portal_frame`. Detalles: el globo se devuelve sin parent para poner el atributo `Bob` antes de replicar (Juice lo lee al aparecer); en nubes/rocas el `rng` se consume en el mismo orden que antes, así la disposición no cambia.
- Doc con la tabla de ranuras y el paso a paso: `docs/modelos/obby-sky-tower.md`.
- Decisiones: todo se construye en el server, así que no hay biblioteca en ReplicatedStorage. No toqué plataformas, obstáculos, tienda, pedestales ni el disco del portal (la lógica de toque vive ahí). Los modelos no se tiñen con el mood de cada torre. El marco del portal de modelo no colisiona (el primitivo sí).

### Cómo lo verifiqué

- `rojo build` de los 6 project files: todos incluyen `ServerStorage.ModelLibrary` (carpeta vacía; el README no molesta).
- Prueba del camino de swap: un `.rbxmx` temporal (Model `tree` con un Part y un Script) en `assets/models`: el build incluyó `ModelLibrary.tree` con el script adentro (se borra en runtime). Lo borré después y rebuildé.
- `luau-lsp analyze` sin salida. Tests puros: icons 82, layout 144843, locale 10164, modelfit 13140, p0 48, pricing 71, rules 3631, visual 12942, todos con 0 fallas.

### Qué mirar en Studio

1. Con la carpeta vacía, el mundo tiene que verse idéntico (AutoTest de `test.project.json`: presupuestos, "scenery has no collisions", "stays out of the lanes").
2. Poner un `tree.rbxm` o `island.rbxm` de prueba: ver que quede apoyado (la isla con la cara de arriba al nivel del piso), sin deformarse, y que los árboles sobre la isla no floten ni se hundan.
3. `balloon.rbxm` (Model): tiene que seguir bamboleándose. `portal_frame.rbxm`: que el disco quede en el hueco y se pueda entrar.
4. Mirar Output: warnings de scripts borrados o de modelos que se pasan del tope de partes.
5. Con modelos cargados, repetir el AutoTest: el tope "scenery parts" (4200) y el de sombras (<25%).

## Ronda 4: UI arreglada con la vista previa

Con `tools/uipreview` (`--all`, más laptop y tablet). Resultado: 0 hallazgos en PC y laptop; en celular solo quedan `core-overlap` de ventanas modales (ver abajo). Se regeneró todo `docs/previews/obby-sky-tower/`.

**Qué arreglé**
- **Checkpoint/Lobby sin texto** (`Kit.luau` `Kit.singleLine`, ~l.293): medía el alto con `Size.Y.Offset` = 0 (botón con alto por escala) y quedaba `TextSize = -8`. Ahora toma el alto del padre (`Scale * parent.Size.Y.Offset`) y se reajusta cuando el padre cambia de tamaño. Antes: dos botones vacíos; después: "Checkpoint" y "Lobby" legibles.
- **Recuadro alrededor del timer** (`Hud.luau` ~l.195): el `UIStroke` ahora es `Contextual`, contornea los números y no la caja.
- **Botón Menu** en celular (`Hud.luau`, `Kit.onLayout`): el alto de diseño sube para que mida >= 46 px reales (antes 37); el bloque de monedas/chips se acomoda según ese alto.
- **Menú abierto bajo el joystick** (`Hud.luau`, `MENU_COLS_TOUCH`): en táctil la grilla pasa a 4 columnas x 2 filas y se abre como popup en la franja libre entre el timer y la barra de nivel, a la derecha del joystick (antes Settings/Invite quedaban encima del pulgar). En PC sigue igual (3 columnas).
- **Columna de acciones** (`Hud.luau`): alturas táctiles 54 (Skip 10, Checkpoint/Lobby, habilidades, explorar); en celular la columna baja hasta justo arriba de la barra de nivel (queda a la izquierda del botón de salto); en tablet se mantiene al 64% para no pisar el salto grande. Botones 44-45 px reales.
- **Ventanas en celular** (`Kit.luau`, `Kit.panel` + `Kit.region(..., touchSize)`, `PANEL_TOUCH_H`): en táctil el panel pasa de 640x460 a 860x350 (apaisado), con encabezado más finito y X de 52 px. Escala ~0.85 en vez de ~0.67: X de 40 px, botones de tienda/ajustes/recompensas/victoria >= 44 px.
- Acomodos táctiles (`Kit.onLayout`) en `SettingsPanel.luau` (coils lado a lado, 12 idiomas en 6 columnas), `RewardsPanel.luau` (diario/códigos más bajos, código + Redeem en una fila, premios de tiempo más compactos) y `WinPanel.luau` (tarjetas y botones dentro del alto nuevo). PC no cambia.
- Plurales: no hay casos en este juego (los hallazgos de "1 Ascensions" eran de ki-warriors); no toqué locales.

**Qué queda**
- `core-overlap` (low/med) en celular dentro de ventanas modales (Shop, Travel, Rewards, Settings): el panel ancho pasa por encima de la zona del joystick. Es modal con velo a pantalla completa (el `Dim` es un botón), así que no se camina mientras está abierta; lo dejo a propósito.
- Si aparecen a la vez portal + habilidades + explorar, la columna de acciones se achica (~0.65) y algún botón puede bajar de 44 px. Caso raro.
- Los nombres en japonés/coreano/tailandés salen como cajitas en la vista previa: falta de fuente CJK de la herramienta (en Roblox se ven).

**Confirmar en Studio**
1. Celular real (o emulador apaisado con notch): Menu, popup del menú y su distancia al joystick dinámico.
2. Que las ventanas anchas (Settings/Rewards/Win/Shop/Travel) no se corten en pantallas 16:9 más angostas (p. ej. 640x360) y se cierren bien con el X.
3. Que el texto de Checkpoint/Lobby no se corta en los 12 idiomas.
4. Timer sin recuadro.

Verificación: `rojo build` OK, `luau-lsp analyze` sin salida, tests puros (`tests/*.luau`) pasan.

## Ronda 5: ritmo de progresión

Simulador de ritmo para un jugador free (obby: curva de dificultad por banda de stages + economía de monedas). Se corre desde `obby-sky-tower/` con `export PATH=/tmp/tools:$PATH; luau sim/pacing_sim.luau` (opcional `-a <jugadores> <días>`, por defecto 41 y 14). El modelo está en `sim/pacing_model.luau` y usa los módulos reales (`Layout.generate` de las 10 torres, `Rules.coinsForStage`, `Gifts`, `Powerups`, y el nuevo `Economy`). El test `tests/pacing_test.luau` (187 checks) falla si un hito se sale de su ventana o si la curva tiene un pico.

**Política del jugador simulado**: camina cada stage (riesgo por salto, kill cubes, spinners, láseres, esperas de movers/lava, muerte y vuelta al último pad que guarda), reclama el diario a los 25 s y cada regalo de tiempo apenas abre, agarra 75% de las monedas del camino, compra el cosmético más caro que puede pagar, usa skip gratis tras 4 muertes en el mismo stage y compra skip con monedas (150) tras 8, y compra escudo en las tiendas de mundo si le sobran monedas. Día 1: sesión de 60 min; después 30 min por día.

**Objetivos (adaptados a obby)**: primera recompensa < 10 s; primera compra < 60 s; 3 compras en ~5 min (en un obby solo se gasta en cosméticos, por eso no pedí 3 en 3 min: el ingreso es ~25 monedas/min); un mundo nuevo (10 stages) cada 1,5-12 min en la torre 1 (el primer mundo es el tutorial, rápido a propósito); nunca más de 10 min sin algo nuevo (mundo, obstáculo nuevo, compra, regalo de tiempo); el "primer prestigio" acá es la cima de la torre 1 (la primera Win): 30-60 min; las torres 2-10 son la cola larga (~17 h de juego activo en total según la curva analítica). Dificultad: los primeros 10 stages son victorias rápidas (<= 30 s cada uno), cada mundo no más de 1,7x el anterior, ningún stage de la torre 1 pasa de 150 s esperados (antes 196 s), ningún stage del juego pasa de 350 s (antes 560 s), los mundos 7-10 promedian >= 44 s y las torres 4-10 >= 60 s (no más fácil que antes).

### Hitos antes / después (mediana de 41 jugadores)

| Hito | Antes | Después |
|---|---|---|
| Primera moneda / recompensa | 0:02 | 0:02 |
| Stage 1 (primer checkpoint) | 0:17 | 0:17 |
| Primer regalo de tiempo | 1:02 | 1:01 |
| Primera compra | 2:25 | 0:32 |
| Tercera compra | 16:52 | 4:33 |
| Compras en la primera hora | 4 | 7 |
| Mayor tramo sin nada nuevo (1ra hora) | 8:11 | 8:59 |
| Mundo 2 (stage 10) | 2:59 | 2:56 |
| Stage 50 | 14:00 | 15:10 |
| Cima torre 1 (stage 100, primera Win) | 42:48 | 47:25 |
| Cima torre 2 / 5 | 1h36 / 5h21 | 1h50 / 5h45 |
| Stage al final del día 14 (30 min/día) | 683 | 625 |
| s esperados por stage, mundos 6-10 de la torre 1 | 21,7 / 44,5 / 46,5 / 48,6 / 49,3 | 32,2 / 34,4 / 45,0 / 47,3 / 52,4 |
| Promedio por torre 1..10 (s/stage esperados) | 30 / 42 / 41 / 68 / 71 / 70 / 75 / 79 / 82 / 103 | 30 / 48 / 45 / 68 / 76 / 68 / 74 / 69 / 72 / 75 |
| Mediana por torre 1..10 | 19 / 31 / 29 / 38 / 52 / 42 / 39 / 42 / 37 / 57 | 23 / 37 / 41 / 56 / 51 / 52 / 56 / 59 / 56 / 54 |
| Stage más duro de la torre 1 (esperado) | 196 s (stage 75, wallhop) | 134 s |
| Stage más duro de todo el juego (esperado) | 560 s | 317 s |

Lectura: el promedio por torre queda igual o más alto hasta la torre 7 y algo más bajo en las 8-10, pero solo porque el "antes" estaba inflado por outliers de 500 s (wallhop, disappear, falling); la mediana de cada torre (el stage típico) sube en 8 de 10 torres (igual en la 5, un poco menos en la 10). Es decir: sin picos, y el stage normal es más difícil que antes.

### Qué cambié y por qué

1. **`src/shared/Economy.luau` (nuevo, puro)**: saqué de `Config` los números de monedas (`CoinsPerTower`, `CoinPickupValue`, `CoinsPerWin`, diario, regalos de tiempo, códigos, precios de trails y efectos). `Config` los re-exporta con los mismos nombres (mismo patrón que `Pricing`). Hacía falta porque `Config` usa `Color3`/`Enum`/`script` y no se carga con `luau` a secas.
2. **Precios de cosméticos (monedas, no Robux)**: Cloud 100 -> 20, Mint 250 -> 50, Fire 500 -> 160, Ocean 800 -> 350, Candy 1200 -> 650, Toxic 1800 -> 1200; Sparkles 400 -> 100, Smoke 900 -> 400, Star Aura 1500 -> 900. Galaxy, Flames y Rainbow igual. Motivo: la primera compra tardaba 2:25 y la tercera ~17 min.
3. **Quitar picos en `Layout.luau`**: wallhop con `gapScale` de 0.72 a 0.82 según dificultad (los ledges chicos al 90% del alcance eran 150-500 s), piso del delay de disappear/falling 0.28 -> 0.45 s (nadie llega a saltar antes), y lava con `gapScale = 0.88` (la lava que sube ya es la presión).
4. **Compensar para que el juego NO sea más fácil (feedback del dueño: muy fácil)**, sin pasar el límite físico (`MAX_REACH` 0.93, el test de layout lo sigue exigiendo):
   - `Layout.reach`: stages 11-50 suben de 0.60-0.80 a 0.60-0.84, stages 51-100 de 0.80-0.89 a 0.84-0.93, torres 2-10 fijas en 0.93 (antes 0.89-0.915).
   - `Layout.difficulty` de la torre 1: exponente 0.75 -> 0.55 (las plataformas se achican antes).
   - Los tipos "regalados" ahora también suben con la dificultad (antes tenían un gap fijo bajo): spinner y laser 0.6 -> 0.88, beam 0.6 -> 0.92, conveyor 0.75 -> 0.92, wind y killbricks 0.85 -> 0.95, y el primer salto del truss 0.7 -> 0.9.
   - Tamaños mínimos tardíos: ancho de jumps 2.8 -> 2.5, disappear/falling/lava 3.2 -> 2.8, glass 3.4 -> 3.0, ice 4 -> 3.6, mixed 3.6 -> 3.1, moving 4 -> 3.6. Período de los movers 2.2 -> 2.05 s (el test exige >= 2 s).
   - Probé subir más la dificultad de las torres 2-10 y rompe el test de hazards ("new hazards in play"); lo dejé afuera.
5. No toqué monedas por stage, regalos de tiempo, diario ni precios en Robux. El salto (JumpPower 50) tampoco: el layout test lo limita y todo el mapa está calibrado contra ese salto.

Como el generador comparte un solo RNG, cambiar cantidad de plataformas cambia qué tipo toca en muchos stages (mismo seed, mapa distinto). No hay datos guardados que dependan del mapa, solo del número de stage. Las cimas salen un poco más tarde que antes (torre 1: 47 min, sigue en la ventana 30-60).

### Límites del simulador

- El riesgo por salto, las esperas y la curva de habilidad (`PacingModel.Tune`) son estimaciones mías, no datos medidos. Sirve para ritmo relativo (rampas, picos, ventanas), no para predecir tiempos reales: un jugador casual real probablemente tarde más por stage.
- No modela la carga inicial (3-5 s), ni abandonos por frustración, ni el x2 del fin de semana, ni pases/Robux, ni los poderes de la tienda salvo escudo y skip. Tampoco power-ups de velocidad/gravedad/doble salto que bajarían el tiempo.
- Las muertes en pads sin guardado se aproximan como rehacer los stages anteriores sin volver a fallarlos.
- Después de comprar todo el catálogo (~torre 3) las monedas no tienen destino salvo skips de 150 y escudos: hay ~25 mil monedas sobrando al final. Falta un sumidero de cola larga (más cosméticos caros, por ejemplo) si se quiere que la economía siga enganchando en las torres 4-10.
- El "algo nuevo" cuenta mundo nuevo, primer encuentro con un tipo de obstáculo, compra, regalo de tiempo y diario; no cuenta cambios de ambiente o eventos.

Verificación: `rojo build default.project.json` OK, `luau-lsp analyze` sin salida, tests puros (`tests/*_test.luau`, incluido el nuevo `pacing_test`, 187 checks) pasan.

## Ronda 6: contenido para el hueco

**Hueco**: después de la torre 3 el catálogo de cosméticos (15k monedas) se agotaba y quedaban ~25k monedas sin destino. Solo cosmético: nada de esto hace más fácil subir (no toqué Layout, salto, skips ni power-ups), así que el ranking de velocidad sigue parejo.

### Qué agregué

1. **Cosméticos por torre superada** (se compran con monedas; se desbloquean cuando `best >= torre * 100`, o sea cuando ya terminaste esa torre). Tabla `Economy.TowerReq`, regla pura `Economy.towerCleared`:
   - Torre 2: estela Blossom (2.500), mascota Star Sprite (3.500)
   - Torre 3: efecto Frostbite (3.000), efecto Embers (4.000)
   - Torre 4: estela Nebula (5.000)
   - Torre 5: estela Tidal (4.500), mascota Moon Bunny (6.000)
   - Torre 6: efecto Prism Halo (7.000)
   - Torre 7: efecto Golden Hour (6.500), estela Sunforge (8.500)
   - Torre 8: mascota Storm Drake (10.000)
   - Torre 9: estela Twilight (9.000), efecto Void Aura (12.000)
   - Torre 10: estela Celestial (15.000), mascota Sky Phoenix (20.000)
   Total ~117k: más de lo que se gana en todo el juego, así que nunca se termina.
2. **Mascotas de hombro** (nuevo): 4, hombro izquierdo (la nubecita del regalo 200 sigue en el derecho). Se arman con primitivas en `Cosmetics.buildCompanion` (objeto chico que se lleva puesto, no prop de mundo: por eso no usan ModelSlots; no hay props grandes nuevos). Remotes `BuyPet` / `EquipPet`.
3. **Shine (mejora de cosméticos)**: cada estela / efecto / mascota que tengas se mejora 3 veces (1.200 / 3.000 / 6.000 monedas, `Economy.ShineCost`). Estela más larga, ancha y brillante; efecto con una capa extra de partículas; mascota con luz (y chispas desde el nivel 2). Remote `UpgradeShine`.
4. **UI**: la tienda (`ShopPanel`) pasa a 4 pestañas: Trails / Effects / Pets / Shine. Los ítems bloqueados muestran "🔒 Tower N" y el precio; los mejorados muestran "Shine ★★☆". La pestaña Shine lista lo que tenés con botón "⬆ 💰 precio" (o MAX).
5. **Guardado**: perfil con `pets`, `equippedPet`, `shine` (defaults en `defaultProfile`; `reconcile` los completa en saves viejos y sanea si vienen corruptos / fuera de rango). Van en el push de estado (`Session.push`). El servidor valida todo: torre superada, dueño, monedas, tope de nivel.
6. **Locales**: 25 claves nuevas en los 12 idiomas (`locale_test` pasa).

### Hitos antes / después (mediana)

| Hito | Antes | Después |
|---|---|---|
| Primera recompensa / compra / 3ra compra | 0:02 / 0:32 / 4:33 | igual (no toqué el principio) |
| Mayor tramo sin nada nuevo, 1ra hora | 8:59 | 9:01 |
| Mayor tramo sin nada nuevo, 2 primeras horas (nuevo) | sin medir | 9:41 |
| Cima torre 1 / 2 / 5 | 47:25 / 1h50 / 5h45 | igual |
| Catálogo de monedas | 15k, agotado ~torre 3 | ~15k + ~117k en 11 ítems por torre + Shine |
| Monedas sin gastar en cada cima (torres 2-10) | ~25k al final | máx. 5,9k (mediana de 11 jugadores) |
| Ítems del catálogo que faltan comprar al llegar a la torre 10 | 0 | 4 (y todo el Shine) |
| Espera entre dos compras después de la torre 2 | sin destino | mediana 1h18 / peor jugador 1h48 de juego activo |

Notas del sim (`PacingModel.lateGame`, política del jugador: compra el ítem desbloqueado más caro que puede pagar; si está juntando para algo desbloqueado no gasta en Shine, pero mientras espera la próxima torre sí mejora lo que tiene). Por eso el Shine casi no se compra en el sim: siempre hay una meta más cara. Un jugador real lo va a mezclar más. Las esperas de ~1h para los más lentos son metas largas a propósito (hay mundo nuevo cada pocos minutos en el medio).

### Tests

`tests/pacing_test.luau` (260 checks, antes 187) ahora también falla si: el tramo sin novedades de las 2 primeras horas pasa de 11 min; alguna torre 2-10 no desbloquea nada; un ítem de torre no tiene precio de cola larga (>= 2000); los niveles de Shine no suben de precio; la espera mediana entre compras después de la torre 2 pasa de 1h35 (peor caso 2h15); hay menos de 10 compras; se acumulan más de 12k monedas sin gastar en una cima; la lista de deseos se vacía antes de la torre 10; se gasta menos del 85% de lo ganado. `sim/pacing_sim.luau` imprime la sección "Late game".

### Previews

`docs/previews/obby-sky-tower/mid-*-shop.*` se regeneraron con el fixture de siempre (perfil de torre 3). Las pestañas nuevas y un perfil de torre 7 (ítems comprados, mascotas, Shine) están en `docs/previews/obby-sky-tower/late/` (`mid-{pc,phone}-shop{,_effects,_pets,_shine}.png`), hechos con una copia temporal del fixture (no toqué `tools/`). PC: 0 hallazgos. Celular: solo el `core-overlap` de ventana modal ya conocido (ver Ronda 4).

### Qué mirar en Studio

1. Comprar una mascota (`best >= 200`, darse monedas): que quede apoyada en el hombro izquierdo sin tapar la nube del regalo 200, sin empujar ni tropezar al avatar, en R15 y R6 y con avatares altos. Que sobreviva a morir / respawn (`applyAll`).
2. Shine nivel 1-3 en estela, efecto y mascota: que se note la diferencia y que los efectos de fuego no tapen la pantalla en celular (con "Visual effects" apagado igual se ven las partículas del servidor: decidir si hace falta atenuarlas).
3. Que el Phoenix / Drake (alas con `Wedge`) se vean bien de lado; ajustar offsets en `buildCompanion` si se cruzan con el torso.
4. La tienda en celular real: 4 pestañas (nombres largos en ru/de/vi), botones Equip / Upgrade >= 44 px.
5. Un save viejo (sin `pets` / `shine`) carga sin errores y un save con `best` alto ve los ítems desbloqueados.
6. Las mascotas no cambian el tiempo de la run: no hay que marcarla como asistida.

Verificación: `rojo build default.project.json` OK, `luau-lsp analyze` sin salida, tests puros (icons, layout, locale, modelfit, p0, pacing, pricing, rules, visual) pasan.

## Ronda 7: seguridad

Auditoría de todos los remotes (solo existe `Request(action, payload)`; no hay RemoteEvents cliente->servidor), compras, DataStore, leaderboards y memoria. Helper nuevo y puro: `src/shared/Security.luau` (tests en `tests/security_test.luau`, 166 checks). Los jugadores legítimos no notan cambios.

| Sev. | Dónde | Cómo se explotaba | Arreglo |
|---|---|---|---|
| Alta | `Checkpoints.luau` `reach` (~l.255) | Un exploiter con teleport se paraba junto a los pads (hasta 3 por delante) cada 0,8 s: stages, monedas y tiempo de speedrun sin caminar. | `Security.hopPlausible`: la distancia desde la última posición conocida (respawn o último pad) hasta el pad tiene que ser recorrible a <= 45 studs/s en el tiempo transcurrido; si no, `retry`. `s.lastPos/lastPosAt` en Session. |
| Alta | `Checkpoints.luau` `advanceTo` (win) + `Leaderboard.recordFastest` | Tiempo ranked "imposible" con teleports en la tabla "Fastest Climb". | El servidor acumula la distancia pad a pad (`run.dist`); si el tiempo medido por el servidor es menor que `dist / 30 studs/s` (piso ~203 s en torre 1) la run deja de ser ranked (el progreso se conserva). Además `recordFastest` ignora < 60 s. El tiempo ya era 100% server-side (`GetServerTimeNow`). |
| Alta | `Monetization.luau` ProcessReceipt (~l.160) | Devolvía `PurchaseGranted` aunque `Data.save` fallara (el save no devolvía nada): se perdía la compra o se re-otorgaba. | `Data.save` ahora devuelve boolean y reintenta; `PurchaseGranted` solo si guardó. Si falla, queda en memoria con el receipt id y devuelve `NotProcessedYet`; el reintento de Roblox guarda sin otorgar dos veces. |
| Alta | `Data.luau` save (~l.200) | Saves solapados (autosave + win + receipt + PlayerRemoving) y sin reintento; valores NaN/inf/negativos podían guardarse (el UpdateAsync falla y se pierde el progreso). Perder el lock seguía intentando escribir. | Mutex por jugador (`saving`), 2-4 intentos con backoff 1/2/4 s, `GetRequestBudgetForRequestType` (el autosave se saltea si no hay presupuesto), `Security.sanitizeProfile` antes de guardar y al cargar, si otro server tomó el lock se deja de guardar. Autosave escalonado. Perfil de versión > `Data.VERSION` no se carga ni se pisa. |
| Media | `Rewards.luau` RedeemCode | Fuerza bruta de códigos a 8 req/s; `gsub` sobre strings enormes. | Cooldown 2 s, tope 64 bytes antes del gsub, 5 fallos seguidos = bloqueo 60 s por jugador. |
| Media | `Remotes.luau` | Payloads con strings gigantes, NaN/inf, tablas anidadas; sin cooldown por acción. | `Security.payloadOk` (tabla plana, <= 8 claves, strings <= 128, números finitos), nombre de acción <= 32, cooldown por acción (`DEFAULT_INTERVALS`: compras 0,3 s, teleports 1 s, ShareLink 3 s, WatchAd 5 s...) además del bucket global 8/s. |
| Media | `Shops.luau` `placePocket` | Teletransportarse lejos, poner el checkpoint portátil ahí y volver (salto sin pasar por los pads). | Exige estar a <= 100 studs del pad actual o el siguiente (`Checkpoints.nearProgress`). |
| Media | `Monetization.luau` WatchAd | `ShowRewardedVideoAdAsync` yielda: varias llamadas en paralelo antes de sumar al cupo diario. | Lock `watching[player]` mientras se muestra el anuncio. |
| Media | `Leaderboard.luau` `write` | `SetAsync` ciego: un valor viejo/reintentado podía empeorar un récord. | `UpdateAsync` que solo acepta mejoras (max para wins/stage, min para tiempos); valores finitos y enteros < 2^31. |
| Baja | `Cosmetics/Lounge/Shops/Rewards` handlers | `tostring(payload.x)` y `tonumber` laxos (strings tipo "0x10", tablas, fracciones). | `Security.str` / `Security.int` con tope y rango (Travel 0..1000, ClaimPlaytime 1..N, ids <= 48 bytes). |
| Baja | `Checkpoints.luau` `lastPortal`, `Rewards` `codeFails`, `Leaderboard` `lastWrite/lastStageWrite/nameCache`, `Remotes` cooldowns | Tablas por jugador que no se limpiaban en PlayerRemoving. | Limpieza en PlayerRemoving (`Leaderboard.forget`, `Remotes.forget`, etc.); `nameCache` acotado a 200. |
| Baja | `Events.luau` | `/event` con minutos enormes y `endsAt` NaN/infinito por MessagingService. | Minutos <= 1440, `endsAt` finito y <= 2 días. |

Ya estaba bien (revisado, sin cambios): precios y dueño de ítems siempre del servidor, `Checkpoints` solo avanza con pads en orden (`Rules.canReach`, MaxStageJump 3, nada cruza un portal), monedas por pickup validadas por distancia, `DevSkip` solo en Studio, receipts con `PurchaseId` guardado y `NotProcessedYet` sin perfil, pases releídos al entrar, `BindToClose` guarda a todos, save en PlayerRemoving, lock de sesión en UpdateAsync, fast-fail en Studio.

Queda pendiente / aceptado:
- Referidos: una cuenta alt puede cobrar el regalo de invitado y acreditar al invitador (tope de por vida `ReferralMaxRewards`). Para cerrarlo hace falta una señal externa (edad de cuenta, verificación); no lo toqué.
- Un teleporter paciente que espera el tiempo de viaje sigue avanzando a ~45 studs/s por pad (no gana nada contra caminar rápido con coil, pero no se detecta); la tabla ranked sí queda protegida por el piso de 30 studs/s acumulado.
- El piso de 30 studs/s está calibrado con WalkSpeed 16 y la geometría actual (torre 1: 6103 studs, salto máx. 63); si se agregan boosts en runs ranked, revisar `Security.RANKED_MAX_SPEED`.
- `UserOwnsGamePassAsync` está cacheado por Roblox: el pase se marca con la señal `PromptGamePassPurchaseFinished` (no la puede disparar el cliente) y se relee al entrar.
- Hay que probar en Studio con 2 servidores: lock de sesión + retry, y una compra con DataStore caído (debe quedar `NotProcessedYet`).

Verificación: `rojo build` OK, `luau-lsp analyze` sin salida, tests puros (icons, layout, locale, modelfit, p0, pacing, pricing, rules, visual, security) y `pacing_sim` OK, preview `--state mid --screen pc`: 0 hallazgos, 0 errores de runtime.

## Ronda 8: primera sesión y game feel

**Recorrido de los primeros 2 minutos, antes.** Entra -> carta de título fija 2,3 s (sin barra ni tip, no esperaba a nada) -> HUD con timer, Menu, monedas, Checkpoint/Lobby y una columna de luz sobre la primera plataforma (único guía). Ningún texto decía qué hacer. Primera recompensa: al pisar el pad 1 llegaban confetti y "STAGE 1!". Primera compra: nada la empujaba (la tienda estaba escondida tras Menu). Los contadores de monedas saltaban de golpe y el temblor de cámara solo existía al morir.

**Después.**
1. Carga (`UI/Intro.luau`): misma carta de marca, ahora con barra de progreso real (estado del servidor + personaje) y un tip rotativo (`intro.tip1..3`). Se va cuando todo llegó (mínimo 1,8 s) y **como máximo a los 5 s pase lo que pase** (timer propio, además fade con pcall; no puede colgarse).
2. Guía de primera sesión (`UI/Guide.luau` + `shared/Onboarding.luau`, puro y testeado): una sola pista de 3-6 palabras ("Jump to the glowing pad", "Next glowing pad!", tras 2 muertes "Wait, then jump!"), pastilla que pulsa, flecha 3D que rebota sobre el próximo pad con distancia en m, y flecha en el borde de la pantalla si el pad queda fuera de cámara. Termina al llegar al stage 3, con Skip, o a los 300 s. Sin estado propio: se deriva del stage guardado, así que al reconectar retoma donde estabas (y un veterano no ve nada). Si no se puede calcular el pad, queda solo el texto. Nunca bloquea input. Primera compra: si cruzaste el stage 3 en esta sesión, tenés monedas para lo más barato (20) y no abriste la tienda, la pastilla dice "Spend coins: Menu > Shop" y el botón Menu parpadea (45 s máx.).
3. Juice: contadores de monedas/victorias que "ruedan" con easing (`UI/Feel.luau` + `shared/FeelMath.luau`), "+N" flotante (pool de 6, 3 en lite), punch en el contador de monedas y en el nivel al subir; micro-shake de cámara en mundo nuevo, torre, victoria y regalos (`Juice.shake`; el más grande no lo pisa uno chico); revelado de regalos con color de rareza (`shared/Rarity.luau`: común/raro/épico/legendario según el id del regalo; toast, confetti y chispas en ese color, más temblor en tiers altos); tope de efectos simultáneos en Juice (12 PC / 5 lite) y de confetti (60 / 24). "Visual effects" apagado = reduced motion: sin rodado, sin popups, sin shake, sin confetti, sin pulsos.
4. Sonido: no había módulo de audio, creé `shared/Sounds.luau` (todos los ids vacíos, no inventé ninguno) y `client/Sfx.luau` con pool de 6 Sound. Hooks: coin, checkpoint, worldUp, rare, win, death, hint. Con id vacío no hace nada.
5. Textos nuevos en los 12 idiomas (`guide.*`, `intro.tip*`, `intro.loading`). Layout.luau intacto.

**Qué mirar en Studio.**
- Flecha 3D sobre el próximo pad y la flecha de borde (en el preview se ve un artefacto del simulador, la cámara real la calcula bien); que no tape el botón de salto en celular.
- Que la barra de carga cierre sola en servidor lento y el Skip de la guía (>= 44 px en celu).
- Sentir el shake en mundo nuevo / regalo del tower 10 (legendario, dorado) y que con Visual effects apagado no haya nada.
- Pegar ids reales en `Sounds.ids` cuando existan.
- Revisar la posición de la pastilla en celu (franja libre entre el joystick y la columna de acciones) y en tablet.

Tests nuevos: `tests/onboarding_test.luau` (122 checks: máquina de pasos, que siempre termina, resume, rareza, FeelMath, sonidos vacíos). Previews antes/después en `docs/previews/obby-sky-tower/` (`new-*-before-r8.png`, `new-*.png`, `new-*-intro-r8.png` con la carga).
