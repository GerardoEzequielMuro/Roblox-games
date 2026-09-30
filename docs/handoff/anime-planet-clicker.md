# Planet Crackers (anime-planet-clicker): handoff

Aviso: nada de esto se vio corriendo. Trabajé en un contenedor Linux sin Roblox Studio. Todo se verificó con build, type checker y tests puros. Lo visual (luces, materiales, íconos) hay que mirarlo en Studio sí o sí.

## Qué cambié

**Revisión de runtime (el juego nunca corrió)**
- Revisé el boot del server (`src/server/Main.server.luau`, el orden de init de los Services), los remotes (`Services/Remotes.luau`) contra cada `WaitForChild`/`Net.event`/`Net.request`/`Kit.request` del cliente, los atributos que se leen contra los que se setean, las claves del snapshot contra lo que lee el cliente, DataStore load/save/lock, entrada y salida de jugadores, spawn, WorldBuilder y el boot del cliente. **No encontré ningún nombre roto**: todos los eventos, requests y atributos coinciden. El único handler sin uso era `CanBuy`, y ahora se usa (ver más abajo).
- `src/server/Services/Data.luau`: si el DataStore responde "sin acceso" (Studio sin *Enable Studio Access to API Services*, o un place sin publicar), deja de reintentar enseguida. Antes el jugador quedaba unos 12 s en "loading" en cada playtest. En ese caso la sesión igual sigue sin guardar, como antes.
- `src/server/Services/Pvp.luau` y `src/server/World/WorldBuilder.luau`: los drones de la arena y las máquinas de cápsulas son `ModelStreamingMode = Atomic`, así que con StreamingEnabled no aparecen a medias.
- Mientras trabajaba, el analyzer detectó un bug mío (un helper que quedaba tapado por una variable local `glow` en la refinería). Lo renombré a `addLight` antes de terminar.

**Retención (planet-wall, sistema por galaxia, zona rara horaria)**: ya estaba todo implementado, no hizo falta código nuevo.
- Gate Planet con HP guardado entre sesiones que bloquea la galaxia siguiente: `Services/Mining.luau` (`syncSpecial`, `unlockNextZone`) y `Config.Zones[n].gateHp`.
- Un sistema multiplicador distinto por galaxia (Relics, Temper, Traits, Overcharge, Constellation): `Config.Systems`.
- Anomaly cada hora UTC (15 min, un break por jugador por ventana) en todas las galaxias: `Formulas.anomaly`, más el reloj en el HUD.
- Sumé 19 tests puros en `tests/unit.luau`: ventana de la anomalía estable y nueva cada hora, la anomalía como jefe, cada gate existe y es más duro que el anterior, los nodos especiales no chocan, y hay un sistema en cada galaxia de la 2 a la 6.

**Íconos**
- `src/client/UI/Theme.luau`: `Theme.ICON_BY_EMOJI` (emoji → nombre en `Shared/Icons`), `Theme.iconImage` y `Theme.glyph`. `glyph` usa `ImageLabel` (ScaleType Fit) cuando `Icons.get` devuelve un id; si no, dibuja el mismo emoji de siempre. Hoy todos los ids están vacíos, así que se ve igual que antes.
- Dónde se usa: los pills de moneda del HUD, el grid del menú, el botón Shop (`UI/Hud.luau`), el medallón de cada ventana (`UI/Windows.luau`) y todos los `Theme.icon` (tiles de Store, Upgrades, Teleport, Quests).

**Look 2026 (sin assets nuevos)**
- `default.project.json`: Lighting `Technology = Future`, más difuso y especular de entorno.
- `src/client/WorldFx.luau`: bloom más fuerte (glow del neon), SunRays suave y color grade con más saturación y contraste. Todo esto se apaga en lite.
- `src/shared/PlanetModel.luau` y `src/client/PlanetField.luau`: la corteza tiene material por galaxia (Sandstone, Slate, Glacier, Basalt, Rock) y por tipo (Aurum Foil, Fury Basalt, Titan Slate, Gate DiamondPlate). El manto de Ember es CrackedLava. Además cada planeta tiene una variación de color (hue, saturación y brillo), así un campo de rocas ya no son todos clones.
- `src/server/World/WorldBuilder.luau`: la estación tiene rim DiamondPlate, casco y postes Metal, y PointLights (sin sombras) en las cápsulas, la refinería, el warp, las estaciones de sistema y los pilones del gate.
- `UI/Hud.luau`: los contadores ahora son pills oscuros con borde del color de la moneda y el ícono sobre un disco con gradiente.

**Cápsulas pagas (policy)**
- Las odds ya se mostraban con `Formulas.odds`, la misma función con la que tira el server (siempre suma 100%), y el server ya leía `PolicyService.ArePaidRandomItemsRestricted` (si falla, se asume restringido).
- `src/client/Purchase.luau`: antes de abrir el prompt de un ítem `random = true`, el cliente ahora pregunta al server (`CanBuy`).
- `UI/CapsulePanel.luau`: si el jugador está restringido, la Quantum Capsule (Robux) no muestra ningún botón de compra. Antes quedaba visible "Open 1".

## Cómo lo verifiqué

- `rojo build default.project.json`: OK (`test.project.json` también buildea).
- `luau-lsp analyze ... src`: 0 errores (igual que el baseline).
- `luau sim/check_config.luau`: `CONFIG OK`.
- `luau sim/economy_sim.luau`: corre, los tiempos no cambiaron (galaxia 6 en unas 5 h, rebirth6 en 6h30).
- `luau tests/locale_check.luau`: `LOCALE CHECKS PASSED` (504/504 claves, 12 idiomas).
- `luau tests/unit.luau`: `UNIT: 156 checks, 0 failures` (antes eran 137).

## Qué hay que mirar en Studio

1. **Performance con Future** en un celular o con Graphics bajo: son unas 36 PointLights en total, y las luces se streamean por zona. Si pesa, volver a `ShadowMap` en `default.project.json` (una línea).
2. **Materiales de los planetas**: fijarse que no queden muy oscuros o ruidosos (sobre todo Glacier en Frost y Foil en Aurum). La tabla está en `PlanetModel.ROCK_MATERIAL` y `KIND_MATERIAL`.
3. **Bloom**: que el neon no queme la imagen (threshold 1.35, intensidad 0.55 en `WorldFx.applyLighting`).
4. **Playtest sin API access**: el jugador tiene que entrar al toque, con el aviso de "no se guarda".
5. **Sonidos**: usan rutas `rbxasset://sounds/...`. Si alguna no existe, en Output aparece un warning, no un error.
6. **HUD**: los pills nuevos en PC y en touch (`ForceTouchLayout`).
7. Correr el playtest automático que ya existe (`test.project.json`, `tests/AutoTest*.luau`). Yo no lo pude correr.

## Pendiente

- Subir los íconos (`tools/icons/upload_assets.py` en la raíz). Cuando `Shared/Icons.luau` tenga ids, el HUD los usa solo. Los chips de auto, los toasts y los botones con texto+emoji siguen con emoji: son strings armados, y pasarlos a imagen es otro laburo.
- Los ids de game passes y productos siguen en 0 ("coming soon").
- Chequear que el nombre "Planet Crackers" esté libre en Roblox.
