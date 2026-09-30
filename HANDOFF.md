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
