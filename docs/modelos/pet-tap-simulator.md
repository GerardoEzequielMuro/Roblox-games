# Modelos 3D para Pet Tap Simulator

Cómo reemplazar las props hechas con partes primitivas por modelos reales, sin tocar código. Si una ranura no tiene archivo, el juego usa la versión primitiva de siempre.

## Ranuras

Carpeta: `pet-tap-simulator/assets/models/`. El nombre del archivo (sin extensión) es el nombre exacto de la ranura. Variantes: `tree_1.rbxm`, `tree_2.rbxm`... (hasta `_16`), elegidas por posición, así un bosque no queda todo igual. El modelo se escala solo para entrar en el tamaño objetivo (proporciones intactas) y se apoya en el piso. Orientación: el frente del modelo tiene que mirar a -Z (lo normal en Studio).

Límite de partes: 300 por modelo (si se pasa, se usa el primitivo y avisa en Output) y 1500 en total en todo el mundo.

| Archivo | Qué es | Dónde aparece | Tamaño objetivo (studs, ancho x alto x fondo) | Qué buscar en el Creator Store | Colisión |
|---|---|---|---|---|---|
| `tree.rbxm` | Árbol redondo | Zona 1 Meadow, unos 24 | 14 x 16 x 14 | `low poly tree`, `stylized cartoon tree` | sí |
| `pine.rbxm` | Pino nevado | Zona 3 Frost, unos 24 | 12 x 16 x 12 | `low poly pine tree snow`, `snowy pine` | sí |
| `rock.rbxm` | Roca | Meadow (9) y orillas del estanque | 5 x 3.5 x 5 | `low poly rock`, `stylized boulder` | sí |
| `bush.rbxm` | Arbusto | Meadow, unos 14 | 6 x 4 x 6 | `low poly bush`, `cartoon bush` | no |
| `mushroom.rbxm` | Hongo rojo | Meadow, unos 12 | 5 x 5 x 5 | `cartoon mushroom`, `low poly mushroom` | no |
| `lollipop.rbxm` | Chupetín gigante | Zona 2 Candy | 7 x 13 x 7 | `lollipop candy low poly`, `giant lollipop` | sí |
| `cupcake.rbxm` | Cupcake | Zona 2 Candy | 7 x 7 x 7 | `cupcake stylized`, `cartoon cupcake` | sí |
| `crystal.rbxm` | Cristal de hielo | Zona 3 Frost, unos 12 (los de lava/cosmic siguen primitivos) | 4 x 8 x 4 | `ice crystal low poly`, `crystal cluster` | sí |
| `snowman.rbxm` | Muñeco de nieve | Zona 3 Frost, 6 | 5 x 9 x 5 | `low poly snowman`, `cartoon snowman` | sí |
| `windmill.rbxm` | Molino (landmark) | Zona 1, esquina izquierda | 26 x 34 x 26 | `low poly windmill`, `stylized farm windmill` | sí |
| `igloo.rbxm` | Iglú (landmark) | Zona 3 | 28 x 16 x 28 | `igloo low poly`, `snow igloo` | sí |
| `cake.rbxm` | Torta de 3 pisos (landmark) | Zona 2 | 28 x 24 x 28 | `layered cake stylized`, `giant cake` | sí |
| `volcano.rbxm` | Volcán (landmark) | Zona 4 Lava | 36 x 34 x 36 | `low poly volcano`, `stylized volcano` | sí |
| `rocket.rbxm` | Cohete en su plataforma (landmark) | Zona 5 Cosmic | 22 x 34 x 22 | `cartoon rocket`, `low poly rocket ship` | sí |

Cosas que NO son ranuras a propósito: los huevos (el cliente gira la cáscara y el prompt depende de esas partes), el portal y el OVNI (los anima el cliente), las plataformas del spawn y las paredes (geometría de juego).

Notas: el molino y el volcán se reemplazan enteros; el molino pierde el giro de las aspas (el cliente solo anima las piezas del modelo primitivo). Las sombras en tiempo real de los modelos quedan apagadas (presupuesto del mundo: máximo 160 casters), y nada es "touchable".

## Estilo (para que el juego quede coherente)

- Low-poly / estilizado tipo dibujito, colores saturados y pastel: verdes vivos, caramelos rosa/celeste/amarillo, hielo celeste, lava naranja.
- Nada realista ni muy detallado; mejor pocas partes (20 a 100). Mesh con textura chica está bien.
- Que cada variante (`tree_1`, `tree_2`) mantenga el mismo estilo y paleta que la base.

## Paso a paso

1. En Studio: Toolbox (Creator Store) > buscar el término > insertar el modelo.
2. Revisar que no tenga scripts (Explorer: buscar `Script`). Borrarlos. Igual el juego borra todo Script/LocalScript/ModuleScript del clon y avisa en Output, pero mejor no confiar en eso.
3. Click derecho en el modelo > Save to File... > guardar como `.rbxm`.
4. Guardar en `pet-tap-simulator/assets/models/<ranura>.rbxm` (ej. `tree.rbxm`).
5. `rojo build default.project.json -o TapPetsSimulator.rbxlx` (o `rojo serve`) y abrir en Studio.
6. Revisar en Studio: que apoye en el piso, que escale bien y que el Output no diga `[ModelSlots] ... skipped`.

## Licencia

Usá solo modelos que tengas permitido usar: los gratis del Creator Store sirven en experiencias; los de IA de Studio también. Evitá todo lo que tenga marcas registradas o personajes de terceros.

## Dónde se arma (técnico)

- Las props se arman en el servidor, así que la biblioteca vive en `ServerStorage.ModelLibrary` (los `*.project.json` la mapean a `assets/models`). No hace falta replicarla al cliente.
- Módulos: `src/server/World/ModelSlots.luau` (spawn) y `ModelSlotsMath.luau` (escala, variantes, presupuesto; test en `tests/model_slots.luau`).
