# Tap Pets Simulator: handoff

Todo se revisó con herramientas estáticas (build, type check, tests puros). **No lo vi andar**: en
este contenedor no hay Roblox Studio, así que no hubo playtest ni capturas.

## Qué cambié

**El HUD que quedó a medias**
- El hallazgo principal: el place ya armado `pet-tap-simulator/TapPetsSimulator.rbxlx` (la "Opción A"
  del README, el que se abre directo en Studio) era **de antes de la reescritura**. Tenía el HUD viejo
  (monedas arriba al centro, sin objetivo, sin dock, sin TAP) y le faltaban los traits y `Guide`.
  Si Gerar abrió ese archivo, vio el HUD viejo. Lo regeneré desde `src` con `rojo build`.
- En `src` la reescritura estaba casi completa: todos los `require`, nombres de ventanas y handlers
  del server cierran. Lo que se había perdido o quedado colgado:
  - El cartel "¡Tocá donde sea para ganar Taps!" del primer minuto se había borrado junto con el
    viejo `Main.client`. Lo volví a poner arriba del botón TAP: se mueve hasta los primeros 60 taps
    y después se desvanece. Está en `src/client/UI/Hud.luau` (`TapHint`).
  - Borré de los 12 idiomas 8 claves que ya no usaba nadie: `hud.autotap_*`, `hud.autohatch_*`,
    `pets.delete`, `rebirth.reward` y `egg.auto_locked` (`src/shared/Locales/*.luau`).
  - Arreglé un comentario viejo en `src/client/UI/Toasts.luau`, que seguía hablando de la barra de
    monedas de arriba.
- **HUD progresivo**, en el nuevo `src/shared/HudUnlock.luau` (es puro y tiene test). Al arrancar se
  ven Recompensas · TAP · Mascotas + Tienda. Los demás botones aparecen con un pop cuando sirven:
  - 1er huevo: Mejoras, Misiones y el chip Auto Tap.
  - 3 huevos: Índice, Códigos/Idioma, Auto Hatch y Auto Equip.
  - 5 huevos: Teletransporte.
  - 10 huevos: Invitar.
  - Zona 3 o rebirth pagable: Rebirth.
  - Primer rebirth: Auto Rebirth.

  Solo mira contadores que nunca bajan y el HUD guarda lo que ya mostró, así que un rebirth no
  esconde nada.
- Los textos sueltos de Super Luck, x2 Taps y amigos pasaron a ser chips oscuros con ícono.

**Íconos** (`src/client/UI/Theme.luau`)
- Agregué `Theme.setIcon`, `Theme.icon`, `Theme.lead`, `Theme.clearLead` y el mapa
  `Theme.EMOJI_ICONS` (emoji → nombre del pack).
- Si `Icons.get(nombre)` devuelve un id, se muestra un `ImageLabel` con ScaleType Fit. Si no, queda
  el mismo emoji que hoy. Como hoy todos los ids están vacíos, **visualmente no cambia nada** hasta
  que se suban.
- Los usan el menú, el dock, el botón TAP, las píldoras (Taps usa `coin`, Gemas usa `gem`), los
  chips auto, los timers y ofertas, los medallones de las ventanas, las tarjetas de la tienda, las
  recompensas, las misiones, las mejoras y los precios en gemas.

**Política de ítems aleatorios pagos**
- Faltaba mostrar los % antes de comprar en dos lugares:
  - Las tarjetas Magic Egg x1/x3 de la tienda.
  - La oferta del Starter Pack, que trae un Magic Egg.

  Ahora muestran cada mascota con su % (suman 100) más la chance de Golden. Lo hacen
  `Formulas.productEgg` (nuevo) y `Purchase.oddsText`, y se ve en `StoreWindow.luau` y
  `Popups.luau`.
- Lucky, VIP, Super Luck y el pase Magic Eggs muestran qué cambian con los números del jugador
  ("Suerte x1.10 → x1.60", "Golden 1% → 10%"), vía `Purchase.effectText`.
- Para los jugadores restringidos, el Magic Egg del spawn (Robux) ahora se oculta: prompt y cartel
  apagados en su cliente, y si igual se dispara, sale un aviso. Está en `EggPanel.luau`.
- Lo que ya estaba bien y no toqué:
  - Bloqueo de compra en `Purchase`.
  - Tienda filtrada.
  - Starter Pack apagado desde el server.
  - Todo restringido hasta que PolicyService responda.
- Test puro nuevo `pet-tap-simulator/tests/policy_hud.luau` (111 checks). Cubre:
  - Flags de todos los productos y pases.
  - Odds que suman exactamente 100% en todos los huevos y con varias suertes.
  - Que el Magic Egg no dependa de la suerte, porque se muestra con suerte 1.
  - Las reglas del HUD progresivo.
- `tests/AutoTestClient.client.luau` (playtest de Studio): lo adapté a los chips que aparecen de a
  poco y le sumé checks de odds en la tienda y del prompt del Magic Egg con restricción.

**Look**
- Paneles con un degradé suave (`Theme.panel`).
- Depth of field lejano muy leve (`WorldBuilder.luau`). Se apaga en perfil lite, igual que bloom y
  sun rays (`WorldFx.luau`).
- El mundo ya tenía cielo, atmósfera, color grade y clima por zona, y mascotas con 3 rigs, así que
  no los toqué.

**Docs**: `DESIGN.md` (HUD progresivo, íconos, odds en tarjetas) y `README.md` (módulos y test nuevos).

## Cómo lo verifiqué

- `rojo build default.project.json` → OK (y regeneré `TapPetsSimulator.rbxlx`).
- `luau-lsp analyze` sobre `src` → 0 errores. En `tests/AutoTestClient` quedaron las mismas 5 lints
  que ya había.
- Tests puros, todos pasan:
  - `check_config`: ALL CHECKS PASSED.
  - `economy_sim`: 1er rebirth ~1h 01m, zona 5 ~3h 31m, sin cambios.
  - `format_check` y `odds_table`: OK.
  - `locale_check`: 356/356 claves en los 12 idiomas.
  - `unit_p0`: 55/55.
  - `policy_hud` (nuevo): 111/111.

## Qué hay que mirar en Studio

- Correr el playtest (`test.project.json`). Toqué los checks de chips y de política, así que es lo
  primero que tiene que dar verde.
- Primer minuto con una cuenta nueva: que se vean solo 4 botones, que el cartel del TAP no tape nada
  y que los botones nuevos "salten" al desbloquearse. Mirar también el layout del menú izquierdo con
  pocos botones.
- Tienda con IDs de prueba: que el texto de odds de las tarjetas Magic Egg entre en la placa de
  40 px, sobre todo en idiomas largos (de/ru) y en celular.
- Popup del Starter Pack: la placa de odds y que el cuerpo del texto (ahora más bajo) se lea bien.
- En Studio, PolicyService puede no responder. En ese caso el jugador queda "restringido" y el
  Magic Egg del spawn aparece apagado a propósito.
- El depth of field: si molesta en alguna zona, bajar `FarIntensity` en `WorldBuilder.luau`.
- Cuando se suban los íconos (`tools/icons/upload_assets.py`), revisar tamaño y posición de las
  imágenes. Ese camino (`ImageLabel`) nunca corrió, porque hoy todos los ids están vacíos.

## Pendiente

- Subir los íconos (no inventé IDs). Hasta entonces todo sigue con emoji.
- Crear los productos y pases en el Creator Dashboard (IDs en `Config.luau`).
- Mascotas con siluetas más trabajadas y una fuente más "2026" (Fredoka bold vía `FontFace`): no
  los toqué sin poder ver el resultado.
- Íconos en lugares secundarios (ventana de Mascotas, Índice, Invitar, cinemática de hatch): siguen
  con emoji.
- Del lado del server no se puede frenar la compra de un restringido que prompteé con un exploit.
  Si llega el recibo, se entrega igual, porque ya pagó. La barrera real es del lado del cliente,
  como indica Roblox.

## Ronda 2

Igual que la ronda 1: todo con herramientas estáticas y tests puros. **No vi nada andando** (sin Studio en el contenedor).
Había ediciones parciales de un intento anterior: solo estaban los precios y pases nuevos en `Config.luau`, sin lógica,
sin textos ni UI. Los conservé (estaban bien) y les construí todo lo que faltaba.

### Precios

Sección 4.3 de `docs/research/top-juegos-y-precios.md`. Los IDs siguen en 0 (los crea Gerar).

| Ítem | Antes | Ahora | Por qué |
|---|---|---|---|
| Double Taps | 399 | 449 | 2x Clicks cuesta 499-599 en el género |
| Lucky | 199 | 249 | PS99 cobra 275 |
| Magic Eggs | 349 | 599 | estaba regalado (PS99 1.200) |
| +3 Pet Slots | 299 | 249 | primer escalón de la escalera 249 / 649 |
| x8 Hatch (nuevo) | — | 699 | Tap Sim 849, PS99 +15 eggs 625. Incluye x3 |
| Auto Rebirth (nuevo) | — | 199 | Tap Sim 199, Clicker 299 |
| Super Lucky (nuevo) | — | 699 | PS99 Ultra 800, Tap Sim 749 |
| +6 Pet Slots (nuevo) | — | 649 | segundo escalón, se suma al +3 |
| +50 Storage (nuevo) | — | 99 | Tapping Sim 199, AD 99 |
| Gems 1.400 (nuevo) | — | 499 | escalera de gemas con bonus creciente (+37% vs el pack de 49) |
| Gems 3.200 (nuevo) | — | 999 | +57%; lleva el cartel "mejor valor" (antes lo tenía el de 600) |
| Auto Tap, x3 Hatch, Auto Hatch, VIP, Gems 100/600, Magic Egg x1/x3, Starter Pack, packs de Taps | sin cambios | sin cambios | la guía dice "ok" |

- El Starter Pack sigue en 99 con 399 tachado. Como ahora hay más productos, agregué un test que comprueba que 399 sea
  **honesto**: comprar las partes por separado (1 Magic Egg + 2 Super Luck de 15 min + 2 packs de 100 gemas) cuesta 445, o sea
  que el precio de lista no supera lo real.
- No agregué el pase "Secret/Huge Hunter" (1.299). Un pase que sube la chance del pet Secret es un modificador pago de
  probabilidades (hay que mostrar el efecto y bloquear restringidos) y se acerca a pay-to-win; preferí no hacerlo sin que Gerar lo decida.
  Lo dejo en Pendiente.
- Cómo quedó cada pase nuevo (todo en el server, en `src/server/Services/` y `src/shared/Formulas.luau`):
  - **x8 Hatch** (`OctoHatch`): `Eggs.hatch` acepta 1/3/8 (`Formulas.validHatchCount`, rechaza cualquier otro número, NaN, texto...).
    Comprar x8 marca también x3 como comprado (`Formulas.applyIncluded`), así que nadie paga algo que ya tiene. El Auto Hatch (con el pase Auto Hatch)
    elige el tamaño más grande que pueda pagar y que entre en el inventario (`Formulas.autoHatchCount`).
  - **Super Lucky**: +150% de suerte, se suma al Lucky (`Formulas.luck`). Es modificador pago: está en `Config.PaidRandomPasses`,
    así que se oculta/bloquea para restringidos y la tienda muestra "Suerte x1.10 → x2.60" con los números del jugador (`Purchase.effectText`).
  - **+6 Pet Slots** (`Formulas.maxEquip`), **+50 Storage** (`Formulas.maxInventory`, `State.maxInventory`, `Pets.hasRoom` ahora recibe el jugador).
  - **Auto Rebirth**: lo gratis pasó de "después del 1er rebirth" a "después del 3er" (`Config.AutoRebirthMinRebirths = 3`); el pase lo abre
    después del 1ro (`Formulas.autoRebirthUnlocked`). Siempre hace falta un rebirth manual para haber visto qué hace.
  - Recibos: no cambié `processReceipt` (idempotente por `PurchaseId`, se guarda antes de devolver `PurchaseGranted`); los packs nuevos de gemas pasan
    por `Rewards.grant` igual que los viejos. Los pases se dan en `PromptGamePassPurchaseFinished` y al entrar.
  - Textos en los 12 idiomas (20 claves nuevas, `locale_check` 375/375 por idioma).
- Política: Super Lucky está dentro de los tests de `tests/policy_hud.luau` (flag, efecto numérico exacto, stack con Lucky, odds de todos los huevos
  suman 100% con Lucky + Super Lucky). Las gemas nuevas no son ítem aleatorio (test).

### Retención

| # | Ítem | Estado | Dónde |
|---|---|---|---|
| 1 | Loop de segundos con feedback inmediato | ya estaba | `client/Tapper.luau` (números flotantes, partículas, sonido), `HatchCinematic.luau` |
| 2 | Próximo objetivo visible y cercano | ya estaba | `client/Guide.luau` (barra + "te faltan X" + rayo al lugar), botón de Rebirth con costo |
| 3 | Metas de sesión y largas | ya estaba | gates, rebirth, huevos; Índice con %, leaderboards, Secret 1/100.000 (`Rewards.luau`, `Leaderboard.luau`) |
| 4a | Login diario con racha | ya estaba; **agregado** el contador de racha | `Rewards.luau`; `client/UI/RewardsWindow.luau` ("🔥 Racha: N días") |
| 4b | Regalos por tiempo en sesión | ya estaba; **ajustado** | `Config.Gifts`: el 1er regalo (1 min de Taps) ahora llega a los 45 s y paga el primer huevo dentro del primer minuto |
| 4c | Offline | ya estaba | `Offline.luau`, cofre del Pet Park |
| 4d | Eventos con reloj | ya estaba; **agregado** el reloj al próximo | `LiveEventService.luau`; el pill del HUD (`Hud.luau`) ahora muestra "Hora de Suerte en 1h 12m" cuando no hay evento (usa `nextAt` del server, que ya viajaba). Cuenta solo el evento recurrente; el Golden Weekend queda solo como evento activo |
| 4e | Stock/restock por hora | no agregado | ver Pendiente |
| 4f | Códigos / grupo | ya estaba | `Config.Codes`, `Social.luau` (`Config.GroupId = 0` hasta que exista el grupo) |
| 5a | Anuncio server-wide de hallazgos raros | ya estaba | `Eggs.broadcast` (Legendary+), Toast global |
| 5b | Invitar / referidos | ya estaba | `Social.luau`, `InviteWindow.luau` |
| 5c | Regalar mascotas | no aplica | sin trading no hay regalos; con mascotas de pago o al azar sería un riesgo de política (trading de ítems aleatorios) y de abuso |
| 5d | Leaderboards en el mundo | ya estaba | tableros en el spawn (`Leaderboard.luau`) |
| 6 | Primer minuto | ya estaba de la ronda 1; **reforzado** con el regalo a los 45 s | `HudUnlock.luau`, `TapHint`, `Config.Gifts` |

### Otros cambios

- `client/UI/EggPanel.luau`: botón x8 (tecla **Q**), 4 botones de 152 px en el panel de 680. Si no tenés el pase, el botón abre la compra
  (igual que el x3). El Magic Egg de Robux ignora el x8.
- `client/UI/HatchCinematic.luau`: con x8 la fila de 8 mascotas se achica para entrar en el ancho de pantalla (antes solo estaba pensada para 3).
- `client/UI/StoreWindow.luau`: íconos de los pases nuevos.
- `Auto Rebirth`: el mensaje de bloqueo ahora dice cuántos rebirths faltan y que existe el pase (`msg.autorebirth_locked`).
- Ronda 1 "Pendiente" (solo lo que es código y seguro): no había nada más que fuera código seguro. Los íconos necesitan subirse a Roblox, y
  las mascotas/fuente nuevas necesitan ver el resultado. Regeneré `TapPetsSimulator.rbxlx` desde `src`.
- `tests/AutoTestClient.client.luau`: checks nuevos (x8 sin pase rechazado, tamaño inventado rechazado, x8 con pase da 8 mascotas).
- Docs: `DESIGN.md` (precios, Auto Rebirth, luck, racha, reloj) y `README.md` (Q = x8, test nuevo).

### Cómo lo verifiqué

- `rojo build default.project.json` → OK (también regenerado `TapPetsSimulator.rbxlx`).
- `luau-lsp analyze` sobre `src` → sin salida (0 errores). Sobre `tests`: las mismas 5 líneas que ya había.
- Tests puros, todos pasan:
  - `tests/passes_pricing.luau` (nuevo): 117 checks, 0 fallas (precios vs la guía, escalera de gemas, Starter Pack honesto, x8/slots/storage/Auto Rebirth/Auto Hatch).
  - `tests/policy_hud.luau`: 136 checks, 0 fallas (antes 111; sumé Super Lucky y gemas nuevas).
  - `tests/locale_check.luau`: LOCALE CHECKS PASSED, 375/375 claves en los 12 idiomas.
  - `tests/unit_p0.luau`: 55/55.
  - `sim/check_config.luau`: ALL CHECKS PASSED (40 pets, 9 eggs, 5 zones, 13 passes, 11 products).
  - `sim/economy_sim.luau`: zona 2 ~5m, zona 3 ~35m, zona 4 ~1h 44m, zona 5 ~3h 20m, 1er rebirth ~1h 00m. El sim modela a un jugador free que no compra,
    así que los precios no lo mueven; el cambio de 0,75 min en el primer regalo casi no se nota.
  - `sim/format_check.luau`, `sim/odds_table.luau`: OK.
- El playtest de Studio (`tests/AutoTestClient`) **no lo pude correr**.

### Qué mirar en Studio

- Correr el playtest (`test.project.json`) primero. Los checks nuevos de x8 están después de los de x3. `grantPasses` ahora da también OctoHatch: el Auto Hatch va a abrir de a 8.
- Panel de huevos: que los 4 botones entren en 680 px, sobre todo en de/ru/vi y en celular (texto "Abrir x8  1.6K").
- x8 en el cinematic: que las 8 mascotas entren en pantalla y no se vea todo diminuto en celular. Si queda chico, partirlo en 2 filas de 4.
- Tienda con IDs de prueba: que entren las 13 tarjetas de pases y las 11 de productos en la grilla, y el cartel "mejor valor" en el pack de 3.200 gemas.
- Pill de eventos del HUD con el reloj al próximo evento (gris): que el texto entre en 200 px en idiomas largos.
- Ventana de Recompensas: la línea de racha arriba a la derecha.
- Auto Rebirth con 1 y 2 rebirths: el chip aparece pero avisa que faltan rebirths; con el pase en Studio (`StudioGrantAllPasses`) debe andar desde el 1ro.

### Pendiente

- Crear en el Creator Dashboard los 5 pases y 2 productos nuevos y pegar los IDs en `Config.luau`, más los que ya estaban pendientes.
- Decidir si va el pase "Secret/Huge Hunter" (1.299): ver arriba el porqué de no haberlo hecho.
- Stock/restock rotativo por hora (estilo Grow a Garden): hace falta decidir qué rota (un huevo "caliente" con más suerte gratis por hora).
  Toca las odds mostradas en vivo y la economía, así que prefiero hacerlo con Gerar viendo el resultado en Studio.
- Íconos subidos a Roblox (sin IDs inventados), mascotas con mejor silueta y fuente nueva, siguen como en la ronda 1.
- Con un exploit, un restringido que fuerce el prompt de compra igual recibe el ítem si paga (limitación de la ronda 1, sin cambios).

## Ronda 3: ranuras de modelos

### Qué cambié

- Carpeta `assets/models/` (solo README) mapeada como `ServerStorage.ModelLibrary` en los 6 `*.project.json`.
- `src/server/World/ModelSlots.luau`: `ModelSlots.spawn(slot, cf, targetSize, parent, fallback, {collide, maxParts})`. Clona el modelo (o variante `slot_N` elegida por posición), borra todo script, escala a la caja, lo apoya en el piso, anclado, sin sombras ni touch. Si no hay modelo, o pasa las 300 partes (1500 en total), llama al `fallback` (el código de antes, sin cambios).
- `ModelSlotsMath.luau`: fit, variantes y presupuesto como funciones puras.
- `WorldBuilder.luau`: 14 ranuras (tree, pine, rock, bush, mushroom, lollipop, cupcake, crystal, snowman, windmill, igloo, cake, volcano, rocket). Las funciones originales pasaron a `xxxPrimitive`; el wrapper usa la ranura solo con los parámetros por defecto (los árboles/pinos/cristales del horizonte con escala y los cristales de colores siguen primitivos). Huevos, portal, OVNI y obby/plataformas no se tocaron.
- Doc con tabla y paso a paso: `docs/modelos/pet-tap-simulator.md`.

### Cómo lo verifiqué

- `rojo build` de los 6 project files: OK con la carpeta solo con README.
- Prueba de swap: un `.rbxmx` temporal (Model con Part + Script llamado `tree`) en `assets/models`; el build incluyó `ServerStorage.ModelLibrary.tree`. Lo borré.
- `luau-lsp analyze` sobre `src`: sin salida. Tests puros: todos pasan, incluido `tests/model_slots.luau` nuevo (19 checks). No pude correr Studio.

### Qué mirar en Studio

- Con la biblioteca vacía el mundo debe ser idéntico. Con un modelo: que apoye en el piso, tamaño/orientación (frente a -Z; molino e iglú giran según `facing`) y que no bloquee el camino.
- Con modelos puestos el RNG del escenario cambia (el fallback consume `rng` y el modelo no), así que las posiciones de las props siguientes se corren. No afecta el juego.
- Correr el playtest (`test.project.json`): los budgets (partes, shadow casters, touchable) cuentan los modelos.

## Ronda 4: UI arreglada con la vista previa

Todo verificado con `tools/uipreview` (PNG/txt regenerados en `docs/previews/pet-tap-simulator/`). Rojo build, luau-lsp y los tests puros quedan en verde.

### Qué se arregló
- **Escala en celular** (`src/client/UI/Root.luau:57`): en táctil la escala ahora es `clamp(min(X/940, Y/390), 0.8, 1)` en vez de 0.55 (PC igual que antes). Antes: botones de 31-39 px y textos de 8 px. Ahora: todos los botones del HUD >= 44 px reales.
- **HUD táctil compacto** (`UI/Hud.luau:129-132,151-159,283`): menú de 4 columnas con celdas de 62 (antes 70), bloque de monedas de 94 de alto, objetivo de 320 de ancho. Con escala 0.8 el bloque izquierdo termina arriba del joystick, el objetivo entra entre las dos columnas y el dock queda entre joystick y salto.
- **Badges "!" tapados** (`Hud.luau:111`, `:202`): `ZIndex = 20 - orden` en los botones del menú (el vecino de la derecha ya no los pisa) y `ZIndex = 5` en Rewards del dock (su badge quedaba debajo del botón TAP).
- **Ventanas en celular** (`UI/Windows.luau:62-70,154-180`): alto máximo 350 y, si la ventana pasa un `canvasH`, el cuerpo es un `ScrollingFrame` en táctil (Upgrades, Teleport, Codes, Quests, Rewards, Index; llamadas en `ProgressWindows.luau`, `QuestsWindow.luau`, `RewardsWindow.luau`, `IndexWindow.luau`). Antes todas se salían de la pantalla (hasta 520 x 0.55 más el escalado). En PC no cambia nada.
- **Botones chicos**: Pets (Equip Best / Delete / "+") pasan a 56 de alto en `PetsWindow.luau:32-70`, pestañas del Index a 56 (`IndexWindow.luau:64`), X del panel de huevos a 56 (`EggPanel.luau:122`).
- **Rebirth en celular** (`ProgressWindows.luau:92-110`): filas más compactas para que el botón no pise la nota.
- **Plural**: "Deleted 1 pets" -> clave nueva `toast.deleted1` en los 12 idiomas (`shared/Locales/*.luau`), usada en `PetsWindow.luau:83`. El resto de textos con `{n}` ya tenían singular o no hay caso n=1 (`reward.egg1`, quests craft/rarity ya están en singular).

### Antes / después
- Celular mid: 8 hallazgos (2 high) -> 0. Todas las ventanas en PC: 0 hallazgos (antes badge tapado en cada captura).
- Celular con ventana abierta: quedan solo avisos `core-overlap` de bajo valor (contenido de una ventana modal sobre la zona del joystick/salto). La ventana es modal y tapa el joystick, así que no afecta el juego.
- Laptop (1366x768) y tablet (1180x820): 0 hallazgos, se ven limpios (no se dejaron PNG extra).

### Lo que queda
- Columna derecha en celular: si aparecen a la vez evento, chips de boost, Starter Pack y botón de anuncio, la columna crece hacia el botón de salto (caso raro; en el estado normal termina en y~250 de 390).
- Probabilidades del huevo con 4 decimales (57.6923%): se leen bien, no las toqué (vienen de `Formulas.displayOdds`).
- Nombres en japonés/coreano/tailandés como cajitas: falta de fuente CJK de la herramienta, no del juego.
- "Lv 6/3" en Pet Slots (Upgrades) sale del perfil de prueba del fixture (nivel por encima del máximo), no es bug de UI.

### Para confirmar en Studio
- Con `ForceTouchLayout` (o el emulador de celular): que el bloque izquierdo no toque el joystick y que el dock quede entre joystick y salto en un iPhone real (el área útil cambia con el notch).
- Que el scroll de las ventanas en táctil se sienta bien (Upgrades, Teleport, Codes, Quests, Rewards, Index) y que el ZIndex de los badges no rompa las animaciones de "pop" al desbloquear botones.
- Que los textos del menú (Upgrades, Teleport) se lean a 0.8 con la fuente real.

## Ronda 5: ritmo de progresión

Simulador nuevo `pet-tap-simulator/sim/pacing_sim.luau` (núcleo en `sim/pacing_core.luau`, usa `Config` y `Formulas` reales). Corre con `luau sim/pacing_sim.luau -a 9` (primera sesión de 4 h) o `-a 5 week` (7 días, 2 sesiones por día). `sim/pacing_tune.luau` reajusta costos de puertas/huevos/rebirth contra los objetivos. Test nuevo: `tests/pacing_targets.luau` (16 checks, falla si un hito sale de su ventana; ~6 s). `economy_sim.luau` queda como modelo viejo (marcado como tal).

### Jugador simulado (free)
Toca 6/s, hatchea cada 3 s el huevo con mejor ganancia esperada (si repaga en 150 s), equipa lo mejor, craftea, compra la puerta apenas puede, rebirth si alcanza y no hay puerta a menos de 5 min, gemas a TapPower/PetSlots/Luck (Walk Speed con el sobrante). Cobra regalos de sesión, daily (a los 30 s), 3 quests por día (una cada ~12 min, huevo Magic de bonus) y offline al volver. Esto es más completo que el sim viejo, por eso los "antes" difieren de los del round anterior (daily/quests/huevos Magic aceleran todo).

### Hitos (tiempo de juego activo, mediana de 9 semillas)
| Hito | Objetivo | Antes | Después |
|---|---|---|---|
| Primera ganancia visible | < 10 s | 1 s | 1 s |
| Primera compra (huevo básico) | < 60 s | 17 s | 17 s |
| Primer upgrade de gemas | <= 3 min | 5:00 | 2:00 |
| Compras en los primeros 3 min (upgrades de gemas) | >= 3 | 10 (0) | 19 (3) |
| Zona 2 Candy Land | ~5 min | 2:43 | 4:31 |
| Huevo Sprinkle | | 9:14 | 7:19 |
| Zona 3 Frost Peak | 10-20 min | 29:55 | 13:10 |
| Zona 4 Lava Caves | 20-40 min | 43:35 | 27:34 |
| Primer rebirth | 30-60 min | 39:27 | 37:59 |
| Rebirth #2 | | 44:51 | 48:11 |
| Zona 5 Cosmic Void | horas | 53:29 | 1h 13m |
| Rebirth #4 | | 56:10 | 1h 48m |
| Rebirth #5 / #6 | cola larga | 1h 05 / 1h 52 | 3h 18 (2 de 9) / nunca en 4 h |
| Mayor hueco entre "tiers nuevos" en la 1ra hora (mediana) | <= 15 min | 22 min | 12.6 min (peor semilla 20) |
| Mayor tramo sin NADA nuevo (tier, regalo, quest, upgrade) | <= 10 min | 8 min | 10 min (regalos cada 10 min) |

Semana (5 semillas, 2 sesiones por día): rebirth #5 en el día 2, #6 en el día 4, #7 pasa de la semana.

### Qué cambié y por qué (`src/shared/Config.luau`)
- Gate Candy Land 27K -> 79K: con daily + spotted egg el jugador llegaba a los 2:43; ahora ~4:30 y se siente ganado.
- Gate Frost Peak 2.6M -> 1.3M y Lava Caves 420M -> 38M: antes había un tramo muerto de ~20 min (sprinkle a los 9 min y nada hasta la zona 3 a los 30); ahora las zonas caen a ~13 y ~27 min.
- Gate Cosmic Void 6B -> 40B: la última zona pasa a ser una meta de horas (1h 13m) en vez de 53 min.
- Precios de huevos seguidos a su puerta (mismo criterio de proporción; Sprinkle va atado a la puerta 3): candy 16K -> 47K, sprinkle 140K -> 70K, frost 260K -> 130K, glacier 2.1M -> 1M, magma 12M -> 1.1M, cosmic 180M -> 1.2B. Siguen ordenados por zona.
- `RebirthBaseCost` 63M -> 2B (crecimiento x8 igual): el primer rebirth sigue en ~38 min, pero #2 a ~48 min llena el hueco 40-60 min y los siguientes se estiran a horas/días (antes #6 a las 2 h).
- Regalo de sesión de 5 min (10 gemas) -> 2 min (35 gemas): dos TapPower + Walk Speed antes del minuto 3 (antes 0 upgrades de gemas hasta el min 5). Las etiquetas se traducen por `kind`, no hay textos que tocar.
- Robux, pases y productos: sin cambios. No hizo falta tocar ningún test existente (todos pasan tal cual); `DESIGN.md` actualizado con la tabla nueva.

### Verificación
`rojo build default.project.json` OK, `luau-lsp analyze` sin salida, tests puros (locale, model_slots, passes_pricing, policy_hud, unit_p0, check_config, pacing_targets) en verde. Mutando la puerta 2 a 400K el test nuevo falla como corresponde.

### Límites del sim
- Jugador siempre activo durante la sesión; no modela AFK (Auto Tap/Auto Hatch libres), caminatas entre zonas/huevos, amigos, anuncios, eventos, códigos, dados de traits ni las recompensas del Index (+10% taps por zona).
- Los quests se asumen completos cada 12 min y el huevo Magic (pets exclusivos escalan con la mejor mascota de la zona) pesa mucho: la variación entre semillas (20 min en el peor hueco de tiers) sale sobre todo de ese sorteo y de los regalos de taps de los minutos 10/40.
- Entre el primer rebirth y Cosmic Void (~35 a ~73 min) los únicos tiers nuevos son rebirth #2 y regalos/quests; si queremos más, falta contenido (más zonas/huevos), no números.
- Números tuneados a 2 cifras significativas con `pacing_tune.luau` (5 semillas); el test usa 7 y ventanas anchas. Cualquier cambio de pets/multiplicadores obliga a re-correr el sim.
- Para confirmar en Studio: que el daily se note a los ~30 s (badge en Rewards) y que los precios de huevos nuevos se lean bien en el panel de huevos.

## Ronda 6: contenido para el hueco

**El hueco:** entre el primer rebirth (~38 min) y la zona 5 Cosmic Void (~1h13) no aparecía nada nuevo salvo rebirth #2 y regalos. Medido con el sim: el mayor tramo sin un tier nuevo en las primeras 2 horas era de **31 min (mediana de 9 semillas, peor 39)**.

### Qué agregué (todo en `src/shared/Config.luau`, datos puros)
Ocho huevos nuevos, cada uno con 4 pets (Uncommon a Legendary/Mythic, sin Common, mejores chances que los huevos abiertos de la zona) + el Shadow Dragon secreto de siempre. 32 pets nuevos en total:
| Huevo | Zona | Se abre con | Precio | Aparece (mediana) |
|---|---|---|---|---|
| Basalt | 4 Lava Caves | la zona (sin rebirth) | 150M | ~30 min |
| Obsidian | 4 Lava Caves | rebirth 1 | 11B | ~43 min |
| Aurora | 3 Frost Peak | rebirth 2 | 12B | ~57 min |
| Geode | 4 Lava Caves | rebirth 2 | 28B | ~67 min |
| Pulsar, Starforge, Singularity | 5 Cosmic Void | rebirth 3 | 250B, 500B, 750B | ~86, ~93, ~100 min |
| Helios | 5 Cosmic Void | rebirth 4 | 500B | ~118 min |

- Campo nuevo `minRebirths` en `Config.Eggs`. Helpers puros en `Formulas`: `eggMinRebirths`, `eggUnlocked`, `eggsUnlockedAt`.
- **Servidor** (autoritativo): `Eggs.hatch` y `SetAutoHatch` rechazan el huevo si `p.rebirths < minRebirths` (`msg.egg_needs_rebirth`). Al hacer rebirth, `Progression.rebirth` avisa "Huevo nuevo desbloqueado" (`msg.egg_unlocked`). **No hay campos nuevos en el perfil**: el único dato es `rebirths`, que ya existía, así que los saves viejos funcionan sin migración (quien ya tiene rebirths ve los huevos abiertos).
- **Cliente:** el cartel del huevo muestra "🔒 Rebirth N" hasta que lo abrís (`WorldText`, se refresca al cambiar los rebirths); el panel del huevo deja ver las chances pero el botón dice "🔒 Rebirth N" y el texto "Este huevo se abre tras el Renacer N" (naranja). Sigue sirviendo de gancho.
- **Index:** las páginas de zona tienen más pets (Cosmic Void llega a 21), así que la grilla pasó a `ScrollingFrame` (mismo patrón que `PetsWindow`). Ojo: quien tenía una página completa sin reclamar ahora necesita los pets nuevos; las ya reclamadas quedan reclamadas.
- **Pets de huevos con rebirth no mueven el poder de los pets exclusivos** (Robux): `Formulas` los excluye del `bestPowerByZone`. Sin esto, un Aurora Wyrm (zona 3) multiplicaba x16 al Sparkle Cat de los jugadores de zona 3 y de paso rompía el ritmo en el sim (lo vi en el primer intento). Lo cubre un test nuevo.
- Precios: los de rebirth siguen el costo del siguiente rebirth (los taps se reinician en cada rebirth, por eso el de R4 cuesta menos que los de R3). Son ~10^4 veces los de la zona porque el ingreso creció; el valor esperado por apertura es 3-5 veces el del huevo abierto de la zona.
- Sin Robux, sin assets inventados. Props grandes nuevos: ninguno (los huevos usan `buildEgg` tal cual), así que no hacen falta ranuras nuevas en `ModelSlots` (19 checks siguen verdes). Posiciones nuevas en `Config` (sin pisar landmarks), chequeadas por `sim/check_config.luau` (distancia mínima 34 studs).
- Textos: 8 nombres de huevo, 32 pets y 4 claves nuevas (`msg.egg_needs_rebirth`, `msg.egg_unlocked`, `world.egg_locked`, `egg.locked_btn`) en **los 12 idiomas** (en es fr de pt ru tr id vi th ja ko). `PetModel.FAMILY`: dragones/fénix/golem/lobo/búho nuevos con su familia.

### Hitos antes / después (mediana de 9 semillas, tiempo de juego activo)
| | Antes | Después |
|---|---|---|
| Primer rebirth | 37:59 | 37:59 (sin cambios) |
| Rebirth #2 / Zona 5 / Rebirth #3 | 48:11 / 1h13 / 1h18 | sin cambios |
| Tiers nuevos entre rebirth #1 y zona 5 | 1 (rebirth #2) | 5 (Obsidian, Aurora, Geode + rebirth #2 + zona) |
| Mayor hueco sin tier nuevo, primeras 2 h (mediana / peor semilla) | **31 min / 39 min** | **10.9 min / 24 min** |
| Mayor hueco, primera hora (mediana / peor) | 12.6 / 20 min | 10.3 / 11.9 min |
| Mayor tramo sin NADA nuevo (tier, regalo, quest), 2 h, mediana | 31 min | 10.7 min |

Los tiempos de las zonas, rebirths y todo lo anterior no cambiaron (el jugador del sim ya llega con pets exclusivos de huevos Magic que tapan a los huevos comunes, así que los nuevos no aceleran ni frenan el ritmo). Límite: las semillas más rápidas (rebirth #4 a los ~89 min) agotan el contenido y después de Helios/Singularity no hay nada hasta el rebirth #5; eso queda fuera de las 2 horas y de esta ronda.

### Tests
- `tests/pacing_targets.luau`: de 16 a 34 checks. Ventanas por huevo (basalt, obsidian, aurora, geode, pulsar, starforge, singularity, helios), cada huevo con rebirth aparece después de su rebirth, hueco de tiers y de "nada nuevo" en 2 h <= 12 min (mediana), y el tramo rebirth 1 -> Cosmic Void <= 12 min. Mutando el precio del Geode a 120B el test falla como corresponde.
- `sim/pacing_core.luau` respeta `minRebirths`; `aggregate(seeds, sessions, window?)` y `Core.LONG_WINDOW` (2 h); `pacing_sim.luau` imprime el bloque de 2 h y marca "R1".." en la tabla de huevos; `pacing_tune.luau` ahora ignora los huevos con rebirth (van a mano).
- `tests/unit_p0.luau` +5 checks (huevo trabado/abierto, `eggsUnlockedAt`, pets gated no mueven los exclusivos); `sim/check_config.luau` valida `minRebirths` y separación; `sim/odds_table.md` regenerada (estaba vieja).

### Verificación
`rojo build` OK, `luau-lsp analyze` sin salida, tests puros en verde (locale 12 idiomas x 410+ claves, model_slots, passes_pricing, policy_hud, unit_p0, check_config, pacing_targets) y el sim. Previews en `docs/previews/pet-tap-simulator/`: `mid-{pc,phone}-egglocked.png` (Aurora trabado), `mid-{pc,phone}-eggopen.png` (Obsidian abierto), `mid-{pc,phone}-index-cosmic.png` (página de 21 pets con scroll), y se regeneró `--all`. 0 errores de runtime; los hallazgos bajos que quedan (superposición con el joystick en ventanas de celular) ya estaban antes. Las capturas `egglocked/eggopen/index-cosmic` las saqué con una copia del fixture en el scratchpad (no toqué `tools/`): rebirths=1, zonas 1-4 y ventanas extra.

### Qué mirar en Studio
1. Los 8 huevos nuevos: que no pisen landmarks ni se vean pegados (Lava Caves ahora tiene 4: Magma al centro, Basalt al fondo izquierda, Obsidian izquierda y Geode derecha; Cosmic Void 5; Frost Peak 3), y que el pilar de luz y los carteles "🔒 Rebirth N" se lean bien desde lejos.
2. Rebirth: que llegue el aviso "Huevo nuevo desbloqueado" y el cartel pase de 🔒 al precio sin reentrar.
3. Los 32 pets nuevos en 3D (sobre todo Borealis Stag, Geode Golem, Singularity Dragon, Solar Phoenix): usan el rig genérico por familia; los que no tienen familia explícita salen como dog/cat/bear según las orejas.
4. Página Cosmic Void del Index: scroll con el dedo en celular y que el botón de reclamar no tape la grilla.
5. Que un jugador de 0 rebirths que toca el prompt de un huevo trabado vea el panel con el botón gris y no pueda abrirlo (ni por auto hatch).

## Ronda 7: seguridad

Auditoría de todo lo que un cliente puede mandar (cada `Request` y el evento `Tap`) más guardado, recibos y memoria. Helper nuevo, puro y testeado: `src/server/Services/Guard.luau` (validadores `num/int/str/uid/oneOf/array/smallTable`, token bucket, `scrub` de NaN/inf, `migrate`, `backoff`). Tests: `tests/security_test.luau` (68 checks, `luau tests/security_test.luau`).

| Sev. | Archivo:línea (aprox.) | Cómo se explotaba | Cómo se arregló |
|---|---|---|---|
| Alta | `Monetization.luau` processReceipt (~164) | Si el perfil no cargó (DataStore caído, sesión "no se guarda"), la compra se otorgaba y se devolvía `PurchaseGranted` sin guardar: Robux cobrados y premio perdido al salir | Con store disponible y perfil no persistente devuelve `NotProcessedYet` (Roblox reintenta al próximo join); `Data.canPersist()` mantiene el comportamiento en Studio sin API |
| Alta | `Monetization.luau` grantReceipt (~111) | Si el primer guardado fallaba, el reintento del mismo recibo veía el marcador en memoria y devolvía `PurchaseGranted` sin haber guardado nada (el comentario decía lo contrario) | Con marcador existente guarda de nuevo y solo confirma si el guardado salió bien. Guard de recibo en vuelo (`receiptBusy`) contra dos hilos con el mismo PurchaseId |
| Alta | `Data.luau` save (~270) | Un solo intento sin reintentos: una falla transitoria al salir perdía la sesión entera. Dos escrituras del mismo jugador (autosave + release + recibo) se pisaban y mutaban `p.lock` a la vez | `UpdateAsync` serializado por jugador (`saving`), 3 intentos (5 al salir) con backoff 1/2/4/8 s, espera de presupuesto, tope de 25 s en BindToClose; se mantiene el chequeo de lock de otro server y el fast-fail de Studio |
| Alta | `Main.server.luau` onPlayerAdded (~150) | Si el jugador se iba mientras corría `loadPasses` (web call), después se ponía `State.ready` y `Plots.assign`: el plot quedaba ocupado para siempre por un jugador ausente y se filtraban tablas | Chequeo `player.Parent` tras el yield: release + cleanup y return |
| Media | `Data.luau` reconcile/save | NaN/inf o negativos en el perfil (bug o dato corrupto) viajaban a DataStore y a la economía; campos con tipo equivocado rompían todo al cargar | `Guard.scrub` y `clampNonNegative` en carga y antes de cada guardado; `fixTypes` contra los defaults; zonas/upgrades/equipados validados; `Data.VERSION` + `Guard.migrate` listo para migraciones (hoy vacío, versión 1) |
| Media | `Remotes.luau` (~100) | Sin límite por acción: `RedeemCode` se podía fuerza-bruta a 12/s, `ClaimGroupGift`/`ShareLink`/`WatchAd` spameaban web calls, `GetState` armaba snapshots a 12/s; payload con 100k claves se recorría entero; llamadas tardías recreaban el bucket del jugador (fuga) | `Remotes.limit(acción, /s, burst)` configurado en `Main.server.luau` para 22 acciones; payload máx. 256 claves; `action` máx. 32 bytes; tabla `departed` (weak) evita recrear estado de quien ya salió |
| Media | `Tapping.luau` onTap (~85) | Miles de eventos `Tap` por segundo: cada uno pasaba por el bucket (CPU) aunque se aceptaran pocos taps; `count` sin tope previo | Limiter de eventos 8/s (burst 16; el cliente manda 4/s) y `count` acotado a 10000; el tope de taps (12/s + 6) queda igual |
| Media | `Monetization.luau` WatchAd (~210) | `ShowRewardedVideoAdAsync` cede: varias llamadas en paralelo pasaban el chequeo del cupo diario antes de sumar | Una sola llamada en vuelo por jugador (`adInFlight`), cupo re-chequeado al terminar |
| Media | `Leaderboard.luau` pushScores (~80) | `SetAsync` ciego sobre el OrderedDataStore: una sesión sin cargar/vieja o un valor NaN pisaba el puntaje; sin chequear presupuesto; un request por jugador cada ciclo | `UpdateAsync` que solo sube (mantiene el máximo), `encodeTaps` rechaza NaN/inf, solo escribe si el valor subió, deja 20 de presupuesto para los perfiles |
| Baja | `Pets.luau` Delete (~142) | `uids` con millones de entradas se recorría completo (solo cortaba al borrar 200); uids de cualquier largo | `Guard.array(<=400)` y `Guard.uid` (`^p%d+$`, <=12) en Equip/Unequip/Lock/Delete/RollTrait/Craft |
| Baja | `Rewards/Progression/Eggs/Auto/QuestService` | Índices fraccionarios o NaN, strings enormes en `egg`/`id`/`key`/`code` | `Guard.int` con rangos (zona, gift, quest) y `Guard.str` con topes (egg 24, code 30, id 24, key 12) |
| Baja | `Rewards.luau` friendCache (~60) | Crecía con cada par de jugadores durante toda la vida del server | Se vacía al pasar de 3000 entradas |
| Baja | `Social.luau` inbox MessagingService | Strings sin tope guardados y reenviados a todos los clientes | Se copian solo `n/p/t/o` truncados (40/40/0-2/24) |
| Baja | `Monetization.luau` PromptGamePassPurchaseFinished | Sin validar tipos ni que la sesión esté lista | Exige `purchased == true`, id entero y `State.ready`; sigue siendo un evento del servidor (el cliente no lo puede disparar) |

Conteo: 4 altas, 5 medias, 5 bajas (14). Lo que ya estaba bien y quedó igual: taps limitados en servidor (12/s + 6 de burst), distancia/cooldown/precio de huevos, zonas, anti-trespass, lock de sesión por JobId, autosave escalonado con presupuesto, `ProcessReceipt` con PurchaseId guardado antes de confirmar, comando `/event` solo admin. Un jugador legítimo no nota nada: los límites por acción están por encima de lo que se puede clickear.

### Qué queda
- `ClaimDaily` sigue guardando en línea (una escritura por reclamo, acotada a 1/s).
- Referidos: el tope vitalicio limita el abuso, pero un granjero con cuentas alt sigue pudiendo cobrar el regalo; hace falta una señal externa (edad de cuenta) que no hay en Studio.
- La posición del personaje sigue siendo del cliente (distancia al huevo, zonas): un teleport exploit solo llega a lo que ya tiene desbloqueado, y el anti-trespass lo devuelve cada segundo.
- Los pase de juego se cachean al entrar; uno comprado por la web a mitad de sesión se ve al reentrar (la compra dentro del juego sí se refleja al instante).
- Probar en Studio publicado: BindToClose con varios jugadores, un recibo con el DataStore caído y que el aviso "no se guarda" aparezca.

### Verificación
`rojo build` OK, `luau-lsp analyze` sin salida, `security_test` 68/68 y el resto de los tests puros y sims en verde (locale, model_slots, passes_pricing, policy_hud, unit_p0 60, pacing_targets 34, check_config, format_check). Preview `--state mid --screen pc`: 0 hallazgos, 0 errores de runtime.

## Ronda 8: primera sesión y game feel

### Recorrido de los primeros 2 minutos
**Antes:** spawn -> HUD ya mínimo (Rewards / TAP / Pets / Store) -> cartel "Tap anywhere" y objetivo "Earn 200 Taps" con barra -> a los 200 Taps aparece el rayo hacia el huevo -> el prompt del huevo abre el panel -> cinemática de eclosión -> se destraban Upgrades/Quests/AutoTap con un pop mudo. Problemas: no había pantalla de carga propia, el botón TAP no llamaba la atención, si el jugador se quedaba parado no pasaba nada, no se podía saltar la guía, y desbloquear botones no se celebraba. Los golpes grandes (combo 25/50/100, legendarias) no movían la cámara.

**Después:** pantalla de carga de marca (máx 6 s) -> HUD mínimo + anillo que pulsa en el botón TAP -> si pasan 14 s sin avanzar, el anillo crece y el texto pasa a "Tap the big button!" -> al juntar los 200 el objetivo cambia a "Walk to the egg" con rayo -> cerca del huevo "Hatch your egg!" -> primer pet -> "Hatch more eggs! 1/5" -> a los 5 vuelve el objetivo normal de siempre. Al destrabarse botones nuevos hay banner "New: Upgrades, Quests, Auto Tap!", sonido, micro-shake y ráfaga de destellos.

### Qué agregué
- `src/shared/Onboarding.luau` (puro): máquina de pasos tap / walk / find / hatch / more / done, tracker de inactividad (`idle`, `progressOf`) y `newlyUnlocked`. No guarda nada: el paso sale de contadores que ya persisten (hatches, taps, zonas, rebirths), así que **se retoma solo al reentrar** y un veterano nunca lo ve. Sin soft-lock: botón **Skip** (por sesión), si falta el personaje/destino cae a texto "Find the egg" sin rayo, y nunca exige caminar para seguir jugando.
- `src/shared/Juice.luau` (puro): envolvente y offset del shake, amplitud con reduced-motion/lite, tope de partículas concurrentes, roll-up, squash.
- `tests/onboarding.luau`: 55 checks (pasos, skip, veterano, destino faltante, idle, unlocks, shake, topes). Corre con `luau tests/onboarding.luau`.
- `src/client/Onboarding.luau`: evalúa el paso, anillo pulsante en TAP, botón Skip (zona táctil de 120x56 bajo la barra del objetivo), celebración de desbloqueos (la primera snapshot de la sesión solo fija la base: no repite al reentrar).
- `src/client/Shake.luau`: micro-shake con `Humanoid.CameraOffset` (no toca la cámara). Se apaga con el atributo `ReducedMotion = true` en Workspace/Player o con el setting de Roblox si existe; en lite es 40% más suave. `Shake.reduced()` también lo usa el flash de la cinemática (arranca al 70% de transparencia en vez de blanco pleno).
- `src/client/Celebrate.luau`: ráfaga de destellos con `rbxasset://textures/particles/sparkles_main.dds`, un solo pool de 24 labels máx, cantidad escalada por `Quality.particles`; banner de desbloqueo. Sonidos por `Theme.play` (sin ids nuevos).
- Hooks: squash/stretch del botón TAP en cada toque (`Tapper.setTapHook`, máx ~12/s), shake + destellos en hitos de combo, shake en eclosiones Legendary+ (`HatchCinematic`), destellos al abrir zona.
- `src/loading/Loading.client.luau` (ReplicatedFirst, agregado a `default.project.json`): nombre del juego, tip (es/en según locale), barra con señales reales (juego cargado, Remotes, HUD creado) + tiempo. Mínimo 1,2 s, tope duro 6 s, watchdog a 9 s; todo en pcall, si algo falla se destruye. No está en `test.project.json` ni `showcase_low.project.json` para no tapar capturas/tests.
- 8 claves `ftue.*` en los 12 idiomas (`locale_check` pasa, 428/428).
- Ya existían y no los toqué: HUD progresivo (`HudUnlock`), count-up de contadores, pops con Back, cinemática con rareza por color.

### Qué mirar en Studio
- Entrar con perfil nuevo: la carga debería durar ~1-2 s y no tapar el HUD; probar con red lenta (que no pase de 6 s).
- El anillo del botón TAP pulsa; esperar 14 s sin tocar y ver que crece. Skip lo apaga y el objetivo normal sigue.
- Con 200 Taps: texto "Walk to the egg" y rayo; al llegar al huevo "Hatch your egg!". Reentrar a mitad de tutorial: debe retomar en el paso correcto.
- Comprar el primer huevo: banner de desbloqueo + shake leve; en celular el shake debe sentirse más suave. Poner `workspace:SetAttribute("ReducedMotion", true)` y confirmar que no hay shake.
- Combo 25/50/100 y un huevo Legendary+: shake corto, sin mareo; el botón TAP se aplasta en cada toque sin lag en celu.
- El tamaño real del botón Skip y la posición del anillo (el preview es aproximado).

### Verificación
`rojo build default.project.json` OK, `luau-lsp analyze` sin salida, todos los tests/sims puros en verde (onboarding 55, locale, model_slots, pacing 34, passes 117, policy_hud 192, security 68, unit_p0 60, check_config, format_check). Previews `new` pc y phone: 0 hallazgos, 0 errores de runtime (antes/después en `docs/previews/pet-tap-simulator/new-*-before-r8.png` vs `new-*.png`; la carga y los efectos animados no se ven en el preview estático).
