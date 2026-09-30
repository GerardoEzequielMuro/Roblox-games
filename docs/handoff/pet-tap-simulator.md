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
