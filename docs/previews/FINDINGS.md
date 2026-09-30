# Hallazgos de UI (uipreview, 30/09)

Capturas generadas con `tools/uipreview` (ver su README). Para cada juego hay `new` y `mid` en `pc` (1920x1080) y `phone` (844x390, táctil), cada ventana principal (estado `mid`) en `pc` y `phone`, y `mid-*-icons` (cómo quedaría con los íconos de `assets/icons` subidos). Cada PNG tiene al lado un `.txt` con los hallazgos automáticos, el rectángulo en pantalla y el `archivo:línea` donde se creó cada objeto.

**Aviso**: es una simulación aproximada del layout de Roblox (fuentes parecidas, sin 3D, sin imágenes subidas; ver "Qué aproxima y qué no" en `tools/uipreview/README.md`). Todo lo de abajo lo revisé mirando los PNG, no solo con los chequeos automáticos. Los puntos marcados **(confirmar)** pueden ser un efecto de la herramienta: conviene mirarlos en Studio antes de tocar código.

## Resumen

| Juego | PC | Celular | Errores de runtime |
|---|---|---|---|
| obby-sky-tower | 2 bugs reales (texto invisible, borde alrededor del timer) | lo mismo + botones de 32-43 px, menú bajo el joystick | ninguno |
| anime-planet-clicker | bien; badges tapados | **HUD y ventanas a escala 0.55**: botones de 19-31 px, textos de 6-8 px | ninguno |
| huerta-tycoon | bien (tienda vacía por ids en 0) | el mejor de los 6 en celular | ninguno (1 propiedad deprecada) |
| ki-warriors | bien; "1 Ascensions" | **HUD a escala 0.55**: botones de 14-31 px, textos de 5-7 px, menú bajo el joystick | ninguno |
| pet-tap-simulator | badges tapados | botones de 31-39 px | ninguno |
| ruleta-pvp | botones tapan texto en Season Pass | Power Core tapa las metas, "+" de monedas de 17 px | ninguno |

### Errores de runtime

La corrida simulada (servidor + cliente, jugador nuevo y a mitad de partida, 8 s virtuales, abriendo cada ventana y, en ruleta, jugando un partido contra bots que arranca el propio servidor) **no encontró errores de Luau en ninguno de los 6 juegos**: ningún `error`, ningún `WaitForChild` colgado, ninguna API inexistente, ninguna tabla rara mandada por un remote. Lo único:

- `huerta-tycoon`: se asigna la propiedad deprecada `BillboardGui.DistanceLowerLimit` (13 veces) en `huerta-tycoon/src/client/UI/Components.luau:21` (desde `UI/Tiles.luau:261`). Funciona, pero está deprecada.

Esto no quiere decir que no haya errores: solo se ejecutó lo que pasa en los primeros segundos y al abrir cada ventana, sin 3D real (los raycast no devuelven nada), sin compras y sin tocar botones de juego.

### Problema común: el escalado en celular (4 de 6 juegos)

`anime-planet-clicker`, `ki-warriors`, `pet-tap-simulator` y `ruleta-pvp` escalan todo el HUD con la misma fórmula:

- `anime-planet-clicker/src/client/UI/Root.luau:57`, `ki-warriors/src/client/UI/Root.luau:57`, `pet-tap-simulator/src/client/UI/Root.luau:57`: `math.clamp(math.min(size.X / 1100, size.Y / 560), 0.5, 1.1)`
- `ruleta-pvp/src/client/UI/Root.luau:68`: lo mismo con tope 1.15

En un iPhone apaisado el área útil es de unos 750x311 px, así que la escala queda en **0.55**: un botón pensado de 56 px termina en 31 px, uno de 34 px en 19 px, y los `TextScaled` con `UITextSizeConstraint` bajan a 5-8 px. Casi todos los hallazgos `small-touch` y `tiny-text` de esos juegos salen de acá. Sugerencia: en táctil usar una escala mínima más alta (0.75-0.8) y compensar con un layout táctil más compacto (como hace `huerta-tycoon` con `UI/Layout.luau`).

---

## obby-sky-tower

1. **"Checkpoint" y "Lobby" no muestran texto** (todas las pantallas). Los botones se crean con alto por escala (`UDim2.new(0, 116, 1, 0)` en `obby-sky-tower/src/client/UI/Hud.luau:338` y `UDim2.new(0, 62, 1, 0)` en `Hud.luau:343`) y después `Kit.singleLine` (`obby-sky-tower/src/client/UI/Kit.luau:293-320`) calcula el alto con `obj.Size.Y.Offset - padY` = `0 - 8`, así que `TextSize` queda en **-8** (Roblox lo lleva a 1: texto invisible). En las capturas se ve un botón naranja y uno gris vacíos abajo al centro. Arreglo: medir con `AbsoluteSize` (dividido por el `UIScale` de la región) o darles alto en offset.
2. **Recuadro alrededor del timer** `00:00.000` (`Hud.luau:193`): `Kit.stroke` (`Kit.luau:90-96`) fuerza `ApplyStrokeMode = Border`, así que el `UIStroke` del `TextLabel` dibuja un rectángulo alrededor de la caja transparente en vez de contornear los números. Para texto hace falta `Contextual` (como en `Kit.bold`).
3. Celular: el botón **Menu** queda de 86x37 px (`Hud.luau:207`) y Checkpoint/Lobby de 43 px de alto. El X de las ventanas es de 32x32 px (`Kit.luau:580`), las pestañas Trails/Effects y los botones de compra de la tienda de 34 px (`UI/ShopPanel.luau:38`, `:129`, `:133`).
4. Celular, menú abierto: **Settings e Invite quedan debajo del joystick** (`Hud.luau:252`, `:255`). El menú se despliega hacia abajo a la izquierda, justo donde apoya el pulgar.

Capturas clave: `obby-sky-tower/mid-pc.png`, `mid-phone-menu.png`, `mid-phone-shop.png`.

## anime-planet-clicker (Planet Crackers)

1. **Celular: todo a escala 0.55** (ver arriba). De `mid-phone.txt`: chips de auto 48x19 px (`anime-planet-clicker/src/client/UI/Hud.luau:213`), botón Shop 169x24 (`Hud.luau:151`), botones del menú 31x31 (`Hud.luau:174`), SELL 53x31 (`Hud.luau:246`), regalo 103x23 (`Hud.luau:274`); etiquetas de 6-8 px (`Hud.luau:190`, `UI/Theme.luau:349`).
2. **Ventanas en celular**: se crean de 780x490 (`UI/Windows.luau:62-75`; tamaños en `PetsWindow.luau:206`, `UpgradesWindow.luau:219`, `StoreWindow.luau:42`, etc.) y se escalan igual: en Pets los botones Equip Best / Fuse All / Delete quedan de 19 px de alto y el "+" de 19x19; el X de 31x31 (`Windows.luau:130`). En Rewards las etiquetas "Day N" y los premios son ilegibles.
3. **Badges "!" tapados por el botón vecino** (PC y celular): el badge de Index queda 38% debajo de Quests y el de Rewards debajo de Auto. El badge se crea en `UI/Theme.luau:411` como hijo del botón y el botón siguiente de la grilla se dibuja encima (mismo `ZIndex`, orden de hermanos con `ZIndexBehavior.Sibling`). Hay que subir el `ZIndex` del contenedor o sacar el badge fuera de la grilla.
4. **(confirmar)** En las tarjetas de mascotas aparece un rectángulo "3D": son `ViewportFrame` (la herramienta no dibuja 3D), no un bug.
5. Economía (no UI): con el perfil mid (2 rebirths, 2.45M stardust) la ventana Rebirth pide 64Qa. Puede ser el perfil de prueba, pero vale mirar la curva.

Capturas clave: `anime-planet-clicker/mid-phone.png`, `mid-phone-pets.png`, `mid-phone-rewards.png`, `mid-pc.png`.

## huerta-tycoon (Crop Kingdom)

El mejor en celular: tiene layout táctil propio (`UI/Layout.luau`) y ningún botón por debajo de 44 px.

1. **La tienda de Robux dice "Store coming soon!"** (`huerta-tycoon/src/client/UI/StorePanel.luau:36-53`): todas las `Config.GamePasses`/`Config.DevProducts` tienen `id = 0`. No es un bug de UI, pero hoy el botón Store del HUD abre una ventana vacía.
2. Celular: el cartel del clima **"Next weather in 1m 48s" se parte en 3 renglones** y el "48s" se sale de la píldora hacia la de abajo (Wild Patch / Lucky Hour). Ver `mid-phone.png`, arriba a la izquierda. **(confirmar)**: depende del ancho real de FredokaOne.
3. Daily Rewards: el ✅ de los días reclamados se dibuja encima del premio y deja asomar el nombre ("Pumpkin") por abajo (`UI/DailyPanel.luau:88`, `UI/Components.luau:191`). Probablemente es a propósito, pero queda sucio.
4. Celular: en Gifts el botón Claim del primer regalo y en Language el botón de coreano quedan debajo del joystick (`UI/GiftsPanel.luau:130`, `UI/LanguagePanel.luau:52`). Se puede scrollear, así que es menor.
5. **(confirmar)** La barra del SELL del HUD muestra el relleno naranja cortado junto al ícono de la mochila (`mid-pc.png`, abajo al centro).
6. Deprecado: `BillboardGui.DistanceLowerLimit` (`UI/Components.luau:21`).

Capturas clave: `huerta-tycoon/mid-phone.png`, `mid-pc-store.png`, `mid-phone-daily.png`.

## ki-warriors

1. **Texto: "1 Ascensions"** en la ventana Ascend (`ki-warriors/src/shared/Locales/en.luau:100` `"{n} Ascensions"`, usado en `src/client/UI/Panels1.luau:176`). Falta el singular.
2. **Celular: HUD a escala 0.55** y es el más cargado de los 6 (32 hallazgos en `mid-phone.txt`):
   - Toggles Auto Train/Ki/Fight de **69x14 px** (`UI/Hud.luau:148-150`, tamaño en `Hud.luau:100`) con texto de 6 px (`Hud.luau:112`).
   - Stats de entrenamiento de 26x26 px (`Hud.luau:157`), Gear de 53x28 (`Hud.luau:184`).
   - Objetivo (QuestTracker) de 139x24 px con título y progreso de 5 px (`UI/QuestTracker.luau:166-171`).
   - Botones táctiles de habilidades de 31-39 px (`UI/TouchControls.luau:48`, posiciones en `:93-132`).
   - Textos de HP, Ki, poder y boost de 6-8 px (`Hud.luau:82`, `:90`, `UI/Theme.luau:388`).
3. **Celular: el menú (Warrior/Quests/Rewards/Shop/Season/More) queda abajo a la izquierda, debajo del joystick**, con botones de 26 px (`UI/Menu.luau:94`, `:173`). En PC está a la izquierda al medio; en táctil conviene subirlo o pasarlo arriba.
4. Celular con una ventana abierta (p. ej. Ascend): el X de la ventana se pisa con el toggle Auto Fight (`mid-phone-ascend.txt`, `mid-phone-invite.txt`).
5. PC: las ventanas se ven bien; Invite y Shop tienen mucho espacio vacío abajo (Shop solo lista 3 semillas; **(confirmar)** con productos reales).

Capturas clave: `ki-warriors/mid-phone.png`, `mid-pc-ascend.png`, `mid-phone-warrior.png`.

## pet-tap-simulator (Tap Pets)

1. **Badges "!" tapados** en PC y celular: el badge de Rewards del dock queda 39% debajo del botón grande de Tap, y el de Index debajo de Teleport (badge creado en `pet-tap-simulator/src/client/UI/Theme.luau:457`). Mismo caso que Planet Crackers: subir el `ZIndex`.
2. Celular (escala 0.55): toggles Auto (Tap/Eggs/Best/Rebirth) de 54x31 px (`UI/Hud.luau:454`), botón de regalo 111x31 (`Hud.luau:340`), botones del menú de 39x39 (`Hud.luau:101`), objetivo de 33 px de alto (`Hud.luau:276`) con porcentaje de 8 px (`Hud.luau:293`). Menos grave que los otros tres porque los botones base son más grandes.
3. El panel del huevo (Basic Egg) muestra probabilidades con 4 decimales (57.6923%, 0.0013%): se lee, pero apretado en celular.
4. **(confirmar)** En Codes & Language los nombres en japonés/coreano/tailandés salen como cajitas: la herramienta no tiene fuente CJK (en Roblox se ven).

Capturas clave: `pet-tap-simulator/mid-phone.png`, `mid-pc.png`, `mid-phone-egg.png`, `mid-phone-codes.png`.

## ruleta-pvp (Spin Showdown)

1. **Season Pass: los botones "Skip tier R$ 39" y "Premium R$ 399" tapan el texto** "Each match: +45 points for a win..." y "Points come only from playing. Buying never..." (PC y celular). Los dos labels ocupan la mitad izquierda (`ruleta-pvp/src/client/UI/MenuWindows.luau:353-354`, `Size = UDim2.new(0.5, 0, ...)`) y los botones arrancan antes de la mitad. Ver `mid-pc-season.png`.
2. **Celular: el panel Power Core tapa las metas** ("80 trophies to Platinum / 60 points to season tier 1"): la píldora `Goals` (`UI/Hud.luau:72`, arriba a la derecha) y `Core` (`Hud.luau:195`, a la derecha al medio) se pisan cuando todo baja a 0.55. En PC no pasa.
3. Celular: el "+" de monedas queda de **17x17 px** (`Hud.luau:63`), Auto-queue 56x31 (`Hud.luau:122`), Tap/Auto del Power Core 98x31 y 98x21 (`Hud.luau:201`, `:208`), botones del menú 36x34 (`Hud.luau:95`); textos de liga/metas/nivel de 7-8 px (`Hud.luau:48-75`).
4. Celular: el menú de la izquierda (Invite/Settings) queda sobre el joystick (`Hud.luau:95`).
5. **(confirmar)** La ventana **Play** tiene el medallón vacío: el ícono es el texto "▶" (`MenuWindows.luau:101`, dibujado por `UI/Windows.luau:110`), blanco sobre el medallón blanco. Si Roblox lo muestra como glifo de texto (sin el selector de emoji `U+FE0F`), no se ve. Usar "▶️" o un ícono del pack.
6. Partido (`mid-*-match.png`, partido real contra bots): se ve bien en PC y en celular.
7. Ranking vacío salvo el propio jugador: no hay datos en el DataStore simulado, no es bug.

Capturas clave: `ruleta-pvp/mid-pc-season.png`, `mid-phone.png`, `mid-pc-play.png`, `mid-pc-match.png`.

---

## Qué puede ser un artefacto de la herramienta

- Tamaños de `TextScaled` y anchos de texto: fuentes aproximadas (Fredoka en lugar de FredokaOne, Montserrat en lugar de Gotham). Diferencias de 1-2 px son esperables.
- Joystick y botón de salto: posiciones aproximadas del PlayerModule. Los `core-overlap` con el joystick marcan la zona del pulgar, no un solapamiento exacto.
- Todo lo que depende del mundo 3D (flechas del tutorial, carteles sobre objetos, `ViewportFrame`) no está.
- Textos en japonés, coreano, chino y tailandés salen como cajitas (no hay fuente CJK en la herramienta).
- La tienda de Robux y los precios usan `GetProductInfo` simulado (99 R$); ningún pase comprado.
- Los chequeos `small-touch` usan 44 px (guía de Apple); Roblox no tiene un mínimo oficial.
