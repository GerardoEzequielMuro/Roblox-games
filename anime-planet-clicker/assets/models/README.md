# Biblioteca de modelos (ranuras)

Acá se dejan modelos 3D reales (`.rbxm` / `.rbxmx`) para reemplazar las props hechas con partes primitivas. **No hay que tocar código.**

- Rojo convierte esta carpeta en `ServerStorage.ModelLibrary`.
- Si existe un archivo con el nombre exacto de una ranura, el juego lo usa; si no, usa el modelo primitivo de siempre.
- Variantes: `obelisk.rbxm`, `obelisk_1.rbxm`, `obelisk_2.rbxm`... el juego elige una según la posición, así un bosque no queda todo igual.
- El modelo se escala solo para entrar en el tamaño objetivo (mantiene proporciones), se apoya en el piso, se ancla y se le borran todos los scripts.
- Si tiene más de 300 partes (o se pasa del presupuesto global de 1200), se ignora y se usa el primitivo (aparece un warn en la consola).

Lista de ranuras, tamaños y qué buscar: `docs/modelos/anime-planet-clicker.md`.

Flujo: Toolbox > insertar > revisar que no tenga scripts > click derecho > Save to File (.rbxm) > guardar acá con el nombre de la ranura > `rojo build`.
