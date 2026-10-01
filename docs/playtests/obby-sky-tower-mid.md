# Playtest de obby-sky-tower

- Comando: `python3 tools/uipreview/preview.py obby-sky-tower --playtest --minutes 10 --seed 1 --state mid`
- Fecha: 2026-10-01 | estado inicial: `mid` | tiempo virtual jugado: 10.2 min | reales: 402 s | rejoins del bot: 1
- El tiempo es virtual (scheduler propio de la herramienta); el bot juega por los remotes/funciones cliente reales del juego. Es una **aproximacion** de Roblox: ver "Que simula la herramienta" al final.

## Resumen (espanol)

**Veredicto: ERRORES (BOT INCOMPLETO)**

> ATENCION: el script del bot fallo y dejo de jugar en t=10:10; el resultado es parcial. bot script error: playtests/obby-sky-tower.luau:23: attempt to index nil with 'at' playtests/obby-sky-tower.luau:23: attempt to index nil with 'at' playtests/obby-sky-tower.luau:23 function at playtests/obby-sky-tower.luau:280 function run /home/user/Roblox-games/tools/uipreview/runtime/playtest:151

- Errores de Luau unicos (del juego): **0**
- Warnings unicos: **0**
- Remotes rechazados por el servidor sin que el bot lo esperara: **0** llamadas en 0 acciones
- Invariantes violados / problemas de guardado / recibos / DataStore: **1**
- Estados trabados > 60 s virtuales: **0**
- Hilos que quedaron esperando para siempre (WaitForChild sin hijo, etc.): **0**
- Avisos de error que el servidor le mostro al jugador (Notify/Toast kind=error): **0**
- APIs de Roblox que el simulador no implementa y otros avisos del motor simulado: **0** (ver seccion "Avisos del simulador")
- Observaciones del bot / herramienta (no son del juego): 1
- Instancias vivas en el DataModel: 14847 (t=0:39) -> 14625 (t=10:09); partes 10445 -> 10168; GUI 1103 -> 1136
- Acciones del bot: deaths=0, falls=0, padsReached=192, panels=8, retries=1, shopBuys=52, skipsOffered=1, skipsUsed=1, towerBest=0, walkFails=0, walks=193

## Analisis del revisor (a mano)

**Hallazgos reales**

1. **Los cofres de monedas del mundo se vuelven a poder juntar si el jugador sale y entra** (diseño, baja): `Session.collected` (`src/server/Session.luau:54`, usado en `Obstacles.collectCoin`, `src/server/Obstacles.luau:147-160`) es memoria de la sesión y solo se limpia en rebirth; después de un rejoin las monedas de las etapas ya recorridas vuelven a estar. En una corrida el perfil cargado tenía 3 monedas más que el guardado (una moneda recogida justo al entrar). Ya estaba pensado "una vez por corrida", pero reentrar lo resetea.
2. **Premios por tiempo de juego (`PlaytimeRewards`) farmeables reentrando** (diseño): `Session.playClaimed` (`src/server/Session.luau:55`) es por sesión; los 5 premios de `Economy.PlaytimeRewards` (incluido uno con skip gratis) vuelven a estar disponibles tras cada rejoin (el bot lo comprueba).
3. Los pases y productos de `Config.Passes/Products` tienen `id = 0` (tienda apagada en el repo); el playtest les pone ids falsos para probar el flujo: el producto "Skip 10" se concedió una vez, no se duplicó al reenviar el recibo, y el recibo tardío -> `NotProcessedYet`.

**Anti-teleport**: el bot camina a `WalkSpeed` en línea recta (más un arco de 5 studs) y **nunca** fue rechazado por `Security.hopPlausible` ni por el piso del tiempo rankeado (`rankedPlausible`): torre 1 completa en ~6 min virtuales (stage 100), portal y torre 2 construida a pedido (las partes pasan de 5.700 a 10.700 y se quedan estables, sin fugas), rejoin en mitad de la subida volvió al último pad guardado.

**Qué NO prueba este bot** (limitaciones de la herramienta): no hay gravedad, saltos ni colisiones; los obstáculos (matan por `Touched`) solo matan si el camino recto cruza su caja (3 muertes en el estado `new`, 0 en `mid`); los obstáculos que se mueven o desaparecen por tween no se mueven porque los tweens saltan al final. Los pads se tocan con la emulación de `Touched` (caja del personaje contra la parte con rotación). La física real de saltos y plataformas se tiene que mirar en Studio.

## Que logro el bot (timeline)

| t (virtual) | at | best | coins | deaths | stage | totalCoins | wins | y |
|---|---|---|---|---|---|---|---|---|
| 0:09 (start) | 238 | 262 | 1835 | 0 | 238 | 5420 | 2 | 388 |
| 0:39 | 247 | 262 | 1074 | 0 | 246 | 6029 | 2 | 491 |
| 1:39 | 270 | 270 | 1277 | 0 | 270 | 7442 | 2 | 727 |
| 2:09 | 278 | 278 | 968 | 0 | 278 | 7933 | 2 | 810 |
| 3:09 | 299 | 299 | 696 | 0 | 298 | 9211 | 2 | 1062 |
| 3:39 | 304 | 304 | 1289 | 0 | 303 | 9904 | 2 | 64 |
| 4:39 | 327 | 327 | 768 | 0 | 326 | 12043 | 2 | 309 |
| 5:09 | 344 | 344 | 2204 | 0 | 343 | 16519 | 2 | 488 |
| 6:09 | 367 | 367 | 4303 | 0 | 366 | 18708 | 2 | 741 |
| 6:39 | 367 | 369 | 4567 | 0 | 367 | 18972 | 2 | 712 |
| 7:39 | 383 | 383 | 5935 | 0 | 383 | 20440 | 2 | 891 |
| 8:09 | 394 | 394 | 928 | 0 | 393 | 21473 | 2 | 1034 |
| 9:09 | 414 | 414 | 3043 | 0 | 413 | 23708 | 2 | 167 |
| 9:39 | 426 | 426 | 4054 | 0 | 426 | 24819 | 2 | 299 |
| 10:09 (end) | 437 | 437 | 5002 | 0 | 436 | 25847 | 2 | 430 |

Hitos:

- 0:09 session started at stage 238
- 0:13 bought power shield
- 0:14 bought power magnet
- 0:14 bought power speed
- 0:14 bought trail white
- 0:35 bought power shield
- 0:36 bought power magnet
- 0:36 bought power speed
- 0:37 bought trail mint
- 0:58 bought power shield
- 0:58 bought power magnet
- 0:58 bought power speed
- 0:59 bought trail fire
- 1:20 bought power shield
- 1:20 bought power magnet
- 1:21 bought power speed
- 1:21 bought trail ocean
- 1:42 bought power shield
- 1:42 bought power magnet
- 1:42 bought power speed
- 1:43 bought trail candy
- 2:15 bought power shield
- 2:16 bought power magnet
- 2:16 bought power speed
- 2:37 bought power shield
- 2:37 bought power speed
- 2:38 bought trail toxic
- 2:58 bought power shield
- 2:59 bought power speed
- 3:11 WIN tower 3 runMs=nil
- 3:11 summit of tower 3: entering the portal
- 3:20 in tower 4 at stage 300
- 3:20 bought power shield
- 3:20 bought power speed
- 3:40 bought power shield
- 3:41 bought power speed
- 4:01 bought power speed
- 4:43 bought power shield
- 4:56 store: clicked 4 buy buttons
- 5:04 bought trail galaxy
- 5:25 bought power shield
- 5:25 bought power magnet
- 6:13 rejoin (save + reload)
- 6:13 rejoin: leaves (midclimb)
- 6:27 rejoin ok: profile reloaded identical
- 6:27 back at stage 366
- 6:58 bought power speed
- 7:18 bought power shield
- 7:39 bought power shield
- 8:00 bought trail rainbow
- 8:20 bought power shield
- 8:23 WIN tower 4 runMs=nil
- 8:23 summit of tower 4: entering the portal
- 8:31 in tower 5 at stage 400
- 8:42 bought power shield
- 9:02 bought power shield
- 9:23 bought power shield
- 9:23 bought power speed
- 9:44 bought power shield
- 10:05 bought power shield
- ... (2 mas)

## Errores de Luau

Ninguno.

## Avisos del simulador

Ninguno.

## Warnings

Ninguno.

## Remotes rechazados inesperadamente

Ninguno (los rechazos que el bot provoco a proposito no cuentan).

## Invariantes, trabas, guardado, recibos

- **Posible bug del juego (detectado por el bot)** t=6:27: the play-time rewards (Config.PlaytimeRewards, 'minutes in this session') are not saved: after rejoining the 2 claimed rewards are claimable again (Session.playClaimed is per session, never in the profile) (`obby-sky-tower/src/server/Session.luau:55 < obby-sky-tower/src/server/Rewards.luau:127`)

## Observaciones del bot (no son bugs del juego)

- t=10:10 bot script error: playtests/obby-sky-tower.luau:23: attempt to index nil with 'at' playtests/obby-sky-tower.luau:23: attempt to index nil with 'at' playtests/obby-sky-tower.luau:23 function at playtests/obby-sky-tower.luau:280 function run /home/user/Roblox-games/tools/uipreview/runtime/playtest:151 function inCtx /home/user/Roblox-games/tools/uipreview/runtime/playtest:2000 

## Trafico de remotes

| remote:accion | llamadas | ok | rechazos inesperados | rechazos provocados | max s |
|---|---|---|---|---|---|
| Request:BuyEffect | 4 | 4 | 0 | 0 | 0 |
| Request:BuyPower | 40 | 40 | 0 | 0 | 0 |
| Request:BuyTrail | 8 | 8 | 0 | 0 | 0 |
| Request:ClaimDaily | 1 | 1 | 0 | 0 | 0 |
| Request:ClaimPlaytime | 2 | 2 | 0 | 0 | 0 |
| Request:EnterPortal | 2 | 2 | 0 | 0 | 0 |
| Request:GetState | 2 | 2 | 0 | 0 | 0 |
| Request:SetLanguage | 3 | 3 | 0 | 0 | 0 |
| Request:SetSetting | 5 | 4 | 0 | 1 | 0 |
| Request:UseFreeSkip | 1 | 1 | 0 | 0 | 0 |

RemoteEvents: Celebrate (srv->cli 193, cli->srv 0), CoinCollected (srv->cli 379, cli->srv 0), Gift (srv->cli 2, cli->srv 0), LiveEventUpdate (srv->cli 4, cli->srv 0), Notify (srv->cli 3, cli->srv 0), OfferSkip (srv->cli 1, cli->srv 0), Shield (srv->cli 18, cli->srv 0), State (srv->cli 675, cli->srv 0), TowerEnter (srv->cli 2, cli->srv 0), Win (srv->cli 2, cli->srv 0)

Avisos del servidor al jugador (Notify/Toast): msg.coins_added [success] x2, msg.skipped_ahead [success] x1

DataStore: SkyTowerObby_Referrals_v1/90000001 (lecturas 7, escrituras 0), SkyTowerObby_Stage_v1/90000001 (lecturas 11, escrituras 11), SkyTowerObby_Wins_v1/90000001 (lecturas 2, escrituras 1), SkyTowerObby_v1/u_90000001 (lecturas 16, escrituras 16)

Compras simuladas: prompt producto 8006 (grant); recibo producto 8006 -> PurchaseGranted; prompt producto 8003 (grant); recibo producto 8003 -> PurchaseGranted; prompt producto 8002 (grant); recibo producto 8002 -> PurchaseGranted; prompt producto 8004 (cancel)

Recibos concedidos: 3; reenviados con el mismo PurchaseId: 3.

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
[info] t=4:44 MarketplaceService:PromptProductPurchase(8006) mode=grant
[info] t=4:47 MarketplaceService:PromptProductPurchase(8003) mode=grant
[info] t=4:50 MarketplaceService:PromptProductPurchase(8002) mode=grant
[info] t=4:53 MarketplaceService:PromptProductPurchase(8004) mode=cancel
```
