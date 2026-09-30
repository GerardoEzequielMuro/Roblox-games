# Modelos 3D para ruleta-pvp (Spin Showdown)

Podés reemplazar las piezas primitivas del lobby por modelos reales sin tocar código. Si la carpeta `ruleta-pvp/assets/models/` está vacía (solo el README), el juego se arma como siempre.

## Qué NO es una ranura
La ruleta, las 6 mesas (escenario `TableRoot`, tambor, podios, pantallas, carteles), el Power Core y los rankings son gameplay: el cliente los espera por tag y por nombre. Las ranuras solo decoran alrededor. Las ruedas las arma cada cliente, así que no hay ranuras del lado cliente: todo sale del servidor (`ServerStorage.ModelLibrary`).

## Ranuras

Todos los modelos se escalan para entrar en el tamaño objetivo (proporciones intactas, el más ajustado manda) y se apoyan con la base en el piso. Límite por ranura: 300 partes; tope total de todos los modelos juntos: 1000 partes (si se pasa, esa ranura usa la primitiva y avisa en el Output).

| Archivo | Qué es | Dónde aparece | Tamaño objetivo (studs, X/Y/Z) | Qué buscar en el Creator Store | Partes máx. |
|---|---|---|---|---|---|
| `pylon.rbxm` | Pilón tech | Alrededor de las mesas de tema neón (6 por mesa) | 3 x 10-16 x 3 | `sci-fi pylon`, `neon pillar`, `tech tower low poly` | 300 |
| `vat.rbxm` | Tanque de slime | Alrededor de las mesas de tema slime (6 por mesa) | 5.4 x 10.5 x 5.4 | `lab tank`, `glass vat`, `chemical tank stylized` | 300 |
| `crystal.rbxm` | Cristal grande | Alrededor de las mesas de tema arcano (6 por mesa) | 4.5 x 12 x 4.5 | `magic crystal`, `purple crystal low poly`, `rune crystal` | 300 |
| `lamp_post.rbxm` | Farol (sin la bola de luz, esa queda) | A los costados de los 6 caminos a las mesas (12) | 2.4 x 12 x 2.4 | `street lamp post`, `sci-fi lamp post`, `neon lamp` | 300 |
| `arch_pillar.rbxm` | Pilar de la entrada de cada mesa | Dos por mesa, a los lados del cartel (12) | 3 x 13 x 3 | `arch pillar`, `sci-fi gate column`, `stone pillar stylized` | 300 |
| `planet.rbxm` | Planeta lejano (ya con anillo si quiere) | Cielo: 4 planetas (tamaño 70 a 150) | caja cúbica de 70-150 (se calcula sola) | `planet low poly`, `ringed planet`, `stylized moon` | 300 |
| `statue.rbxm` | Estatua (opcional, no hay primitiva) | 6 en el plaza, a 40 studs del centro, mirando al core | 7 x 13 x 7 | `hero statue low poly`, `robot statue`, `trophy statue stylized` | 300 |
| `planter.rbxm` | Maceta / planta (opcional) | 12 en el plaza, a 44 studs del centro | 6 x 7 x 6 | `planter low poly`, `stylized bush`, `sci-fi plant pot` | 300 |
| `bench.rbxm` | Banco (opcional) | 12 alrededor del plaza, a 52 studs, mirando al centro | 7 x 3.5 x 3 | `bench low poly`, `sci-fi bench`, `park bench stylized` | 300 |
| `floating_rock.rbxm` | Roca flotante (opcional) | 8 lejos de la isla, solo paisaje | 46 x 34 x 46 | `floating island low poly`, `floating rock`, `asteroid stylized` | 300 |

Las ranuras marcadas "opcional, no hay primitiva" solo aparecen si el archivo existe.

### Variantes
Con sufijo numérico: `pylon.rbxm`, `pylon_1.rbxm`, `pylon_2.rbxm`... El juego elige una según la posición (siempre la misma para el mismo lugar, vecinos distintos), así no queda todo idéntico.

### Colisión
Se mantiene igual que la primitiva: pilones, tanques, cristales, faroles, pilares, estatuas, macetas y bancos son sólidos; planetas y rocas flotantes no. Todo se ancla solo.

## Estilo para que quede coherente
- Low-poly / estilizado, nada fotorrealista ni con texturas pesadas.
- Paleta del juego: azul noche y violeta de base con acentos neón (cian `#00E1FF`, magenta `#FF46CD`, verde lima, dorado). Preferí modelos oscuros o metálicos que dejen brillar los neones que ya hay.
- Evitá modelos que parezcan de casino o con logos/marcas.
- Bajas partes: mejor 1 a 30 MeshParts que 300 partes chicas (el tope de partes del mapa es ajustado).

## Paso a paso
1. En Studio: Toolbox > buscar el modelo (términos de arriba) > insertarlo al Workspace.
2. Revisar que no tenga scripts (Explorer, buscar `Script`). Igual el juego los borra al clonar y avisa en el Output, pero mejor limpiarlo a mano.
3. Que sea un solo Model (o MeshPart) parado derecho, con la base hacia abajo. Nombre libre: el nombre lo define el archivo.
4. Click derecho en el modelo > Save to File... > formato `.rbxm`.
5. Guardarlo como `ruleta-pvp/assets/models/<ranura>.rbxm` (ej. `pylon.rbxm`, `statue.rbxm`).
6. `cd ruleta-pvp && rojo build default.project.json -o SpinShowdown.rbxlx` (o `rojo serve`) y probar en Studio.
7. Si algo sale mal, borrar el archivo: vuelve la versión primitiva.

## Licencia
Usá solo modelos que tengas permiso de usar. Los modelos gratis del Creator Store se pueden usar en experiencias, pero revisá el autor y evitá cualquier cosa con marcas registradas o personajes de terceros. Los modelos generados con la IA 3D de Studio también sirven.
