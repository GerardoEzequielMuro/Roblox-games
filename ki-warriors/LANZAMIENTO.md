# Ki Warriors — lanzamiento (lo que solo puede hacer Gerar)

## 1. Publicar

1. Abrir `KiWarriors.rbxlx` en Studio → **File → Publish to Roblox As…** → experiencia nueva.
2. **Game Settings → Security → Enable Studio Access to API Services = ON** (sin eso no guarda progreso ni rankings).
3. **Game Settings → Avatar → Avatar Type = R15** (las poses de pelea, carga y vuelo están hechas para R15; en R6 se juega igual pero sin poses).
4. Servidores: **12 jugadores** como máximo (arena + co-op contra jefes).
5. Poner la experiencia en **Public**.

## 2. Nombre, descripción e ícono (regla dura)

- Título: `Ki Warriors`. Buscarlo antes en Roblox; si hay un juego activo con ese nombre, usar `Aura Breakers` o `Starforge Fighters`.
- **Cero marcas**: nada de nombres de animes, personajes, razas, técnicas o planetas conocidos, ni deformaciones, en título, descripción, tags, passes, productos, ícono o miniaturas. Roblox tiene escaneo proactivo de IP y un reclamo válido baja el juego entero.
- Ícono y miniaturas: capturas del propio juego (personaje transformado con aura + jefe). El texto se agrega con cualquier editor. Máximo 2–4 palabras.

## 3. Creator Dashboard

- Crear los **passes** y **productos** de la tabla de `DESIGN.md` con esos precios y pegar los IDs en `src/shared/Config.luau` (`Config.Passes`, `Config.Products`, `Config.AdProducts`). Lo que quede en 0 no aparece en la tienda. Rebuild + republicar.
- Grupo de Roblox → `Config.GroupId`. Tu UserId → `Config.AdminUserIds` (comandos de evento).
- Cuestionario de madurez: pelea de fantasía sin sangre (violencia leve).
- Verificación de ID + 2FA (DevEx, anuncios con recompensa).

## 4. Ítems aleatorios pagos

El giro de auras muestra probabilidades en % que suman 100 y nunca da "nada". El juego consulta `PolicyService` y oculta el giro con Gems y el pass Lucky Aura donde está restringido. No agregar cajas al azar dentro de packs ni del pase de batalla.

## 5. Ideas de videos (TikTok / Shorts)

1. "De 20 de poder a la primera transformación en 60 segundos" (el momento del estallido con la columna de luz).
2. "Probé todas las formas: cuál tiene el mejor aura" (las 7 seguidas en la plaza).
3. "Rayo cargado al máximo contra el jefe" (cámara lenta del impacto).
4. "Auto-pelea toda la noche: cuánto poder gané" (antes/después).
5. "1 vs el jefe mundial" y "arena: nuevo contra veterano".
Poner el share link del juego en cada video (Creator Rewards paga por los usuarios nuevos que entran por el link).

## 6. Proceso

Update chico cada sábado (arco nuevo, forma o evento) + `[UPD n]` en el título + código nuevo por hito de likes o visitas.
