# Spin Showdown (ruleta-pvp): handoff

Aviso: nada de esto se vio corriendo. Trabajé en un contenedor Linux sin Roblox Studio, así que todo se verificó con el build, el type checker y los tests puros. Lo visual (cámara, grading, partículas, íconos) y los tiempos del partido hay que mirarlos en Studio sí o sí.

## Qué cambié

**Revisión de runtime (el juego nunca corrió)**
- Revisé el boot del server (`src/server/Main.server.luau` y el orden de init de los Services), los remotes (`Services/Remotes.luau`) contra cada `Net.event`/`Net.request` del cliente, los tipos de evento del partido que emiten `MatchCore`/`MatchRunner` contra los handlers del `Director`, y los atributos que se leen contra los que se setean. **No encontré nombres rotos.** Todos los eventos, requests y atributos coinciden, y cada evento del partido tiene handler o se ignora a propósito (`start`). También revisé la máquina de estados de la mesa (open → countdown → playing → open) y los casos borde: alguien se va en medio de la ronda, se van todos los humanos (el partido se aborta), mesa solo con bots (no arranca sin humanos), el que llega tarde (no se puede sentar en una mesa que está jugando y la mira como espectador) y el jugador AFK.
- **Bug: el AFK quedaba pegado para siempre.** Después de 2 timeouts el server jugaba por vos, pero el cliente escondía los botones, así que no había forma de volver, y el toggle de Auto-play mostraba OFF aunque estuviera jugando solo. Además un solo turno AFK contaba doble (se contaba el timeout de decidir y también el del freno). El arreglo:
  - `src/shared/MatchFlow.luau` (nuevo, puro): cuenta un strike por turno y el auto-play arranca después de 2 turnos AFK seguidos, como dice el DESIGN.
  - `Services/MatchRunner.luau`: nueva acción `Act { kind = "back" }` ("volví").
  - `UI/MatchHud.luau`: cuando el server juega por vos, el botón Auto-play dice ON con borde amarillo. Si lo tocás, te devuelve los turnos. No hace falta texto nuevo en los 12 idiomas.
- `Services/Tables.luau`: si `startMatch` tira un error, antes mataba el loop de countdowns de **todas** las mesas. Ahora va con `pcall`: limpia los bots, levanta a los humanos con un aviso y la mesa vuelve a quedar libre. Las reglas de relleno con bots, el countdown y quién se queda después del partido ahora salen de `MatchFlow`, con la misma lógica que antes.
- `Services/Data.luau`: si el DataStore responde "sin acceso" (Studio sin *Enable Studio Access to API Services*, o el place sin publicar), deja de reintentar enseguida. Antes cada playtest dejaba al jugador unos 12 s en "loading" sin poder sentarse. La sesión sigue sin guardar, igual que antes.
- `*.project.json` (los 5): `Workspace.StreamingEnabled = false`, puesto explícito. El cliente espera las 6 mesas por tag (`TableRoot`) y con streaming las mesas lejanas no llegarían nunca.
- Temporada: `State.addTrophies` y el loop del leaderboard llaman a `State.checkSeason`. Así, un server que queda prendido cuando cambia el mes hace el rollover, y el board de temporada (`Leaderboard.luau`) no sube trofeos de la temporada anterior.

**Suspenso / intensidad**
- `Arena/Mood.luau`: nuevo `Mood.grade(sat, contraste, tint, segundos)`, un pulso de ColorCorrection que se desvanece. Además el latido golpea un poco el contraste, y hay depth-of-field (efecto `Focus` creado en `LobbyBuilder`) que desenfoca el fondo cuando se apagan las luces. Todo se apaga en lite y se suaviza si el jugador desactivó los flashes. Si pasás a lite a mitad del partido, Lighting vuelve a como estaba.
- `Arena/Director.luau`: en la eliminación el mundo se desatura (más fuerte si sos vos), sale una ráfaga de chispas con humo en el podio y hay un punch de FOV. Cuando cae Doom sube el contraste con un tint rojizo antes del apagón. Si te pegan a vos, pulso rojo. Al ganar, un pulso cálido y saturado.
- `Arena/Fx.luau`: `Fx.burst` con dos emisores con texturas built-in (`rbxasset://textures/particles/sparkles_main.dds` y `smoke_main.dds`). Siguen siendo pooled: 2 emisores en total. Actualicé el límite en `tests/AutoTestClient.client.luau` y en el DESIGN.
- `UI/MatchHud.luau`: en los últimos 3 segundos de tu decisión, cada segundo hace pop del número, un tick de audio que va subiendo y el borde se pone rojo.
- `Arena/Cam.luau`: con "screen shake" apagado (movimiento reducido), los punches de FOV quedan al 30%.
- Audio: `client/Audio.luau` ya existía y hace no-op con ids en 0 (`Config.Audio`). No inventé ningún id.

**Íconos**
- `src/shared/Icons.luau`: `Icons.emoji` (emoji → nombre del pack). `Icons.get` acepta el nombre o el emoji. Los ids siguen vacíos, así que hoy todo devuelve nil.
- `UI/Theme.luau`: `Theme.icon` (un `ImageLabel` con ScaleType Fit si hay id; si no, el emoji como hasta ahora), `Theme.iconImage` y la opción `Icon` en `Theme.button` (con id, la imagen reemplaza al emoji del prefijo). Lo usan los pills de trofeos y monedas, el menú del lobby, el medallón de cada ventana (`UI/Windows.luau`), Tap del Core, Invitar, Crear privada, Retar y Aceptar duelo.

**Retención**: ya estaba todo implementado, no hizo falta código nuevo. Quests diarias (`QuestService`), board de temporada en OrderedDataStore por temporada (`Leaderboard.luau`, `_lb_season_<n>`) y 65 cosméticos que se compran con monedas (`Cosmetics`).

**UI y luces**
- `UI/Theme.luau`: los paneles tienen un gradiente sutil de arriba hacia abajo (se multiplica con el color de cada panel).
- `World/LobbyBuilder.luau`: SunRays suave y DepthOfField (apagado por defecto, lo maneja Mood).

**Tests**: `tests/unit_core.luau` pasa de 579 a 659 checks. Los nuevos cubren `MatchFlow` (tamaño legal de mesa en todos los modos, countdowns, quién se queda, AFK con strikes por turno y "volví") y los íconos (ningún id inventado, todos los emojis mapean a un ícono que existe).

## Cómo lo verifiqué
```
rojo build default.project.json -o /tmp/tools/ruleta.rbxlx      -> Built project (los 5 project.json buildean)
luau-lsp analyze ... src                                         -> 0 errores (también 0 en tests/AutoTest*.luau)
luau tests/locale_check.luau                                     -> LOCALE CHECKS PASSED
luau tests/unit_core.luau                                        -> 659 checks, 0 failures / UNIT CORE PASSED
```
También confirmé que el rbxlx trae `StreamingEnabled=false`.

## Qué hay que mirar en Studio
- Correr `test.project.json` (AutoTest y AutoTestClient). Es el playtest automático que ya existía y nunca se corrió. Es la mejor prueba de todo el flujo.
- Un partido completo solo contra bots: el countdown de 4 s en el primer partido, la intro, los turnos y el freno. Fijarse que la mesa vuelva a "open" y que los bots desaparezcan al final.
- AFK: no tocar nada durante 2 turnos. El botón Auto-play tiene que pasar a ON con borde amarillo, y al tocarlo tus turnos siguientes tienen que volver a ser tuyos.
- Irse en medio del partido (botón Salir y cerrar el cliente): el partido sigue. Si no queda ningún humano, se aborta.
- El grading y el DoF: que la desaturación de la eliminación no quede exagerada y que el DoF no desenfoque la rueda (FocusDistance 26, InFocusRadius 22; ajustar en `LobbyBuilder` si hace falta).
- Que las texturas `sparkles_main.dds` y `smoke_main.dds` carguen (son built-in, pero no las pude ver).
- Con API Services apagado: el jugador tiene que entrar enseguida y ver el aviso "no se guarda".

## Pendiente
- Subir los íconos (`tools/icons/upload_assets.py`) para que aparezcan las imágenes. Hasta entonces se ven los emojis.
- Audio real: los ids de `Config.Audio` los tiene que cargar el dueño.
- El chip de jugador del HUD de partido (corazones) y los botones con texto dinámico (Auto-queue, Auto-charge) siguen con emoji aunque haya ícono subido.
- IDs de passes y productos (siguen en 0).

## Ronda 2

Aviso: nada de esto se vio corriendo. Sin Studio, todo se verificó con build, type checker y tests puros.

### Precios
Fuente: `docs/research/top-juegos-y-precios.md` sección 4.6. Todos los precios están en `src/shared/Config.luau`. Los IDs siguen en 0.

| Ítem | Antes | Ahora | Por qué |
|---|---|---|---|
| Double Coins (pass) | 149 | 199 | Rango recomendado 199-249; Epic Minigames cobra 299 |
| Emote Pack (pass) | 79 | 99 | Rango 79-99; "Second Effect" de Epic Minigames es 99 |
| VIP / Legend Skins / Finisher Pack / Auto Charge | 299 / 199 / 149 / 99 | igual | Ya estaban en el precio recomendado |
| CoinsS / M / L / XL | 49 / 99 / 249 / 499 | igual | Escalera buena (+0 / +24 / +48 / +77 %) |
| CoinsMega (nuevo, 40.000 monedas) | no existía | 999 | Escalón que faltaba; +96 % de bonus, siempre mejor valor por R$ (test) |
| Starter Pack | 49 (tachado 199, 1.500 monedas) | 49 (tachado 147, 3.000 monedas) | El 199 tachado no era el precio de nada. Ahora el tachado es lo que cuestan las mismas monedas en 3 bolsas CoinsS (147) y se calcula solo en Config; un test lo verifica |
| Server Party | 25 | 25 | Recomendado |
| Season Pass Premium (nuevo, producto) | no existía | 399 | Recomendado 399 (RIVALS 599) |
| Season Tier Skip (nuevo, producto) | no existía | 39 | Recomendado 29-49 |
| Kill sound (pass nuevo 99) | no existía | NO agregado | Necesita ids de audio que tiene que subir el dueño; con ids en 0 sería un pass que no suena. Queda en Pendiente |

Regla: nada pago cambia partidas, giros ni odds. Todos los pases y productos tienen `affectsMatch = false` y hay tests puros que lo verifican (ver abajo). No hay ítems random pagos, así que no hace falta UI de odds ni PolicyService.

### Season pass (nuevo)
- Mensual (mismo id que la temporada de trofeos), 30 niveles de 60 puntos. Puntos solo por jugar: 20 por partida, +10 si quedás top 3 (mesa de 4+), +25 si ganás, mitad en mesa solo con bots. Nada comprado los multiplica.
- Pista gratis: monedas, título, emote, aura. Pista premium: monedas, título, emote, mesa, aura y dos ruedas. 9 cosméticos nuevos (`unlock.type = "season"`). Todo fijo y visible antes de comprar.
- Comprar premium es retroactivo a los niveles ya alcanzados. El reloj de fin de temporada se ve en la ventana (es un cierre real). Lo no reclamado se pierde al cambiar el mes.
- Archivos: `src/shared/SeasonPass.luau` (reglas puras), `src/server/Services/SeasonService.luau` (puntos, reclamo, productos), `MatchRewards.luau` suma los puntos, `Monetization.luau` (kinds `season` y `tier`, recibos idempotentes por PurchaseId), `Data.luau` (campo `sp` con reconcile), UI en `UI/MenuWindows.luau` (ventana "Season" con las dos pistas, reclamar, reclamar todo, comprar premium, saltar nivel) y botón con badge en `UI/Hud.luau`.
- Compras duplicadas: un segundo Premium en la misma temporada o un skip en el último nivel pagan monedas en vez de perderse (`Config.SeasonPass.duplicatePremiumCoins` / `maxTierSkipCoins`).

### Retención
| Punto | Estado | Dónde |
|---|---|---|
| 1. Bucle de segundos | Ya estaba | Core (`CoreService`, `Hud.coreProgress`), partida (`MatchHud`, `Fx`, `Audio`) |
| 2. Próxima meta visible | Agregado | Chip "goals" en `UI/Hud.luau`: trofeos a la próxima liga y puntos al próximo nivel de temporada. La barra de XP ya estaba |
| 3. Metas de sesión y largas | Ya estaba + agregado | Quests, ligas, leaderboards (`Leaderboard.luau`); ahora también season pass |
| 4. Volver mañana | Ya estaba (+ season) | Diario con racha (`Rewards.luau`), regalos por tiempo, códigos, grupo, eventos con reloj (`LiveEventService`, chip en Hud; DoubleXP cada 3 h, Chaos Weekend). Offline y "restock" no aplican a este juego, y no se inventó escasez |
| 5. Social | Ya estaba | Referidos (`Social.luau`), tableros en el mundo (`LobbyBuilder`), party de servidor. Anuncios de "hallazgos raros" y regalos no aplican (no hay drops) |
| 6. Primer minuto | Ya estaba | Tutorial con bonus (`Config.Tutorial`), tip "Jugá" y primera partida con bots |

Además: la pantalla de resultados muestra "Season points" ganados (`MatchHud.luau`, el panel creció de 370 a 414 px).

### Otros cambios
- Tienda: tarjeta que abre la ventana Season, línea "+N% extra" en cada bolsa de monedas calculada con los precios reales, etiqueta "Best value" pasó a CoinsMega, 6 columnas de monedas.
- 39 claves de idioma nuevas en los 12 idiomas (en/es/pt/fr/de/id/tr/ru/ja/ko/th/vi).
- `DESIGN.md` y `LANZAMIENTO.md` actualizados con precios y productos nuevos.
- Tests: `AutoTest` y `AutoTestClient` ahora cubren el flujo del pass (reclamo gratis, bloqueo premium, recibo, recibo repetido, reclamar todo). No se corrieron (requieren Studio).
- Pendiente de round 1 que era seguro en código: no había nada más que fuera solo código (íconos, audio e IDs dependen del dueño).

### Cómo lo verifiqué
```
rojo build (default, showcase, showcase_low, showcase_touch, test)  -> los 5 "Built project"
luau-lsp analyze src                                                -> sin salida (0 errores)
luau-lsp analyze tests/AutoTest*.luau (con test.project.json)       -> sin salida
luau tests/unit_core.luau                                           -> 1017 checks, 0 failures / UNIT CORE PASSED (antes 659)
luau tests/locale_check.luau                                        -> 12 idiomas con 431/431 claves / LOCALE CHECKS PASSED
```
Tests nuevos de `unit_core.luau`: `affectsMatch == false` explícito en cada pass y producto, kinds permitidos, precios recomendados, escalera de monedas, ancla honesta del Starter Pack, y toda la lógica del season pass (puntos, niveles, reclamo, doble reclamo, premium retroactivo, skip, tope, reset de temporada, cada cosmético alcanzable una sola vez).

### Qué mirar en Studio
- Ventana Season: que las 30 columnas scrolleen en horizontal, el badge del botón y que reclamar/reclamar todo actualicen la vista.
- Con IDs en 0, los botones de comprar avisan "coming soon". Probar con IDs reales en un place de test.
- Chip de metas en el HUD (esquina superior derecha, debajo del chip de evento): que no tape otros elementos en pantallas chicas y en touch.
- Panel de resultados (más alto ahora) y el menú de la izquierda (8 botones en 4 filas).
- Correr `test.project.json` para el playtest automático con los checks nuevos del pass.

### Pendiente
- Crear en el Creator Dashboard: CoinsMega, SeasonPass, SeasonTier y cargar los IDs en Config (pases existentes con los precios nuevos: Double Coins 199, Emote Pack 99).
- Pass de kill sound: requiere audios propios/licenciados.
- Subir íconos y audio (igual que en ronda 1).
- Revisar el balance del season pass con datos reales (puntos por partida, 60 por nivel).

## Ronda 3: ranuras de modelos

### Qué cambié
- Carpeta `ruleta-pvp/assets/models/` (con README en español) mapeada como `ServerStorage.ModelLibrary` en los 5 `*.project.json` (default, showcase, showcase_low, showcase_touch, test). Rojo ignora el README, la carpeta queda vacía en el build.
- `src/server/World/ModelSlots.luau`: `ModelSlots.spawn(slot, cf, targetSize, parent, fallback, {collide, maxParts})`. Si hay modelo (o variantes `slot_1`, `slot_2`..., elegidas por posición) lo clona, borra todo script, escala con `ScaleTo` para entrar en `targetSize`, apoya la base en `cf`, ancla todo y fija `CanCollide` según la primitiva. Si no hay, corre el fallback tal cual. Tope de 300 partes por ranura y 1000 en total (si se pasa, usa la primitiva y avisa).
- `src/shared/ModelFit.luau`: matemática pura (escala de ajuste, nombres de variantes, selector determinístico, presupuesto). Tests en `tests/model_slots.luau`.
- `LobbyBuilder.luau` cableado a 10 ranuras: `pylon`, `vat`, `crystal`, `lamp_post`, `arch_pillar`, `planet` (con primitiva) y `statue`, `planter`, `bench`, `floating_rock` (solo decoración, sin primitiva). No se tocó ninguna instancia con tag de gameplay (`TableRoot`, `PowerCore`, `Board`, podios, pantallas, etc.). Todo es del servidor: la ruleta la arma el cliente y no usa ranuras.
- Doc para el dueño: `docs/modelos/ruleta-pvp.md`.

### Cómo lo verifiqué
```
rojo build (los 5 project.json)           -> OK
luau-lsp analyze src                      -> sin salida
luau tests/model_slots.luau               -> 23 checks, 0 failures
luau tests/unit_core.luau                 -> 1017 checks, 0 failures
luau tests/locale_check.luau              -> LOCALE CHECKS PASSED
```
Prueba del swap: un `pylon.rbxmx` temporal (Model con Part y Script) apareció en `ServerStorage.ModelLibrary.pylon` del build; después lo borré.

### Qué mirar en Studio
- Con la librería vacía el lobby debe verse idéntico (solo aparece un Folder `Dressing` vacío en `World`).
- Con un modelo: que quede parado sobre el piso, escalado y mirando bien (estatua/banco/maceta miran al centro), que no tape los caminos ni los spawns, y que el Output avise si se borran scripts.
- El `server part budget` del playtest (`test.project.json`) si se cargan muchos modelos.
- Nota: el farol conserva la bola de luz primitiva arriba del modelo (a 12.6 studs).

## Ronda 4: UI arreglada con la vista previa

Todo verificado con `tools/uipreview` (capturas en `docs/previews/ruleta-pvp/`). Resultado: PC, laptop y tablet con 0 hallazgos; celular con 0 hallazgos en el HUD del lobby y del partido y, en las ventanas, solo quedan avisos `core-overlap` (ver "Qué queda").

### Qué arreglé
- **Escala del HUD en celular** (`src/client/UI/Root.luau`, `compute` y `Root.mountWindow`): en táctil ahora es `clamp(min(X/960, Y/420), 0.62, 1.1)` (antes salía ~0.55, ahora ~0.74 en un iPhone apaisado). No subí solo el número: rearmé el layout táctil en `Hud.luau`/`MatchHud.luau` para que entre. En PC la fórmula y el layout no cambian.
- **Ventanas en celular** (`Root.luau:mountWindow`, usado por `Windows.luau:75`): escala propia (1.0 si entra, como mínimo 0.7) y se recorta el alto de diseño para que nunca salgan de la pantalla (los cuerpos scrollean). Antes quedaban a 0.55 con botones de 19 px.
- **Botones táctiles** (`Theme.luau`, `Theme.button` + `Theme.TouchMin = 52`): en táctil ningún botón queda más bajo/angosto que 52 px de diseño (>= 44 px reales en ventanas). `KeepSize = true` lo saltea cuando el llamador ya lo dimensionó. Texto mínimo 12 px de diseño (`Theme.MinText`). `Theme.toggle` pasa de 44 a 62 de alto en táctil.
- **Lobby táctil** (`Hud.luau`): menú en 2 filas de 4 arriba al centro (antes sobre el joystick), metas bajo el perfil (antes se pisaban con el Power Core), Power Core bajo las monedas y con botones de 62; "+" de monedas de 17 a ~46 px reales; Auto-queue/Starter 112x66; panel de mesa más ancho con botones de 62. Las posiciones apiladas siguen la escala (`Hud.luau`, bloque `stack`) para que en tablet no se pisen.
- **Partido táctil** (`MatchHud.luau`): Leave/Auto-play 160x62, Emote 64, grilla de emotes 62, barra de espectador con botones de 62, botones de resultados 66, cartas de la mano 100x112 con texto de 14.
- **Season Pass** (`MenuWindows.luau`, `buildSeason`): los botones "Skip tier"/"Premium"/"Claim all" ya no tapan los textos (textos a 300 px de ancho, botones más angostos); en táctil la grilla de recompensas scrollea también en vertical (la fila premium quedaba cortada).
- **Play** (`MenuWindows.luau`, `buildPlay`): en táctil la columna de modos scrollea (Teams se salía de la pantalla) y el medallón ya no sale vacío: el ícono pasó de "▶" (glifo blanco sobre blanco) a "🎡" (mapeado al ícono `wheel` del pack).
- Alturas táctiles en Locker, Rewards, Quests, Ranking, Invite, Settings, Shop y Play (helper `tp(pc, touch)` en `MenuWindows.luau`) para que los botones de 52 no se pisen con lo de al lado.
- **Plurales** (`Locale.luau`, `Locales/*.luau`): `Locale.t` usa la clave `<clave>.one` cuando `args.n` es singular (1 en en/de/es/fr/pt; 1, 21, 31 pero no 11 en ru) y si el idioma no la tiene cae a la clave normal. Agregué `.one` en en/de/es/fr/pt (y ru donde hacía falta) para `goal.league`, `goal.season`, `season.next`, `season.claimed_n`, `unlock.wins`, `quest.win`, `quest.chaos`, `quest.teams` (antes "Win 1 matches", "1 points to tier 2"). `rank.record` lo reescribí sin plural ("Wins: 1 / Matches: 1 / Best streak: 1") en en/de/es/fr/id/pt/ru. `tests/locale_check.luau` acepta claves `.one` opcionales y tiene 6 chequeos nuevos de plurales.

### Antes / después (en palabras)
- `mid-phone`: antes todo a 0.55, menú sobre el joystick, metas tapadas por el Power Core, 16 hallazgos; ahora el HUD se lee, el menú está arriba, nada bajo el joystick ni el salto, 0 hallazgos.
- `mid-pc-season`: los botones ya no tapan "Each match: +45 points...".
- Ventanas en celular: de ~396x242 px reales con botones de 20-30 px a ventanas de ~700x280 con botones de 44+ px.

### Qué queda
- Ventanas en celular: sigue saliendo `core-overlap` (med/low) porque el contenido de la ventana pasa por la zona del joystick. La ventana es modal, tapa todo y sus botones reciben el toque antes que el joystick, así que lo dejé. Si en Studio se siente mal, se puede correr la ventana unos px a la derecha.
- El panel de resultados del partido y los carteles grandes no salen en las capturas del fixture (solo el partido en curso): no los pude mirar en celular. Les subí los botones a 66 pero hay que verlos.
- El evento en vivo (chip bajo las monedas) no aparece en el fixture; su posición sigue la escala pero conviene verlo.
- `rank.record` y las claves `.one` de ja/ko/th/vi/id/tr no existen a propósito (no tienen plural). El ruso solo cubre la forma "1, 21, 31" (2-4 sigue sin forma propia: "2 трофеев").
- Hallazgo de la herramienta: `mid-*-icons` no muestra diferencia con `mid-*` salvo los íconos; sin problemas.

### Qué confirmar en Studio (celular real)
- Que el menú arriba al centro no se choque con los botones de Roblox (R/chat/...) en pantallas con notch.
- Que las ventanas (Play, Shop, Season, Locker) se vean completas y scrolleen bien con el dedo, y que los textos de 12-14 px se lean.
- El medallón de Play con la rueda (con los íconos subidos se verá la imagen `wheel`).
- Que el tamaño del HUD en un teléfono chico (escala mínima 0.62) siga usable.

## Ronda 5: ritmo de progresión

Armé `sim/pacing_sim.luau` (modelo en `sim/PacingModel.luau`, se corre con `luau sim/pacing_sim.luau` desde `ruleta-pvp/`) y `tests/pacing_test.luau` (falla si un hito sale de su ventana). El sim usa los módulos reales: `MatchCore` + `BotBrain` juegan el asiento humano (de ahí salen puestos, turnos y stats por partida), y `Progression`, `SeasonPass`, `Quests` y `Config` ponen todos los números de premios, precios y desbloqueos. Jugador free: toca el Power Core, compra el cosmético de monedas más barato que puede pagar, reclama diario, regalos de sesión, misiones (y persigue las de chaos/teams) y tiers gratis del pase; sesión de 75 min el día 0 y 25 min por día después; 40 jugadores con semilla, mediana y p90.

### Hitos antes / después (mediana, p90 entre paréntesis)
| Hito | Antes | Después | Objetivo |
|---|---|---|---|
| Primera moneda (Power Core) | 8 s | 8 s | < 10 s |
| 1ª partida pagada | 4,1 min | 4,1 min | < 6 min |
| 1ª compra (emote 300) | partida 1 | partida 1 | partidas 2-3 |
| 3ª compra | 13 min (21) | 11 min (16) | < 30 min |
| Nivel 2 | 8,0 min | 5,3 min | < 10 min |
| Nivel 5 (Auto Charge) | 19,9 min | 11,3 min | < 30 min |
| Nivel 10 | día 3 | 38 min | < 2 h |
| Tier 1 del pase | 10 min | 23 min | < 30 min |
| Pase completo (25 min/día) | día 9 | día 23 (p90 25) | día 18-31 |
| Toda la tienda de monedas | día 7 | día 22 | día 14-35 |
| Mayor tramo sin nada nuevo en la 1ª hora | 10,3 min (p90 12,2) | 10,8 min (p90 14,8) | <= 12 (p90 <= 17) |
| Nivel al día 7 / 30 | 16 / 34 | 27 / 55 | sigue subiendo |

### Qué cambié y por qué (todo en `Config.luau` salvo una fórmula)
- **Pase de temporada**: `pointsPerTier` 60 -> 140. Con 60 un jugador de 25 min/día lo terminaba en 9 días (el pase es mensual y tiene que durar 3-4 semanas). Ahora ~140 partidas promedio. El precio del salto de tier (Robux) no se tocó. `DESIGN.md` actualizado.
- **Precios en monedas** (subí el techo, bajé un poco el piso): w_neon 600->500, t_carbon 700->700, ti_lucky 800->900, w_candy 900->1200, a_sparks 1000->1600, t_bubblegum 1100->2200, f_rocket 1200->3200, a_hearts 1400->5500, w_lava 2200->9000, f_freeze 2600->12000, a_flames 3200->16000. Los dos emotes de 300 quedan igual (primera compra en la partida 1). Antes la tienda entera se vaciaba en una semana; ahora dura ~3 semanas y hay una compra cada ~10-15 min en la primera hora.
- **Regalos de sesión** (`Gifts`): 5/10/15/25/40/60 min -> 3/8/15/24/38/55 min (mismos premios). Primer regalo con la primera partida y un regalo cada 7-14 min en la hora 1.
- **XP de nivel** (`Progression.xpForLevel`): `100 + 40*(L-1)` -> `45 + 15*(L-1)`, y `Config.LevelCoins` 100 -> 60 (por nivel, +10 por nivel como antes). El nivel 2 cae en las primeras 1-2 partidas y hay subida de nivel cada 2-3 partidas hasta el nivel 10; bajé las monedas por nivel para que la inflación de subidas rápidas no se coma la tienda.
- **Desbloqueos por victorias**: `ti_survivor` 3 -> 2 victorias y `e_clap` 5 -> 4 (un hito nuevo antes en la hora 1).
- **Tests** (`tests/unit_core.luau`): los 3 tests de XP usaban 100/140 literales; ahora usan `xpForLevel` (cambio intencional: primer nivel barato). El test "pase completo en <= 100 partidas" pasó a "entre 100 y 150" (el pase ahora es de ~140, pensado para un mes).

### Límites del sim
- Duración de partida modelada (no medida): cuenta turnos reales del motor y los tiempos de `Config.Timing`/`Wheel`, pero el tiempo humano por turno (4 s decidiendo + 2 s girando), caminar a la mesa (12 s) y dejar la mesa 5 s después de caer son supuestos. Da ~3,4 min por partida; si en Studio dura distinto, los hitos en minutos se escalan.
- El humano juega como `BotBrain` (puestos de un jugador decente, sin skill de frenada); 60% de las mesas con un 2º humano (el resto paga la mitad de puntos/trofeos). Sin duelos (necesitan amigo).
- Sin eventos en vivo (DoubleXP), códigos ni Starter Pack: es el peor caso free. Power Core: 4 toques/s a mano y solo en el lobby.
- Los "hitos" se cuentan al final de cada partida (el jugador mira el HUD entre partidas), por eso el tramo máximo sin novedades tiene granularidad de ~3,4 min; con partidas así, "nunca más de 10 min" equivale a 3 partidas seguidas sin nada y el piso realista es ~11-12 min en mediana. Quedan huecos hacia el minuto 55-75 (se acaban los regalos y los niveles se espacian); si se quiere más densidad ahí, el palanca es un 7º regalo (la fila de regalos de `MenuWindows` hoy entra con 6) o tiers más baratos al principio del pase (requiere curva no lineal en `SeasonPass`).
- Sin ramas de tienda elegidas por gusto: el jugador compra siempre lo más barato (maximiza la cadencia). Sin reset mensual del pase en el sim (asume instalación a principio de mes). Sin nivel 100 (~meses) ni trofeos de liga campeón.

## Ronda 7: seguridad

Auditoría de todos los `Remotes.handle`, el `CoreTap`, compras, DataStore y fugas, asumiendo un cliente exploiter. Helper nuevo y puro: `src/shared/Guard.luau` (validadores, token bucket, cooldowns, lockout por fallos, `sanitize` de NaN/inf, `RepeatLimiter`). Tests: `tests/security_test.luau` (60 checks). Comportamiento del jugador legítimo igual, salvo lo marcado como "cambio visible".

### Vulnerabilidades

| Sev. | Dónde | Cómo se explotaba | Cómo se arregló |
|---|---|---|---|
| Alta | `Monetization.luau` `processReceipt` (~110-160) | Con el perfil no persistente (DataStore caído) devolvía `PurchaseGranted` sin guardar: Robux cobrados y compra perdida. Y si el primer save fallaba, el reintento de Roblox encontraba el PurchaseId en memoria y devolvía `PurchaseGranted` sin haber guardado nunca | Perfil no persistente => `NotProcessedYet` (salvo Studio). El reintento también guarda (con reintentos y backoff) y solo confirma si guardó. PurchaseId validado |
| Alta | `MatchRunner.luau` `pay` (~120-175) | Se pagaba con `humanCount` del arranque: una cuenta alt que se sienta y se va dejaba al principal con trofeos/puntos de pase "con humanos" completos. En duelo entre dos cuentas, el que se iba regalaba la victoria: 80 monedas, 80 xp y 18 trofeos cada ~20 s | `humans` = humanos que no abandonaron. Victoria por abandono sin bots ("no contest") no paga. Mismo grupo de humanos más de 8 partidas/hora o 40/día paga como práctica (monedas/xp x0,25, trofeos y pase a la mitad, no cuenta para el tablero) |
| Alta | `Data.luau` `save`/`release` | Un solo intento: un error transitorio al salir o en `BindToClose` perdía el progreso, y `release` tiraba el perfil igual. Perder el lock (otro server) fallaba en silencio y se seguía jugando sin guardar | Guardados críticos (salida, compras, cierre) con 4 intentos, backoff, esperan presupuesto y un guardado por jugador a la vez. Lock perdido => se deja de escribir y se expulsa con mensaje para reentrar |
| Alta | `MatchRunner.luau` `pay` + `Tables.luau` `finishMatch` | Un personaje parado en una mesa con Auto-cola: el server jugaba por él (AFK) y le pagaba y lo dejaba sentado para la siguiente, indefinido | Seat que el server tuvo que jugar por AFK (2 turnos vencidos, no el toggle propio) no cobra y se levanta al terminar. **Cambio visible** (jugador AFK real) |
| Media | `Remotes.luau` (todo `Request`) | Sin cooldown por acción: `RedeemCode` y `JoinPrivate` (4 letras) se podían adivinar a 12 req/s; `Challenge` spameaba popups; `ClaimGroupGift`/`ShareLink` (web call, prompt) a ritmo máximo | Cooldown por acción y jugador (`cooldowns` en Remotes). `RedeemCode`: 6 fallos en 60 s bloquean 2 min. `JoinPrivate` exige 4 letras |
| Media | `Remotes.luau` | Payloads con strings enormes, NaN/inf, tablas gigantes o anidadas llegaban a los handlers | `payloadOk`: tope de strings (128), entradas (64), sin NaN/inf, sin Instances ni funciones. Handlers con `Guard.isInt/isString/isList/isUserId` (Act, ClaimSeason, ClaimQuest, ClaimGift, Challenge, SetEmotes, SetSetting, SetLanguage, JoinTable, GetMatch...) |
| Media | `MatchRewards.luau`, `Leaderboard.luau` | Ranking de victorias (histórico y semanal) farmeable contra bots, 24/7 | `pvpWins`: solo cuentan victorias contra otros humanos (migración v1->v2 la inicializa con las victorias actuales, nadie baja). `wins` sigue contando para desbloqueos y quests. **Cambio visible** (tablero) |
| Media | `MatchRewards.luau` | Trofeos ilimitados contra bots (la mitad, pero sin techo) | `Config.PracticeTrophyCap = 500`: mesas de bots no suben trofeos más allá de platino |
| Media | `Leaderboard.luau` `pushScores` | `SetAsync` ciego: un push viejo o de otro server bajaba el puntaje; sin chequeo de presupuesto | `UpdateAsync` que solo sube, valores acotados, salta si el presupuesto es bajo |
| Media | `Data.luau` | Sin sanitizar al cargar/guardar (NaN/inf podían persistir); sin migración ni protección contra datos de una versión más nueva | `Guard.sanitize` en `reconcile` y antes de cada escritura; `CURRENT_VERSION = 2` con `migrate`; perfil de versión más nueva => sesión sin guardar (no se pisa) |
| Media | `Social.luau` `onMatchFinished` | El invitador cobraba 500 monedas (x25) cuando el invitado terminaba una sola partida contra bots (cuentas alt) | Se acredita a las 3 partidas (`Config.Referral.matchesToCredit`) |
| Media | `Data.luau` `startAutosave` | Todos los guardados en el mismo instante, sin mirar presupuesto | Escalonados, y se saltea el autosave si `GetRequestBudgetForRequestType` es bajo |
| Baja | `Remotes.luau` | Un request que llegaba tras `PlayerRemoving` recreaba `budget` del jugador (fuga) | Chequeo `player.Parent` y tablas de claves débiles |
| Baja | `Monetization.luau` `PromptGamePassPurchaseFinished` | Recreaba `State.passes[player]` de un jugador ya salido (fuga) | Solo si el jugador sigue y tiene sesión |
| Baja | `Leaderboard.luau` | `nameCache` sin tope | Tope de 500 |
| Baja | `Tables.luau` Challenge/AnswerChallenge/CreatePrivate | No exigía `State.ready` del que desafía ni validaba el userId; `CreatePrivate` sin ready | Validado (`isUserId`, ready en ambos lados) |
| Baja | `Monetization.luau` `loadPasses` | Un fallo del web call dejaba al dueño del pase sin pase toda la sesión | 3 intentos con espera |
| Baja | `Tables.luau` `startMatch` | En un duelo por desafío, si el rival se iba en la cuenta regresiva el otro jugaba el duelo contra un bot con premio de duelo | El duelo se cancela y se levanta a los presentes |
| Baja | `CoreService.luau` | (Ya tenía bucket) | Pasado a `Guard.takeUpTo`: 8 taps/s, ráfaga 6, NaN/inf descartados; sigue exigiendo estar en el lobby y a rango |

Total arreglado: 4 altas, 8 medias, 7 bajas.

Revisado y sin cambios (estaba bien): `Act` (turno, mesa propia y fase vía `where[player]`, `m.spinner` y `awaiting`; objetivos con `validTarget`, mágnet/pase sobre vivos), el resultado de la ruleta (semilla del server; el cliente solo manda cuándo frenó, acotado a 0,2 s atrás y nunca antes de `minSpin`), mano e identidad (`Hand` solo al dueño, `draw`/`stolen` públicos sin la carta, el Oráculo solo a su dueño), compras de cosméticos y reclamos (marcan antes de pagar), `GetMatch` (solo info pública).

### Tests / verificación
- `luau tests/security_test.luau`: validadores (NaN/inf/huge/tipos), bucket (flood acotado a rate*T+burst, reloj hacia atrás), cooldown, lockout de adivinación, sanitize (NaN, inf, ciclos, profundidad), `RepeatLimiter` (colusión limitada, amigos y públicas no), economía de práctica.
- `tests/AutoTestClient`: `req` espera y reintenta cuando el server responde `slow_down` (cooldowns nuevos); el comando `boards` del server de test fija `pvpWins >= 1`. No se pudo correr el playtest en Studio acá.

### Lo que queda
- Auto-jugar + Auto-cola con el toggle propio (no AFK) sigue pagando sin supervisión; lo frena el kick por inactividad de Roblox (bypasseable con input falso). Habría que poner un tope de partidas contra bots por hora si se quiere cerrar.
- Colusión entre dos cuentas controladas por la misma persona queda limitada (8 partidas/h y 40/día a pago completo), no eliminada; no hay forma de saber que son la misma persona.
- Duelo privado contra bot (`CreatePrivate` + modo duelo + bots) sigue permitido (lo usa el test y la UI): paga el premio de duelo con trofeos a la mitad.
- `wins` (desbloqueos por victorias, quest "win") sigue contando victorias contra bots; solo los tableros usan `pvpWins`.
- Los regalos de sesión se reinician por server (reentrar cada 3 min rinde parecido a una sesión larga, no se tocó).
- Crédito de referido fire-and-forget: si falla el `UpdateAsync` del invitador el crédito se pierde (queda en el log).
- `tests/unit_core.luau:761` tiene una advertencia de tipos previa (no afecta a `src`).

## Ronda 8: primera sesión y game feel

### Recorrido de los primeros 2 minutos
**Antes:** el jugador nuevo aparece con el HUD completo (8 botones de menú, metas, Núcleo de energía, Auto-cola), un cartelito "Juega tu primera partida" sin animación, y al apretar JUGAR se abre una ventana con modos que hay que elegir. Dentro de la partida solo había frases largas de 5-9 s ("Tu turno. Elegí a quién zapear y apretá GIRAR...") que se tapan entre sí. No había pantalla de carga propia. Capturas: `docs/previews/ruleta-pvp/r8-before/`.

**Después:**
1. 0-2 s: pantalla de carga de marca (Spin Showdown, rueda girando, barra, tip rotativo). Tope duro de 6 s, nunca cuelga.
2. HUD mínimo: solo perfil, monedas y JUGAR. El menú, metas, Auto-cola, evento y Núcleo entran con un pop recién al terminar la primera partida.
3. Un cartel "Toca JUGAR" + flecha que rebota + borde que pulsa sobre el botón. Un toque y va directo a la partida guiada (mesa clásica con bots; el server ya la fuerza). Si falla, se abre la ventana Jugar para no trabarse.
4. En la partida: una sola cosa por vez, con 2-4 palabras y flecha: "Elegí un rival" (apunta a los rivales), "Ahora GIRAR", "¡FRENÁ!" (apunta al botón), "Mirá la rueda" mientras juegan otros, "Eliminado! Ahora el premio".
5. El momento "wow" (primer giro/eliminación) ya estaba bien armado (finisher, cámara, grading); no toqué tiempos. Lo que sumé es la recompensa: pantalla de resultado con números que suben (monedas, XP, trofeos, bono de tutorial) con pop por fila, y el HUD recupera menú/metas con pop.

### Qué agregué
- `src/shared/Tutorial.luau` (puro): el paso es una función del estado visible (`done`, sentado, en partida, mi turno, fase, objetivo elegido, eliminado). No guarda progreso propio, así que no se puede trabar, retoma solo después de reentrar (`tutorialDone` sigue en el perfil) y se recupera si falta el objetivo (después de 2,5 s queda solo el texto). Tracker con "Saltar tutorial" (por sesión; reentrando vuelve si no terminó la primera partida).
- `src/shared/LoadingFlow.luau` (puro): progreso por etapas ponderadas, mínimo 1,2 s, máximo 6 s, una etapa que falla cuenta como hecha, rotación de tips.
- `tests/tutorial_test.luau`: 57 checks (recorrido completo, todas las combinaciones de contexto, recuperación, carga).
- `src/client/UI/Guide.luau`: flecha, borde pulsante, línea corta, botón Saltar. Con "Sacudida" apagada la flecha no rebota; con "Destellos" apagados el borde no pulsa.
- `src/client/UI/Loading.luau` (autocontenida, con watchdog y pcall en todo) + `src/first/Boot.client.luau` en ReplicatedFirst (quita la pantalla por defecto de Roblox y pone un telón de marca que se autodestruye a los 7 s). Agregué `ReplicatedFirst` a los 5 `*.project.json`.
- `src/client/UI/Moments.luau`: tarjeta de subida de nivel (confeti, "¡SUBISTE DE NIVEL!") y de desbloqueo con color de rareza (rare/epic/legendary; mayor ráfaga y tiempo según rareza; common sigue siendo toast). Una sola tarjeta, sin apilar. Sonido por `Audio.play("win")` (ids vacíos, silencioso hasta que el dueño cargue ids).
- Juice: `Theme.roll` (contador que sube con easing), monedas del HUD que suben, barra de XP y barra del Núcleo con tween, Núcleo con tono que sube en cada toque, "+1" flotante (pool de 8, apagado en lite), confeti al cobrar carga, filas de resultado que suben.
- Locales: 15 claves nuevas en los 12 idiomas (`tut.step.*`, `tut.skip`, `loading.*`, `hud.level_up`, `reveal.new`); acorté `tut.intro`/`tut.eliminated` en en/es y saqué de Popups las líneas de decidir/girar (las reemplaza la guía).
- Playtest (`tests/AutoTestClient`): el chequeo del cartel "PlayTip" ahora verifica que la guía apunte a JUGAR y que el HUD sea mínimo.

### Verificación
Build `default.project.json` OK (y test/showcase*), `luau-lsp analyze src` sin salida, unit_core 1019, security 60, pacing 17, model_slots 23, locale_check, check_keys y tutorial_test pasan; preview con 0 errores de runtime. Capturas: `docs/previews/ruleta-pvp/r8-after/` (nuevo pc/phone, carga pc/phone, partida phone, ventana Jugar).

### Qué mirar en Studio
- El simulador no aplica `UIScale` a `AbsoluteSize`: en la captura el borde pulsante sale corrido del botón JUGAR. En Studio tiene que calzar justo (la guía usa `AbsolutePosition/Size`). Mirar también el modo "izquierda" de la flecha sobre GIRAR/FRENAR y el borde sobre la fila de rivales; la captura no llegó a mi turno.
- Pantalla de carga: que el telón `SpinBoot` de ReplicatedFirst se reemplace sin parpadeo y que no tape el HUD pasados ~2 s en conexión lenta.
- Sacudida de cámara: sigue solo dentro de la arena (la cámara del lobby es la de Roblox); no agregué temblor en el lobby.
- Tarjetas de nivel/desbloqueo con un cosmético épico/legendario y con "Sacudida" apagada.

### Pendiente
- "Saltar tutorial" es solo de sesión; si se quiere permanente haría falta un flag en el server.
- Sin ids de audio: los cues nuevos (`win`) son silenciosos hasta cargarlos en `Config.Audio.sfx`.

## Ronda 10: arreglos del playtest

- Regalos por minutos: ahora se guardan en el perfil (`giftState = {day, played, claimed}`, dia UTC). Logica pura en `src/shared/Gifts.luau` (`roll`, `startFor`, `playedAt`); `State.loadGifts` al cargar el perfil y `State.syncGifts` (snapshot, reclamo, salida) guardan el tiempo jugado hoy. Reentrar el mismo dia no permite reclamar de nuevo y el reloj continua; un dia UTC nuevo reinicia todo. Saves viejos: default seguro via reconcile + `Gifts.roll`. Tests en `tests/unit_core.luau`.
- "Jugar de nuevo": el cliente siempre manda `QuickPlay`. El servidor (`Tables.releaseFinished`) suelta la mesa en cuanto salen los resultados (`runner.resultsOut`, puesto en `MatchRunner` al emitir `ended`), tambien en `JoinTable`. Si el jugador ya espera en una mesa (auto-cola) `QuickPlay` responde ok sin error.
- `not_your_turn` con carta PASS/SKIP: `Director.H.card` apaga `myTurn`/fase del HUD apenas el jugador juega esa carta, hasta el evento `turn`.
- Playtest (new y mid): veredicto OK, sin rechazos de remotes.
