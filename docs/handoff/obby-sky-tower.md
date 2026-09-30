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
