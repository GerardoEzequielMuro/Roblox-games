# Playtest de huerta-tycoon

- Comando: `python3 tools/uipreview/preview.py huerta-tycoon --playtest --minutes 10 --seed 1 --state mid`
- Fecha: 2026-10-01 | estado inicial: `mid` | tiempo virtual jugado: 10.2 min | reales: 70 s | rejoins del bot: 1
- El tiempo es virtual (scheduler propio de la herramienta); el bot juega por los remotes/funciones cliente reales del juego. Es una **aproximacion** de Roblox: ver "Que simula la herramienta" al final.

## Resumen (espanol)

**Veredicto: OK**

- Errores de Luau unicos (del juego): **0**
- Warnings unicos: **0**
- Remotes rechazados por el servidor sin que el bot lo esperara: **0** llamadas en 0 acciones
- Invariantes violados / problemas de guardado / recibos / DataStore: **0**
- Estados trabados > 60 s virtuales: **0**
- Hilos que quedaron esperando para siempre (WaitForChild sin hijo, etc.): **0**
- Avisos de error que el servidor le mostro al jugador (Notify/Toast kind=error): **0**
- APIs de Roblox que el simulador no implementa y otros avisos del motor simulado: **0** (ver seccion "Avisos del simulador")
- Instancias vivas en el DataModel: 8692 (t=0:39) -> 8472 (t=10:09); partes 4674 -> 4602; GUI 1095 -> 1053
- Acciones del bot: claimed=1, harvests=169, panels=14, planted=240, rebirths=1, seedsBought=100, sells=14, tiles=8, tpSell=14, upgrades=12

## Analisis del revisor (a mano)

**Hallazgos reales**

1. **Regalos por minutos de sesión farmeables reentrando** (diseño, baja/media): `giftsClaimed` vive en la sesión (`src/server/Services/Session.luau:70`) y no se guarda en el perfil; `Config.PlaytimeGifts` se reclama de nuevo después de reentrar.
2. Los pases y productos de `Config.GamePasses/DevProducts` tienen `id = 0` (tienda apagada en el repo); el playtest les pone ids falsos para probar el flujo de compra. Con eso: pases y productos concedidos una vez, recibo reenviado con el mismo `PurchaseId` sin conceder dos veces y recibo tardío para un jugador que ya salió -> `NotProcessedYet`.

**Sin errores de Luau ni advertencias** en 10 min (nuevo y mid): el loop de comprar semillas, plantar todas las tiles, esperar el crecimiento, cosechar, ir al puesto de venta con el propio `Teleport.toSellStand()` del cliente y vender, comprar tiles y mejoras, y volver a entrar (perfil idéntico) funcionó siempre. Con el estado `mid` el bot llega a rebirth.

**Qué no se pudo ejercitar**: el clima y los eventos en vivo corren (sin errores) pero el bot no los usa; el Wild Patch (nodos de la zona salvaje) y los trofeos/exhibiciones no están en el bot. Auto-farm queda bloqueado en el estado `new` (se prueba que se rechaza el pedido sin Farmhand).

## Que logro el bot (timeline)

| t (virtual) | cash | earned | empty | growing | rebirths | ripe | tiles | tutorial |
|---|---|---|---|---|---|---|---|---|
| 0:09 (start) | 184250 | 2300000 | 8 | 0 | 1 | 10 | 18 | 1 |
| 0:39 | 8414 | 2358482 | 0 | 19 | 1 | 0 | 19 | 1 |
| 1:39 | 9230 | 2359298 | 0 | 19 | 1 | 0 | 19 | 1 |
| 2:09 | 18014 | 2368082 | 0 | 19 | 1 | 0 | 19 | 1 |
| 3:09 | 28616 | 2500514 | 2 | 17 | 1 | 0 | 19 | 1 |
| 3:39 | 30575 | 2535430 | 12 | 7 | 1 | 0 | 19 | 1 |
| 4:39 | 57411 | 2562266 | 12 | 7 | 1 | 0 | 19 | 1 |
| 5:09 | 25 | 40237695 | 3 | 3 | 2 | 0 | 6 | 1 |
| 6:09 | 5 | 40237875 | 4 | 3 | 2 | 0 | 7 | 1 |
| 6:39 | 13 | 40238535 | 3 | 5 | 2 | 0 | 8 | 1 |
| 7:39 | 5 | 40239635 | 0 | 9 | 2 | 0 | 9 | 1 |
| 8:09 | 157 | 40241885 | 5 | 5 | 2 | 0 | 10 | 1 |
| 9:09 | 301 | 40243541 | 4 | 7 | 2 | 0 | 11 | 1 |
| 9:39 | 468 | 40248988 | 10 | 2 | 2 | 0 | 12 | 1 |
| 10:09 (end) | 18 | 40248988 | 4 | 8 | 2 | 0 | 12 | 1 |

Hitos:

- 0:09 session started
- 0:11 upgrade GrowSpeed
- 0:15 upgrade CropValue
- 0:18 upgrade Luck
- 2:31 upgrade GrowSpeed
- 2:34 upgrade CropValue
- 2:37 upgrade Backpack
- 3:11 upgrade Luck
- 4:56 store: clicked 4 buy buttons
- 4:58 upgrade GrowSpeed
- 4:58 rebirth!
- 6:13 rejoin (save + reload)
- 6:13 rejoin: leaves (mid)
- 6:27 rejoin ok: profile reloaded identical
- 6:32 upgrade Backpack
- 7:18 upgrade GrowSpeed
- 8:05 upgrade CropValue
- 9:36 upgrade GrowSpeed
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

Ninguno.

## Trafico de remotes

| remote:accion | llamadas | ok | rechazos inesperados | rechazos provocados | max s |
|---|---|---|---|---|---|
| Request:BuySeed | 23 | 23 | 0 | 0 | 0 |
| Request:BuyTile | 8 | 8 | 0 | 0 | 0 |
| Request:BuyUpgrade | 12 | 12 | 0 | 0 | 0 |
| Request:ClaimDaily | 1 | 1 | 0 | 0 | 0 |
| Request:HarvestAll | 42 | 42 | 0 | 0 | 0 |
| Request:Hello | 2 | 2 | 0 | 0 | 0 |
| Request:PlantAll | 35 | 35 | 0 | 0 | 0 |
| Request:Rebirth | 1 | 1 | 0 | 0 | 0 |
| Request:RedeemCode | 2 | 1 | 0 | 1 | 0 |
| Request:SellAll | 14 | 14 | 0 | 0 | 0 |
| Request:SetAuto | 1 | 1 | 0 | 0 | 0 |
| Request:SetAutoSeed | 1 | 1 | 0 | 0 | 0 |
| Request:SetLanguage | 4 | 4 | 0 | 0 | 0 |

RemoteEvents: HarvestFx (srv->cli 199, cli->srv 0), LiveEventUpdate (srv->cli 2, cli->srv 0), Notify (srv->cli 30, cli->srv 0), StateUpdate (srv->cli 162, cli->srv 0), StockUpdate (srv->cli 27, cli->srv 0), WeatherUpdate (srv->cli 4, cli->srv 0)

Avisos del servidor al jugador (Notify/Toast): ✨ PreviewPlayer harvested a Shocked Carrot! [rare] x5, ✨ PreviewPlayer harvested a Shocked Tomato! [rare] x2, Welcome back! Your crops kept growing while you were away 🌾 [success] x2, 🌙 12 crops ripened while you were away! [success] x1, Thanks! 2x Cash unlocked ⭐ [success] x1, 📖 New in Index: Golden Tomato! [rare] x1, 📖 New in Index: Shocked Tomato! [rare] x1, 📖 New in Index: Golden Blueberry Bush! [rare] x1, +$12.2M added! 💰 [success] x1, +$25.3M added! 💰 [success] x1, ✨ PreviewPlayer harvested a Golden Blueberry Bush! [rare] x1, 🌟 Moon Melon is in stock at the Seed Shop! [rare] x1, 📖 New in Index: Shocked Carrot! [rare] x1, ✨ PreviewPlayer harvested a Golden Carrot! [rare] x1, 🌟 Starfruit is in stock at the Seed Shop! [rare] x1, ✨ PreviewPlayer harvested a Golden Pumpkin! [rare] x1, 🌙 3 crops ripened while you were away! [success] x1, 📖 New in Index: Watermelon! [rare] x1, 📖 New in Index: Apple Tree! [rare] x1, 🔁 PreviewPlayer reached Rebirth 2! [success] x1, 📖 New in Index: Golden Carrot! [rare] x1, ✨ PreviewPlayer harvested a Golden Tomato! [rare] x1, 🌟 Mango Tree is in stock at the Seed Shop! [rare] x1, 📖 New in Index: Golden Pumpkin! [rare] x1

DataStore: CropKingdom_Referrals_v1/90000001 (lecturas 7, escrituras 0), CropKingdom_TotalEarned_v1/90000001 (lecturas 7, escrituras 7), CropKingdom_v1/u_90000001 (lecturas 12, escrituras 12)

Compras simuladas: prompt pase 7001 (grant); prompt producto 8007 (grant); recibo producto 8007 -> PurchaseGranted; prompt producto 8008 (grant); recibo producto 8008 -> PurchaseGranted; prompt producto 8009 (cancel)

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
[info] t=4:44 MarketplaceService:PromptGamePassPurchase(7001) mode=grant
[info] t=4:47 MarketplaceService:PromptProductPurchase(8007) mode=grant
[info] t=4:50 MarketplaceService:PromptProductPurchase(8008) mode=grant
[info] t=4:53 MarketplaceService:PromptProductPurchase(8009) mode=cancel
```
