# Handoff: sesión en la nube del 30/09 (tarde) — COMPLETA

Leé esto antes de retomar con la sesión local. El detalle por juego está en `docs/handoff/<juego>.md`.

## 1. Cambió dónde vive el código (importante)

- Los 6 juegos ahora viven en **un solo repo**: `GerardoEzequielMuro/Roblox-games`, cada uno en su carpeta.
- Los `.git` propios de cada juego se movieron a `C:\work\_Personal\_git-backups\<juego>.git`. El historial viejo está ahí, pero **los hashes y los `git reset --hard <hash>`** de `ROBLOX-MEJORAS-NOCHE.md` ya no aplican dentro de `proyectos`.
- Lo que había sin commitear en cada juego al pausar (Crop Kingdom 45 archivos, Tap Pets 31, etc.) **quedó incluido** en el primer commit del monorepo.
- El trabajo de esta sesión está en la rama `claude/hello-iselsx`. Para traerlo:

```powershell
cd C:\work\_Personal\proyectos
git fetch origin
git merge origin/claude/hello-iselsx     # o abrir un PR a main y mergear desde GitHub
```

- El prompt del `/loop` de la sesión local habla de "commitear en cada repo". Ahora es un solo repo: los agentes tienen que commitear en `proyectos` y **no pueden commitear en paralelo** (se pisan con el `index.lock`). Un agente por juego editando y **uno solo** commiteando.

## 2. Por qué se ven "de 2016" (medido, no opinión)

| Juego | Archivos .luau | Mallas (MeshId) | Imágenes subidas (rbxassetid) |
|---|---|---|---|
| anime-planet-clicker | 83 | 0 | 0 |
| huerta-tycoon | 96 | 0 | 0 |
| ki-warriors | 76 | 2 | 0 |
| obby-sky-tower | 81 | 0 | 0 |
| pet-tap-simulator | 79 | 0 | 0 |
| ruleta-pvp | 69 | 0 | 0 |

- Todo está hecho con piezas primitivas creadas por código, y los íconos del HUD son emojis de texto.
- Los juegos top usan modelos 3D, íconos dibujados, texturas y sonido. **Sin assets no hay loop de código que los haga ver de 2026.**

## 3. Qué hice yo (compartido para los 6)

- **Pack de 46 íconos propios** en `assets/icons/*.png` (512 px), estilo glossy de simulador (contorno grueso, gradiente, brillo). Vista general: `assets/icons_sheet.png`.
  - Se regeneran con `python tools/icons/make_icons.py` (necesita `pip install cairosvg pillow`).
- **`src/shared/Icons.luau` en cada juego**: `Icons.get("coin")` devuelve la imagen si está subida, o `nil`. Con `nil` el HUD sigue mostrando el emoji: nada se rompe antes de subir los íconos.
- **Script de subida**: `tools/icons/upload_assets.py`. Sube los PNG con la API Open Cloud de Roblox y escribe los IDs en el `Icons.luau` de los 6 juegos.

### Lo que tenés que hacer vos: subir los íconos (unos 10 minutos)

1. https://create.roblox.com/dashboard/credentials → Create API Key. Permiso: **Assets → Read y Write**. IP: la tuya.
2. Buscá tu user id en la URL de tu perfil (`roblox.com/users/<ID>/profile`).
3. En PowerShell, desde `proyectos`:

```powershell
pip install cairosvg pillow
$env:ROBLOX_API_KEY = "<la key>"      # solo en la terminal, nunca en un archivo del repo
$env:ROBLOX_USER_ID = "<tu id>"
python tools/icons/upload_assets.py
```

4. Commit de `assets/asset_ids.json` y de los `Icons.luau` actualizados.
5. **Verificar en Studio que el ID sirve para un ImageLabel.** Open Cloud sube como "Decal". Según la documentación y herramientas como Asphalt, el ID que devuelve es la imagen, pero no lo pude probar desde acá. Si algún ícono sale en blanco, ese es el primer sospechoso.

## 4. Qué hicieron los agentes por juego

Todo verificado dos veces (por el agente y por mí) sin Studio: `rojo build` OK, `luau-lsp analyze` con 0 errores y todos los tests puros en verde. **Nada se vio corriendo.** Cada `docs/handoff/<juego>.md` tiene la lista "Qué hay que mirar en Studio".

Los 6 juegos tienen los íconos integrados: muestran la imagen cuando el ícono está subido y el emoji mientras tanto.

| Juego | Bugs arreglados | Mejoras | Tests puros |
|---|---|---|---|
| **Sky Tower Obby** | El botón "Lobby" del teletransportador **borraba el progreso** (del 850 al 0). Se podían farmear Wins y el bonus de cumbre sin límite. Tocar un portal viejo te mandaba para atrás. Los botones de prueba de Studio ya no aparecen en el juego publicado. Posible causa del personaje desarmado: accesorios soldados antes de que cargue el avatar. | Materiales nuevos en los mundos 7-9 y degradé en el HUD. | layout 144.843, rules 3.569, visual 12.942, locale 9.780, p0 48, icons 82 (nuevo) |
| **ki-warriors** | Placa del enemigo gigante, cubos oscuros al pegar, esfera violeta que tapaba al personaje (forma Eclipse) y HUD en inglés (Studio tomaba el idioma de su interfaz). | Materiales por planeta, variación de color, 30 detalles de suelo por planeta, cielos menos saturados, fuentes FredokaOne/Bangers. No usé los íconos `orb` ni `cloud`: se parecen demasiado a Dragon Ball. | locale 336/336, glyphs (nuevo) |
| **Tap Pets** | `TapPetsSimulator.rbxlx` **estaba viejo**: tenía el HUD anterior, así que lo que viste no era el código nuevo. Regenerado. La reescritura del HUD quedó completa. El Huevo Mágico x1/x3 y el Starter Pack no mostraban probabilidades antes de comprar. | HUD progresivo: arranca con 4 botones y el resto aparece con el avance, como los juegos top. | unit_p0 55, policy_hud 111 (nuevo), locale 356, check_config OK |
| **Crop Kingdom** | Botones de menos de 40 px en celulares chicos. Carteles de crecimiento superpuestos, que ahora se ven solo en las 6 parcelas más cercanas. Números "+$" apilados. | Choclo afinado, hojas con material y verde variable, sombras y degradé en el HUD. | 8 tests en verde, incluido ui_test (nuevo) |
| **Planet Crackers** | En Studio, el DataStore dejaba 12 s cargando en cada playtest. Las cápsulas pagas no chequeaban la restricción antes de comprar. | Iluminación Future, material y color por galaxia, estación con luces. La retención recomendada (planeta muro, multiplicador por zona, zona rara por hora) ya estaba hecha. | unit 156 (antes 137), locale 504, check_config OK |
| **Ruleta PvP** | El AFK dejaba al jugador sin forma de volver a jugar. Un error en un partido tiraba abajo todas las mesas. El DataStore tardaba 12 s en Studio. El ranking de temporada no se reiniciaba al cambiar el mes. | Suspenso: desaturación al eliminar, pulsos de color, profundidad de campo, cuenta roja en los últimos 3 segundos, respetando los ajustes de flashes y temblor. | unit_core 659 (antes 579), locale OK |

**Archivos para publicar:** regeneré desde `src` `KiWarriors.rbxlx`, `SkyTowerObby.rbxlx` y `TapPetsSimulator.rbxlx`. En los otros 3 juegos el `.rbxlx` no está en el repo: se genera con `rojo build`.


## 4b. Ronda 2: precios realistas y retención

Base: `docs/research/top-juegos-y-precios.md`. Son precios de juegos reales sacados de wikis y guías: el proxy bloqueó la API de Roblox, así que no están confirmados contra la tienda. El detalle de cada juego está en la sección "Ronda 2" de `docs/handoff/<juego>.md`.

| Juego | Precios | Retención nueva | Tests |
|---|---|---|---|
| Crop Kingdom | 2x Cash 349, 2x Grow Speed 399 (nuevo), Instant Grow 9 R$ (compra de impulso), packs 49/199/499/999 | Chip "te faltan $X para...", regalo de bienvenida al terminar el tutorial | goals y pricing (nuevos) |
| Sky Tower Obby | Skip 19 R$ (niveles 1-300) y 29 R$ (301-1000), x10 a 149, Fusion Coil 139, Starter 59 | Regalo al primer minuto, anuncio al servidor al llegar a una cumbre | pricing (nuevo) |
| Tap Pets | x8 Hatch 699, Super Lucky 699 (con odds visibles), Auto Rebirth 199, +6 slots 649, Magic Eggs 599 | Racha diaria visible, reloj al próximo evento | passes_pricing 117 (nuevo), policy_hud 136 |
| Planet Crackers | Lucky 249, Super Lucky 699, x8 Open 699, +4 slots 649 | Evento Star Surge martes y sábado con reloj. **En el PvP no cuenta ningún pase pago.** | unit 175 |
| ki-warriors | 7 pases y 5 productos nuevos, 2 pases de batalla a 399 | Semillas (Vigor/Titan/Spark) con stock por hora, 11 skins de saga, 2 nubes, auras, forma Unbound, 2 ataques oscuros. **Todo lo pago también se gana jugando**, y en la arena no funcionan las ventajas pagas. La temporada 1 arranca el 01/10. | 4 tests nuevos, locale 423 |
| Ruleta PvP | Double Coins 199, pase de temporada 399, tier 39, pack 999 | Pase de temporada mensual (gratis + premium) que se sube solo jugando, chip de metas. **Un test asegura que nada pago afecta el partido.** | unit_core 1017 |

**Precios tachados honestos:** en varios juegos el precio tachado de las ofertas era inventado (un "-70%" que no existía). Ahora se calcula con lo que cuesta de verdad el contenido comprado por separado, y hay un test que lo controla. Mostrar un descuento falso es justo lo que puede traer problemas con Roblox.

**Decisiones tuyas pendientes, nuevas:**
- Tap Pets: el pase "Secret Hunter" (1.299 R$), que sube la chance de la mascota más rara. No lo agregué porque se acerca a pay-to-win.
- Crop Kingdom: el Starter Pack a 15 R$ con tachado 49. El 49 no es el precio real de nada. La investigación recomienda 29-49 R$.

**Todos los IDs de pases y productos siguen en 0.** Hay que crearlos en el Creator Dashboard y pegar los IDs en el `Config.luau` de cada juego.


## 4d. Ronda 3: espacios para modelos 3D

- Cada juego tiene entre 10 y 14 ranuras (78 en total) para sus props principales: árboles, rocas, edificios, estaciones, estatuas de jefes, landmarks.
- Para usar un modelo: en Studio, Toolbox → insertar → revisar que no tenga scripts → click derecho → Save to File (.rbxm) → guardarlo en `<juego>/assets/models/<ranura>.rbxm` → `rojo build`.
- Si la ranura está vacía se usan las piezas de siempre. Los scripts que traiga el modelo se borran solos, y si el modelo tiene demasiadas partes se descarta.
- La lista de ranuras de cada juego, con tamaño y qué buscar en el Creator Store, está en `docs/modelos/<juego>.md`.
- Las plataformas del obby y todo lo que afecta al gameplay no se tocaron.

## 4e. Ronda 4: interfaz revisada con la vista previa

- **Herramienta nueva, `tools/uipreview`:** arranca server y cliente de cada juego en un Roblox simulado (Lune), valida cada propiedad contra la API de Roblox y dibuja la interfaz en PC, laptop, tablet y celular. Se corre con `python3 tools/uipreview/preview.py <juego> --all`. Los límites están en su README: fuentes aproximadas y sin 3D.
- **Resultado del primer pase:** ningún juego tira errores al arrancar ni al abrir sus ventanas. Sí había muchos problemas de pantalla, sobre todo en celular: en 4 juegos el HUD quedaba a escala 0,55, con botones de 14 a 31 px y textos de 5 a 8 px.
- **Después de la ronda 4:** el HUD de celular de los 6 juegos queda sin hallazgos, con botones de al menos 44 px y textos de al menos 11 px, y las ventanas scrollean. Solo quedan avisos menores de contenido de ventanas que pasa por la zona del joystick; la herramienta marca esa zona entera aunque el joystick real aparece solo donde tocás. También se arreglaron plurales ("1 Ascensions", "Deleted 1 pets") y, en el obby, botones sin texto.
- **Capturas actuales:** `docs/previews/<juego>/`, con el detalle en cada `.txt`.
- **Para confirmar en un celular real:** que nada choque con el notch ni con la barra de Roblox, y la posición real del joystick y del botón de salto.


## 4f. Ronda 5: ritmo de progresión (simuladores)

Cada juego tiene ahora un simulador en Luau puro que usa su `Config` y sus fórmulas reales. Simula a un jugador que no paga, arma la línea de tiempo de hitos y tiene un test que falla si el ritmo se sale de los objetivos. Se corre con `luau sim/pacing_sim.luau` desde la carpeta del juego.

| Juego | Hallazgo | Cambio medido |
|---|---|---|
| ki-warriors | **El juego se terminaba en unos 90 minutos**: los multiplicadores por planeta estaban 3 o 4 órdenes de magnitud de más. | Planeta 2 de 17 a 6 min, primera ascensión a los 33 min, planeta 10 cerca del día 29. Los pases de batalla se completan dentro de la temporada jugando activo. |
| Planet Crackers | Esperas de 25 a 30 min sin nada nuevo en la primera hora. | Espera máxima de 31 a unos 9 min, primer rebirth de 51 a 39 min. |
| Tap Pets | Frost Peak llegaba a los 30 min y la primera mejora con gemas al minuto 5. | Frost de 30 a 13 min, Lava de 44 a 28, primera mejora al minuto 2. |
| Crop Kingdom | Lo que frenaba era el stock de semillas, no la plata. El mango tardaba unos 52 min. | Mango a 32 min, primer rebirth de 61 a 45 min, bache máximo de 10 a 6 min. |
| Sky Tower Obby | Etapas imposibles, como un wallhop de unos 200 s, en medio de etapas fáciles. | Sin picos injustos y **más difícil en promedio**, como pediste: la mediana por torre subió en 8 de 10. Cosméticos más accesibles al principio. |
| Ruleta PvP | El pase de temporada se completaba en 9 días y la tienda se vaciaba en una semana. | Pase en unos 23 días, tienda para semanas, nivel 10 a los 38 min en vez de al día 3. |

**Límites:** los simuladores modelan un tipo de jugador con supuestos propios, como cuántos clicks hace o el riesgo de cada salto. Sirven para comparar antes y después y encontrar baches, no para predecir tiempos exactos. Los tiempos reales se miden con analíticas cuando el juego esté publicado.

**Huecos de contenido: resueltos en la ronda 6**

| Juego | Qué se agregó | Resultado |
|---|---|---|
| Tap Pets | 8 huevos nuevos con 32 mascotas, que se desbloquean por cantidad de rebirths | Bache máximo en las primeras 2 h: de 31 a unos 11 min |
| Planet Crackers | 11 herramientas de "Asteroid Field" dentro de las galaxias 4 y 5 | Bache máximo en las primeras 2 h: de unos 48 a unos 9 min |
| Sky Tower Obby | 15 cosméticos por torre, 4 mascotas de hombro y mejoras "Shine". Todo cosmético, nada ayuda a escalar. | Siempre hay algo por qué juntar monedas hasta la torre 10 |
| ki-warriors | XP gratis del pase (primera victoria diaria, desafíos semanales, recuperación si vas atrasado) y dos formas nuevas, Corona y Solstice | El jugador casual completa los dos pases (día 45-46 de 56). Hueco de 20 min cerrado. |

## 4c. Hasta dónde conviene seguir sin Studio

Después de 2 rondas, todo lo que se puede verificar sin Studio está hecho. Lo que falta necesita ver el juego andando:

- **Muchísima UI nueva que nadie vio:** ventanas de temporada y de estilo, chips de meta, tienda con 13 tarjetas, botones x8, cinemática con 8 mascotas. Seguro hay textos cortados o cosas encimadas.
- **Los AutoTest de Studio se actualizaron pero nunca se corrieron.**
- **Assets:** íconos subidos, modelos 3D y sonido.

Otra ronda de código a ciegas suma riesgo: más código sin ver, sobre código que tampoco se vio. **Lo siguiente es correr el AutoTest de cada juego en Studio y arreglar lo que falle.** Recomendado de a un juego por vez, empezando por ki-warriors.

## 5. Cómo verificar sin Studio (lo que usé acá)

Las mismas herramientas corren en Windows (Rojo ya lo tenés en `huerta-tycoon\tools\rojo.exe`):

| Chequeo | Comando (desde la carpeta del juego) |
|---|---|
| Compila | `rojo build default.project.json -o out.rbxlx` |
| Tipos | `rojo sourcemap default.project.json -o sm.json` y después `luau-lsp analyze --definitions=@roblox=globalTypes.d.luau --sourcemap=sm.json src` |
| Tests puros | `luau tests\<test>.luau` (los que no son `.server` ni `.client`) |

- `luau-lsp`: https://github.com/JohnnyMorganz/luau-lsp/releases
- `globalTypes.d.luau`: https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau

Al arrancar, los 6 juegos daban **0 errores de tipos** y **todos los tests puros en verde**.

## 6. Recomendación para la sesión de la noche

1. **No relanzar 6 agentes en loop sobre el código.** Eso fue lo que quemó el límite en 2 horas, y el cuello de botella son los assets, no el código.
2. Subir los íconos (sección 3) y abrir cada juego en Studio para revisar la lista "Qué hay que mirar en Studio" de cada `docs/handoff/<juego>.md`.
3. Para modelos 3D:
   - Creator Store: modelos gratis de Roblox o de creadores verificados, agregados a tu inventario.
   - O la generación 3D con IA de Studio.
   - Registrarlos en un módulo `Models.luau` por juego, igual que `Icons.luau`: ID vacío = se usa la pieza primitiva actual.
4. Pendientes tuyos que siguen abiertos:
   - Precio del Starter Pack de Crop Kingdom: 15 o 99 Robux.
   - ki-warriors: nombres propios o la marca real.
