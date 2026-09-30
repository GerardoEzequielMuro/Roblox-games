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
| Nube voladora | Zephyr Puff (montura; variante oscura Thunderhead) | `mount.*` |
| Semilla que cura todo | Vigor Seed | `item.vigor_seed` |
| Semilla de fuerza / de energía | Titan Seed / Spark Seed | `item.*` |
| Visor que lee el poder | Power Lens — planificado | `item.power_lens` |
| Radar de orbes | Seal Compass (pass RelicRadar) | `pass.RelicRadar` |
| Cápsulas | Pocket Pods — planificado | `item.*` |

## Loop

1. **Entrenar**: cada golpe (click / botón Punch) es una repetición del stat elegido (Strength, Ki, Defense, Agility, Jump). Auto-entrenar gratis (1,5/s) y más rápido con mejora o pass. Las **zonas de entrenamiento** multiplican (x4 … x600M; cada planeta nuevo ofrece una zona mejor que la mejor del anterior) si tenés el poder que piden. Las **pesas** (Sparks) multiplican todo.
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
- Formas: Kindled x2 (1K) · Blazing x5 (50K) · Tempest x15 (20M) · Eclipse x50 (100M) · Nova x200 (15B) · Celestial x1000 (1,5T) · Primordial x5000 (200T + 3 ascensiones).
- Ascensión: 40M × 40^n de poder (cada ascensión pide el poder de entrada del planeta siguiente); +100% de entrenamiento cada una; +25 Gems.
- Ritmo (simulador `sim/pacing_sim.luau`, guardado por `tests/pacing_check.luau`): planeta 2 ~6 min, 3 ~13 min, 4 ~33 min, primera ascensión ~33 min, planeta 5 ~1,3 h, planeta 10 ~35 h de juego (~1 mes activo).
- Autos (server): auto-entrenar 1,5 rep/s (+0,5 por nivel de mejora, x2 con TurboAuto), auto-ki (carga sola bajo 20%), auto-pelea 1,1 ataques/s (x2 con TurboAuto). Ninguno funciona dentro de la arena.

## Monetización (IDs en 0 hasta crearlos en el Dashboard; lo que está en 0 queda oculto)

| Pass | R$ | Efecto |
|---|---|---|
| VIP | 299 | +20% entrenamiento, tag dorado, 10 Gems diarias, aura VIP Gold |
| Double Training | 249 | x2 stats |
| Double Sparks | 249 | x2 Sparks |
| x2 Bundle | 449 | los dos de arriba (por separado 498) |
| Turbo Auto | 249 | autos x2 más rápido |
| Ki Mastery | 199 | formas drenan 50% menos, +50% recarga (apagado en la arena) |
| Lucky Aura | 249 | x2 suerte en auras Rare+ (las probabilidades en pantalla se actualizan) |
| Seal Compass | 299 | haces de luz hacia los sellos |
| Fast Flight | 79 | +50% velocidad de vuelo (normalizado en la arena) |
| Time Chamber | 499 | offline al 50% y hasta 12 h guardadas. También se gana con 2 ascensiones |
| Unbound Form | 599 | forma especial Unbound sin las 3 victorias contra Korrath (sigue pidiendo poder y ascensiones). Se gana matando a Korrath 3 veces |
| Dark Arts | 399 | aprender los ataques oscuros (Umbral Barrage, Null Nova) y el aura Umbral sin matar a los jefes. Se ganan con 3 victorias contra Mordrak / Rime Empress |
| Saga Skins | 299 | las 11 skins de saga (cosmético). Cada una se gana con el jefe de su arco |
| Sky Mounts | 149 | Zephyr Puff y Thunderhead (cosmético). Se ganan con Bramble King / Tempest Warden |
| Epic Auras | 199 | aura Nebula (Epic) y Gilded (Legendary). Se ganan con 1 y 3 ascensiones |

| Producto | R$ | Da |
|---|---|---|
| Starter Pack (24 h, una vez) | 99 (valor real por separado: 224) | 200 Gems + 50 min de Sparks + 30 min x2 + aura Starter Flame (fija, sin azar) |
| Sparks S/M/L/XL | 49 / 99 / 199 / 399 | 20 / 50 / 120 / 300 min de ingreso (+0 / +24 / +48 / +84%) |
| Gems S/M/L/XL | 49 / 129 / 299 / 699 | 60 / 190 / 480 / 1.300 (+0 / +20 / +31 / +52%) |
| Boost x2 30 min | 49 | x2 entrenamiento |
| Wish Now | 199 | completa el set de sellos (el deseo se elige, no es azar) |
| Seed Sampler / Seed Case | 25 / 99 | 1 / 5 de cada semilla (Vigor, Titan, Spark) |
| Battle pass S1 / S2 | 399 c/u | pista premium de la temporada |
| Tier Skip | 49 | sube 1 nivel del pase de la temporada activa |

## Sistemas de la ronda 2 (todo por datos en Config)

- **Semillas** (`Config.Seeds`, `Services/Items`): Vigor (cura todo + 50% ki, 15 s de espera), Titan (+50% de daño a enemigos 10 min), Spark (ki lleno y regen x2,5 10 min). Se compran con Sparks (precio = minutos de ingreso del mejor planeta) con stock por hora que se repone en punto (reloj en la tienda), o con los packs de Robux (sin límite). Teclas J / K / L. No funcionan en la arena.
- **Skins de saga / monturas / auras exclusivas** (`Config.Skins`, `Mounts`, `Auras`, `Services/Cosmetics`): cada una se consigue jugando (`earn`: jefe del arco, ascensiones, victorias en arena) o con el pass. Solo cosméticos (el aura suma al entrenamiento como todas). Ventana "Style".
- **Formas y ataques especiales**: forma Unbound (x8.000) y ataques oscuros (N / M). `special = { boss, count, pass }`: se ganan matando al jefe N veces o se compran con el pass, que solo salta el requisito del jefe (poder y ascensiones siguen). `Collection.specialOk`.
- **Pases de batalla** (`Config.BattlePass`, `Services/Season`): 30 niveles de 90 XP, pista gratis y premium, temporadas de 8 semanas con reloj visible: S1 "Dream Eater" (demonio rosa, desde 2026-10-01 UTC) y S2 "Sleeping God" (dioses). XP por misión diaria, jefes, jefe mundial, victoria en arena y tiempo jugado. Sin cajas al azar.
- **Arena sin pay-to-win**: dentro del Coliseo se apagan Ki Mastery, Fast Flight, las semillas y los ataques oscuros / especiales; el daño PvP ya dependía solo de la relación de poder (no de formas ni de pases). Al entrar, aviso en pantalla.
- **Meta siguiente** (`Shared/Goals`): terminada la historia, el tracker muestra la forma / planeta / ascensión más cercana con barra.

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
