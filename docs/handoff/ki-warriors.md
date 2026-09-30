# Ki Warriors: handoff

Todo esto se hizo sin Studio: no vi el juego corriendo en ningún momento. Lo verifiqué con build, type check y tests puros. Todo lo visual está razonado desde el código y hay que mirarlo en Studio.

## Qué cambié

**Íconos (pack compartido)**
- `src/shared/Glyphs.luau` (nuevo, puro): mapea emoji → nombre del pack (`⚡`→coin, `💎`→gem, `👊`→fist, `🛡️`→shield, `🔥`→flame, `🌟`→rebirth, `🔒`→lock, `✔`→check, `🎁`→gift, `🛒`→shop, `⚙️`→settings, `📜`→quest, `🪐`→planet, `🧭`→map, etc.; son 45). Ignora el selector U+FE0F. **No se usan `orb` ni `cloud`**: la bola naranja con estrella y la nube amarilla voladora se parecen demasiado a Dragon Ball (regla de IP de DESIGN.md). Los emoji sin ícono (🦘, 💨, ☄️, 🔵, 🕊️, 👤, 💥…) quedan como están.
- `src/client/UI/Theme.luau`: `Theme.icon(glyph, props)` devuelve un ImageLabel (ScaleType Fit, fondo transparente) si `Icons.get` tiene id; si no, el mismo TextLabel emoji de siempre. `Theme.button` usa el ícono y, si hay imagen, parte los textos tipo "💎 120" en ícono + "120".
- Sitios que pasan por ahí: `UI/Kit.luau` (chips, y `Kit.text` cuando el texto es un glifo solo), `UI/Hud.luau` (medallas de monedas, slots de stats, slots de movimientos, badge de poder), `UI/Windows.luau` (medallón del título; la X de cerrar pasa al ícono `close`), `UI/Menu.luau`, `UI/TouchControls.luau`. Los emoji que están dentro de frases traducidas no se tocaron.
- Hoy todos los ids de `Icons.luau` están vacíos, así que **la UI se ve exactamente igual que antes** hasta que se suban.

**Bugs visuales**
- Placa de nombre/vida de enemigos (`src/client/NpcRender.luau`): ya estaba en offset (no en scale). Ahora es más chica (96×24 normal, 170×34 jefe), tiene un tope del ~9–16% del ancho de la pantalla (para celulares y ventanas chicas de Studio, donde 210 px podían ser un tercio de la pantalla), `AlwaysOnTop = false` explícito, `MaxDistance` 70/200 y se redimensiona cuando cambia el viewport. También achiqué el tag de poder de los jugadores (`CharFx.luau`) y el del maestro (`WorldBuilder.luau`).
- Cubos oscuros al pegar (`src/client/Fx.luau`, `CombatFx.luau`, `CharFx.luau`): eran los "chips" de material Slate gris que saltaban en Meteor Dive y en las transformaciones. Los reemplacé por `Fx.debris`: un burst de ParticleEmitter (textura por defecto, sin assets) en calidad normal, y en lite unas motitas claras chiquitas que se desvanecen del todo. Las chispas ahora terminan en transparencia 1 (antes quedaban al 0.6). El pool de partes cancela los tweens pendientes al liberar una parte, así un efecto terminado no puede seguir moviendo o agrandando una parte que ya usa otro efecto.
- Esfera violeta que tapaba al personaje (`CharFx.luau`): Eclipse es la forma "shadow", violeta. Había tres culpables: (1) la cáscara del aura era un elipsoide Neon de 6×9 studs alrededor del cuerpo, (2) las bolas Neon del burst de transformación arrancaban del tamaño del personaje con 0.2–0.35 de transparencia, (3) en las formas shadow, una de cada tres lenguas del aura era SmoothPlastic casi negra y opaca. Ahora la cáscara y los bursts usan material ForceField (borde brillante, centro transparente; está en `Fx.shell`), hay un burst de partículas y las lenguas oscuras son Neon semitransparentes. El pilar de luz pasó de 0.2 a 0.4 de transparencia.
- HUD en inglés con el idioma en español (`src/client/Lang.luau`, `src/shared/Locale.luau`): los textos del HUD ya pasaban por traducción. El problema era de dónde salía el idioma. En Studio, `Player.LocaleId` sigue el idioma de la interfaz de Studio (casi siempre inglés). Ahora en Studio manda primero `LocalizationService.SystemLocaleId` (el del sistema operativo) y en vivo se usa `Player.LocaleId` → `RobloxLocaleId` → `SystemLocaleId` (con `Locale.resolveFirst`, que es puro y está testeado). Además, **el AutoTest dejaba guardado `lang = "en"`** en el perfil de Studio al terminar; ahora restaura la preferencia que había (`tests/AutoTestClient.client.luau`). Los "MAX" del HUD y del panel de mejoras ahora pasan por `ui.max`.

**Look 2026 (sin assets nuevos)**
- `src/client/WorldFx.luau`: saturación de todos los cielos un ~40% más baja, contraste 0.1, bloom un poco más presente (umbral 1.35), `EnvironmentDiffuseScale` 1 y `EnvironmentSpecularScale` 0.7 para que se lean los materiales con Future, y `ShadowSoftness` 0.25.
- `src/server/World/WorldBuilder.luau`:
  - Cada tema tiene `rockMat`, `foliageMat` y `pathMat` (Rock/Grass/Ground en Verdia, Basalt en el volcán, Glacier/Snow/Ice en el hielo, Sandstone/Sand en el desierto, etc.). Troncos y tótems son Wood; la plaza es Pavement/Slate; las piedras de los portales, Slate.
  - Ruido de color por parte (`vary`, con su propio RNG) en montañas, colinas, rocas, árboles, arbustos y parches de suelo.
  - Detalle de suelo nuevo: 30 por planeta (matas de pasto, montículos de nieve o piedritas según el tema), de 2 partes cada uno, con su propio RNG para no mover nada de lo que ya estaba.
- UI (`Theme.luau`, `Hud.luau`): los números usan FredokaOne (`Theme.Display`) y Bangers queda para el combo, el nombre de la forma y los números de daño (`Theme.Comic`). Hay `Theme.pressable` (hover + squash al apretar) en los toggles de auto, el botón de pesas y los slots de movimientos. Las píldoras de moneda tienen gradiente y números más grandes con contorno. Los toggles tienen brillo arriba.

## Cómo lo verifiqué

- `rojo build default.project.json`: OK (`Built project to ki-warriors.rbxlx`).
- `luau-lsp analyze … src`: 0 líneas de salida, o sea 0 errores.
- Tests puros: **2/2 OK**. `tests/locale_check.luau` (12 idiomas con 336/336 claves, más 5 casos nuevos de `resolveFirst`) y `tests/glyphs_check.luau` (nuevo: todos los íconos mapeados existen en el pack, no hay orb ni cloud, split y normalización andan, sin ids no hay imagen y 28/32 íconos de Config tienen imagen). No hay carpeta `sim/`.
- Presupuesto de partes del mundo: armé un harness con mocks en el scratchpad (no quedó en el repo) que corre `WorldBuilder.build()`. Dio **11.186 → 11.786 partes de 14.000** (`Config.Budget.worldParts`). El Random del mock no es el de Roblox, así que el número real puede variar un poco; el test de Studio "world part budget" es el que vale.

## Qué hay que mirar en Studio

1. **Transformarse a Eclipse** (y a cualquier otra forma): el personaje tiene que verse siempre y la cáscara del aura tiene que ser un borde brillante, no una bola. Si ForceField se ve demasiado fuerte o no se ve, ajustar `shell.Transparency` en `CharFx.updateAura` y los valores de `Fx.shell` en `transformBurst`.
2. **Meteor Dive y transformación**: que ya no queden cubos grises flotando. Tiene que haber un puff de partículas (o motitas en lite). Probarlo también con Graphics Quality 1.
3. **Placas de enemigos**: compactas a distancia media, que no tapen la pantalla en el emulador de celular ni con la ventana chica, y que el nombre se siga leyendo.
4. **Idioma**: con el sistema en español, entrar en Play sin `ForceLanguage` y ver el HUD en español. Si igual sale en inglés, puede que el perfil tenga `lang = "en"` guardado de antes: en Ajustes, elegir Español (o borrar el dato).
5. **Mundo**: cómo se ven los materiales (Rock/Grass/Basalt/Glacier…) y el ruido de color en cada planeta, sobre todo Verdia. Las matas de pasto son elipsoides aplastados cruzados, así que hay que ver si parecen pasto o "hojas". Correr el AutoTest y confirmar el "world part budget".
6. **Luz**: que el bloom nuevo (umbral 1.35) no queme los planetas con mucho Neon (Rift, Kaldera). Si pasa, volver a 1.6.
7. **Fuentes**: FredokaOne en poder, monedas y stats. Ver que no se corten los números largos ("1.23T").
8. **Íconos**: cuando se suban, revisar tamaño y posición del ícono dentro de los botones con precio ("💎 120") y en la X de las ventanas.

## Pendiente

- No encontré una placa gigante en el código actual (ya estaba en offset). Si en Studio se sigue viendo, quiero la captura para saber qué objeto es.
- Los materiales de estructuras (anillos de las zonas, portales, arena, coliseo) siguen en SmoothPlastic. Convendría una pasada con criterio visual en Studio.
- Faltan sombras (drop shadow) en toasts y en el tracker de misiones, y el estilo de los paneles de las ventanas se podría unificar más.
- Falta la opción "Automático" en el selector de idioma (el servidor ya acepta `lang = ""`).
- Nada del backlog de contenido de DESIGN.md (arcos nuevos, monturas, semillas): no es solo código seguro sin probar.
- Faltan íconos propios para ki (✨ usa `aura`), salto, dash, vuelo y rayo: el pack no tiene uno adecuado.
