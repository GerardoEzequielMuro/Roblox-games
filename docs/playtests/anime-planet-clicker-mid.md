# Playtest de anime-planet-clicker

- Comando: `python3 tools/uipreview/preview.py anime-planet-clicker --playtest --minutes 10 --seed 1 --state mid`
- Fecha: 2026-10-01 | estado inicial: `mid` | tiempo virtual jugado: 10.2 min | reales: 20 s | rejoins del bot: 1
- El tiempo es virtual (scheduler propio de la herramienta); el bot juega por los remotes/funciones cliente reales del juego. Es una **aproximacion** de Roblox: ver "Que simula la herramienta" al final.

## Resumen (espanol)

**Veredicto: OK**

- Errores de Luau unicos (del juego): **0**
- Warnings unicos: **0**
- Remotes rechazados por el servidor sin que el bot lo esperara: **3** llamadas en 2 acciones
- Invariantes violados / problemas de guardado / recibos / DataStore: **0**
- Estados trabados > 60 s virtuales: **0**
- Hilos que quedaron esperando para siempre (WaitForChild sin hijo, etc.): **0**
- Avisos de error que el servidor le mostro al jugador (Notify/Toast kind=error): **0**
- APIs de Roblox que el simulador no implementa y otros avisos del motor simulado: **0** (ver seccion "Avisos del simulador")
- Instancias vivas en el DataModel: 4517 (t=0:39) -> 5843 (t=10:09); partes 2307 -> 2868; GUI 549 -> 607
- Acciones del bot: capsules=18, clicks=1095, hatchedNew=0, planetsBroken=0, rebirths=0, sellWalks=12, sells=12, tools=2, upgrades=20, walks=32, windows=12, zonesMoved=2

## Analisis del revisor (a mano)

**Hallazgos reales**

1. **Regalos por minutos de sesión farmeables reentrando** (diseño, baja/media): `State.giftsClaimed` es por sesión (`src/server/Services/State.luau:42`) y no está en el perfil; `Config.Gifts` se puede volver a reclamar después de salir y entrar (el bot lo comprueba).
2. Los pases/productos de `Config` tienen `id = 0` (tienda apagada en el repo); el playtest les pone ids falsos solo para probar el flujo de compra. Con eso: recibos concedidos una sola vez aunque se reenvíen, y la compra cancelada no cambia nada.
3. Los paquetes "minutos de minado" (`StardustSmall/Medium/Large`, 30/180/720 min) se pagan con el ingreso ideal por segundo (`Formulas.income`); para un jugador de 5 minutos con pico de titanio los tres paquetes valen ~14 millones de stardust, que es lo que el bot mina en ~10 horas reales... pero coincide con su ritmo real de minado (≈15-19 mil por minuto) × 930 min, así que no hay inconsistencia: solo es una compra que salta mucho el progreso (herramientas de la galaxia 2: 170 mil, 18 millones). Para revisar si es lo deseado en la economía.

**Sin errores de Luau ni advertencias** en 10 min (nuevo y mid). El perfil se guardó y se recargó idéntico (incluido un dron de carga en vuelo al salir: `Mining.forget` lo aterriza antes de guardar).

**Qué se probó**: tutorial completo (minar, romper el núcleo, vender caminando al Refinery, abrir cápsula, comprar herramienta, activar Auto Mine), minado con `Miner.simulate` (el mismo camino que un click), cápsulas, mejoras, regalos, misiones, todas las ventanas, ajustes de auto, idiomas, compras, rejoin. Rebirth y galaxias lejanas no se alcanzan en 10 min.

## Que logro el bot (timeline)

| t (virtual) | crystals | hits | mined | pets | planetsBroken | rebirths | stardust | tool | tutorial | zones |
|---|---|---|---|---|---|---|---|---|---|---|
| 0:09 (start) | 340 | 21000 | 31000000 | 14 | 900 | 2 | 2450000 | drill_twin | 7 | 3 |
| 0:39 | 442 | 21036 | 31183926 | 14 | 910 | 2 | 2633926 | drill_twin | 7 | 3 |
| 1:39 | 444 | 21214 | 1218204726 | 16 | 914 | 2 | 609654726 | drill_plasma | 7 | 3 |
| 2:09 | 444 | 21316 | 21041452086 | 17 | 917 | 2 | 20302902086 | drill_plasma | 7 | 3 |
| 3:09 | 451 | 21458 | 41602878006 | 19 | 923 | 2 | 40604328006 | drill_plasma | 7 | 3 |
| 3:39 | 451 | 21568 | 50810820918 | 20 | 926 | 2 | 89422314264 | drill_plasma | 7 | 3 |
| 4:39 | 460 | 21687 | 137017798480 | 18 | 945 | 2 | 125367141475 | drill_quake | 7 | 3 |
| 5:09 | 470 | 21738 | 137017798480 | 19 | 961 | 2 | 125237141475 | drill_quake | 7 | 3 |
| 6:09 | 489 | 21795 | 282067734045 | 21 | 978 | 2 | 29880631877040 | drill_quake | 7 | 3 |
| 6:39 | 447 | 21850 | 282067734045 | 22 | 992 | 2 | 29880501877040 | drill_quake | 7 | 3 |
| 7:39 | 453 | 21885 | 428218037891 | 23 | 1003 | 2 | 30026522180886 | drill_quake | 7 | 3 |
| 8:09 | 453 | 21896 | 428218037891 | 23 | 1006 | 2 | 30026522180886 | drill_quake | 7 | 3 |
| 9:09 | 276 | 21991 | 491214314349 | 25 | 1034 | 2 | 30089258457344 | drill_quake | 7 | 3 |
| 9:39 | 101 | 22032 | 558275647956 | 27 | 1045 | 2 | 30156059790951 | drill_quake | 7 | 3 |
| 10:09 (end) | 113 | 22080 | 696448281761 | 28 | 1060 | 2 | 30294102423915 | drill_quake | 7 | 3 |

Hitos:

- 0:09 session started, tutorial step 7
- 0:53 teleported to galaxy 3
- 1:14 bought tool drill_plasma
- 3:52 bought tool drill_quake
- 6:49 rejoin (save + reload)
- 6:49 rejoin: leaves (mid)
- 7:03 rejoin ok: profile reloaded identical
- 8:01 teleported to galaxy 3
- 10:10 bot script finished
- 10:19 late receipt for a player that left -> NotProcessedYet

## Errores de Luau

Ninguno.

## Avisos del simulador

Ninguno.

## Warnings

Ninguno.

## Remotes rechazados inesperadamente

| remote:accion | llamadas | ok | rechazos | motivos |
|---|---|---|---|---|
| Request:Open | 20 | 18 | 2 | msg.get_closer x2 |
| Request:Upgrade | 21 | 20 | 1 | msg.unknown_upgrade x1 |

Ejemplos de `Request:Open`: `t=50 Open(capsule=verdant,count=1) -> msg.get_closer`; `t=478 Open(capsule=frost,count=1) -> msg.get_closer`

Ejemplos de `Request:Upgrade`: `t=610 Upgrade(id=MoveSpeed) -> msg.unknown_upgrade`


## Invariantes, trabas, guardado, recibos

Ninguno.

## Trafico de remotes

| remote:accion | llamadas | ok | rechazos inesperados | rechazos provocados | max s |
|---|---|---|---|---|---|
| Request:BuyTool | 2 | 2 | 0 | 0 | 0 |
| Request:CanBuy | 3 | 3 | 0 | 0 | 0 |
| Request:ClaimDaily | 1 | 1 | 0 | 0 | 0 |
| Request:ClaimGift | 2 | 2 | 0 | 0 | 0 |
| Request:EquipBest | 11 | 11 | 0 | 0 | 0 |
| Request:GetNodes | 8 | 8 | 0 | 0 | 0 |
| Request:GetState | 2 | 2 | 0 | 0 | 0 |
| Request:Open | 20 | 18 | 2 | 0 | 0 |
| Request:SetAuto | 17 | 17 | 0 | 0 | 0 |
| Request:SetLanguage | 3 | 3 | 0 | 0 | 0 |
| Request:Teleport | 2 | 2 | 0 | 0 | 0 |
| Request:Upgrade | 21 | 20 | 1 | 0 | 0 |

RemoteEvents: Currency (srv->cli 276, cli->srv 0), Hit (srv->cli 0, cli->srv 676), LiveEventUpdate (srv->cli 2, cli->srv 0), Mine (srv->cli 655, cli->srv 0), Node (srv->cli 153, cli->srv 0), Notify (srv->cli 20, cli->srv 0), Quests (srv->cli 180, cli->srv 0), Reward (srv->cli 18, cli->srv 0), State (srv->cli 177, cli->srv 0)

Avisos del servidor al jugador (Notify/Toast): msg.mastery_up [success] x9, msg.buff_ended [info] x7, msg.thanks [success] x3, msg.pass_unlocked [success] x1

DataStore: PC_LB_Arena_v1/90000001 (lecturas 2, escrituras 1), PC_LB_Mined_v1/90000001 (lecturas 9, escrituras 9), PC_LB_Rebirths_v1/90000001 (lecturas 2, escrituras 1), PlanetCrackers_Referrals_v1/90000001 (lecturas 7, escrituras 0), PlanetCrackers_v1/u_90000001 (lecturas 19, escrituras 19)

Compras simuladas: prompt producto 8001 (grant); recibo producto 8001 -> PurchaseGranted; prompt producto 8002 (grant); recibo producto 8002 -> PurchaseGranted; prompt producto 8003 (grant); recibo producto 8003 -> PurchaseGranted; prompt pase 7001 (grant); prompt producto 8011 (cancel)

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
[info] t=5:21 MarketplaceService:PromptProductPurchase(8001) mode=grant
[info] t=5:24 MarketplaceService:PromptProductPurchase(8002) mode=grant
[info] t=5:27 MarketplaceService:PromptProductPurchase(8003) mode=grant
[info] t=5:30 MarketplaceService:PromptGamePassPurchase(7001) mode=grant
[info] t=5:33 MarketplaceService:PromptProductPurchase(8011) mode=cancel
```
