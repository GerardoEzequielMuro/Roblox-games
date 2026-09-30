# Ki Warriors: handoff

Todo esto se hizo sin Studio: no vi el juego corriendo en ningún momento. Lo verifiqué con build, type check y tests puros. Todo lo visual está razonado desde el código y hay que mirarlo en Studio.

## Qué cambié

**Íconos (pack compartido)**
- `src/shared/Glyphs.luau` (nuevo, puro): mapea emoji → nombre del pack (`⚡`→coin, `💎`→gem, `👊`→fist, `🛡️`→shield, `🔥`→flame, `🌟`→rebirth, `🔒`→lock, `✔`→check, `🎁`→gift, `🛒`→shop, `⚙️`→settings, `📜`→quest, `🪐`→planet, `🧭`→map, etc.; son 45). Ignora el selector U+FE0F. **No se usan `orb` ni `cloud`**: la bola naranja con estrella y la nube amarilla voladora se parecen demasiado a Dragon Ball (regla de IP de DESIGN.md). Los emoji sin ícono (🦘, 💨, ☄️, 🔵, 🕊️, 👤, 💥…) quedan como están.
- `src/client/UI/Theme.luau`: `Theme.icon(glyph, props)` devuelve un ImageLabel (ScaleType Fit, fondo transparente) si `Icons.get` tiene id; si no, el mismo TextLabel emoji de siempre. `Theme.button` usa el ícono y, si hay imagen, parte los textos tipo "💎 120" en ícono + "120".
- Sitios que pasan por ahí: `UI/Kit.luau` (chips, y `Kit.text` cuando el texto es un glifo solo), `UI/Hud.luau` (medallas de monedas, slots de stats, slots de movimientos, badge de poder), `UI/Windows.luau` (medallón del título; la X de cerrar pasa al ícono `close`), `UI/Menu.luau`, `UI/TouchControls.luau`. Los emoji que están dentro de frases traducidas no se tocaron.
- Hoy todos los ids de `Icons.luau` están vacíos, así que **la UI se ve exactamente igual que antes** hasta que se suban.

**Bugs visuales**
- Placa de nombre/vida de enemigos (`src/client/NpcRender.luau`): ya estaba en offset (no en scale). Ahora es más chica (96×24 normal, 170×34 jefe), tiene un tope del ~9–16% del ancho de la pantalla (para celulares y ventanas chicas de Studio, donde 210 px podían ser un tercio de la pantalla), `AlwaysOnTop = false` explícito, `MaxDistance` 70/200 y se redimensiona cuando cambia el viewport. También achiqué el tag de poder de los jugadores (`CharFx.luau`) y el del maestro (`WorldBuilder.luau`).
- Cubos oscuros al pegar (`src/client/Fx.luau`, `CombatFx.luau`, `CharFx.luau`): eran los "chips" de material Slate gris que saltaban en Meteor Dive y en las transformaciones. Los reemplacé por `Fx.debris`: un burst de ParticleEmitter (textura por defecto, sin assets) en calidad normal, y en lite unas motitas claras chiquitas que se desvanecen del todo. Las chispas ahora terminan en transparencia 1 (antes quedaban al 0.6). El pool de partes cancela los tweens pendientes al liberar una parte, así un efecto terminado no puede seguir moviendo o agrandando una parte que ya usa otro efecto.
- Esfera violeta que tapaba al personaje (`CharFx.luau`): Eclipse es la forma "shadow", violeta. Había tres culpables: (1) la cáscara del aura era un elipsoide Neon de 6×9 studs alrededor del cuerpo, (2) las bolas Neon del burst de transformación arrancaban del tamaño del personaje con 0.2–0.35 de transparencia, (3) en las formas shadow, una de cada tres lenguas del aura era SmoothPlastic casi negra y opaca. Ahora la cáscara y los bursts usan material ForceField (borde brillante, centro transparente; está en `Fx.shell`), hay un burst de partículas y las lenguas oscuras son Neon semitransparentes. El pilar de luz pasó de 0.2 a 0.4 de transparencia.
- HUD en inglés con el idioma en español (`src/client/Lang.luau`, `src/shared/Locale.luau`): los textos del HUD ya pasaban por traducción. El problema era de dónde salía el idioma. En Studio, `Player.LocaleId` sigue el idioma de la interfaz de Studio (casi siempre inglés). Ahora en Studio manda primero `LocalizationService.SystemLocaleId` (el del sistema operativo) y en vivo se usa `Player.LocaleId` → `RobloxLocaleId` → `SystemLocaleId` (con `Locale.resolveFirst`, que es puro y está testeado). Además, **el AutoTest dejaba guardado `lang = "en"`** en el perfil de Studio al terminar; ahora restaura la preferencia que había (`tests/AutoTestClient.client.luau`). Los "MAX" del HUD y del panel de mejoras ahora pasan por `ui.max`.

**Look 2026 (sin assets nuevos)**
- `src/client/WorldFx.luau`: saturación de todos los cielos un ~40% más baja, contraste 0.1, bloom un poco más presente (umbral 1.35), `EnvironmentDiffuseScale` 1 y `EnvironmentSpecularScale` 0.7 para que se lean los materiales con Future, y `ShadowSoftness` 0.25.
- `src/server/World/WorldBuilder.luau`:
  - Cada tema tiene `rockMat`, `foliageMat` y `pathMat` (Rock/Grass/Ground en Verdia, Basalt en el volcán, Glacier/Snow/Ice en el hielo, Sandstone/Sand en el desierto, etc.). Troncos y tótems son Wood; la plaza es Pavement/Slate; las piedras de los portales, Slate.
  - Ruido de color por parte (`vary`, con su propio RNG) en montañas, colinas, rocas, árboles, arbustos y parches de suelo.
  - Detalle de suelo nuevo: 30 por planeta (matas de pasto, montículos de nieve o piedritas según el tema), de 2 partes cada uno, con su propio RNG para no mover nada de lo que ya estaba.
- UI (`Theme.luau`, `Hud.luau`): los números usan FredokaOne (`Theme.Display`) y Bangers queda para el combo, el nombre de la forma y los números de daño (`Theme.Comic`). Hay `Theme.pressable` (hover + squash al apretar) en los toggles de auto, el botón de pesas y los slots de movimientos. Las píldoras de moneda tienen gradiente y números más grandes con contorno. Los toggles tienen brillo arriba.

## Cómo lo verifiqué

- `rojo build default.project.json`: OK (`Built project to ki-warriors.rbxlx`).
- `luau-lsp analyze … src`: 0 líneas de salida, o sea 0 errores.
- Tests puros: **2/2 OK**. `tests/locale_check.luau` (12 idiomas con 336/336 claves, más 5 casos nuevos de `resolveFirst`) y `tests/glyphs_check.luau` (nuevo: todos los íconos mapeados existen en el pack, no hay orb ni cloud, split y normalización andan, sin ids no hay imagen y 28/32 íconos de Config tienen imagen). No hay carpeta `sim/`.
- Presupuesto de partes del mundo: armé un harness con mocks en el scratchpad (no quedó en el repo) que corre `WorldBuilder.build()`. Dio **11.186 → 11.786 partes de 14.000** (`Config.Budget.worldParts`). El Random del mock no es el de Roblox, así que el número real puede variar un poco; el test de Studio "world part budget" es el que vale.

## Qué hay que mirar en Studio

1. **Transformarse a Eclipse** (y a cualquier otra forma): el personaje tiene que verse siempre y la cáscara del aura tiene que ser un borde brillante, no una bola. Si ForceField se ve demasiado fuerte o no se ve, ajustar `shell.Transparency` en `CharFx.updateAura` y los valores de `Fx.shell` en `transformBurst`.
2. **Meteor Dive y transformación**: que ya no queden cubos grises flotando. Tiene que haber un puff de partículas (o motitas en lite). Probarlo también con Graphics Quality 1.
3. **Placas de enemigos**: compactas a distancia media, que no tapen la pantalla en el emulador de celular ni con la ventana chica, y que el nombre se siga leyendo.
4. **Idioma**: con el sistema en español, entrar en Play sin `ForceLanguage` y ver el HUD en español. Si igual sale en inglés, puede que el perfil tenga `lang = "en"` guardado de antes: en Ajustes, elegir Español (o borrar el dato).
5. **Mundo**: cómo se ven los materiales (Rock/Grass/Basalt/Glacier…) y el ruido de color en cada planeta, sobre todo Verdia. Las matas de pasto son elipsoides aplastados cruzados, así que hay que ver si parecen pasto o "hojas". Correr el AutoTest y confirmar el "world part budget".
6. **Luz**: que el bloom nuevo (umbral 1.35) no queme los planetas con mucho Neon (Rift, Kaldera). Si pasa, volver a 1.6.
7. **Fuentes**: FredokaOne en poder, monedas y stats. Ver que no se corten los números largos ("1.23T").
8. **Íconos**: cuando se suban, revisar tamaño y posición del ícono dentro de los botones con precio ("💎 120") y en la X de las ventanas.

## Pendiente

- No encontré una placa gigante en el código actual (ya estaba en offset). Si en Studio se sigue viendo, quiero la captura para saber qué objeto es.
- Los materiales de estructuras (anillos de las zonas, portales, arena, coliseo) siguen en SmoothPlastic. Convendría una pasada con criterio visual en Studio.
- Faltan sombras (drop shadow) en toasts y en el tracker de misiones, y el estilo de los paneles de las ventanas se podría unificar más.
- Falta la opción "Automático" en el selector de idioma (el servidor ya acepta `lang = ""`).
- Nada del backlog de contenido de DESIGN.md (arcos nuevos, monturas, semillas): no es solo código seguro sin probar.
- Faltan íconos propios para ki (✨ usa `aura`), salto, dash, vuelo y rayo: el pack no tiene uno adecuado.

## Ronda 2

Igual que en la ronda 1: **no vi nada corriendo** (no hay Studio acá). Todo está verificado con build, type check y tests puros. La parte visual y los flujos de compra/uso hay que mirarlos en Studio (ver "Qué mirar en Studio"). Los IDs de passes y productos siguen en 0 (los crea el dueño).

### Precios

Precios de la sección 4.5 de `docs/research/top-juegos-y-precios.md`, en `src/shared/Config.luau`.

| Ítem | Antes | Ahora | Por qué |
|---|---|---|---|
| Fast Flight (pass) | 99 | **79** | Nimbus 79, Fast Travel 39 |
| 2x Training (pass) | 349 | **249** | x2 Chikara 249 |
| 2x Sparks (pass) | 199 | **249** | x2 Yen 249 |
| **x2 Bundle** (pass, nuevo) | n/a | **449** | bundle AFS 549; acá es 10% menos que los dos por separado (498). Tener el bundle cuenta como tener los dos (`Collection.expandPasses`) |
| Turbo Auto | 249 | 249 | ok |
| Ki Mastery | 199 | 199 | ok |
| Lucky Aura | 249 | 249 | ok (sigue mostrando las odds en vivo y se oculta si `ArePaidRandomItemsRestricted`) |
| Seal Compass (Relic Radar) | 149 | **299** | Dragon Radar 299 |
| VIP | 399 | **299** | AFS/AV/AD 299 |
| **Time Chamber** (pass, nuevo) | n/a | **499** | Time Chamber 899-1000 en juegos grandes; acá offline al 50% (antes 25%) y hasta 12 h guardadas. **También se gana** con 2 ascensiones |
| **Unbound Form** (pass, nuevo) | n/a | **599** | salta solo el requisito de matar 3 veces a Korrath; poder y ascensiones se piden igual. Se gana matando a Korrath 3 veces |
| **Dark Arts** (pass, nuevo) | n/a | **399** | aprender los 2 ataques oscuros sin matar a los jefes + aura Umbral. Se gana con 3 victorias contra Mordrak / Rime Empress |
| **Saga Skins** (pass, nuevo) | n/a | **299** | rango 199-399 de cosméticos premium; las 11 skins. Cada una se gana con el jefe de su arco |
| **Sky Mounts** (pass, nuevo) | n/a | **149** | rango 49-149 comunes; Zephyr Puff + Thunderhead. Se ganan con Bramble King / Tempest Warden |
| **Epic Auras** (pass, nuevo) | n/a | **199** | Nebula (Epic) + Gilded (Legendary). Se ganan con 1 y 3 ascensiones |
| Gems 2 (producto) | 180 por 129 | **190 por 129** | la investigación pide subir el bonus a ~+20%; la escalera queda +0/+20/+31/+52% |
| Sparks / Gems restantes | 49→399 / 49→699 | igual | ya estaban bien (bonus +24/+48/+84%) |
| Starter Pack | 99 (tachado 399) | **99 (tachado 224)** | el 399 no era un precio real. Ahora el tachado es la suma real del contenido comprado suelto en la tienda, con la tarifa más barata (200 Gems + 50 min de Sparks + 30 min x2). Se calcula en Config y un test lo verifica. La aura sigue siendo fija |
| **Seed Sampler / Seed Case** (producto, nuevo) | n/a | **25 / 99** | compra impulsiva 9-25; 1 / 5 de cada semilla. Las semillas también se compran con Sparks |
| **Battle pass S1 / S2** (producto, nuevo) | n/a | **399 c/u** | rango 299-499 para juego chico; pista premium de la temporada |
| **Tier Skip** (producto, nuevo) | n/a | **49** | "skip de tier 49" de la guía |

No agregué emote slots / kill sounds (99-149 en la investigación): no hay sistema de emotes todavía (Pendiente).

Reglas de política que quedaron en tests (`tests/pricing_check.luau`): ningún pass/producto es aleatorio; las semillas, el pase y las skins son listas fijas; toda skin/montura/aura pagada y toda forma/ataque especial tiene `earn` (ganable jugando); los anclajes tachados son reales; el giro de auras sigue sumando 100% y las auras pagas no están en el giro.

### Retención

| # | Item | Estado | Dónde |
|---|---|---|---|
| 1 | Loop de segundos con feedback inmediato | **ya estaba** | `CombatFx.luau` (números de daño, hit-stop, partículas), `Toasts.luau`, `Fx.sound` |
| 2 | Próxima meta siempre visible y cercana | **ya estaba** (historia, upgrade de pesas en el HUD) + **agregado** | `Shared/Goals.luau` (puro); `UI/QuestTracker.luau`: terminada la historia, el tracker muestra la forma / planeta / ascensión más cercana con barra. Antes el panel se escondía |
| 3 | Metas de sesión y largo plazo | **ya estaba** (zonas, planetas, ascensión, ranking, Starlight 0,1%) + **agregado** | Colección x/total en la ventana Style (`UI/Panels3.luau`), temporadas de 8 semanas (`Services/Season.luau`), skins por arco, forma Unbound |
| 4 | Razones para volver | **ya estaba**: racha diaria, regalos por tiempo, offline, códigos, grupo, Power Hour cada 3 h y Spark Weekend con reloj, jefe mundial cada 30 min. **Agregado**: muestra explícita de la racha ("Racha: N días") en Premios (`UI/Panels2.luau`); stock de semillas por hora con reloj "reposición en mm:ss" (`Services/Items.luau`, `Shared/Seeds.luau`); temporada con reloj de fin; Time Chamber para el offline |
| 5 | Social | **ya estaba**: anuncios globales (aura rara, deseo, Arena Rush), invitados con premio, tableros en la plaza, ranking. **Agregado**: anuncio global cuando alguien llega a Celestial / Primordial / Unbound (`Services/Social.luau`). **No agregué regalos entre jugadores** (ver Pendiente) |
| 6 | Primer minuto | **ya estaba** (las 5 primeras misiones son el tutorial, primer premio a los segundos, menú que aparece de a poco). Sigue igual: los botones nuevos (Season) aparecen después del tutorial |

### Otros cambios

**Contenido estilo Dragon Ball, con nombres originales de `Names.luau`** (todo por datos en Config):
- **Semillas** (Vigor, Titan, Spark): `Config.Seeds`, `Services/Items.luau`, `Shared/Seeds.luau`. Se compran con Sparks (precio = minutos de ingreso del mejor planeta, stock por hora con reposición en punto, tope de 30 encima) o con los packs de Robux (sin tope ni stock). Se usan desde la Tienda, con J / K / L, con los slots sobre el dock de movimientos (PC) o botones táctiles. Vigor cura todo + 50% ki (15 s de espera), Titan +50% de daño a enemigos 10 min, Spark ki lleno y regen x2,5 10 min.
- **Skins de saga** (11, una por arco), **monturas voladoras** (Zephyr Puff, Thunderhead), **auras Epic/Legendary** exclusivas (Nebula, Gilded, Umbral): ventana nueva **Style** (Guerrero > Style), `Services/Cosmetics.luau`, `Shared/Collection.luau`. Se consiguen jugando o con el pass. Render: piezas procedurales en `CharFx.luau` (capa, cinturón, vincha, hombreras; puff blanco u oscuro bajo los pies al volar). Sin assets.
- **Forma Unbound** (x8000, última de la escalera) y **ataques oscuros** (Umbral Barrage en N, Null Nova en M): `special = { boss, count, pass }` en Config; `Formulas.bestForm` y `BuyTechnique` lo respetan en el servidor.
- **Pases de batalla**: S1 "Dream Eater" (demonio rosa, arco 8) y S2 "Sleeping God" (dioses, arco 9). 30 niveles de 90 XP, pista gratis y premium, sin cajas al azar. XP por misión diaria, jefes, jefe mundial, victoria en arena y tiempo jugado. S1 arranca **2026-10-01 00:00 UTC** y cada temporada dura 8 semanas (`Config.BattlePass.seasons`; hoy, 30/09, la ventana muestra "empieza en X"). Ventana **Season** con reloj, barra, reclamar todo, comprar premium y saltar nivel. Recibos idempotentes por el mismo `ProcessReceipt`.
- **Arena sin pay-to-win**: dentro del Coliseo se apagan Ki Mastery, Fast Flight (`Training.luau`), semillas y buffs (`Combat.luau`, `Fighters.damageBoost`, `Items.use`), y los ataques oscuros/especiales (`Combat.technique`). El daño PvP ya dependía solo de la relación de poder, nunca de formas ni de pases. Al entrar sale un aviso ("Juego limpio"). Los x2 de entrenamiento no afectan la pelea, solo la velocidad a la que crecés (igual que ganar jugando más horas).
- **Time Chamber**: `Offline.luau` (tasa 50% y tope 12 h con el pass o con 2 ascensiones).
- Traducciones: 88 claves nuevas en los **12 idiomas** (423/423 en cada uno). Las de ja/ko/th/vi/ru/tr/id conviene que las mire alguien que hable el idioma.
- `DESIGN.md` y `README.md` actualizados (precios, sistemas, teclas).

Del "Pendiente" de la ronda 1, el backlog de contenido de `DESIGN.md` ahora tiene monturas, semillas, skins de saga y pases de batalla. Los arcos nuevos con zona propia (pendientes 2, 10, 11 y 12 del plan) no se tocaron.

### Cómo lo verifiqué

Desde `ki-warriors/` con `PATH=/tmp/tools:$PATH`:
- `rojo build default.project.json -o /tmp/tools/ki-warriors.rbxlx`: OK. También compilan `test`, `showcase`, `showcase_low` y `showcase_touch`.
- `rojo sourcemap ... && luau-lsp analyze --definitions=@roblox=... src`: **0 líneas de salida** (0 errores). También limpio sobre `tests/AutoTest.server.luau` y `tests/AutoTestClient.client.luau`.
- Tests puros, **6/6 OK** (`luau tests/<archivo>`):
  - `locale_check.luau`: LOCALE CHECKS PASSED, 12 idiomas con 423/423 claves (antes 336).
  - `glyphs_check.luau`: GLYPH CHECKS PASSED (35/46 íconos de Config con imagen).
  - `pricing_check.luau` (nuevo): PRICING CHECKS PASSED (15 passes, 16 productos, valor del Starter Pack 224 R$ por 99 R$). Precios exactos, escaleras, bundle más barato que las partes, tachado honesto, earn en todo lo pago, odds de auras = 100.
  - `collection_check.luau` (nuevo): COLLECTION CHECKS PASSED (reglas earn/pass, forma Unbound, bundles, TimeChamber).
  - `battlepass_check.luau` (nuevo): BATTLE PASS CHECKS PASSED (reloj de temporadas, tiers, claims, tablas de premios válidas, 1 h por día alcanza para el pase gratis en 8 semanas pero no en una).
  - `seeds_check.luau` (nuevo): SEEDS / GOALS CHECKS PASSED (precio, stock por hora, reposición, tope, próxima meta).
  - No hay carpeta `sim/` en este juego (igual que en la ronda 1).
- Extendí el playtest de Studio (`tests/AutoTest*.luau`, **no lo corrí**): compra/uso de semillas, stock, pase de batalla (claims, premium por recibo, tier skip), skins/montura por jefe, Dark Arts, forma Unbound; y ajusté el chequeo de offline a la tasa variable. Hook de test `Season.forceActive` porque la S1 real empieza mañana.
- El presupuesto de partes del mundo no cambió (no toqué `WorldBuilder`).

### Qué mirar en Studio

1. **Correr el AutoTest** (`test.project.json`) y mirar el bloque "Round 2" del reporte: es lo más probable que falle por cosas que no puedo ver (p. ej. orden de eventos, tiempos de `waitFor`).
2. **Tienda**: los 15 passes y los productos entran en la grilla (tarjeta de 330x92; revisar que el texto largo de Dark Arts / Unbound no se corte); la sección **Semillas** (precio, stock n/m, botón Usar, reloj de reposición); el Starter Pack muestra "Vale 224 R$ si se compra por separado" tachado. Con ids en 0 los ítems aparecen solo en Studio (y dicen "próximamente" al tocar).
3. **Ventana Season** (botón nuevo del menú, aparece después del tutorial): hoy dice "Dream Eater Season empieza en …". Para verla viva hay que cambiar `startsAt` de s1 en Config o correr el AutoTest. Revisar filas de 30 niveles, el ancho de las dos columnas y los botones Reclamar.
4. **Ventana Style** (Guerrero > Style): filas de skins con el texto de requisito ("Derrota a X 1/3 · o consigue Saga Skins").
5. **Skins en el personaje**: capa / cinturón / vincha / hombreras en R15 y R6 (los offsets salen de los tamaños de `UpperTorso`/`Head`; en R6 usan `Torso`). **Montura**: el puff bajo los pies al volar (¿queda bien con la pose de vuelo? ajustar el `Vector3` de `updateMount` en `CharFx.luau`).
6. **HUD**: el dock de movimientos ahora crece hacia arriba (13 slots: 3 filas de 6) y los slots de semillas (J/K/L) aparecen encima. En celular, los botones nuevos (N/M y semillas) están en `TouchControls.LAYOUT`: revisar que no pisen el botón de salto ni el pulgar.
7. **Arena**: entrar al Coliseo con Ki Mastery/Fast Flight, una semilla activa y un ataque oscuro y confirmar que no hacen nada ahí; debe salir el aviso "Juego limpio".
8. **Tracker** terminada la historia: la barra de "próxima meta" (se puede probar seteando `story.step` al final).
9. **Dark techniques**: cómo se ven las 7 esferas violeta de Umbral Barrage y la esfera de Null Nova (usan el mismo render de proyectiles con color propio).

### Pendiente

- **Crear los passes/productos en el Dashboard** y pegar los IDs: 15 passes y 16 productos (ver tabla; 2 productos de pase de batalla por temporada, uno por cada `season`). Los precios regionales vienen activados por defecto desde 2026-03-30.
- El Time Chamber como "sala donde el tiempo corre x2" (la investigación) quedó como mejora del offline; una zona física con ese efecto es contenido nuevo.
- **Regalos entre jugadores** y **emote slots / kill sounds**: no existen los sistemas; no los agregué por no ser código chico y seguro.
- Los arcos 2, 10 y 11 del catálogo (escalera del torneo, evento Gilded, torneo de 5 rivales) siguen sin implementar, y las películas P2 y P3 (Mirrorborn, Chrome Tyrant) solo existen como jefes mundiales sin forma/skin propia. Los ítems "Power Lens" y "Pocket Pods" del plan siguen sin hacer.
- Más temporadas: agregar entradas a `Config.BattlePass.seasons` (con su `product` y su clave en `Names.luau`) y crear el producto en el Dashboard.
- Dark branch "con alineamiento" (moral) del plan: hoy son solo 2 ataques y un aura.
- Un recibo de Tier Skip cuando no hay temporada activa devuelve 60 Gems (`skipRefundGems`): es un caso raro, pero conviene confirmar que te parezca bien.
- Traducciones de los 10 idiomas que no son en/es: revisar con hablantes.
- Siguen los pendientes de la ronda 1 que no eran código puro (iconos, materiales de estructuras, sombras de toasts, opción "Automático" en idioma).

## Ronda 3: ranuras de modelos

Sin Studio, igual que antes. Objetivo: poder soltar modelos 3D reales (Creator Store / Toolbox / IA de Studio) en el repo sin tocar código; el armado con partes queda de respaldo.

### Qué cambié

- `ki-warriors/assets/models/` (nueva, solo con `README.md`): Rojo la monta como `ServerStorage.ModelLibrary` en `default`, `test`, `showcase`, `showcase_low` y `showcase_touch` (`.project.json`). El README no molesta a Rojo (se ignora).
- `src/shared/ModelFit.luau` (nuevo, puro): escala para entrar en una caja (`fitScale`), lista de variantes `slot`, `slot_1`, `slot_2`... (`collectVariants`), elección determinística por posición (`pickVariant`) y regla de presupuesto (`withinBudget`).
- `src/server/World/ModelSlots.luau` (nuevo): `ModelSlots.spawn(slot, cf, targetSize, parent, fallback, opts?)`. Si hay modelo: lo clona, **borra todos los scripts y avisa**, ancla, ajusta colisión (`opts.collide`, igual que el primitivo), lo escala parejo (`ScaleTo` / `Size`) y lo apoya con la base en `cf`. Si no hay, o pasa el tope de partes, o no hay presupuesto, llama al `fallback` sin cambios.
- `WorldBuilder.luau`: helper `slot(...)` (cadena específica > genérica, tope de partes por ranura, suma las partes del modelo a `partCount`, y consume los mismos draws del `Random` para que el layout no cambie). 14 ranuras: `tree`, `pine`, `cactus`, `rock`, `bush`, `tower`, `totem`, `ki_crystal`, `warp_gate`, `floating_island`, `boss_statue` (+ `boss_<id>`), `master`, `altar_monolith`, `landmark` (+ `landmark_<tema>`). Tabla y tamaños en `docs/modelos/ki-warriors.md`.
- Cliente: todo el mundo se construye en el server, así que la biblioteca es solo de ServerStorage (decisión documentada).
- No toqué geometría de juego (coliseo, zonas de entrenamiento, suelo, montañas, lagos, prompts/portal/estrella).
- `tests/modelfit_check.luau` (nuevo, puro).

### Cómo lo verifiqué

Desde `ki-warriors/` con `PATH=/tmp/tools:$PATH`:
- `rojo build` de `default`, `test`, `showcase`, `showcase_low`, `showcase_touch`: OK con la carpeta solo con README (el README no aparece en el `.rbxlx`).
- `rojo sourcemap` + `luau-lsp analyze src`: 0 líneas.
- Tests puros: los 7 pasan (`modelfit_check.luau` nuevo: fit, variantes, picker determinístico y repartido, presupuesto).
- Prueba del swap: armé un `tree.rbxmx` temporal (Model con una Part y un Script), compilé y confirmé que aparece `ServerStorage.ModelLibrary.tree` con sus hijos; lo borré.
- Con la biblioteca vacía el camino es el `fallback` original; conservé el orden de los draws de `Random` y de `vary`, así que el mundo y `PartCount` no cambian (no lo pude correr).

### Qué mirar en Studio

1. Con la carpeta vacía: el mundo igual que antes (mismo `PartCount` en el atributo de `World`) y el AutoTest (`test.project.json`) sin cambios.
2. Soltar un `tree.rbxm` de prueba: que se apoye en el piso (no flote ni se hunda), que entre bien en 9x15 studs, que no haya colisión, y que los scripts se borren con el warning en Output. Probar `tree_1`/`tree_2` para ver el reparto por posición.
3. `warp_gate`: que el anillo quede de frente al jugador que viene del centro de la plaza y que el disco del portal quede dentro del aro (si el modelo mira para otro lado hay que rotarlo en Studio antes de guardarlo).
4. `boss_statue`: está detrás del arena, a 0.72 del radio; revisar que no tape la pelea ni esté fuera de los pilares.
5. `master`: el orbe queda invisible (la etiqueta y su luz se mantienen). Revisar que el modelo mire hacia los jugadores.
6. `landmark*`: los modelos son enormes; probar con Streaming y que los ajustes de `LANDMARK_BOX` en `WorldBuilder` (tamaños y `lift`) queden bien.
7. Si un modelo entra con el tamaño chico/grande, se ajusta la caja en la tabla de ranuras (`targetSize` en el código de cada prop).

### Pendiente

- Elegir y bajar los modelos (hoy no hay ninguno: no inventé ids).
- Los props que dependen del color del tema (cristales, hongos/shards, pilones, lollipops) siguen primitivos: un modelo no se tiñe. Si hace falta, agregar ranuras por tema.
- Si se usa un landmark de modelo, el `Random` de las nubes del cielo del planeta queda corrido (el landmark original consume draws que no se compensan); solo cambian las nubes.

## Ronda 4: UI arreglada con la vista previa

Todo verificado con `tools/uipreview` (PNG/txt regenerados en `docs/previews/ki-warriors/`, `--all` + laptop + tablet). Estado final: PC y laptop 0 hallazgos; celular HUD 0 hallazgos (new y mid); tablet 0; ventanas en celular solo quedan hallazgos `low/med` de `core-overlap` (el contenido scrolleable de una ventana modal pasa por la zona del joystick, se puede scrollear) y nada `high`. 0 errores de runtime.

### Qué arreglé
- **Escala táctil** (`UI/Root.luau`): en táctil la escala ahora es `clamp(min(X/860, Y/365), 0.75, 1.1)` (~0.85 en un iPhone apaisado, antes ~0.6). Expone `Root.area` (espacio útil en unidades de diseño), `Theme.minText = 13` (texto escalado nunca baja de ~11 px reales) y `Theme.minButtonH = 52` (botones >= 44 px reales). PC sin cambios.
- **Theme** (`Theme.luau:~122` `Theme.text`, `Theme.button`): usan esos mínimos.
- **HUD táctil reordenado** (`UI/Hud.luau`): los toggles Auto pasaron a una fila propia de 3 píldoras de 53 px bajo las barras (icono + ON/OFF; el nombre completo no entra en todos los idiomas); el dock de entrenamiento queda solo con los 5 slots (58 px) + pesas + línea de tasa; zona y barra de jefe más angostas y debajo.
- **Objetivo** (`UI/QuestTracker.luau`): arriba a la derecha, título en 2 líneas, barra de 20 px, alto 54 px reales; la pista del tutorial debajo.
- **Menú** (`UI/Menu.luau`): en táctil es una fila horizontal abajo, entre el joystick y los botones de combate (antes debajo del joystick); botones de 44 px; los bloqueados no dejan huecos (UIListLayout); submenú en grilla de 2 columnas que abre hacia arriba; los badges ya no quedan tapados por el botón vecino (ZIndex decreciente).
- **Botones de combate** (`UI/TouchControls.luau`): `LAYOUT` ahora en px desde la esquina inferior derecha (todos >= 44 px, fuera de la zona del salto), semillas en fila sobre el menú; en tablet el cluster se corre a la izquierda/arriba con la escala.
- **Eventos** (`UI/EventsHud.luau`): en táctil van arriba al centro, 2 chips por fila (antes tapaban Volar/Forma).
- **Ventanas** (`UI/Windows.luau`, `UI/Kit.luau`, `Panels1/2`): en táctil se achican para entrar en el área útil y quedan pegadas arriba (medallón y X ya no pisan la barra de Roblox); botones de las filas >= 52 px (la fila crece); CodeBox y grilla de idiomas también. X de la ventana ya no choca con los toggles.
- **Plurales** ("1 Ascensions"): claves nuevas `ascend.count_one` y `forms.need_asc_one` en los 12 idiomas; `Panels1.luau:176` y `:62` eligen según n == 1.

### Qué queda
- Celular: el contenido scrolleable de ventanas largas pasa por debajo de la zona del joystick (solo al scrollear).
- Con 3-4 eventos activos a la vez, la segunda fila de chips puede tapar un poco la barra de jefe (no son botones).
- Teléfonos de menos de ~700 px útiles: la escala baja a 0.75 y el centro del HUD queda justo.
- Shop/Invite: mucho espacio vacío en PC (sin cambios; depende de productos reales).

### Qué confirmar en Studio
- Escala real en un teléfono (emulador de dispositivo, y `Workspace.ForceTouchLayout`): posición real del joystick/salto vs. la fila del menú y el cluster.
- `UIScale` en el holder: que el `Position` en offset no se escale (la herramienta asume que no).
- Íconos 💪/🔋/⚔️ de los toggles Auto (si se sube el pack, agregarlos a `Glyphs`).
- `UIListLayout.Wraps` en los chips de eventos.

Nota de herramienta: el chequeo `core-overlap` marca el área completa del joystick aunque el joystick dinámico real solo aparece donde se toca.
