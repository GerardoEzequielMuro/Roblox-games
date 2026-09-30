# Ki Warriors — diseño

Juego de entrenamiento y pelea anime para Roblox (proyecto Rojo, todo por código, sin assets subidos).

**Título:** **Ki Warriors**. Alternativas: *Aura Breakers*, *Starforge Fighters*. Antes de publicar, buscar el nombre en Roblox para confirmar que no choca con otro juego activo (Roblox va a bajar copias de título/miniatura desde fines de 2026).

## Regla de propiedad intelectual (no negociable)

El juego es **inspirado en el género**, con mundo propio. Nada de marcas, personajes, razas, técnicas, planetas ni diseños de un anime/manga/juego existente, ni deformaciones del nombre. Eso incluye título, descripción, tags, íconos, passes y productos. Un reclamo válido baja el juego entero y pone en riesgo la cuenta (que comparte los otros juegos).

Todos los nombres visibles salen de **un solo archivo**: `src/shared/Names.luau` (por clave). El código, Config y los tests usan claves neutras. Cambiar un nombre = editar una línea ahí.

### Concepto del género → nombre propio

| Lo que un fan reconoce | En Ki Warriors | Clave |
|---|---|---|
| Energía de pelea | Ki (palabra genérica) | — |
| Moneda | Sparks (blanda) · Gems (premium, también se gana) | `currency.*` |
| 7 orbes + deseo | 6 Astral Seals + altar de deseos, aparece Astra, the Wish Comet | `item.seal`, `npc.wishkeeper` |
| Raza guerrera | Voltari (marca de luz en la frente) | `race.voltari` |
| Raza alienígena sabia | Lumen (cristales) | `race.lumen` |
| Raza de cuernos | Drakhar | `race.drakhar` |
| Humano | Terran | `race.terran` |
| Escalera de transformaciones | Kindled → Blazing → Tempest → Eclipse → Nova → Celestial → Primordial | `form.*` |
| Rayo insignia cargado | Star Lance (el rayo base) | `tech.star_lance` |
| Ráfaga de bolas de energía | Pulse Volley | `tech.pulse_volley` |
| Bola gigante de energía | Sunfall | `tech.sunfall` |
| Caída con onda expansiva | Meteor Dive | `tech.meteor_dive` |
| Cámara de gravedad | Gravity Dome | `zone.gravity_dome` |
| Cámara del tiempo | Timeless Vault | `zone.timeless_vault` |
| Ropa con peso | Weights (13 niveles) | — |
| Maestro anciano | Master Oru | `npc.master` |
| Torneo de artes marciales | Sky Coliseum (arena PvP) | `world.arena` |
| Nube voladora | Zephyr Puff (montura; variante oscura Thunderhead) — planificado | `mount.*` |
| Semilla que cura todo | Vigor Seed — planificado | `item.vigor_seed` |
| Semilla de fuerza / de energía | Titan Seed / Spark Seed — planificado | `item.*` |
| Visor que lee el poder | Power Lens — planificado | `item.power_lens` |
| Radar de orbes | Seal Compass (pass RelicRadar) | `pass.RelicRadar` |
| Cápsulas | Pocket Pods — planificado | `item.*` |

## Loop

1. **Entrenar**: cada golpe (click / botón Punch) es una repetición del stat elegido (Strength, Ki, Defense, Agility, Jump). Auto-entrenar gratis (1,5/s) y más rápido con mejora o pass. Las **zonas de entrenamiento** multiplican (x4 … x250K) si tenés el poder que piden. Las **pesas** (Sparks) multiplican todo.
2. **Pelear**: golpes con combo de 4 (el cuarto es remate), ráfaga de ki, rayo cargado, bloqueo, dash con invulnerabilidad, vuelo, carga de ki con aura, técnicas (Z/X/V). El servidor decide todo: cooldowns, ki, hitboxes, daño.
3. **Transformarse**: formas por nivel de poder, con multiplicador de daño, reducción de daño y drenaje de ki. Cada una cambia aura, cresta, pelo y contorno.
4. **Avanzar**: enemigos y jefe por planeta → Sparks y Gems → pesas, técnicas, planeta siguiente. Historia lineal (las primeras 5 misiones son el tutorial). Ascensión (rebirth) multiplica el entrenamiento.
5. **Arena**: PvP solo dentro del Sky Coliseum; afuera es zona segura. El daño PvP es una fracción de la vida del rival ajustada por la relación de poder (no hay one-shots).

## Números (todo en `src/shared/Config.luau`)

- Poder = Strength + Ki + Defense + 0,5·Agility + 0,5·Jump.
- Ganancia por repetición = zona × pesas × (1 + ascensiones) × mejora × aura × deseo × passes × evento × (1 + bonus social + raza).
- Vida = 100 + 4·Defense. Golpe = (4 + Strength) × forma. Ráfaga = (3 + 0,8·Ki) × forma. Rayo = (12 + 5·Ki) × (0,3 a 1 según carga) × forma.
- Ki en fracción de barra: ráfaga 4%, dash 5%, rayo 10–32%, recarga pasiva 3%/s (0 transformado), cargando 34%/s.
- Planetas: Verdia (0) → Kaldera (25K poder, 5K Sparks) → Frostreach (2M) → Zephyra (200M) → The Rift (25B).
- Formas: Kindled x2 (1K) · Blazing x5 (50K) · Tempest x15 (3M) · Eclipse x50 (150M) · Nova x200 (15B) · Celestial x1000 (1,5T) · Primordial x5000 (200T + 3 ascensiones).
- Ascensión: 5M × 8^n de poder; +100% de entrenamiento cada una; +25 Gems.
- Autos (server): auto-entrenar 1,5 rep/s (+0,5 por nivel de mejora, x2 con TurboAuto), auto-ki (carga sola bajo 20%), auto-pelea 1,1 ataques/s (x2 con TurboAuto). Ninguno funciona dentro de la arena.

## Monetización (IDs en 0 hasta crearlos en el Dashboard; lo que está en 0 queda oculto)

| Pass | R$ | Efecto |
|---|---|---|
| VIP | 399 | +20% entrenamiento, tag dorado, 10 Gems diarias, aura VIP Gold |
| Double Training | 349 | x2 stats |
| Double Sparks | 199 | x2 Sparks |
| Turbo Auto | 249 | autos x2 más rápido |
| Ki Mastery | 199 | formas drenan 50% menos, +50% recarga |
| Lucky Aura | 249 | x2 suerte en auras Rare+ (las probabilidades en pantalla se actualizan) |
| Seal Compass | 149 | haces de luz hacia los sellos |
| Fast Flight | 99 | +50% velocidad de vuelo |

| Producto | R$ | Da |
|---|---|---|
| Starter Pack (24 h, una vez) | 99 (antes 399) | 150 Gems + 30 min x2 + aura Starter Flame (fija, sin azar) |
| Sparks S/M/L/XL | 49 / 99 / 199 / 399 | 20 / 50 / 120 / 300 min de ingreso |
| Gems S/M/L/XL | 49 / 129 / 299 / 699 | 60 / 180 / 480 / 1.300 |
| Boost x2 30 min | 49 | x2 entrenamiento |
| Wish Now | 199 | completa el set de sellos (el deseo se elige, no es azar) |

**Ítems aleatorios pagos**: el único azar es el giro de auras (25 Gems o giros gratis). Las probabilidades se muestran en % y suman 100: Breeze 22 · Ember 20 · Moss 18 · Tide 13 · Dusk 12 · Volt 6 · Frostfire 4 · Crimson 2,5 · Abyss 1,5 · Solar 0,9 · Starlight 0,1. Todo giro da un aura (no hay "perder"). Donde `PolicyService.ArePaidRandomItemsRestricted` es verdadero, el giro con Gems y el pass Lucky Aura se ocultan y quedan los giros gratis.

## Catálogo completo por arcos (plan)

Cada arco = zona/planeta + 2 enemigos + jefe + misiones + set de recompensas (skin del arco, técnica o forma, aura). Hecho = jugable hoy. El resto se suma por rondas sin tocar código: son datos en `Config` + nombres en `Names.luau`.

| # | Estructura que un fan reconoce | Arco propio | Zona | Jefe | Recompensas del arco | Estado |
|---|---|---|---|---|---|---|
| 1 | Aventura inicial y búsqueda de los orbes | The First Seals | Verdia (pradera) | Bramble King | Skin "Wanderer", montura Zephyr Puff, primer deseo | Zona, enemigos y jefe hechos |
| 2 | Torneo de artes marciales | Sky Coliseum Cup | Coliseo en Verdia | Campeón del torneo (escalera de 3 rivales) | Skin "Contender", título | Arena construida |
| 3 | Ejército / organización militar | The Iron Legion | Fort Brask (desierto, torre por pisos) | Marshal Krome | Skin "Legion Breaker", técnica de ráfaga | Plan |
| 4 | Rey demonio | The Horned King | Kaldera (volcán) | Forge Tyrant | Skin "Emberguard", rama de técnicas oscuras | Zona, enemigos y jefe hechos |
| 5 | Invasores del espacio | Storm Invaders | Cracked Mesa (páramo) | Prince Vael | Skin "Storm Armor", forma Kindled potenciada | Plan |
| 6 | Tirano galáctico en planeta alienígena | Tyrant of the Ice World | Frostreach (hielo) | Rime Empress (4 fases) | Skin "Lumen Elder", forma Tempest | Zona, enemigos y jefe hechos |
| 7 | Androides y el bio-androide con su torneo | The Perfect Machine | Null City (ciudad en ruinas) | Chimera Prime + "Chimera's Games" | Skin "Unit Zero", técnica de absorción | Plan |
| 8 | Demonio rosa | The Dream Eater | Bubble Realm | Glutt | Pase de batalla temporada 1, skin "Glutt Hood" | Plan |
| 9 | Dioses de la destrucción | The Sleeping God | Zephyra (cielo y tormenta) | Tempest Warden | Forma Celestial, aura divina, pase temporada 2 | Zona, enemigos y jefe hechos |
| 10 | Tirano resucitado | Gilded Return | Frostreach (evento) | Gilded Empress | Skin dorada, aura Solar | Plan |
| 11 | Torneo entre universos | Twin Worlds Tournament | Arena | Escalera de 5 rivales | Skin "Twin Champion" | Plan |
| 12 | Dios-villano del futuro | The False Judge | Broken Tomorrow | Arbiter Null | Skin "Timewalker", técnica oscura definitiva | Plan |
| 13 | Torneo de supervivencia multiversal | Last Realm Standing | The Rift (vacío) | The Hollow Star | Forma Primordial, skin "Silent Titan" | Zona, enemigos y jefe hechos |
| P1 | Película: guerrero legendario descontrolado | Korrath the Unbound | Jefe mundial | Korrath | Forma especial "Unbound" (también comprable) | Plan |
| P2 | Película: fusión | Twinsoul | Evento | Mirrorborn | Forma "Twinsoul" | Plan |
| P3 | Película: conquistador metálico | Chrome Tyrant | Evento | Chrome Tyrant | Skin cromada | Plan |
| — | Jefe mundial cada 30 min | Astral Titan | Cráter en Verdia | Astral Titan | Gems y Sparks por aporte | Sitio construido |

Sistemas planificados sobre esa base: skins por arco (partes procedurales + índice), técnicas y formas especiales **comprables o ganables con la misma potencia**, rama oscura con alineamiento, pases de batalla por temporada (pista gratis + premium, sin cajas al azar), monturas de vuelo, tienda de consumibles separados (Vigor / Titan / Spark Seed, Power Lens, Seal Compass, Pocket Pods), eventos con reloj (fin de semana x2, orbe de zona cada hora, deseo cada 15 min).

## Rendimiento

- Efectos solo en el cliente, con pool de partes; un loop por sistema; StreamingEnabled (radio 320–900).
- Enemigos: el servidor replica una parte invisible por enemigo y una sola IA a 10 Hz; el cliente arma y anima el modelo. Solo los planetas con jugadores tienen enemigos vivos.
- Perfil lite (celulares, o ajuste): menos lenguas de aura, sin partículas ni luces dinámicas, menor distancia de efectos.
- Presupuestos como test: 5.200 partes de mundo, 90 enemigos activos, 260 partes de efecto, 120 MB de heap Lua.
- Gráficos al mínimo: el look está en colores y siluetas horneados en las partes; auras, rayos, chispas y grietas son geometría. Bloom/sombras/atmósfera son un extra.
