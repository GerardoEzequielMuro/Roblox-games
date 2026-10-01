# Playtest de ki-warriors

- Comando: `python3 tools/uipreview/preview.py ki-warriors --playtest --minutes 10 --seed 1 --state mid`
- Fecha: 2026-10-01 | estado inicial: `mid` | tiempo virtual jugado: 10.2 min | reales: 116 s | rejoins del bot: 1
- El tiempo es virtual (scheduler propio de la herramienta); el bot juega por los remotes/funciones cliente reales del juego. Es una **aproximacion** de Roblox: ver "Que simula la herramienta" al final.

## Resumen (espanol)

**Veredicto: OK**

- Errores de Luau unicos (del juego): **0**
- Warnings unicos: **0**
- Remotes rechazados por el servidor sin que el bot lo esperara: **3** llamadas en 3 acciones
- Invariantes violados / problemas de guardado / recibos / DataStore: **0**
- Estados trabados > 60 s virtuales: **0** (ademas 1 tramos de progreso muy lento donde el bot sigue avanzando)
- Hilos que quedaron esperando para siempre (WaitForChild sin hijo, etc.): **0**
- Avisos de error que el servidor le mostro al jugador (Notify/Toast kind=error): **0**
- APIs de Roblox que el simulador no implementa y otros avisos del motor simulado: **0** (ver seccion "Avisos del simulador")
- Instancias vivas en el DataModel: 18487 (t=0:39) -> 18460 (t=10:09); partes 13064 -> 13052; GUI 803 -> 801
- Acciones del bot: beams=0, blasts=22, charges=0, deaths=13, flights=0, forms=0, kills=16, punches=1307, relics=0, skipped=1, stepsDone=8, tech=0, walks=29, windows=16

## Analisis del revisor (a mano)

**Hallazgos reales**

1. **La historia pide mucho más poder que el que el propio tutorial entrena** (pacing, severidad baja/media): el paso 9 pide 1.000 de poder, pero el paso 13 ("Aprender una técnica") necesita 2.000 de poder para poder comprar la primera técnica (`Config.Techniques[1].reqPower = 2_000`, `src/shared/Config.luau:280`; el servidor responde `msg.need_power` en `src/server/Services/Progression.luau:138`) y el paso 14 (zona `thunder_falls`) pide 5.000 (`reqPower` de la zona). El texto del paso es solo "Aprender una técnica" (`src/shared/Locales/en.luau:143`) sin decir que hace falta más poder: el jugador ve el botón fallar. El bot (que ya entrena en la mejor zona disponible, x4) pasa los pasos 1-12 en ~2,5 min y después se queda ~3 min en el paso 13 y varios más en el 14: el vigilante lo marca como "progreso muy lento", no como traba (el poder sigue subiendo). `SkipStep` no ayuda: solo se puede saltar durante el tutorial (`Onboarding.canSkip`, `src/server/Services/Story.luau:110-118`) y devuelve `false` sin mensaje.
2. **Regalos por minutos de sesión farmeables reentrando** (diseño): `State.giftsClaimed` (`src/server/Services/State.luau:34`) es por sesión y no se guarda en el perfil; `Config.Gifts` se vuelve a poder reclamar después de reentrar.
3. Los pases y productos tienen `id = 0` (tienda apagada en el repo); el playtest les pone ids falsos para probar el flujo de compra: recibos concedidos una vez y reenviados sin duplicar.

**Sin errores de Luau ni advertencias** en 10 min (nuevo y mid): entrenar (golpes = reps), cargar ki, ráfagas, volar, caminar al campamento y pelear contra los enemigos del servidor, comprar equipo, entrenar en la zona, transformarse, rayo cargado, comprar y usar la técnica, reliquias, viajar entre planetas (estado `mid`), jefes, ajustes de auto, tienda y rejoin (perfil idéntico).

**Limitaciones de la herramienta que afectan a este juego**: no hay colisiones ni terreno (el bot camina en línea recta a `WalkSpeed`), los enemigos son los del servidor (sí se mueven y pelean) y el combate usa los mismos `Controls.punch/blast/beam` del cliente; el daño que recibe el bot casi no se ejercita porque el bot es muy fuerte frente a los enemigos de la planeta 1.

## Que logro el bot (timeline)

| t (virtual) | forms | gear | gems | kills | planet | power | progress | reps | sparks | story |
|---|---|---|---|---|---|---|---|---|---|---|
| 0:09 (start) | 2 | 4 | 135 | 340 | 3 | 126000 | 0 | 52000 | 49500 | 14 |
| 0:39 | 2 | 4 | 155 | 340 | 1 | 132336 | 60 | 52060 | 49500 | 14 |
| 1:39 | 2 | 4 | 190 | 349 | 2 | 138953 | 10 | 52131 | 83808 | 19 |
| 2:09 | 2 | 4 | 190 | 349 | 2 | 148220 | 91 | 52212 | 83808 | 19 |
| 3:09 | 2 | 4 | 195 | 349 | 2 | 156914 | 0 | 52288 | 99808 | 20 |
| 3:39 | 2 | 4 | 195 | 355 | 2 | 157204 | 0 | 52321 | 150816 | 21 |
| 4:39 | 2 | 4 | 195 | 355 | 2 | 208244 | 145 | 52466 | 150816 | 21 |
| 5:09 | 2 | 4 | 195 | 355 | 2 | 223944 | 188 | 52509 | 97430816 | 21 |
| 6:09 | 2 | 4 | 200 | 355 | 2 | 279352 | 0 | 52647 | 97478816 | 22 |
| 6:39 | 2 | 4 | 235 | 356 | 2 | 279584 | 0 | 52669 | 98064416 | 24 |
| 7:39 | 2 | 4 | 235 | 356 | 3 | 279584 | 0 | 52669 | 98064416 | 24 |
| 8:09 | 2 | 4 | 235 | 356 | 3 | 279584 | 0 | 52669 | 98064416 | 24 |
| 9:09 | 2 | 4 | 235 | 356 | 3 | 279584 | 0 | 52669 | 98064416 | 24 |
| 9:39 | 2 | 4 | 235 | 356 | 3 | 279584 | 0 | 52669 | 98064416 | 24 |
| 10:09 (end) | 2 | 4 | 235 | 356 | 3 | 279584 | 0 | 52669 | 98064416 | 24 |

Hitos:

- 0:09 session started, story step 14
- 0:09 story step 14 (zone)
- 0:58 story step 15 (relic)
- 1:04 story step 16 (boss)
- 1:14 story step 18 (defeat)
- 1:31 story step 19 (zone)
- 3:01 story step 20 (defeat)
- 3:34 story step 21 (zone)
- 5:57 story step 22 (boss)
- 6:20 story step 24 (defeat)
- 7:23 rejoin (save + reload)
- 7:23 rejoin: leaves (mid)
- 7:37 rejoin ok: profile reloaded identical
- 8:50 pressing SKIP on story step 24
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
| Request:CollectRelic | 2 | 1 | 1 | msg.already_claimed x1 |
| Request:SkipStep | 1 | 0 | 1 | ? x1 |
| Request:Travel | 6 | 5 | 1 | msg.in_combat x1 |

Ejemplos de `Request:CollectRelic`: `t=64 CollectRelic(i=1) -> msg.already_claimed`

Ejemplos de `Request:SkipStep`: `t=530 SkipStep() -> ?`

Ejemplos de `Request:Travel`: `t=380 Travel(planet=3) -> msg.in_combat`


## Invariantes, trabas, guardado, recibos

- **Progreso muy lento (no es una traba: el bot sigue avanzando)** t=7:52: 'story step progress' did not progress for 91 s of virtual time (state: 24:0) \| step 24 (defeat): power 279584 \| the bot kept making measurable progress toward it (a long grind, not a freeze)

## Trafico de remotes

| remote:accion | llamadas | ok | rechazos inesperados | rechazos provocados | max s |
|---|---|---|---|---|---|
| Request:ClaimDaily | 1 | 1 | 0 | 0 | 0 |
| Request:CollectRelic | 2 | 1 | 1 | 0 | 0 |
| Request:GetBoards | 1 | 1 | 0 | 0 | 0 |
| Request:GetState | 2 | 2 | 0 | 0 | 0 |
| Request:SetLanguage | 3 | 3 | 0 | 0 | 0 |
| Request:SetSetting | 6 | 6 | 0 | 0 | 0 |
| Request:SetStat | 5 | 5 | 0 | 0 | 0 |
| Request:SkipStep | 1 | 0 | 1 | 0 | 0 |
| Request:SpinAura | 6 | 3 | 0 | 3 | 0 |
| Request:Travel | 6 | 5 | 1 | 0 | 0 |

RemoteEvents: Act (srv->cli 0, cli->srv 674), Arena (srv->cli 3, cli->srv 0), Combat (srv->cli 87, cli->srv 0), Fx (srv->cli 1066, cli->srv 0), Knock (srv->cli 73, cli->srv 0), LiveEventUpdate (srv->cli 2, cli->srv 0), Notify (srv->cli 9, cli->srv 0), Numbers (srv->cli 660, cli->srv 0), Quests (srv->cli 561, cli->srv 0), Reward (srv->cli 4, cli->srv 0), State (srv->cli 41, cli->srv 0), Toast (srv->cli 1, cli->srv 0), WorldBoss (srv->cli 2, cli->srv 0)

Avisos del servidor al jugador (Notify/Toast): msg.thanks [success] x3, msg.cosmetic_unlocked [success] x3, toast.rush_start [info] x1, msg.bp_weekly [success] x1, msg.bp_firstwin [success] x1, msg.pass_unlocked [success] x1

DataStore: KiWarriors_Power_v1/90000001 (lecturas 2, escrituras 1), KiWarriors_Profiles_v1/u_90000001 (lecturas 17, escrituras 17), KiWarriors_Rebirths_v1/90000001 (lecturas 2, escrituras 1), KiWarriors_Referrals_v1/90000001 (lecturas 7, escrituras 0)

Compras simuladas: prompt producto 8002 (grant); recibo producto 8002 -> PurchaseGranted; prompt producto 8003 (grant); recibo producto 8003 -> PurchaseGranted; prompt producto 8004 (grant); recibo producto 8004 -> PurchaseGranted; prompt pase 7001 (grant); prompt producto 8016 (cancel)

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
[info] t=4:52 MarketplaceService:PromptProductPurchase(8002) mode=grant
[info] t=4:55 MarketplaceService:PromptProductPurchase(8003) mode=grant
[info] t=4:58 MarketplaceService:PromptProductPurchase(8004) mode=grant
[info] t=5:01 MarketplaceService:PromptGamePassPurchase(7001) mode=grant
[info] t=5:04 MarketplaceService:PromptProductPurchase(8016) mode=cancel
```
