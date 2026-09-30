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
