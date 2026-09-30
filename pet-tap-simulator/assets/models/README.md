# Modelos 3D (ranuras)

Acá van los modelos `.rbxm` / `.rbxmx` que reemplazan las props armadas con partes primitivas. Sin código: copiás el archivo con el nombre exacto de la ranura y hacés `rojo build`. Si falta un archivo, el juego usa la versión primitiva de siempre.

Guía completa (tabla de ranuras, qué buscar en el Creator Store, tamaños): `docs/modelos/pet-tap-simulator.md`.

## Flujo

1. Toolbox (o Creator Store) > buscar el modelo > insertar en Studio.
2. Revisar que NO tenga scripts (igual el juego los borra al clonar, pero mejor limpio).
3. Click derecho en el modelo > Save to File... > guardar como `<ranura>.rbxm` en esta carpeta (ej. `tree.rbxm`).
4. Variantes: `tree_1.rbxm`, `tree_2.rbxm`... (hasta `_16`). Se eligen según la posición.
5. `rojo build default.project.json -o TapPetsSimulator.rbxlx` y abrir en Studio.

El modelo se escala solo al tamaño de la ranura (manteniendo proporciones) y se apoya en el piso. El nombre del archivo (sin extensión) tiene que ser igual al de la ranura.

Usá solo modelos que tengas permitido usar (los gratis del Creator Store sirven en experiencias); evitá cualquier cosa con marcas registradas.
