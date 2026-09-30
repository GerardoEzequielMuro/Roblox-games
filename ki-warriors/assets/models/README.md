# Biblioteca de modelos 3D (ranuras)

Esta carpeta es `ServerStorage.ModelLibrary` en el juego. Si ponés acá un `.rbxm` / `.rbxmx`
con el nombre exacto de una ranura, el mundo usa ese modelo en lugar del armado con partes
primitivas. **No hay que tocar código.** Si la carpeta está vacía (solo este README), el
juego se ve exactamente como hoy.

Guía completa, con la tabla de ranuras, tamaños y qué buscar en el Creator Store:
[`docs/modelos/ki-warriors.md`](../../../docs/modelos/ki-warriors.md).

## Flujo rápido

1. Studio > Toolbox > Modelos: buscá el modelo e insertalo.
2. Revisá que no tenga scripts (igual el juego los borra, pero mejor saberlo).
3. Un solo objeto raíz (un `Model` o un `MeshPart`). Click derecho > **Save to File** > `.rbxm`.
4. Guardalo acá con el nombre de la ranura: `tree.rbxm`, `rock.rbxm`, `warp_gate.rbxm`...
   - Variantes: `tree_1.rbxm`, `tree_2.rbxm`... (se elige una por posición, así un bosque no es idéntico).
5. `rojo build default.project.json -o KiWarriors.rbxlx` (o `rojo serve`) y abrir en Studio.

El modelo se escala solo para entrar en el tamaño objetivo de la ranura (manteniendo
proporciones), se apoya en el piso, se ancla y se le borran los scripts. Modelos de más de
300 partes se ignoran (y se avisa en Output): se usa el armado original.
