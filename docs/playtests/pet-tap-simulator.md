# Playtest de pet-tap-simulator

- Comando: `python3 tools/uipreview/preview.py pet-tap-simulator --playtest --minutes 10 --seed 1`
- Fecha: 2026-10-01 | estado inicial: `new` | tiempo virtual jugado: 10.2 min | reales: 44 s | rejoins del bot: 1
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
- Instancias vivas en el DataModel: 7598 (t=0:39) -> 7513 (t=10:09); partes 3564 -> 3564; GUI 1201 -> 1166
- Acciones del bot: hatches=88, langs=3, purchases=3, quests=2, rebirths=0, taps=3000, upgrades=11, windows=11, zones=1

## Analisis del revisor (a mano)

**Hallazgos reales**

1. **Regalos por minutos de sesión farmeables reentrando** (diseño, severidad baja/media): `State.giftsClaimed` se crea al entrar (`src/server/Services/State.luau:39`) y se descarta al salir (`:47`); no está en el perfil (`Data.luau`). El regalo 2 de `Config.Gifts` (35 gemas a los 2 min, `src/shared/Config.luau:528-537`) se puede reclamar otra vez después de cada rejoin; con 35 gemas ya se compra el primer nivel de TapPower y WalkSpeed. El bot lo detecta solo (reclama, sale, entra y los vuelve a ver disponibles). Mismo patrón en los otros 5 juegos.
2. Los 13 pases y 11 productos de `Config` tienen `id = 0` ("todavía no existen", `src/shared/Config.luau:387-433`): la tienda de Robux está apagada en el repo y `Purchase.pass/product` solo muestra "pronto". No es un bug; para poder probar el flujo de compra el playtest les pone ids falsos (`fixtures/pet-tap-simulator.luau`, `playtestPatches`). Con eso: 3 compras concedidas, 1 cancelada, recibos reenviados con el mismo `PurchaseId` sin conceder dos veces, y recibo tardío para un jugador que ya salió -> `NotProcessedYet`.

**Sin errores de Luau ni advertencias** en 10 min (nuevo y mid). El perfil se guardó al salir (coincide con la memoria) y se recargó idéntico después del rejoin.

**Ritmo**: en 10 min el bot (tocando ~6/s con los límites del cliente y del servidor) compra todas las mejoras de gemas que puede, desbloquea la zona 2 hacia el minuto 4, y eclosiona ~90 huevos. La rebirth cuesta 2.000 millones de taps (`Config.RebirthBaseCost`) y no se alcanza en 10 min, así que el flujo de rebirth solo se ejerce con el estado `mid`... que tampoco llega (taps del perfil `mid` < costo): ese camino no se ejercitó en el playtest.

## Que logro el bot (timeline)

| t (virtual) | gems | hatched | pets | rebirths | taps | totalTaps | upgrades | zones |
|---|---|---|---|---|---|---|---|---|
| 0:09 (start) | 0 | 0 | 1 | 0 | 12 | 12 | 0 | 1 |
| 0:39 | 0 | 4 | 5 | 0 | 456 | 456 | 0 | 1 |
| 1:39 | 0 | 16 | 17 | 0 | 2023 | 1543 | 0 | 1 |
| 2:09 | 0 | 19 | 20 | 0 | 1877 | 1997 | 0 | 1 |
| 3:09 | 8 | 30 | 26 | 0 | 1961 | 4281 | 6 | 1 |
| 3:39 | 14 | 33 | 29 | 0 | 777 | 6497 | 7 | 1 |
| 4:39 | 5 | 42 | 38 | 0 | 362053 | 10873 | 10 | 2 |
| 5:09 | 5 | 47 | 43 | 0 | 43268 | 42088 | 10 | 2 |
| 6:09 | 5 | 51 | 47 | 0 | 9893 | 64713 | 10 | 2 |
| 6:39 | 5 | 56 | 52 | 0 | 29283 | 99103 | 10 | 2 |
| 7:39 | 5 | 64 | 60 | 0 | 21726 | 153646 | 10 | 2 |
| 8:09 | 40 | 69 | 65 | 0 | 52926 | 199846 | 10 | 2 |
| 9:09 | 9 | 78 | 74 | 0 | 25238 | 243158 | 11 | 2 |
| 9:39 | 9 | 85 | 81 | 0 | 29648 | 268568 | 11 | 2 |
| 10:09 (end) | 9 | 91 | 87 | 0 | 38213 | 295133 | 11 | 2 |

Hitos:

- 0:09 session started
- 0:10 claimed daily
- 0:54 claimed gift 1
- 2:12 claimed gift 2
- 2:41 crafted a golden cat:0
- 4:26 bought zone 2
- 5:45 rejoin (save + reload)
- 5:45 rejoin: leaves (midgame)
- 5:59 rejoin ok: profile reloaded identical
- 5:59 back after rejoin
- 6:52 claimed gift 1
- 8:07 claimed gift 2
- 10:10 bot script finished
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

- **Posible bug del juego (detectado por el bot)** t=5:59: the session gifts (Config.Gifts, 'minutes since joining') are not saved: after rejoining all 2 claimed gifts are claimable again, so gems/taps can be farmed by leaving and joining (State.giftsClaimed is per session, never in the profile) (`pet-tap-simulator/src/server/Services/State.luau:39 < pet-tap-simulator/src/server/Services/Rewards.luau:130`)

## Trafico de remotes

| remote:accion | llamadas | ok | rechazos inesperados | rechazos provocados | max s |
|---|---|---|---|---|---|
| Request:BuyZone | 1 | 1 | 0 | 0 | 0 |
| Request:ClaimDaily | 1 | 1 | 0 | 0 | 0.07 |
| Request:ClaimGift | 4 | 4 | 0 | 0 | 0 |
| Request:ClaimOffline | 10 | 0 | 0 | 10 | 0 |
| Request:ClaimQuest | 2 | 2 | 0 | 0 | 0 |
| Request:Craft | 1 | 1 | 0 | 0 | 0 |
| Request:Delete | 2 | 1 | 0 | 1 | 0 |
| Request:EquipBest | 22 | 22 | 0 | 0 | 0 |
| Request:GetState | 2 | 2 | 0 | 0 | 0 |
| Request:GoPark | 1 | 1 | 0 | 0 | 0 |
| Request:Hatch | 88 | 88 | 0 | 0 | 0 |
| Request:Lock | 2 | 2 | 0 | 0 | 0 |
| Request:RedeemCode | 2 | 1 | 0 | 1 | 0 |
| Request:RollTrait | 1 | 1 | 0 | 0 | 0 |
| Request:SetAuto | 2 | 2 | 0 | 0 | 0 |
| Request:SetAutoHatch | 2 | 2 | 0 | 0 | 0 |
| Request:SetLanguage | 4 | 4 | 0 | 0 | 0 |
| Request:Teleport | 3 | 3 | 0 | 0 | 0 |
| Request:Upgrade | 11 | 11 | 0 | 0 | 0 |

RemoteEvents: Currency (srv->cli 440, cli->srv 0), Hatched (srv->cli 3, cli->srv 0), LiveEventUpdate (srv->cli 2, cli->srv 0), Notify (srv->cli 7, cli->srv 0), Quests (srv->cli 14, cli->srv 0), Reward (srv->cli 10, cli->srv 0), State (srv->cli 143, cli->srv 0), Tap (srv->cli 0, cli->srv 475)

Avisos del servidor al jugador (Notify/Toast): msg.got_dice [success] x2, msg.thanks [success] x2, msg.unlocked_zone [success] x1, msg.pass_unlocked [success] x1, msg.crafted [success] x1

DataStore: TapPets_Profiles_v1/u_90000001 (lecturas 14, escrituras 14), TapPets_Referrals_v1/90000001 (lecturas 7, escrituras 0), TapPets_TotalTaps_v1/90000001 (lecturas 10, escrituras 10)

Compras simuladas: prompt producto 8004 (grant); recibo producto 8004 -> PurchaseGranted; prompt pase 7001 (grant); prompt producto 8001 (grant); recibo producto 8001 -> PurchaseGranted; prompt producto 8005 (cancel)

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
[info] t=4:11 MarketplaceService:PromptProductPurchase(8004) mode=grant
[info] t=4:14 MarketplaceService:PromptGamePassPurchase(7001) mode=grant
[info] t=4:17 MarketplaceService:PromptProductPurchase(8001) mode=grant
[info] t=4:20 MarketplaceService:PromptProductPurchase(8005) mode=cancel
```
