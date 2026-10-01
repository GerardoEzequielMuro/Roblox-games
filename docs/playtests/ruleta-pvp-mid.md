# Playtest de ruleta-pvp

- Comando: `python3 tools/uipreview/preview.py ruleta-pvp --playtest --minutes 25 --seed 1 --state mid`
- Fecha: 2026-10-01 | estado inicial: `mid` | tiempo virtual jugado: 25.2 min | reales: 14 s | rejoins del bot: 1
- El tiempo es virtual (scheduler propio de la herramienta); el bot juega por los remotes/funciones cliente reales del juego. Es una **aproximacion** de Roblox: ver "Que simula la herramienta" al final.

## Resumen (espanol)

**Veredicto: ERRORES**

- Errores de Luau unicos (del juego): **0**
- Warnings unicos: **0**
- Remotes rechazados por el servidor sin que el bot lo esperara: **6** llamadas en 3 acciones
- Invariantes violados / problemas de guardado / recibos / DataStore: **2**
- Estados trabados > 60 s virtuales: **0**
- Hilos que quedaron esperando para siempre (WaitForChild sin hijo, etc.): **0**
- Avisos de error que el servidor le mostro al jugador (Notify/Toast kind=error): **0**
- APIs de Roblox que el simulador no implementa y otros avisos del motor simulado: **0** (ver seccion "Avisos del simulador")
- Instancias vivas en el DataModel: 6371 (t=0:39) -> 4753 (t=25:09); partes 1459 -> 1560; GUI 1719 -> 1064
- Acciones del bot: aborted=1, afkTurns=2, botTurnsSeen=123, brakes=9, cards=8, eliminated=2, ended=5, leftMid=1, matches=4, maxBotTurnGapAfter=landed, maxBotTurnGapS=8, maxGapAfter=decide, maxGapS=14, playAgainNoop=2, playAgainOk=0, releasedAfterEnded=9.1, resultAfterEnded=2.2, results=5, spins=5, targets=5, wins=2

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
| 0:09 (start) | 2340 | 74 | 14 | 60 | 2 | 420 | 1 | 21 | 180 |
| 1:39 | 2140 | 74 | 14 | 60 | 2 | 420 | 1 | 21 | 180 |
| 3:39 | 2140 | 74 | 14 | 60 | 2 | 420 | 1 | 21 | 180 |
| 5:09 | 2242 | 77 | 15 | 61 | 3 | 432 | 1 | 22 | 42 |
| 7:09 | 2242 | 77 | 15 | 61 | 3 | 432 | 1 | 22 | 42 |
| 9:09 | 2282 | 77 | 15 | 62 | 0 | 433 | 1 | 22 | 88 |
| 10:39 | 2012 | 77 | 15 | 62 | 0 | 433 | 1 | 22 | 148 |
| 12:39 | 2012 | 77 | 15 | 62 | 0 | 433 | 1 | 22 | 148 |
| 14:39 | 2012 | 77 | 15 | 62 | 0 | 433 | 1 | 22 | 148 |
| 16:12 | 4352 | 77 | 16 | 63 | 1 | 442 | 1 | 23 | 143 |
| 18:12 | 4392 | 77 | 16 | 64 | 0 | 443 | 1 | 23 | 173 |
| 20:12 | 4392 | 77 | 16 | 64 | 0 | 443 | 1 | 23 | 173 |
| 21:42 | 4392 | 77 | 16 | 64 | 0 | 443 | 1 | 23 | 173 |
| 23:42 | 3252 | 77 | 16 | 64 | 0 | 443 | 1 | 23 | 173 |
| 25:09 (end) | 3252 | 77 | 16 | 64 | 0 | 443 | 1 | 23 | 173 |

Hitos:

- 0:09 lobby ready
- 0:09 claimed daily
- 0:09 bought cosmetic e_cool
- 0:23 match 1 seated
- 4:43 match 1 result: place 1/5 classic coins +132 xp +102 trophies +12
- 5:00 bought cosmetic e_cry
- 5:01 match 2 seated
- 8:58 match 2 eliminated (keeps watching): place 4/6 chaos coins +40 xp +46 trophies +1
- 9:48 match 2 result: place 4/6 chaos coins +40 xp +46 trophies +1
- 9:54 bought cosmetic w_neon
- 9:55 match 3 seated
- 14:48 match 3 result: place 1/6 teams coins +80 xp +80 trophies +9
- 15:05 bought cosmetic t_carbon
- 15:17 match 4 seated
- 15:54 leaves mid match
- 15:57 bought cosmetic ti_lucky
- 15:57 rejoin: leaves (mid)
- 16:12 rejoin ok: profile reloaded identical
- 16:12 match 5 seated
- 17:51 match 5 eliminated (keeps watching): place 6/6 chaos coins +40 xp +30 trophies +1
- 22:57 match 5 result: place 6/6 chaos coins +40 xp +30 trophies +1
- 23:01 bought cosmetic w_candy
- 23:03 match 6 seated
- 25:09 match 6 ended without a result screen: stopped
- 25:09 bot script finished
- 25:19 late receipt for a player that left -> NotProcessedYet

## Errores de Luau

Ninguno.

## Avisos del simulador

Ninguno.

## Warnings

Ninguno.

## Remotes rechazados inesperadamente

| remote:accion | llamadas | ok | rechazos | motivos |
|---|---|---|---|---|
| Request:Act | 27 | 23 | 4 | msg.not_your_turn x4 |
| Request:ClaimDaily | 2 | 1 | 1 | msg.daily_tomorrow x1 |
| Request:LeaveTable | 4 | 3 | 1 | msg.bad_request x1 |

Ejemplos de `Request:Act`: `t=952 Act(kind=target,target=b1_2) -> msg.not_your_turn`; `t=953 Act(kind=spin) -> msg.not_your_turn`; `t=1415 Act(kind=target,target=b1_7) -> msg.not_your_turn`; `t=1415 Act(kind=spin) -> msg.not_your_turn`

Ejemplos de `Request:ClaimDaily`: `t=905 ClaimDaily() -> msg.daily_tomorrow`

Ejemplos de `Request:LeaveTable`: `t=1509 LeaveTable() -> msg.bad_request`


## Invariantes, trabas, guardado, recibos

- **Posible bug del juego (detectado por el bot)** t=4:58 x2: 'Play again' pressed 2.6 s after the result screen appeared (the server still had me at the table: true) ends in the lobby without a new match: Main.client.luau:96 onPlayAgain only calls QuickPlay when Net.get('table') is nil, but the table is not released until MatchRunner finishes T.ending (9 s) after the 'ended' event (`ruleta-pvp/src/client/Main.client.luau:96 < ruleta-pvp/src/server/Services/MatchRunner.luau:198 < ruleta-pvp/src/server/Services/Tables.luau:327`)
- **Posible bug del juego (detectado por el bot)** t=16:12: the session gifts (Config.Gifts, 'minutes since joining') are not saved: after rejoining the 2 claimed gifts are claimable again (State.giftsClaimed is per session, never in the profile) (`ruleta-pvp/src/server/Services/State.luau:32 < ruleta-pvp/src/server/Services/Rewards.luau:83`)

## Trafico de remotes

| remote:accion | llamadas | ok | rechazos inesperados | rechazos provocados | max s |
|---|---|---|---|---|---|
| Request:Act | 27 | 23 | 4 | 0 | 0 |
| Request:Buy | 6 | 6 | 0 | 0 | 0 |
| Request:ClaimDaily | 2 | 1 | 1 | 0 | 0 |
| Request:ClaimGift | 4 | 4 | 0 | 0 | 0 |
| Request:ClaimQuest | 2 | 2 | 0 | 0 | 0 |
| Request:Equip | 4 | 4 | 0 | 0 | 0 |
| Request:GetBoards | 26 | 26 | 0 | 0 | 0 |
| Request:GetState | 2 | 2 | 0 | 0 | 0 |
| Request:GetTables | 2 | 2 | 0 | 0 | 0 |
| Request:LeaveTable | 4 | 3 | 1 | 0 | 0 |
| Request:QuickPlay | 6 | 6 | 0 | 0 | 0 |
| Request:SetSetting | 15 | 15 | 0 | 0 | 0 |

RemoteEvents: Hand (srv->cli 106, cli->srv 0), LevelUp (srv->cli 2, cli->srv 0), LiveEventUpdate (srv->cli 2, cli->srv 0), Match (srv->cli 598, cli->srv 0), Notify (srv->cli 3, cli->srv 0), Result (srv->cli 4, cli->srv 0), State (srv->cli 29, cli->srv 0), Tables (srv->cli 22, cli->srv 0), Unlock (srv->cli 1, cli->srv 0)

Avisos del servidor al jugador (Notify/Toast): msg.thanks [success] x2, msg.pass_unlocked [success] x1

DataStore: SpinShowdown_v1/u_90000001 (lecturas 24, escrituras 24), SpinShowdown_v1_lb_season_24321/90000001 (lecturas 12, escrituras 4), SpinShowdown_v1_lb_wins/90000001 (lecturas 12, escrituras 1), SpinShowdown_v1_referrals/90000001 (lecturas 13, escrituras 0)

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
[info] t=15:06 MarketplaceService:PromptProductPurchase(8001) mode=grant
[info] t=15:09 MarketplaceService:PromptProductPurchase(8002) mode=grant
[info] t=15:12 MarketplaceService:PromptGamePassPurchase(7002) mode=grant
[info] t=15:15 MarketplaceService:PromptProductPurchase(8003) mode=cancel
```
