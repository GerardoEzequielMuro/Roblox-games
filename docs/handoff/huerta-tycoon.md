# Crop Kingdom (huerta-tycoon): handoff

Todo esto se hizo en un contenedor Linux sin Roblox Studio. **No vi el juego corriendo en ningún momento.** Lo que
sigue está verificado con build, analizador y tests puros; lo visual hay que mirarlo en Studio (ver abajo).

Cuando lo revisé, el juego ya tenía bastante trabajo encima: Lighting completo (Atmosphere, Bloom, ColorCorrection,
SunRays, DOF, Clouds), terreno con materiales, fuente FredokaOne, botones con gloss, stroke y tweens de hover/press,
módulo de audio con IDs en 0 que no hace nada, y guardado en DataStore serializado por jugador con autosave
escalonado. Eso no lo toqué (el punto 4 del backlog ya estaba hecho). Me enfoqué en los íconos, los bugs visuales y
en darle más textura a cultivos y props.

## Qué cambié

**Íconos (pack compartido `Shared/Icons`)**
- `src/client/UI/Theme.luau`: agregué `Theme.EmojiIcon`, que mapea el emoji usado como ícono al nombre del pack
  (🛒→shop, 🔁→rebirth, 💎→gem, 🎁→gift, 🎟️→ticket, ⏰→clock, 📖→book, 👋→invite, 🏆→trophy, 🤖→auto, 💰/💵→cash,
  💲→coin, 🍀/🎲→luck, 👑→crown, ✅→check, ✕→close, ⭐→star, 🌱→sprout, 🔒→lock, ⚡→bolt…).
- `src/client/UI/Components.luau`: helpers nuevos, todos en un solo lugar:
  - `C.icon(parent, emoji, size, props, name?)`: con la imagen subida crea un `ImageLabel` (ScaleType Fit, fondo
    transparente) dentro de un marco del mismo tamaño y posición. Si no hay imagen, llama a `C.label` con los mismos
    argumentos de siempre, así que hoy se ve **exactamente igual**.
  - `C.iconPrefix(emoji)` + `C.addIcon(btn, emoji)`: en botones con texto, la imagen va a la izquierda de la etiqueta
    y se saca el emoji del texto. Sin imagen, el texto queda como estaba.
  - `C.panel`: el ícono del título pasa a ser una imagen si está subida. Nuevo `IconName` opcional (Upgrades usa
    "upgrade" en lugar de "bolt").
  - El botón ✕ de cierre usa el ícono "close" si está subido.
- Lugares donde se aplica: menú lateral (`Panels.luau`), títulos de todos los paneles, moneda del HUD ("coin") y botón
  Auto (`Hud.luau`), íconos de upgrades (`UpgradesPanel.luau`), productos de la tienda (`StorePanel.luau`), modos de
  auto-farm (`AutoPanel.luau`), recompensas diarias (`DailyPanel.luau`) y regalos (`GiftsPanel.luau`).
- No toqué los emojis que forman parte de oraciones traducidas, ni las semillas, mutaciones y clima (no hay ícono
  equivalente en el pack).

**Bugs visuales**
- Paneles en celulares chicos (`src/client/UI/Panels.luau`, `Layout.luau`, nuevo `UiMath.luau`). Antes, un panel de
  700x520 se achicaba para entrar entero en la pantalla, y en un teléfono sus botones de 54 px quedaban en unos
  26 px reales. Ahora el panel nunca baja de la escala que deja los botones en 44 px táctiles (40 con mouse). Si
  así no entra de alto, el panel se hace más corto: los paneles que ya tienen lista scrolleable achican esa lista, y
  el resto (Rebirth, Daily, Codes, Invite, Starter, Auto, Language, Gifts) se envuelve en un `ScrollingFrame`
  vertical con su alto original. En PC y tablets no cambia nada: si el panel entra, se ve igual que antes.
- Carteles flotantes sobre la parcela (`src/client/UI/Tiles.luau`):
  - Las barras de crecimiento solo aparecen en las **6 más cercanas** dentro de 40 studs. Antes había una por cada
    tile plantado (hasta 30), siempre visibles y encimadas. También las hice más chicas (2.8 x 0.42 studs).
  - "READY!" sigue limitado a los 3 más cercanos, ahora con la misma función pura (`UiMath.nearest`).
  - En tu próximo tile a comprar, el precio pintado por el server (`LockGui`) se oculta solo para vos, porque el cartel
    flotante ya muestra lo mismo encima.
- Números "+$" de Harvest All (`src/client/UI/Fx.luau`): antes subían hasta 12 números encimados. Ahora los primeros
  3 salen sueltos y el resto de la ráfaga se suma en un solo número dorado más grande ("+$total", "xN") que se
  actualiza. Las mutaciones y los tamaños Big/Giant siempre muestran su propio número.
- Tamaño del HUD: lo revisé con la cuenta. En 1920x1080 la escala raíz ya estaba topeada en 1, así que el HUD mide
  lo que dice en píxeles de diseño y no se agranda. En celulares el canvas compacto deja los botones de 54 px en
  ≥ 44 px reales (en un 620x330, 45 px). Ahí no cambié números: el bug real de botones < 40 px estaba en los paneles.

**Look 2026**
- `src/server/World/CropVisuals.luau`:
  - El tallo del maíz ya no es un caño: ahora es un huso que se afina hacia la espiga (misma cantidad de partes).
  - El follaje deja de ser SmoothPlastic: arbustos y copas usan Grass, y hojas, chala, pétalos, tallos, guías,
    brotes y brazos de cactus usan Fabric. La fruta mantiene el acabado liso y brillante, y las mutaciones conservan
    su material.
  - Cada tile tiene su verde, ±7% de brillo derivado de la posición, así que siempre se ve igual. Una parcela llena
    ya no parece copiar y pegar.
  - El presupuesto de partes por tile (24) no cambia: no agregué partes.
- `src/server/World/Props.luau`: las partes sin material explícito lo toman de su nombre. Marcos, molduras, vigas,
  postes y aleros van como Wood; sogas, banderines y cintas como Fabric; juncos, guías y camalotes como Grass. Los
  animales, globos y detalles chicos siguen con el acabado cartoon.
- HUD (`Hud.luau`, `Hotbar.luau`, `Components.luau`): sombra suave (`C.dropShadow`, un frame hermano que sigue
  posición, tamaño y visibilidad) y degradé vertical en la tarjeta de stats, la barra de canasta y la hotbar.

**Tests**
- `tests/ui_test.luau` (nuevo, puro), con 11 checks:
  - elección de canvas;
  - escala 1 en 1080p;
  - botones ≥ 44 px en teléfonos;
  - 12 tamaños de panel × 8 pantallas: entra, no se achica bajo el mínimo y queda con alto útil;
  - `nearest`: los N más cercanos, rango y desempates.

## Cómo lo verifiqué
- `rojo build default.project.json`: OK (también `test.project.json` y `showcase.project.json`).
- `luau-lsp analyze … src`: **0 errores**, sin salida fuera de INFO/WARN, igual que antes.
- Tests puros (`luau tests/<x>.luau`):
  - autofarm_test: 28 checks, 0 failures
  - locale_test: 11 languages, 326 keys in en, 3597 checks, 0 failures
  - odds_test: 46 checks, 0 failures
  - p0_test: 47 checks, 0 failures
  - trophies_test: 27 checks, 0 failures
  - ui_test: 11 checks, 0 failures (nuevo)
  - wild_test: 28 checks, 0 failures
  - world_test: 72 checks, 0 failures
- No corrí el playtest de Studio (`tests/AutoTest*.luau`). No hay Studio acá.

## Qué hay que mirar en Studio
1. **Paneles en pantalla chica** (ventana 1050x600, que da un viewport de unos 570x345, y 1400x760): abrí Shop,
   Upgrades, Store, Index, Rebirth, Daily y Starter.
   - El panel tiene que verse grande, no a la mitad.
   - Los botones de comprar tienen que quedar cómodos.
   - Rebirth, Daily y Starter tienen que scrollear vertical sin cortar nada a los costados.
   - El botón ✕ tiene que seguir en la esquina.
   - Las badges de las tarjetas (arriba a la derecha) no tienen que quedar recortadas por el borde del scroll.
2. **Paneles en PC** (1920x1032): tienen que verse idénticos a antes (sin scroll).
3. **Parcela plantada entera (30 tiles)**:
   - que se vean como mucho 6 barras de crecimiento, las más cercanas;
   - que no se encimen;
   - que al caminar vayan cambiando a los tiles cercanos.
4. **Harvest All con la parcela llena**: 3 números sueltos y después un "+$total xN" dorado que va subiendo. Una
   mutación tiene que seguir mostrando su propio número de color.
5. **Próximo tile a comprar**: en tu parcela, un solo cartel con 🔒 y el precio, no dos. En parcelas ajenas sigue
   pintado en el piso.
6. **Cultivos**:
   - el maíz, que el tallo se afine hacia arriba y no parezca un palo;
   - las texturas Grass y Fabric en arbustos, copas y hojas: si Grass se ve muy "ruidoso" de cerca, se cambia en
     `FOLIAGE`, en `CropVisuals.luau`;
   - la variación de verdes entre tiles;
   - las mutaciones (Golden, Frozen, Rainbow), que tienen que verse igual que antes.
7. **Props**: molduras, marcos y postes de granero, casa y puestos con veta de madera, y banderines y sogas con tela.
   Que nada blanco se vea sucio.
8. **HUD**: sombra suave debajo de la tarjeta de stats, la canasta y la hotbar, sin desfasarse cuando cambian de
   tamaño o posición (rotá o redimensioná la ventana).
9. **Íconos**: cuando se suban (`tools/icons/upload_assets.py`), revisá el menú, los títulos de panel, el ✕, la
   moneda del HUD, el botón Auto, las tarjetas de Store y Upgrades y Daily/Gifts. Esa rama (ImageLabel) no se probó
   nunca, porque hoy `Icons.get` devuelve nil y todo cae al emoji.
10. Correr `tests/run.ps1`: el playtest completo tiene que seguir en PASS (budgets de partes de cultivos incluidos).

## Pendiente
- Subir el pack de íconos: hasta entonces todo sigue con emoji.
- Precio del Starter Pack (15 vs 99 R$): no lo toqué, lo decide Gerar.
- El pedido hablaba de "carteles de % / chances sobre las parcelas". En el código no encontré un cartel de % en el
  mundo. Asumí que eran las barras de crecimiento, los "+$" de cosecha y el precio duplicado del tile. Si en Studio
  se sigue viendo otro cartel encimado, hay que sacarle una captura para ubicarlo.
- No agregué sombras a los paneles: el `PopScale` los anima y una sombra hermana no lo seguiría. Habría que meter
  cada panel dentro de un contenedor.
- Sonidos: siguen en 0 en `Config.Sounds`. El módulo está listo y no hace nada sin IDs.
- Los cultivos siguen siendo de partes primitivas. Un salto grande de calidad necesita meshes subidos, y eso no se
  puede hacer sin assets.
