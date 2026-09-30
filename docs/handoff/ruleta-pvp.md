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
