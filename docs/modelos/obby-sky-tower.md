# Modelos 3D para Sky Tower Obby

Podés reemplazar los props armados con partes por modelos reales **sin tocar código**. Si no hay archivo para una ranura, el juego usa el prop primitivo de siempre (con la carpeta vacía todo queda idéntico a hoy).

Los props de este juego se construyen todos en el **server**, así que la biblioteca vive en `ServerStorage.ModelLibrary` (Rojo la arma desde `obby-sky-tower/assets/models/`). No hay props del cliente que usen la biblioteca.

## Paso a paso

1. En Studio: Toolbox > Creator Store > buscar el modelo > insertar.
2. **Revisar que no tenga scripts** (el juego igual los borra y avisa en Output, pero mejor no traerlos). Sacar también sonidos, luces y partículas raras.
3. Que sea **un solo Model** (o una MeshPart). Pivot/orientación da igual: el juego lo escala y lo apoya solo. Que "mire" hacia adelante (-Z) si tiene frente.
4. Click derecho > Save to File (.rbxm).
5. Guardarlo en `obby-sky-tower/assets/models/<ranura>.rbxm` con el nombre exacto de la tabla.
6. `rojo build default.project.json -o SkyTowerObby.rbxlx` (o `rojo serve`).
7. Variantes: `tree.rbxm`, `tree_1.rbxm`, `tree_2.rbxm`... El juego elige una según la posición (siempre la misma en el mismo lugar), así no sale todo igual.

**Licencia:** usá solo modelos que tengas permiso de usar (los gratis del Creator Store sirven para experiencias). Evitá cualquier cosa con marcas registradas o personajes de terceros.

## Reglas que aplica el juego

- Se escala **parejo** (sin deformar) para entrar en el tamaño objetivo, y se apoya con la base donde estaba la base del prop primitivo.
- Todo queda anclado, sin colisión, sin touch, sin query y sin sombras (igual que el resto del decorado). Ninguna ranura de este juego es transitable, así que nunca se activa colisión.
- Se borran todos los Script / LocalScript / ModuleScript del modelo.
- Límite de partes: cada ranura tiene su tope (tabla). Si el modelo se pasa, **se ignora** y se usa el primitivo (warning en Output). Además hay un tope total de 2000 partes de modelos por servidor (el presupuesto de decorado es 4200). Las ranuras que se repiten mucho (árbol, roca, nube) tienen que ser muy livianas.
- Los colores del modelo **no** se tiñen con el "mood" de cada torre (los primitivos sí). Si la torre 5 tiene que verse distinta, usá variantes.

## Ranuras

Tamaño objetivo = caja donde entra el modelo. `r` es el radio del prop, entre 8 y 15 studs según la pieza.

| Archivo | Qué es | Dónde aparece | Tamaño objetivo aprox. (studs) | Qué buscar en el Creator Store | Partes máx. |
|---|---|---|---|---|---|
| `island.rbxm` | Isla flotante (disco arriba, roca que se afina abajo). La apoya con la **cara de arriba a la altura del piso**, así que los props encima siguen bien. | Todos los mundos, sets exteriores de cada torre | 16-30 de ancho, 14-24 de alto | "floating island low poly", "sky island stylized" | 120 |
| `tree.rbxm` | Árbol de hojas redondas | Islas del mundo 1 (Grassy Hills) | 3-8 de ancho, 5-14 de alto | "low poly tree", "stylized cartoon tree" | 60 |
| `pine.rbxm` | Pino nevado | Islas del mundo 3 (Frozen Peaks) | 3-8 de ancho, 4-12 de alto | "low poly pine tree snow", "stylized snowy pine" | 60 |
| `windmill.rbxm` | Molino con aspas | 1 de cada 3 islas del mundo 1 | 15-28 de ancho y de fondo, 17-31 de alto | "low poly windmill", "cartoon windmill" | 300 |
| `cupcake.rbxm` | Cupcake gigante | 1 de cada 3 sets del mundo 2 (Candy Land) | 15-28 de ancho, 20-37 de alto | "cupcake low poly", "candy land cupcake stylized" | 300 |
| `snowman.rbxm` | Muñeco de nieve | Islas nevadas del mundo 3 | 2-5 de ancho, 5-9 de alto | "low poly snowman", "cartoon snowman" (sin marcas) | 100 |
| `pyramid.rbxm` | Pirámide escalonada con punta | 1 de cada 3 sets del mundo 4 (Desert Ruins) | 14-25 de ancho, 18-33 de alto | "stylized pyramid", "low poly desert ruins pyramid" | 300 |
| `cloud.rbxm` | Nube del mar de nubes bajo el lobby | Lobby, 26 nubes | 50-95 x 16-30 x 40-76 | "low poly cloud", "stylized fluffy cloud" (blanca, sin luces) | 40 |
| `rock.rbxm` | Roca en el borde del lobby | Lobby, ~24 a lo largo del borde | 6.5-13 x 4-8 x 5-10 | "low poly rock", "stylized boulder" (gris) | 50 |
| `bush.rbxm` | Arbusto en el borde del lobby | Lobby, ~20 a lo largo del borde | 6.5-13 x 4-8 x 5-10 | "low poly bush", "stylized shrub" (verde) | 50 |
| `lamp_post.rbxm` | Farol del camino al tower | Lobby, 6 faroles | 1.6 x 10.9 x 1.6 | "low poly street lamp", "fantasy lamp post" | 60 |
| `balloon.rbxm` | Globo aerostático (flota en el lobby; el bamboleo se mantiene) | Lobby, 2 globos | 26 x 36 x 26 | "hot air balloon low poly", "cartoon hot air balloon" | 300 |
| `trophy.rbxm` | Copa dorada gigante | Sala de la cumbre, 2 copas junto al cartel WINNER | 12 x 17 x 9 | "golden trophy cup low poly", "stylized gold cup" | 300 |
| `portal_frame.rbxm` | Marco del portal (pilares + dintel). El disco brillante, la luz, las chispas y el cartel siguen en código. | Portal de la cumbre, portal de vuelta al lobby | 13 x 14 x 2.4 | "stone portal arch", "magic gate low poly" | 300 |

Notas por ranura:

- `island`, `tree`, `pine`, `snowman`, `windmill`, `cupcake`, `pyramid`: en cada torre hay muchas piezas (la torre 1 completa y las demás más livianas), así que pensalas livianas. Con 30-60 partes por isla ya se llena el tope total.
- `cloud`: blanca o casi blanca. Si tiene transparencia propia, se respeta (las nubes primitivas tienen 0.08).
- `portal_frame`: las columnas primitivas eran sólidas; las del modelo **no colisionan** (así nunca estorban la entrada). Dejá el hueco del medio libre: ahí va el disco de entrada.
- `lamp_post`: el modelo reemplaza también la luz del farol (de noche/de día no se nota mucho, y queda una luz menos en el presupuesto).
- `balloon`: si el archivo es una MeshPart sola (no Model), no flota; usá un Model.
- **No** hay ranuras para plataformas, saltos ni obstáculos: el layout y los tests dependen de esa geometría exacta, sigue siendo primitiva.

## Estilo para que el juego quede coherente

- Low-poly / estilizado, colores saturados y limpios (el juego es colorido tipo cartoon). Nada realista ni oscuro.
- Mismo nivel de detalle entre props: si la isla es muy detallada y el árbol es un cubo, desentona.
- Sin texturas gigantes ni decals con texto. Sin partículas, luces ni sonidos adentro.
- Preferir modelos con pocas partes y MeshParts simples antes que modelos de 300 partes sueltas.
