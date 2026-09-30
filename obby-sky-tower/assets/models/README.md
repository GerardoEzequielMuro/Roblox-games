# Modelos 3D (ranuras)

Acá van los modelos `.rbxm` / `.rbxmx` que reemplazan a los props armados con partes primitivas.
Rojo mapea esta carpeta a `ServerStorage.ModelLibrary`. Si no hay un archivo para una ranura, el juego usa el prop primitivo de siempre. No hay que tocar código.

- El nombre del archivo es el nombre de la ranura: `tree.rbxm`, `island.rbxm`, `cloud_1.rbxm`...
- Variantes: `tree.rbxm`, `tree_1.rbxm`, `tree_2.rbxm`... El juego elige una según la posición, así un bosque no sale todo igual.
- Solo vale un Model o una MeshPart por archivo. Los scripts adentro se borran solos (y avisa en Output).
- Si el modelo pasa el límite de partes de la ranura (300 por defecto), se ignora y se usa el primitivo.
- La lista completa de ranuras, tamaños y qué buscar está en `docs/modelos/obby-sky-tower.md`.

Pasos: Toolbox > insertar > revisar que no tenga scripts > click derecho > Save to File (.rbxm) > guardar acá con el nombre de la ranura > `rojo build` (o `rojo serve`).

Usá solo modelos que tengas permiso de usar (los gratis del Creator Store sirven para experiencias). Evitá cualquier cosa con marcas registradas.
