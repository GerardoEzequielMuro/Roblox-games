# Playtest de ruleta-pvp

- Comando: `python3 tools/uipreview/preview.py ruleta-pvp --playtest --minutes 30 --seed 1`
- Fecha: 2026-10-01 | estado inicial: `new` | tiempo virtual jugado: 30.2 min | reales: 18 s | rejoins del bot: 1
- El tiempo es virtual (scheduler propio de la herramienta); el bot juega por los remotes/funciones cliente reales del juego. Es una **aproximacion** de Roblox: ver "Que simula la herramienta" al final.

## Resumen (espanol)

**Veredicto: ERRORES**

- Errores de Luau unicos (del juego): **0**
- Warnings unicos: **0**
- Remotes rechazados por el servidor sin que el bot lo esperara: **6** llamadas en 2 acciones
- Invariantes violados / problemas de guardado / recibos / DataStore: **2**
- Estados trabados > 60 s virtuales: **0**
- Hilos que quedaron esperando para siempre (WaitForChild sin hijo, etc.): **0**
- Avisos de error que el servidor le mostro al jugador (Notify/Toast kind=error): **0**
- APIs de Roblox que el simulador no implementa y otros avisos del motor simulado: **0** (ver seccion "Avisos del simulador")
- Instancias vivas en el DataModel: 6384 (t=0:39) -> 4728 (t=30:09); partes 1461 -> 1580; GUI 1721 -> 1045
- Acciones del bot: aborted=1, afkTurns=2, botTurnsSeen=118, brakes=13, cards=9, eliminated=2, ended=6, leftMid=1, matches=5, maxBotTurnGapAfter=landed, maxBotTurnGapS=8, maxGapAfter=decide, maxGapS=14, playAgainNoop=3, playAgainOk=0, releasedAfterEnded=9.1, resultAfterEnded=3.8, results=6, spins=7, targets=7, wins=4

## Analisis del revisor (a mano)

**Hallazgos reales (con evidencia de esta corrida)**

1. **"Jugar de nuevo" no hace nada si se aprieta dentro de los ~7 s posteriores a que aparece el resultado** (bug de cliente/servidor, severidad media: el jugador vuelve al lobby sin partido y tiene que apretar JUGAR otra vez). Reproducido en cada partido terminado, apretando el botón entre 1,5 y 3 s después de que aparece la pantalla de resultado.
   - `src/client/Main.client.luau:93-99`: `MatchHud.onPlayAgain` esconde el HUD y **solo llama `QuickPlay` si `Net.get("table")` es nil**.
   - Pero el servidor no suelta la mesa hasta que `MatchRunner` termina su pausa final: `src/server/Services/MatchRunner.luau:198` (`self:wait(T.ending)`, `Config.Timing.ending = 9`, `src/shared/Config.luau:152`) y después `Tables.finishMatch` (`src/server/Services/Tables.luau:315-352`, `MatchFlow.afterMatch` devuelve "leave" en mesas públicas) hace `Tables.leave` y recién ahí el estado del cliente pierde `table`.
   - El cliente muestra el resultado antes de eso: `src/client/Arena/Director.luau:849` (+3,2 s si ganó, +1,6 s si perdió, contado desde el evento `ended`). Medido: resultado visible a +2,1 s (hasta +3,8 s) del `ended`, mesa liberada a +9,1 s. Ventana muerta de ~5 a 7 s.
   - Arreglo sugerido (para la ronda de arreglos, no se tocó): en `onPlayAgain` mandar siempre `QuickPlay` (el servidor ya contesta `msg.already_seated` si todavía está sentado; reintentar al llegar el snapshot sin mesa) o hacer que el servidor suelte la mesa en cuanto manda `ended`.
2. **Regalos por minutos de sesión farmeables reentrando**: `State.giftsClaimed` (`src/server/Services/State.luau:32`) vive solo en memoria de la sesión y `Rewards` (`src/server/Services/Rewards.luau:83-100`) lo consulta; no se guarda en el perfil. Después de salir y volver a entrar, los regalos de `Config.Gifts` (60/120/250/400/700 monedas) vuelven a estar disponibles (el bot lo comprueba: lo reclamó antes y después del rejoin). Mismo patrón en los otros 5 juegos. Es de diseño, no un crash, pero rejoin-farmear es trivial.
3. **Menor, visto en una versión previa del bot**: después de jugar la carta PASS ("otro gira") el cliente sigue mostrando GIRAR / elegir objetivo hasta que llega el evento `turn` (~`cardFx` = 1,3 s después); si el jugador aprieta ahí, el servidor contesta `msg.not_your_turn` (8 rechazos `Act` en esa corrida). Solo un toast de error, sin consecuencias.

**Sobre el "congelamiento en el turno de un bot" visto en la captura estática: es un artefacto de la herramienta (o de mirar una foto), no un bug del juego.**
- Se jugaron 5 a 7 partidos completos por corrida (clásico, caos y equipos, contra bots, incluyendo uno con el jugador AFK dos turnos, uno abandonado a mitad y uno tras reentrar) y el vigilante de "stuck" (60 s sin eventos del servidor ni cambio de fase/turno en el cliente) **no saltó ni una vez**. El bot vio ~120 turnos de bots; el hueco más largo entre dos eventos `Match` de un turno de bot fue de 8 s (`landed` -> siguiente: `landPause` 1,1 s + `effect` 2,2 s + pausas), y el único hueco de 14 s es el reloj de decisión del propio jugador AFK (`Config.Timing.decide`).
- Con el humano completamente ocioso (diagnóstico aparte de 150 s) la secuencia fue siempre `decide` (1,4-2,8 s) -> `spinning` (~3,5 s) -> `landed`/`hit`/`elim` -> siguiente turno: un turno de bot completo dura ~14-15 s virtuales y el contador de eventos del servidor sube todo el tiempo.
- La captura estática (`docs/previews/ruleta-pvp/mid-pc-match.png`) se saca ~27 s después de `QuickPlay` (cuenta atrás de 12 s + 4 s de intro): cae justo en el turno de un bot (Echo) mientras se muestra su carta ROBAR; es una foto de un instante normal del partido, y en ese entorno no hay 3D (la ruleta no se dibuja), por eso parece parado.
- Lo que sí hace falta mirar en Studio, porque la herramienta no lo ve: la cámara/animación de la ruleta (no hay 3D) y el pacing real con latencia.

**Qué se probó**: partidos completos hasta el resultado en los tres modos públicos (el bot juega por `MatchHud.press`/`pickTarget`/botones de cartas y de resultado), AFK 2 turnos, abandonar a mitad (`MatchHud.onLeave`), tienda (productos, pase, compra cancelada), cosméticos (comprar y equipar), regalos, misiones, ajustes, rejoin.

## Que logro el bot (timeline)

| t (virtual) | coins | elims | level | matches | streak | trophies | tutorialDone | wins | xp |
|---|---|---|---|---|---|---|---|---|---|
| 0:09 (start) | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2:09 | 100 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| 4:09 | 100 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| 6:39 | 250 | 3 | 2 | 1 | 1 | 12 | 1 | 1 | 57 |
| 8:39 | 250 | 3 | 2 | 1 | 1 | 12 | 1 | 1 | 57 |
| 10:39 | 410 | 3 | 4 | 2 | 0 | 13 | 1 | 1 | 28 |
| 13:09 | 410 | 3 | 4 | 2 | 0 | 13 | 1 | 1 | 28 |
| 15:09 | 3740 | 3 | 5 | 3 | 1 | 22 | 1 | 2 | 88 |
| 17:10 | 3160 | 3 | 6 | 3 | 1 | 22 | 1 | 2 | 83 |
| 19:40 | 3200 | 3 | 6 | 4 | 0 | 23 | 1 | 2 | 113 |
| 21:40 | 3200 | 3 | 6 | 4 | 0 | 23 | 1 | 2 | 113 |
| 23:54 | 2300 | 3 | 6 | 4 | 0 | 23 | 1 | 2 | 113 |
| 26:24 | 2300 | 3 | 6 | 4 | 0 | 23 | 1 | 2 | 113 |
| 28:24 | 2300 | 3 | 6 | 4 | 0 | 23 | 1 | 2 | 113 |
| 30:09 (end) | 1750 | 5 | 8 | 5 | 1 | 35 | 1 | 3 | 10 |

Hitos:

- 0:09 lobby ready
- 0:09 claimed daily
- 0:24 match 1 seated
- 4:35 match 1 result: place 1/5 classic coins +110 xp +102 trophies +12
- 4:52 bought cosmetic e_cool
- 4:53 match 2 seated
- 8:50 match 2 eliminated (keeps watching): place 4/6 chaos coins +40 xp +46 trophies +1
- 9:40 match 2 result: place 4/6 chaos coins +40 xp +46 trophies +1
- 9:46 bought cosmetic e_cry
- 9:47 match 3 seated
- 14:40 match 3 result: place 1/6 teams coins +80 xp +80 trophies +9
- 14:57 bought cosmetic w_neon
- 15:09 match 4 seated
- 15:46 leaves mid match
- 15:49 bought cosmetic t_carbon
- 15:50 match 5 seated
- 17:29 match 5 eliminated (keeps watching): place 6/6 chaos coins +40 xp +30 trophies +1
- 22:34 match 5 result: place 6/6 chaos coins +40 xp +30 trophies +1
- 22:39 bought cosmetic ti_lucky
- 22:40 rejoin: leaves (mid)
- 22:54 rejoin ok: profile reloaded identical
- 22:55 match 6 seated
- 29:34 match 6 result: place 1/5 classic coins +220 xp +102 trophies +12
- 29:52 bought cosmetic w_candy
- 29:53 match 7 seated
- 30:09 match 7 ended without a result screen: stopped
- 30:09 bot script finished
- 30:19 late receipt for a player that left -> NotProcessedYet

## Errores de Luau

Ninguno.

## Avisos del simulador

Ninguno.

## Warnings

Ninguno.

## Remotes rechazados inesperadamente

| remote:accion | llamadas | ok | rechazos | motivos |
|---|---|---|---|---|
| Request:Act | 36 | 32 | 4 | msg.not_your_turn x4 |
| Request:ClaimDaily | 3 | 1 | 2 | msg.daily_tomorrow x2 |

Ejemplos de `Request:Act`: `t=944 Act(kind=target,target=b1_2) -> msg.not_your_turn`; `t=945 Act(kind=spin) -> msg.not_your_turn`; `t=1407 Act(kind=target,target=b1_7) -> msg.not_your_turn`; `t=1407 Act(kind=spin) -> msg.not_your_turn`

Ejemplos de `Request:ClaimDaily`: `t=897 ClaimDaily() -> msg.daily_tomorrow`; `t=1791 ClaimDaily() -> msg.daily_tomorrow`


## Invariantes, trabas, guardado, recibos

- **Posible bug del juego (detectado por el bot)** t=4:50 x3: 'Play again' pressed 2.6 s after the result screen appeared (the server still had me at the table: true) ends in the lobby without a new match: Main.client.luau:96 onPlayAgain only calls QuickPlay when Net.get('table') is nil, but the table is not released until MatchRunner finishes T.ending (9 s) after the 'ended' event (`ruleta-pvp/src/client/Main.client.luau:96 < ruleta-pvp/src/server/Services/MatchRunner.luau:198 < ruleta-pvp/src/server/Services/Tables.luau:327`)
- **Posible bug del juego (detectado por el bot)** t=22:54: the session gifts (Config.Gifts, 'minutes since joining') are not saved: after rejoining the 3 claimed gifts are claimable again (State.giftsClaimed is per session, never in the profile) (`ruleta-pvp/src/server/Services/State.luau:32 < ruleta-pvp/src/server/Services/Rewards.luau:83`)

## Trafico de remotes

| remote:accion | llamadas | ok | rechazos inesperados | rechazos provocados | max s |
|---|---|---|---|---|---|
| Request:Act | 36 | 32 | 4 | 0 | 0 |
| Request:Buy | 6 | 6 | 0 | 0 | 0 |
| Request:ClaimDaily | 3 | 1 | 2 | 0 | 0 |
| Request:ClaimGift | 4 | 4 | 0 | 0 | 0 |
| Request:ClaimQuest | 3 | 3 | 0 | 0 | 0 |
| Request:Equip | 4 | 4 | 0 | 0 | 0 |
| Request:GetBoards | 32 | 32 | 0 | 0 | 0 |
| Request:GetState | 2 | 2 | 0 | 0 | 0 |
| Request:GetTables | 2 | 2 | 0 | 0 | 0 |
| Request:LeaveTable | 4 | 4 | 0 | 0 | 0 |
| Request:QuickPlay | 7 | 7 | 0 | 0 | 0 |
| Request:SetSetting | 18 | 18 | 0 | 0 | 0 |

RemoteEvents: AskNotifications (srv->cli 1, cli->srv 0), Hand (srv->cli 126, cli->srv 0), LevelUp (srv->cli 7, cli->srv 0), LiveEventUpdate (srv->cli 2, cli->srv 0), Match (srv->cli 711, cli->srv 0), Notify (srv->cli 3, cli->srv 0), Result (srv->cli 5, cli->srv 0), State (srv->cli 34, cli->srv 0), Tables (srv->cli 24, cli->srv 0), Unlock (srv->cli 6, cli->srv 0)

Avisos del servidor al jugador (Notify/Toast): msg.thanks [success] x2, msg.pass_unlocked [success] x1

DataStore: SpinShowdown_v1/u_90000001 (lecturas 28, escrituras 28), SpinShowdown_v1_lb_season_24321/90000001 (lecturas 13, escrituras 5), SpinShowdown_v1_referrals/90000001 (lecturas 17, escrituras 0)

Compras simuladas: prompt producto 8001 (grant); recibo producto 8001 -> PurchaseGranted; prompt producto 8002 (grant); recibo producto 8002 -> PurchaseGranted; prompt pase 7002 (grant); prompt producto 8003 (cancel)

Recibos concedidos: 2; reenviados con el mismo PurchaseId: 2.

## Que simula la herramienta en este modo

- **Tiempo**: virtual, 30 fps, `task.wait/delay/spawn`, Heartbeat/RenderStepped y `os.clock/os.time/tick` avanzan juntos. Nada depende del reloj real.
- **Servidor + cliente en un proceso** con los `RemoteEvent/RemoteFunction` reales (argumentos copiados como en Roblox). Los errores de handlers del servidor se registran con su stack y el cliente recibe un error "Server script error".
- **DataStore** en memoria con las reglas que Roblox aplica al guardar: claves de hasta 50 caracteres, tablas mixtas/con huecos/NaN/inf/ciclicas se rechazan, valores de hasta 4 MB, presupuesto de requests por minuto (60 + 10 por jugador, solo se **reporta**, no se frena). Se registra cada escritura por clave.
- **Salir/entrar**: `PlayerRemoving`, `Parent = nil` y destruccion del Player como el motor; despues se espera el guardado, se compara lo guardado con el perfil en memoria y se entra de nuevo con un cliente nuevo (modulos del cliente recargados, hilos y conexiones del cliente viejo muertos). Al final de la corrida se corre `BindToClose` con 30 s de limite.
- **MarketplaceService**: `PromptProductPurchase`/`PromptGamePassPurchase` entregan un recibo falso a `ProcessReceipt` (PurchaseId unico), despues lo **reenvian con el mismo PurchaseId** para comprobar que no se concede dos veces; los ids de Robux que en el repo estan en 0 se reemplazan por ids falsos solo durante el playtest (fixture `playtestPatches`).
- **Fisica minima**: `CFrame`/`Position` de las partes sincronizados, `PivotTo`/`MoveTo` de modelos, `Humanoid:MoveTo` camina en linea recta a `WalkSpeed` (sin gravedad ni colision con el mundo), `Humanoid.Health = 0` dispara `Died` y respawnea a los 5 s en el `SpawnLocation`, `Touched/TouchEnded` se disparan cuando la caja del personaje solapa la parte (revision cada 0,1 s), `Workspace:Raycast` contra cajas de partes, proyeccion de camara `WorldToViewportPoint`. No hay colisiones, ni terreno, ni salto, ni caida: el bot es responsable de ir a posiciones validas.
- **GUI**: el layout de Luau ignora `UIListLayout/UIGridLayout`; los clicks del bot disparan directamente `Activated/MouseButton1Click` del boton (si esta visible) en vez de calcular donde esta en pantalla.

## Log crudo (extracto)

```
[info] t=14:58 MarketplaceService:PromptProductPurchase(8001) mode=grant
[info] t=15:01 MarketplaceService:PromptProductPurchase(8002) mode=grant
[info] t=15:04 MarketplaceService:PromptGamePassPurchase(7002) mode=grant
[info] t=15:07 MarketplaceService:PromptProductPurchase(8003) mode=cancel
```
