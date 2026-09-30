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
