# Playtest de anime-planet-clicker

- Comando: `python3 tools/uipreview/preview.py anime-planet-clicker --playtest --minutes 10 --seed 1`
- Fecha: 2026-10-01 | estado inicial: `new` | tiempo virtual jugado: 10.2 min | reales: 29 s | rejoins del bot: 1
- El tiempo es virtual (scheduler propio de la herramienta); el bot juega por los remotes/funciones cliente reales del juego. Es una **aproximacion** de Roblox: ver "Que simula la herramienta" al final.

## Resumen (espanol)

**Veredicto: ERRORES**

- Errores de Luau unicos (del juego): **0**
- Warnings unicos: **0**
- Remotes rechazados por el servidor sin que el bot lo esperara: **1** llamadas en 1 acciones
- Invariantes violados / problemas de guardado / recibos / DataStore: **1**
- Estados trabados > 60 s virtuales: **0**
- Hilos que quedaron esperando para siempre (WaitForChild sin hijo, etc.): **0**
- Avisos de error que el servidor le mostro al jugador (Notify/Toast kind=error): **0**
- APIs de Roblox que el simulador no implementa y otros avisos del motor simulado: **0** (ver seccion "Avisos del simulador")
- Instancias vivas en el DataModel: 6060 (t=0:39) -> 5975 (t=10:09); partes 2980 -> 2926; GUI 599 -> 609
- Acciones del bot: capsules=20, clicks=942, hatchedNew=3, planetsBroken=0, rebirths=0, sellWalks=13, sells=13, tools=2, upgrades=25, walks=34, windows=12, zonesMoved=0

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
| 0:09 (start) | 0 | 0 | 0 | 1 | 0 | 0 | 0 | pick_rusty | 1 | 1 |
| 0:39 | 50 | 136 | 103 | 2 | 1 | 0 | 1743 | pick_iron | 7 | 1 |
| 1:39 | 17 | 417 | 2468 | 5 | 12 | 0 | 1078 | pick_titanium | 7 | 1 |
| 2:09 | 19 | 541 | 11627 | 6 | 21 | 0 | 10117 | pick_titanium | 7 | 1 |
| 3:09 | 6 | 703 | 36810 | 8 | 38 | 0 | 34977 | pick_titanium | 7 | 1 |
| 3:39 | 12 | 793 | 48542 | 9 | 48 | 0 | 90987 | pick_titanium | 7 | 1 |
| 4:39 | 18 | 884 | 85764 | 11 | 63 | 0 | 35426 | pick_titanium | 7 | 1 |
| 5:09 | 24 | 909 | 115828 | 12 | 70 | 0 | 13858750 | pick_titanium | 7 | 1 |
| 6:09 | 5 | 976 | 133134 | 13 | 88 | 0 | 13875436 | pick_titanium | 7 | 1 |
| 6:46 | 5 | 1004 | 148512 | 14 | 94 | 0 | 13889132 | pick_titanium | 7 | 1 |
| 7:46 | 24 | 1081 | 202512 | 16 | 114 | 0 | 13940221 | pick_titanium | 7 | 1 |
| 8:16 | 20 | 1114 | 234599 | 17 | 124 | 0 | 13970688 | pick_titanium | 7 | 1 |
| 9:16 | 26 | 1209 | 259802 | 19 | 147 | 0 | 13991029 | pick_titanium | 7 | 1 |
| 9:46 | 28 | 1238 | 315475 | 21 | 157 | 0 | 14038282 | pick_titanium | 7 | 1 |
| 10:09 (end) | 8 | 1280 | 315475 | 21 | 169 | 0 | 14082778 | pick_titanium | 7 | 1 |

Hitos:

- 0:09 session started, tutorial step 1
- 0:27 bought tool pick_iron
- 0:31 tutorial: Auto Mine switched on
- 1:12 bought tool pick_titanium
- 6:31 rejoin (save + reload)
- 6:31 rejoin: leaves (mid)
- 6:46 rejoin ok: profile reloaded identical
- 10:12 bot script finished
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
| Request:Open | 21 | 20 | 1 | msg.unknown_capsule x1 |

Ejemplos de `Request:Open`: `t=609 Open(capsule=dawn,count=1) -> msg.unknown_capsule`


## Invariantes, trabas, guardado, recibos

- **Posible bug del juego (detectado por el bot)** t=6:46: the session gifts (Config.Gifts, 'minutes since joining') are not saved: after rejoining the 1 claimed gifts are claimable again (State.giftsClaimed is per session, never in the profile) (`anime-planet-clicker/src/server/Services/State.luau:42 < anime-planet-clicker/src/server/Services/Rewards.luau:121`)

## Trafico de remotes

| remote:accion | llamadas | ok | rechazos inesperados | rechazos provocados | max s |
|---|---|---|---|---|---|
| Request:BuyTool | 2 | 2 | 0 | 0 | 0 |
| Request:CanBuy | 3 | 3 | 0 | 0 | 0 |
| Request:ClaimDaily | 1 | 1 | 0 | 0 | 0 |
| Request:ClaimGift | 2 | 2 | 0 | 0 | 0 |
| Request:ClaimQuest | 1 | 1 | 0 | 0 | 0 |
| Request:EquipBest | 12 | 12 | 0 | 0 | 0 |
| Request:GetNodes | 5 | 5 | 0 | 0 | 0 |
| Request:GetState | 2 | 2 | 0 | 0 | 0 |
| Request:Open | 21 | 20 | 1 | 0 | 0 |
| Request:SetAuto | 18 | 18 | 0 | 0 | 0 |
| Request:SetLanguage | 3 | 3 | 0 | 0 | 0 |
| Request:Upgrade | 25 | 25 | 0 | 0 | 0 |

RemoteEvents: Currency (srv->cli 319, cli->srv 0), Hit (srv->cli 0, cli->srv 587), LiveEventUpdate (srv->cli 2, cli->srv 0), Mine (srv->cli 931, cli->srv 0), Node (srv->cli 165, cli->srv 0), Notify (srv->cli 20, cli->srv 0), Quests (srv->cli 220, cli->srv 0), Reward (srv->cli 45, cli->srv 0), State (srv->cli 197, cli->srv 0), Tutorial (srv->cli 6, cli->srv 0)

Avisos del servidor al jugador (Notify/Toast): msg.mastery_up [success] x9, msg.buff_ended [info] x7, msg.thanks [success] x3, msg.pass_unlocked [success] x1

DataStore: PC_LB_Mined_v1/90000001 (lecturas 10, escrituras 10), PlanetCrackers_Referrals_v1/90000001 (lecturas 7, escrituras 0), PlanetCrackers_v1/u_90000001 (lecturas 17, escrituras 17)

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
[info] t=5:01 MarketplaceService:PromptProductPurchase(8001) mode=grant
[info] t=5:04 MarketplaceService:PromptProductPurchase(8002) mode=grant
[info] t=5:07 MarketplaceService:PromptProductPurchase(8003) mode=grant
[info] t=5:10 MarketplaceService:PromptGamePassPurchase(7001) mode=grant
[info] t=5:13 MarketplaceService:PromptProductPurchase(8011) mode=cancel
```
