# Playtest de obby-sky-tower

- Comando: `python3 tools/uipreview/preview.py obby-sky-tower --playtest --minutes 10 --seed 1`
- Fecha: 2026-10-01 | estado inicial: `new` | tiempo virtual jugado: 10.2 min | reales: 237 s | rejoins del bot: 1
- El tiempo es virtual (scheduler propio de la herramienta); el bot juega por los remotes/funciones cliente reales del juego. Es una **aproximacion** de Roblox: ver "Que simula la herramienta" al final.

## Resumen (espanol)

**Veredicto: ERRORES**

- Errores de Luau unicos (del juego): **0**
- Warnings unicos: **0**
- Remotes rechazados por el servidor sin que el bot lo esperara: **0** llamadas en 0 acciones
- Invariantes violados / problemas de guardado / recibos / DataStore: **1**
- Estados trabados > 60 s virtuales: **0**
- Hilos que quedaron esperando para siempre (WaitForChild sin hijo, etc.): **0**
- Avisos de error que el servidor le mostro al jugador (Notify/Toast kind=error): **0**
- APIs de Roblox que el simulador no implementa y otros avisos del motor simulado: **0** (ver seccion "Avisos del simulador")
- Instancias vivas en el DataModel: 8785 (t=0:39) -> 15062 (t=10:09); partes 5674 -> 10675; GUI 795 -> 1115
- Acciones del bot: deaths=3, falls=0, padsReached=152, panels=8, retries=1, shopBuys=40, skipsOffered=0, skipsUsed=0, towerBest=0, walkFails=0, walks=157

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
| 0:09 (start) | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 |
| 0:39 | 7 | 7 | 55 | 0 | 7 | 75 | 0 | 80 |
| 1:39 | 18 | 18 | 36 | 3 | 18 | 186 | 0 | 205 |
| 2:09 | 25 | 25 | 60 | 3 | 25 | 250 | 0 | 261 |
| 3:09 | 38 | 38 | 55 | 3 | 38 | 415 | 0 | 420 |
| 3:39 | 44 | 44 | 111 | 3 | 44 | 521 | 0 | 489 |
| 4:39 | 64 | 64 | 64 | 3 | 64 | 944 | 0 | 726 |
| 5:09 | 80 | 80 | 2232 | 3 | 80 | 4282 | 0 | 896 |
| 6:09 | 100 | 100 | 1510 | 3 | 100 | 5120 | 1 | 5 |
| 6:39 | 100 | 101 | 247 | 3 | 100 | 5157 | 1 | 14 |
| 7:39 | 105 | 105 | 336 | 3 | 104 | 5306 | 1 | 59 |
| 8:09 | 116 | 116 | 607 | 3 | 116 | 5687 | 1 | 178 |
| 9:09 | 139 | 139 | 1263 | 3 | 138 | 6503 | 1 | 427 |
| 9:39 | 151 | 151 | 1652 | 3 | 150 | 6972 | 1 | 558 |
| 10:09 (end) | 162 | 162 | 2075 | 3 | 162 | 7435 | 1 | 683 |

Hitos:

- 0:09 session started at stage 0
- 0:16 bought trail white
- 0:59 bought power shield
- 1:21 bought power shield
- 1:21 bought trail mint
- 2:04 bought power shield
- 2:24 bought power shield
- 2:48 bought power shield
- 2:48 bought power magnet
- 3:08 bought power shield
- 3:31 bought power magnet
- 3:54 bought power magnet
- 3:55 bought power speed
- 4:15 bought power magnet
- 4:16 bought power speed
- 4:37 bought power shield
- 4:37 bought power magnet
- 4:38 bought power speed
- 4:56 store: clicked 4 buy buttons
- 4:59 bought power magnet
- 4:59 bought power speed
- 4:59 bought trail fire
- 5:21 bought power speed
- 5:21 bought trail ocean
- 5:42 bought power shield
- 5:42 bought power speed
- 5:43 bought trail candy
- 6:00 WIN tower 1 runMs=nil
- 6:00 summit of tower 1: entering the portal
- 6:09 in tower 2 at stage 100
- 6:09 bought power shield
- 6:10 bought power speed
- 6:10 bought trail toxic
- 6:12 rejoin (save + reload)
- 6:12 rejoin: leaves (midclimb)
- 6:27 rejoin ok: profile reloaded identical
- 6:27 back at stage 100
- 7:29 bought power speed
- 7:50 bought power magnet
- 7:51 bought power speed
- 8:11 bought power speed
- 8:32 bought power speed
- 8:52 bought power shield
- 9:13 bought power shield
- 9:34 bought power shield
- 9:54 bought power shield
- 10:09 bot script finished
- 10:19 late receipt for a player that left -> NotProcessedYet

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

## Trafico de remotes

| remote:accion | llamadas | ok | rechazos inesperados | rechazos provocados | max s |
|---|---|---|---|---|---|
| Request:BuyEffect | 3 | 3 | 0 | 0 | 0 |
| Request:BuyPower | 31 | 31 | 0 | 0 | 0 |
| Request:BuyTrail | 6 | 6 | 0 | 0 | 0 |
| Request:ClaimDaily | 1 | 1 | 0 | 0 | 0 |
| Request:ClaimPlaytime | 3 | 3 | 0 | 0 | 0 |
| Request:EnterPortal | 1 | 1 | 0 | 0 | 0 |
| Request:GetState | 2 | 2 | 0 | 0 | 0 |
| Request:SetLanguage | 3 | 3 | 0 | 0 | 0 |
| Request:SetSetting | 5 | 4 | 0 | 1 | 0 |

RemoteEvents: AskNotifications (srv->cli 1, cli->srv 0), Celebrate (srv->cli 154, cli->srv 0), CoinCollected (srv->cli 253, cli->srv 0), Gift (srv->cli 1, cli->srv 0), LiveEventUpdate (srv->cli 4, cli->srv 0), Notify (srv->cli 3, cli->srv 0), Shield (srv->cli 12, cli->srv 0), State (srv->cli 498, cli->srv 0), TowerEnter (srv->cli 1, cli->srv 0), Win (srv->cli 1, cli->srv 0)

Avisos del servidor al jugador (Notify/Toast): msg.coins_added [success] x2, msg.skipped_ahead [success] x1

DataStore: SkyTowerObby_Referrals_v1/90000001 (lecturas 7, escrituras 0), SkyTowerObby_Stage_v1/90000001 (lecturas 12, escrituras 12), SkyTowerObby_Wins_v1/90000001 (lecturas 3, escrituras 1), SkyTowerObby_v1/u_90000001 (lecturas 17, escrituras 17)

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
