# Biblioteca de modelos 3D (Huerta Tycoon)

Esta carpeta se mapea a `ServerStorage.ModelLibrary` (ver `*.project.json`). Si dejás acá un modelo con el nombre exacto de una ranura, el juego lo usa en lugar de las piezas primitivas. Sin archivos, el mapa se construye igual que siempre.

Flujo rápido:

1. En Studio: Toolbox (Creator Store) o generador 3D con IA, insertá el modelo.
2. Borrá cualquier Script/LocalScript/ModuleScript que traiga (el juego igual los borra al clonar).
3. Click derecho > Save to File... > formato `.rbxm`.
4. Guardalo acá con el nombre de la ranura, por ejemplo `tree.rbxm`. Variantes: `tree_1.rbxm`, `tree_2.rbxm`...
5. `rojo build default.project.json -o huerta.rbxlx` (o `rojo serve`) y probá.

La lista de ranuras, tamaños y qué buscar está en `docs/modelos/huerta-tycoon.md`.
