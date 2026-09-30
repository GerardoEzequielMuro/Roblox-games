# Modelos 3D: Planet Crackers (anime-planet-clicker)

Dejás archivos `.rbxm` en `anime-planet-clicker/assets/models/` y el mundo los usa en lugar de las partes primitivas. Sin archivos, el juego se ve igual que hoy. El mundo se arma en el servidor, así que la biblioteca vive en `ServerStorage.ModelLibrary` (no hace falta ReplicatedStorage; los planetas y el cielo que dibuja el cliente no tienen ranuras).

## Ranuras

Tamaño objetivo = caja donde entra el modelo (se escala manteniendo proporciones y se apoya en el piso). Todos los modelos quedan anclados y **con colisión** (igual que la versión primitiva). Límite: 300 partes por modelo, 1200 en total entre todos los modelos del mundo.

| Archivo | Qué es | Dónde aparece | Tamaño objetivo (studs, ancho x alto x fondo) | Buscar en el Creator Store | Partes |
|---|---|---|---|---|---|
| `capsule_machine.rbxm` | Máquina de cápsulas (gacha) | Plaza de cada galaxia, 1 por cápsula | 10 x 17 x 10 | `gacha machine`, `capsule machine low poly`, `vending capsule toy` | <= 300 |
| `refinery_building.rbxm` | Edificio refinería / tolva | Junto al pad de refinería de cada galaxia | 14 x 15 x 8 | `factory building low poly`, `sci-fi refinery`, `smelter` | <= 300 |
| `workshop_stall.rbxm` | Puesto/taller de mejoras con toldo | Plaza de cada galaxia | 10 x 9.5 x 6 | `market stall`, `blacksmith shop`, `workshop stall stylized` | <= 300 |
| `warp_gate.rbxm` | Arco/portal de teletransporte (sin el disco del piso) | Pad de warp de cada galaxia y de la arena | 15 x 14 x 2.6 | `portal arch`, `sci-fi gate`, `teleporter frame` | <= 300 |
| `system_monument.rbxm` | Monumento/reliquia del sistema | Estaciones de sistema (galaxias 2 a 6) | 7 x 10 x 7 | `crystal monument`, `sci-fi relic`, `floating crystal pedestal` | <= 300 |
| `gate_pylon.rbxm` | Pilar alto del portón a la siguiente galaxia (2 por galaxia) | Portón de cada galaxia menos la última | 5.6 x 52 x 5.6 | `sci-fi pylon`, `tall tower pillar`, `energy pillar` | <= 300 |
| `arena_pylon.rbxm` | Poste de peligro | 16 alrededor de la Meteor Arena | 2.6 x 10 x 2.6 | `hazard pylon`, `warning post`, `light tower` | <= 100 |
| `arena_cover.rbxm` | Cobertura (muro bajo) | 4 dentro de la arena | 10 x 7 x 3 | `barricade`, `sci-fi cover wall`, `concrete barrier` | <= 100 |
| `rock_spire.rbxm` | Roca / espira | Decoración de galaxias con estilo "rocks" | ~5 x 4-9 x 5 (varía por instancia) | `low poly rock`, `stone spire`, `boulder stylized` | <= 100 |
| `mushroom.rbxm` | Hongo gigante | Galaxias con estilo "mushrooms" | ~5 x 5-9 x 5 | `giant mushroom low poly`, `fantasy mushroom` | <= 100 |
| `ice_crystal.rbxm` | Cristal / pinchos de hielo | Galaxias con estilo "ice" | ~5 x 4-8 x 4 | `ice crystal`, `ice spikes low poly`, `frozen crystal` | <= 100 |
| `lava_vent.rbxm` | Chimenea de lava / volcán chico | Galaxias con estilo "vents" | ~5 x 3 x 5 | `lava vent`, `mini volcano low poly`, `magma rock` | <= 100 |
| `tesla_coil.rbxm` | Bobina Tesla | Galaxias con estilo "coils" | ~4 x 8-12 x 4 | `tesla coil`, `energy tower`, `sci-fi antenna` | <= 100 |
| `obelisk.rbxm` | Obelisco | Galaxias con estilo "obelisks" | ~3 x 10-15 x 3 | `obelisk`, `ancient monolith`, `rune stone` | <= 100 |

Variantes: `rock_spire_1.rbxm`, `rock_spire_2.rbxm`, etc. (hasta 12). Las props de decoración eligen variante según la posición; las demás también, pero como hay pocas se nota menos.

Notas por ranura:
- Las props (`rock_spire` ... `obelisk`) pierden las animaciones (flotar, girar, brillo) al ser reemplazadas; los prompts, carteles y luces de las estaciones se mantienen (quedan en partes invisibles).
- El modelo debería tener el "frente" mirando a +Z y el suelo en su base; se apoya por la base de su caja.
- `warp_gate`: el disco que se pisa para teletransportarse NO se reemplaza (es lo que usa el gameplay); el modelo es solo el arco.

## Estilo para que quede coherente

Low-poly / estilizado, colores saturados y limpios, sin texturas fotorrealistas. Temática espacial/cartoon (naves, cristales, neón). Evitá modelos con muchas partes chicas: se cuentan contra el presupuesto.

## Paso a paso

1. En Studio: Toolbox > buscá el modelo (términos de la tabla) > insertalo en el Workspace.
2. Revisá que no tenga scripts (Explorer: buscá `Script`, `LocalScript`, `ModuleScript`). Si tiene, borralos (igual el juego los borra al cargar, pero mejor limpio).
3. Mirá la cantidad de partes (Explorer o `#model:GetDescendants()`): respetá el límite de la tabla.
4. Click derecho en el modelo > Save to File... > guardá como `.rbxm`.
5. Renombrá el archivo con el nombre exacto de la ranura (ej. `obelisk.rbxm`, `obelisk_1.rbxm`) y ponelo en `anime-planet-clicker/assets/models/`.
6. `rojo build default.project.json -o PlanetCrackers.rbxlx` (o `rojo serve`) y abrí en Studio. Si falta algo, mirá el Output: hay `[ModelSlots]` warns cuando se descarta un modelo.

## Licencia

Usá solo modelos que puedas usar: los modelos gratis del Creator Store se pueden usar en experiencias de Roblox, pero revisá el autor/licencia. Evitá cualquier cosa con marcas registradas (logos, personajes de anime o de otras marcas). No uses IDs de assets inventados.
