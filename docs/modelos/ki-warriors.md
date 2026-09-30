# Modelos 3D para Ki Warriors

Podés reemplazar los props armados con partes por modelos reales **sin tocar código**. Si no hay archivo para una ranura, el juego usa el prop primitivo de siempre. Con la carpeta vacía el mundo queda idéntico a hoy (mismo layout, mismas partes).

Todo el mundo de Ki Warriors se construye en el **server** (el cliente solo anima las partes marcadas), así que la biblioteca vive en `ServerStorage.ModelLibrary` (Rojo la arma desde `ki-warriors/assets/models/`) y no se replica a los jugadores. No hay props del cliente que la usen.

## Paso a paso

1. Studio > Toolbox (Creator Store) > Modelos > buscar > insertar.
2. **Revisar que no tenga scripts** (el juego igual los borra y avisa en Output, pero mejor no traerlos). Sacá también sonidos, luces y partículas raras.
3. Que sea **un solo objeto raíz**: un `Model` o una `MeshPart` (no una Folder). El pivot y la orientación dan igual, el juego lo escala y lo apoya solo. Si tiene frente, que mire hacia adelante (-Z).
4. Click derecho > **Save to File** > `.rbxm`.
5. Guardarlo en `ki-warriors/assets/models/<ranura>.rbxm` con el nombre exacto de la tabla (minúsculas, sin espacios).
6. Desde `ki-warriors/`: `rojo build default.project.json -o KiWarriors.rbxlx` (o `rojo serve`) y abrirlo en Studio.
7. **Variantes**: `tree.rbxm`, `tree_1.rbxm`, `tree_2.rbxm`... El juego elige una según la posición (siempre la misma en el mismo lugar), así un bosque no sale todo igual. Con solo `tree_1.rbxm` y `tree_2.rbxm` (sin `tree.rbxm`) también anda.

**Licencia:** usá solo modelos que tengas permiso de usar (los gratis del Creator Store sirven para experiencias). Evitá cualquier cosa con marcas registradas o personajes de terceros (Dragon Ball incluido: el juego es "inspirado", los modelos tienen que ser genéricos).

## Reglas que aplica el juego

- Se escala **parejo** (sin deformar) hasta que entra en el tamaño objetivo, y la base del modelo queda donde estaba la base del prop primitivo.
- Todo queda anclado. Colisión igual que el primitivo: rocas, torres, tótems y monolito **sí** colisionan; árboles, arbustos, cactus, islas, estatuas y el resto **no** (sin collide, sin touch, sin query).
- Se borran todos los `Script` / `LocalScript` / `ModuleScript` del modelo (y se avisa en Output).
- **Límite de partes** por modelo (tabla). Si se pasa, o si no queda presupuesto en el mundo (`Config.Budget.worldParts`), **se ignora** y se usa el primitivo, con un warning en Output. Las ranuras que se repiten mucho (árbol, roca, arbusto, tótem) tienen que ser livianas: hay ~60 props sueltos por planeta y 10 planetas.
- Los colores del modelo **no** se tiñen con el tema del planeta (los primitivos sí). Si querés que el planeta 3 se vea distinto, usá variantes o ranuras por tema (abajo).
- Los modelos no tienen animación: donde el primitivo flotaba o giraba (cristal de la plaza, islas) el modelo queda quieto.
- Si reemplazás un modelo grande, conviene probar en Studio con Streaming: los mapas con StreamingEnabled descargan por distancia.

## Ranuras

Tamaño objetivo = caja donde entra el modelo (ancho, alto, fondo), en studs. `s` es un factor aleatorio por prop entre 0.85 y 1.5 (los árboles sueltos varían de tamaño), así que el tamaño real cambia de un árbol a otro.

| Archivo | Qué es | Dónde aparece | Tamaño objetivo | Qué buscar (Creator Store) | Partes máx. |
|---|---|---|---|---|---|
| `tree.rbxm` | Árbol (temas "tree": Verdia) | Props sueltos de los planetas con tema árbol, terrazas, islas flotantes | 9s x 15.5s x 9s (~10 x 17 x 10) | `low poly tree`, `stylized tree` | 40 |
| `pine.rbxm` | Pino (temas "pine") | Props sueltos de planetas con pinos | 8.4s x 11.2s x 8.4s | `low poly pine tree`, `snowy pine` | 40 |
| `cactus.rbxm` | Cactus (desierto) | Props sueltos de Brask | 6.6s x 9.8s x 6.6s | `low poly cactus`, `stylized cactus` | 40 |
| `rock.rbxm` | Roca (colisiona) | Sueltas, orillas de lagos, campamentos | 6s x 4s x 5s | `low poly rock`, `stylized boulder` | 25 |
| `bush.rbxm` | Arbusto | Sotobosque de todos los planetas (~23 por planeta) | 4.4s x 3s x 3.6s | `low poly bush`, `stylized shrub` | 25 |
| `tower.rbxm` | Torre / farol roto (colisiona) | Planetas de ciudad (temas "tower") | 5s x (10..22)s x 5s | `ruined tower`, `sci-fi pillar`, `broken skyscraper low poly` | 60 |
| `totem.rbxm` | Tótem de campamento enemigo (colisiona) | 5 por campamento, 2 campamentos por planeta | 3 x 11.8 x 3 | `tribal totem`, `war banner pole`, `low poly totem` | 40 |
| `ki_crystal.rbxm` | Cristal de ki flotante de la plaza | Monumento de cada plaza (centro, ~8 a 21 studs de altura) | 7 x 13 x 7 | `floating crystal`, `glowing crystal low poly` (Neon ayuda) | 100 |
| `warp_gate.rbxm` | Anillo del portal de viaje | Plaza de cada planeta (el disco del portal y el prompt se mantienen; el anillo mira hacia +X) | 17.4 x 17.4 x 3.6 | `stargate ring`, `sci-fi portal frame`, `stone arch portal` | 150 |
| `floating_island.rbxm` | Roca flotante | 4 por planeta, a gran altura (la tapa caminable sigue siendo primitiva) | 60 x 24 x 60 | `floating island low poly`, `sky island rock` | 150 |
| `boss_statue.rbxm` | Estatua del jefe del planeta (nuevo: hoy no hay nada ahí) | Detrás del arena de cada jefe, mirando a la entrada | 14 x 22 x 14 | `demon statue`, `stone titan statue`, `dark lord statue low poly` | 300 |
| `master.rbxm` | El Maestro (NPC de misiones, reemplaza la figura; quedan la base y la etiqueta) | Plaza del planeta 1 | 7 x 9 x 4 | `old master monk`, `kung fu master statue`, `wise old man stylized` | 150 |
| `altar_monolith.rbxm` | Monolito del Altar de Deseos (colisiona; la estrella queda al frente) | Planeta 1 | 7 x 22 x 3 | `ancient monolith`, `rune stone`, `sci-fi obelisk` | 100 |
| `landmark.rbxm` | Hito gigante genérico, más allá del borde del planeta (colisiona) | Uno por planeta, a 150 studs del borde | Según tema (tabla de abajo) | `giant tree`, `volcano`, `ice mountain`, `space tower`, según el planeta | 300 |

### Ranuras por tema y por jefe (opcionales, pisan a la genérica)

- **Hitos por planeta**: `landmark_<tema>.rbxm` se usa en ese planeta; si no existe se prueba `landmark.rbxm`; si tampoco, el primitivo. Tamaños objetivo (ancho x alto x fondo):

| Archivo | Planeta | Hito primitivo | Tamaño objetivo |
|---|---|---|---|
| `landmark_meadow.rbxm` | Verdia | Árbol del mundo | 170 x 290 x 150 |
| `landmark_desert.rbxm` | Brask | Fortaleza de la Legión | 200 x 330 x 200 |
| `landmark_volcano.rbxm` | Kaldera | Volcán | 300 x 290 x 300 |
| `landmark_wasteland.rbxm` | Mesa | Mesetas y cápsulas estrelladas | 300 x 250 x 300 |
| `landmark_ice.rbxm` | Frostreach | Cristales de hielo | 190 x 270 x 190 |
| `landmark_ruins.rbxm` | Nullcity | Skyline muerto | 330 x 350 x 330 |
| `landmark_candy.rbxm` | Bubble | Castillo de torta | 270 x 310 x 270 |
| `landmark_storm.rbxm` | Zephyra | Torre de tormenta | 80 x 300 x 80 |
| `landmark_future.rbxm` | Tomorrow | Torre de reloj rota | 120 x 250 x 80 |
| `landmark_void.rbxm` | Rift | Luna rota (flota a 176 studs) | 290 x 150 x 290 |

  Son modelos enormes y de una sola pieza por planeta: buscá `giant`, `landmark`, `environment`, y mantené el límite de 300 partes.
- **Estatua de jefe específica**: `boss_<id>.rbxm` pisa a `boss_statue.rbxm` en ese jefe. Ids: `bramble_king` (Verdia), `marshal_krome` (Brask), `forge_tyrant` (Kaldera), `prince_vael` (Mesa), `rime_empress` (Frostreach), `chimera_prime` (Nullcity), `glutt` (Bubble), `tempest_warden` (Zephyra), `arbiter_null` (Tomorrow), `hollow_star` (Rift). Mismo tamaño objetivo y límite que `boss_statue`.

## Fuera de alcance / no tocado

- Los personajes (skins, auras, capas) y los enemigos normales: se dibujan en el cliente y no usan esta biblioteca.
- El Coliseo, las zonas de entrenamiento, el suelo, las montañas del borde y los lagos siguen primitivos (son geometría de juego y de composición del mapa).
- Los colores y brillos Neon de los primitivos (luces, anillos orbitantes, banderas animadas) se mantienen: decoran alrededor del modelo.

## Verificar

- Compilar: `rojo build default.project.json -o KiWarriors.rbxlx` (hay que compilar también `test.project.json` y las variantes `showcase*.project.json`, todas mapean la carpeta).
- En Studio, Output: `[ModelSlots] ... tiene N partes (tope M)` = el modelo se pasó y se usa el primitivo; `... traia N script(s): eliminados` = limpieza de seguridad.
- El atributo `World` > `PartCount` cuenta también las partes de los modelos.
