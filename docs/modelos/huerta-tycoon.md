# Modelos 3D para Huerta Tycoon

El mapa se arma con piezas primitivas desde código. Con este sistema podés reemplazar los props más visibles por modelos reales (Creator Store / Toolbox / generador 3D de Studio) sin tocar código. Si una ranura no tiene archivo, se usa la versión primitiva de siempre.

## Paso a paso

1. En Studio abrí la Toolbox (Creator Store), buscá el modelo e insertalo.
2. Revisá que no tenga scripts (Explorer: buscá Script, LocalScript, ModuleScript) y borralos. Igual el juego los borra al clonar y avisa en Output, pero mejor no confiar.
3. Click derecho sobre el modelo > Save to File... > formato `.rbxm`.
4. Guardalo en `huerta-tycoon/assets/models/<ranura>.rbxm` con el nombre exacto de la tabla.
5. `rojo build default.project.json -o huerta.rbxlx` (o `rojo serve`) y abrilo en Studio.

Variantes: `tree.rbxm`, `tree_1.rbxm`, `tree_2.rbxm`... (hasta 12). Se elige una por posición de forma determinística, así un bosque no queda todo igual. Si hay `tree_1` sin `tree`, funciona igual; si falta un número, se cortan ahí.

## Reglas que aplica el juego

- Escala uniforme para entrar en el tamaño objetivo (gana el eje más justo), apoya la base donde estaba la base del primitivo y ancla todo.
- El frente del modelo debe mirar a -Z (convención de Roblox: el frente es el "Front" del modelo). Si sale de espaldas, rotalo en Studio antes de guardar.
- Colisión igual que el primitivo: edificios, fuente, estatua, tractor, rocas, faroles y bancos son sólidos; árboles (solo un tronco invisible), arbustos, espantapájaros y globo no colisionan.
- Borra todo Script/LocalScript/ModuleScript del modelo (seguridad).
- Presupuesto: si el modelo pasa el límite de partes de su ranura (o el total de 6000 partes entre todos los modelos), se ignora y se usa el primitivo, con un warn en Output.
- Los modelos se ponen del lado servidor (`ServerStorage.ModelLibrary`). Este juego construye todo el mapa en el servidor, así que no hace falta la variante de cliente.
- Con modelo, se pierden los extras del primitivo: humo de la chimenea (granja), chorro de agua (fuente). El farol sí conserva su luz. El globo sigue flotando (tag `CK_Float`).

## Ranuras

Tamaños en studs (ancho x alto x profundo). Los árboles, arbustos y rocas se multiplican por su escala aleatoria (árboles 0.85 a 1.5, rocas 0.9 a 3).

| Archivo | Qué es | Dónde aparece | Tamaño objetivo | Qué buscar (Creator Store, en inglés) | Partes máx |
|---|---|---|---|---|---|
| `tree.rbxm` (`tree_1`...) | Árbol | Todo el mapa, decenas | 12 x 15 x 12 | `low poly tree`, `stylized tree`, `cartoon tree` | 80 |
| `bush.rbxm` | Arbusto | Mapa, bordes de parcelas, molino | 4.8 x 2.8 x 4.2 | `low poly bush`, `cartoon shrub` | 40 |
| `rock.rbxm` | Roca | Mapa, estanque | 2.4 x 1.65 x 2 | `low poly rock`, `stylized boulder` | 40 |
| `farmhouse.rbxm` | Casa de cada parcela (frente = puerta) | Detrás de cada parcela | 21 x 17.5 x 19.8 | `low poly farmhouse`, `cartoon cottage`, `stylized farm house` | 300 |
| `barn.rbxm` | Edificio del granero (sin silo ni corral, esos quedan) | Punto de interés granero | 26 x 21 x 23 | `low poly red barn`, `cartoon barn` | 300 |
| `fountain.rbxm` | Fuente de la plaza | Centro de la plaza | 28 x 14.5 x 28 | `low poly fountain`, `stone fountain stylized` | 300 |
| `carrot_statue.rbxm` | Estatua de la zanahoria con corona, mascota del reino | Plaza, lado oeste | 9 x 16 x 9 | `carrot statue`, `cartoon carrot`, `golden crown statue` | 300 |
| `tractor.rbxm` | Tractor (sin el remolque, queda) | Punto de interés tractor | 8.6 x 9.3 x 12 | `low poly tractor`, `cartoon farm tractor` | 300 |
| `lamp.rbxm` | Farol de la plaza | Plaza, anillo de faroles | 1.9 x 11 x 1.9 | `low poly street lamp`, `stylized lamp post` | 60 |
| `bench.rbxm` | Banco | Plaza | 6.4 x 3.4 x 2.1 | `low poly park bench`, `wooden bench stylized` | 60 |
| `scarecrow.rbxm` | Espantapájaros | Molino y parcelas | 5.4 x 7.7 x 1.8 | `low poly scarecrow`, `cartoon scarecrow` | 100 |
| `balloon.rbxm` | Globo aerostático flotante (incluye canasto; la base del canasto apoya donde estaba) | Cielo sobre las colinas, 3 | 30 x 41 x 30 | `low poly hot air balloon`, `cartoon balloon` | 150 |

No tienen ranura (siguen primitivos): molino (sus aspas giran por código), cultivos, parcelas, carteles, puestos de la plaza y todo lo jugable.

## Coherencia de estilo

Todo el juego es de colores saturados y formas redondeadas. Buscá modelos low-poly / cartoon, paleta cálida (verdes vivos, rojo granero, madera clara), sin texturas realistas ni fotogrametría, y que se lean bien de lejos. Probá un modelo por vez y mirá cómo queda al lado de los primitivos antes de cargar más. Conviene que los tres o cuatro árboles variantes compartan paleta.

## Licencia

Usá solo modelos que tengas permiso de usar: los modelos gratuitos del Creator Store se pueden usar en experiencias de Roblox, pero revisá el autor y evitá cualquier cosa con marcas registradas (logos, personajes, marcas de tractores o de bebidas). Si lo generás con IA de Studio, revisá el resultado igual.

## Solución de problemas

- No aparece: nombre exacto (minúsculas, sin espacios), extensión `.rbxm`, y rehacé el build. Mirá Output por `[ModelSlots]`.
- Sale de espaldas o de costado: rotá el modelo en Studio para que el frente mire a -Z y guardalo de nuevo.
- Sale chico o grande: la escala se calcula con la caja del modelo; si hay una parte suelta lejos (un plano de suelo, una luz), el modelo entero se achica. Borrala.
- Dice "using the primitive version": pasó el límite de partes; simplificalo o bajá el detalle.
