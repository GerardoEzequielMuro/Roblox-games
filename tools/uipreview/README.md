# uipreview: capturas aproximadas de la UI sin Roblox Studio

Esta herramienta corre el código **cliente y servidor** de cada juego en un Roblox simulado (sin Studio, en Linux), arma el `PlayerGui` que construye el juego, calcula el layout y dibuja un PNG que se parece a lo que vería el jugador en PC o en celular. Además saca una lista de problemas detectados automáticamente: texto cortado, botones fuera de pantalla, botones encimados, botones chicos para el dedo, y errores de runtime con archivo y línea.

**Ojo: es una aproximación.** Sirve para encontrar problemas gruesos de layout, no para validar píxel por píxel. Antes de "arreglar" algo que sale acá, fijate en la sección [Qué aproxima y qué no](#qué-aproxima-y-qué-no).

## Cómo se corre

Requisitos (en esta máquina ya están en `/tmp/tools`):

- [Lune](https://github.com/lune-org/lune/releases) 0.10.x (`lune` en el PATH o en `/tmp/tools`)
- [Rojo](https://github.com/rojo-rbx/rojo) 7.x (para el sourcemap)
- Python 3 con Pillow. Opcional: `fonttools` (`pip install fonttools`) para que los caracteres que la fuente no tiene se dibujen con una fuente de reemplazo, como hace Roblox.

```bash
export PATH=/tmp/tools:$PATH

# HUD de un jugador nuevo en PC
python tools/uipreview/preview.py huerta-tycoon

# jugador a mitad de partida, en celular
python tools/uipreview/preview.py ki-warriors --state mid --screen phone

# abrir una ventana (los nombres salen de --list-windows)
python tools/uipreview/preview.py pet-tap-simulator --state mid --screen phone --open pets
python tools/uipreview/preview.py all --list-windows

# todo lo de un juego: new+mid en pc+phone, cada ventana (estado mid) en pc+phone y mid con --icons
python tools/uipreview/preview.py obby-sky-tower --all

# todo para los 6 juegos
python tools/uipreview/preview.py all --all
```

Opciones útiles:

| Opción | Qué hace |
|---|---|
| `--state new\|mid` | `new`: primera vez que entra (no hay nada guardado). `mid`: carga el perfil guardado del fixture. |
| `--screen pc\|laptop\|phone\|tablet` | pc 1920x1080, laptop 1366x768, phone 844x390 (táctil, con notch), tablet 1180x820 (táctil). |
| `--open <ventana>` | Abre esa ventana llamando a las funciones del propio juego (ver fixtures). |
| `--icons` | Hace de cuenta que los íconos de `assets/icons` ya están subidos: completa `Icons.ids` con ids falsos y dibuja los PNG. Sirve para ver cómo va a quedar después de subirlos. |
| `--annotate` | Dibuja cuadros numerados alrededor de cada hallazgo. |
| `--locale es-es` | Idioma del dispositivo simulado (por defecto `en-us`). |
| `--boot 12` | Segundos virtuales que corre el juego antes de sacar la foto (por defecto 8). |
| `--dump-json` | Guarda también el árbol con las propiedades, al lado del PNG. |
| `--from-cache` | No vuelve a correr el juego: usa el último volcado de `.cache` y solo rehace layout, dibujo y chequeos (para iterar sobre la herramienta). |
| `--outdir <dir>` | Otra carpeta de salida. |

Salida: `docs/previews/<juego>/<estado>-<pantalla>[-<ventana>][-icons].png` y un `.txt` con el mismo nombre que tiene:

1. **Layout findings**: cada problema con severidad (`high`/`med`/`low`), la ruta del objeto en el `PlayerGui`, el rectángulo en coordenadas de la pantalla completa, y **dónde se creó** ese objeto (`archivo:línea` de las 3 primeras llamadas del juego en la pila, por ejemplo `Kit.luau:209 < Hud.luau:338 < init.client.luau:34`).
2. **Runtime log**: errores de Luau, `WaitForChild` que nunca terminan, APIs de Roblox que el simulador no implementa, tablas raras mandadas por remotes, propiedades deprecadas.
3. **Other log**: `warn`/`print` del juego y lo que hizo el fixture.

Las imágenes de PC se guardan achicadas a 1280 px de ancho y todas con paleta de 256 colores para que no pesen. Las coordenadas del `.txt` son siempre las de la pantalla completa.

## Cómo funciona

```
preview.py ── rojo sourcemap ──► .cache/<juego>.sourcemap.json
    │
    ├─► lune run runtime/main.luau  (simula Roblox, corre server + client, abre la ventana)
    │        └─► .cache/<...>.json  (árbol del PlayerGui + log)
    │
    ├─► layout.py    (UDim2, AnchorPoint, UIListLayout, UIGridLayout, UIScale, etc.)
    ├─► render.py    (Pillow: fondos, esquinas, bordes, gradientes, texto, emoji, íconos)
    └─► findings.py  (chequeos automáticos)
```

### El runtime (`runtime/*.luau`, corre en Lune)

- **Instancias verificadas contra el API dump de Roblox** (`data/api.json`, se genera solo desde el [API-Dump.json](https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json) la primera vez). Si el juego lee o escribe un miembro que no existe, tira el mismo error que Roblox (`X is not a valid member of Y`). Las escrituras chequean el tipo (`bool expected, got nil`, enums por nombre o número, etc.) y las propiedades de solo lectura.
- **APIs que existen en Roblox pero el simulador no implementa**: devuelven `nil` y quedan anotadas como `unknown_api` con la línea que las llamó (no rompen la corrida).
- **"Play Solo" en un solo proceso**: primero corren los `Script` del servidor, después entra el jugador (`PlayerAdded`), se clonan `StarterGui` y `StarterPlayerScripts`, aparece el personaje y corren los `LocalScript`. Los `RemoteEvent`/`RemoteFunction` conectan cliente y servidor de verdad (copiando los argumentos como hace Roblox), así que el snapshot que recibe el cliente sale **del código del servidor de cada juego**, no de datos inventados.
- **Estado del jugador**: el `DataStore` es de mentira. Con `--state new` está vacío (jugador nuevo); con `--state mid` devuelve el perfil del fixture para la clave del jugador, y el `Data.load`/`reconcile` del propio juego completa el resto.
- **`require` por instancia**, resuelto con el árbol del sourcemap de Rojo; cachés separados para cliente y servidor (como en Roblox, que son dos VMs).
- **Reloj virtual y scheduler**: `task.spawn/defer/delay/wait`, `wait`, `delay`, `spawn`, `RunService.Heartbeat/RenderStepped/...`, `BindToRenderStep`. El tiempo avanza de a 1/30 s durante 8 s virtuales (tarda 1 o 2 s reales). Los `while true do task.wait() end` no cuelgan: se cortan cuando termina la simulación.
- **`TweenService`**: aplica el estado final enseguida y dispara `Completed`.
- **`WaitForChild`**: devuelve al toque si el hijo existe; si no, espera; a los 5 s anota "Infinite yield possible" y, si al final sigue colgado, sale como `blocked-thread`.
- **Servicios simulados**: Players/LocalPlayer/PlayerGui/Character, UserInputService (TouchEnabled según la pantalla), GuiService (inset de 58 px del topbar), Workspace.CurrentCamera.ViewportSize, MarketplaceService, PolicyService, LocalizationService, TextService:GetTextSize (mide con las mismas fuentes que dibuja), DataStoreService, HttpService, CollectionService, TextChatService, SocialService, BadgeService, etc.
- **Mediciones en vivo** (`AbsoluteSize`, `AbsolutePosition`, `TextBounds`, `TextFits`, `AbsoluteContentSize`): aproximadas del lado de Luau, sin layouts. El layout "de verdad" lo hace Python.

### Fixtures (`fixtures/<juego>.luau`)

Cada juego tiene un fixture con:

- `profileStore` y `midProfile(h)`: el perfil guardado de un jugador a mitad de partida (con la forma de `Data.luau` del juego; `h.shared("Shared.Config")` da acceso a la config para elegir ids válidos).
- `windows`: cómo abrir cada ventana, llamando a las funciones del juego (`ctx.client("UI.Windows").open("Pets")`, `ctx.click(ctx.find("MenuButton"))`, etc.). En `ruleta-pvp`, `match` pide `QuickPlay` al servidor y espera a que arranque un partido de verdad contra bots.

`ctx` tiene: `client(path)`, `shared(path)`, `find(name)`, `findButton(patrón)`, `click(botón)`, `wait(s)`, `log(msg)`, `serverFire(remote, ...)`.

## Chequeos automáticos

| Tipo | Qué detecta |
|---|---|
| `text-overflow` | Texto que no entra en su caja al `TextSize` que tiene (sin `TextScaled`). |
| `tiny-text` | `TextScaled` que termina en menos de 9 px, o `TextSize` final (con `UIScale`) menor a 9 px. |
| `offscreen` | Elementos que se salen de la pantalla (total o parcialmente). |
| `clipped` | Botones o textos cortados por un padre con `ClipsDescendants` (sin contar el scroll normal). |
| `canvas-short` | Contenido que queda debajo del `CanvasSize` de un `ScrollingFrame` (no se puede scrollear hasta ahí). |
| `overlap` | Botones que se pisan entre sí (no cuenta si una ventana opaca los tapa). |
| `text-overlap` | Textos que se pisan entre sí. |
| `covered` | Un texto o botón tapado en 30% o más por otra pieza chica y opaca del HUD dibujada encima (las ventanas grandes cuentan como modales y no se reportan). |
| `small-touch` | Botones de menos de 44 px en pantallas táctiles. |
| `core-overlap` | Botones o textos debajo de los botones del topbar de Roblox o del joystick/salto en táctil. |

Hallazgos repetidos (mismo tipo, mismo lugar del código) se agrupan: `(x5 similar)`.

## Qué aproxima y qué no

Lo que **sí** se simula: `Size`/`Position` con `UDim2` y `AnchorPoint`, `SizeConstraint`, `UIPadding`, `UIListLayout` (dirección, `Padding`, alineaciones, `SortOrder` LayoutOrder/Name, `Wraps`, flex aproximado), `UIGridLayout` (`CellSize`, `CellPadding`, `FillDirectionMaxCells`, `UIAspectRatioConstraint` en las celdas), `UIPageLayout` (solo la primera página), `UIAspectRatioConstraint`, `UISizeConstraint`, `UITextSizeConstraint`, `UIScale` (acumulado; escala offsets, texto y bordes), `AutomaticSize` (aproximado), `ScrollingFrame` (`CanvasSize`, `AutomaticCanvasSize`, `CanvasPosition`, barra), `Visible`, `Enabled`, `ZIndex` con `ZIndexBehavior` Sibling/Global, `DisplayOrder`, `ScreenInsets`/`IgnoreGuiInset` (topbar de 58 px y, en phone, notch de 47 px a los costados), `ClipsDescendants` (rectangular), `UICorner`, `UIStroke` (borde y contorno de texto), `UIGradient` (color y transparencia, con rotación), `CanvasGroup.GroupTransparency`, `TextScaled`/`TextWrapped`/`TextTruncate`/alineaciones/`RichText` (se sacan los tags) y emoji a color.

Lo que **no** (o muy por arriba):

- **Fuentes**: FredokaOne se dibuja con Fredoka SemiBold, Gotham con Montserrat, el resto con Source Sans 3. Los anchos se parecen pero no son idénticos: un texto que "no entra por 2 px" puede ser un falso positivo; uno que no entra por 30 px, no.
- **`TextScaled`**: el tamaño que elige Roblox puede diferir en 1 o 2 px.
- **Imágenes**: no hay acceso a los assets de Roblox. Un `ImageLabel` con `rbxassetid://` se dibuja como rectángulo rayado con el id; si es uno de los íconos del pack (`--icons` o `assets/asset_ids.json`) se dibuja el PNG de `assets/icons`. Las fotos de avatar son un círculo gris.
- **`ViewportFrame`**: rectángulo "3D viewport" (no hay 3D).
- **Mundo 3D**: el fondo es un cielo y pasto genéricos. `BillboardGui`/`SurfaceGui` no se dibujan. `Raycast` devuelve nada y la cámara no proyecta, así que lo que depende de posiciones 3D (flechas del tutorial que apuntan a un objeto del mundo, carteles sobre la cabeza) no es confiable.
- **Topbar, joystick y botón de salto**: se dibujan encima con posiciones aproximadas del PlayerModule de Roblox (el joystick dinámico real ocupa toda la esquina).
- **Animaciones**: los tweens saltan al final. Si algo arranca invisible y aparece con un tween que depende de un evento que no pasa, puede no verse.
- **`Rotation`** rota solo el propio elemento, no sus hijos. `UIFlexItem`, `UITableLayout` y `AutomaticSize` anidado son aproximados.
- **Tiempo**: 8 s virtuales. Lo que depende de esperar minutos (cofres, eventos por hora) sale como lo ve el jugador a los 8 s.
- **Ranking, amigos, compras**: vacíos o de ejemplo (`GetProductInfo` devuelve 99 R$, ningún pase comprado).
- **Mediciones en Luau** (`AbsoluteSize`, `TextBounds`…) no consideran los layouts. Si el juego usa `AbsoluteSize` de algo que está dentro de un `UIListLayout` para calcular otra cosa, el resultado puede diferir.

Posibles artefactos de la herramienta que conviene confirmar en Studio antes de tocar código:

- `text-overflow` por pocos píxeles.
- `offscreen` o `core-overlap` de elementos que el juego posiciona después según algo del mundo 3D.
- `unknown_api`: casi siempre es una API que el simulador no implementa, no un bug del juego. Los `error` sí son errores reales de Luau (salvo que el mensaje venga de `tools/uipreview/runtime`, que sería un bug de la herramienta).

## Archivos

- `preview.py`: CLI.
- `runtime/`: simulador de Roblox en Luau para Lune (`core.luau` scheduler, señales y datatypes; `instance.luau` instancias; `services.luau` servicios; `text.luau` medición de texto; `main.luau` arranque y volcado).
- `layout.py`, `render.py`, `findings.py`, `fonts.py`, `build_data.py`.
- `fixtures/`: estado mid y ventanas de cada juego.
- `fonts/`: Fredoka, Luckiest Guy, Bangers, Montserrat, Source Sans 3 (licencias OFL/Apache en la misma carpeta). Emoji: Noto Color Emoji del sistema (`/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf`), o una cajita si no está.
- `data/`: `api.json` (API dump compactado) y `metrics.json` (anchos de caracteres). Se regeneran con `python tools/uipreview/build_data.py --force`.
- `.cache/`: sourcemaps, configuraciones y volcados JSON de cada corrida (se puede borrar).
