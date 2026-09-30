# Handoff: Sky Tower Obby (obby-sky-tower)

Sesión en la nube, sin Studio. **No vi nada corriendo**: todo lo que sigue está verificado con build, chequeo de tipos y tests puros, no jugando. No commiteé.

## Qué cambié

### Bugs reales del rediseño de 1000 niveles

- **El botón "Lobby" del teletransportador te borraba el progreso.** `Travel` con destino 0 guardaba `stage = 0`: alguien en el nivel 850 que tocaba "Lobby" volvía al 0 (y se guardaba). Ahora va al lobby y **conserva el checkpoint**.
  `src/server/Lounge.luau`, `src/server/Checkpoints.luau` (`travel` rechaza el 0 y manda al lobby).
- **Se podían farmear Wins y el bonus de cumbre.** Con el teletransportador ibas al mundo 91-100, subías 10 niveles y te daba Win +1 y 250 monedas. Podías repetirlo sin límite, con rebirth en el medio, e inflar el ranking de Top Wins. Ahora cada cumbre paga **una vez por run**: campo nuevo `profile.runTop`, regla pura `Rules.summitRewarded`. El rebirth lo resetea. Teletransportarte debajo de una cumbre renuncia a esa cumbre hasta el próximo rebirth. Los regalos siguen siendo una vez en la vida, igual que antes.
  `src/shared/Rules.luau`, `src/server/Checkpoints.luau`, `src/server/Data.luau`.
- **Migración de saves viejos:** si falta `runTop`, se completa con la última cumbre por debajo del nivel guardado (`Rules.runTopFromStage`). No se borra nada. También agregué una defensa por si `settings` viene corrupto.
  `src/server/Data.luau`.
- **Un portal viejo podía mandarte para atrás.** Pasar volando con el planeador/nube, o subir la torre 1 a pie desde el lobby, y rozar el portal de la cumbre 100 te dejaba en el nivel 100 aunque estuvieras en el 850. Ahora el portal **por contacto** se ignora en modo explorar o si tu checkpoint está más arriba (`Rules.portalTouchAllowed`). El prompt y el botón del HUD siguen andando.
- **Ranking "Fastest Climb":** un power-up comprado y ya vencido antes de arrancar desde el nivel 0 marcaba la run como asistida para siempre. Ahora, al salir del 0, solo cuenta lo que sigue activo. `src/server/Checkpoints.luau`.

### Problemas conocidos

- **Botones de prueba de Studio ("SALTAR NIVEL (prueba Studio)").** Ahora necesitan **Studio Y un flag**:
  - `Config.StudioFreeSkips` ahora es `false` por defecto.
  - El atributo de Workspace `StudioTestTools` solo lo pone `test.project.json`.
  - El server lo decide (`Session.studioTools` → `Rules.studioTools`) y el cliente además chequea su propio `RunService:IsStudio()`.
  - Un playtest normal en Studio ya se ve como el juego publicado, y el publicado nunca los muestra.
  - Archivos: `src/shared/Config.luau`, `src/shared/Rules.luau`, `src/server/Session.luau`, `src/server/Checkpoints.luau`, `src/client/UI/Hud.luau`, `src/client/UI/Prompts.luau`, `test.project.json`.
- **Personaje "desarmado" en el spawn del lobby.** No lo pude reproducir. Arreglé la causa más probable que encontré en el código:
  - Las piezas soldadas al personaje (mascota nube del regalo 200, corona del 1000) se soldaban a Head/Torso **antes** de que terminara de cargar el avatar. Si la apariencia reemplazaba esas partes, las piezas quedaban sueltas y se caían.
  - Ahora se espera `CharacterAppearanceLoaded` (máximo 8 s) y se re-aplican si cambia Head/Torso.
  - Las piezas se sueldan antes de meterlas en el personaje.
  - Los avatares altos (HipHeight grande) se levantan para no aparecer con los pies dentro del pad o del spawn.
  - Archivos: `src/server/init.server.luau`, `src/server/Cosmetics.luau`, `src/server/Checkpoints.luau` (`teleport`).

### Íconos

- `Kit.icon(parent, emoji, ...)` en `src/client/UI/Kit.luau` es el único lugar donde se dibujan íconos:
  - Si el emoji tiene ícono en el pack **y** ese ícono tiene id, sale un `ImageLabel` con `ScaleType Fit`.
  - Si no, sale el emoji exactamente como hoy.
  - `Kit.coin` usa el ícono `coin` cuando exista.
- El mapa emoji → ícono está en `Icons.GLYPHS` / `Icons.forGlyph`, en `src/shared/Icons.luau`, fuera del bloque que genera el script de subida.
- Lo usan los botones del menú, el contador de wins, los chips de power-ups y la tienda de Robux (`Hud.luau`, `StorePanel.luau`).
- Hoy todos los ids están vacíos, así que **no cambia nada visible** hasta subir los íconos.

### Look

- Materiales por mundo en `Scenery.dressPlatform` (`src/server/Scenery.luau`):
  - Toxic Factory: tapa de metal.
  - Cloud Kingdom: plataformas de mármol.
  - Neon Space: losas de pizarra oscura con la tapa en Neon (antes toda la losa era Neon).
  - No agregué partes.
- HUD: las pastillas "glass" tienen un brillo en degradé en vez de relleno plano (`Hud.luau`).
- Los kill bricks ya eran Neon rojo con pulso y la iluminación por altura ya existía. No los toqué: ForceField en un peligro me pareció riesgoso para la lectura sin poder verlo.

### Docs y tests

- `DESIGN.md` actualizado (runTop, teletransportador, flag de Studio).
- `tests/rules_test.luau` tiene +33 checks (cumbres una vez por run, migración, portal por contacto, flag de Studio).
- `tests/icons_test.luau` es nuevo.
- `tests/AutoTestClient.client.luau` tiene un check nuevo: "Lobby" del teletransportador conserva el checkpoint.

## Cómo lo verifiqué

Desde `obby-sky-tower/`, con `PATH=/tmp/tools:$PATH`:

- `rojo build default.project.json` → OK. `rojo build test.project.json` → OK.
- `luau-lsp analyze ... src` → **0 errores** (igual que al empezar).
- Tests puros:

| Test | Checks | Resultado |
|---|---|---|
| layout_test | 144843 (incluye alcance físico del salto) | 0 fallas |
| rules_test | 3569 (antes 3536) | 0 fallas |
| visual_test | 12942 | 0 fallas |
| locale_test | 9780 | 0 fallas |
| p0_test | 48 | 0 fallas |
| icons_test (nuevo) | 82 | 0 fallas |

No toqué salto ni dificultad: JumpPower 50 y la curva quedaron como los dejó el rediseño.

## Qué hay que mirar en Studio

1. **Personaje en el lobby:** darle Play con tu avatar, y también con uno alto/Rthro. ¿Sigue "desarmado"?
   - Si sigue, sacá captura del Explorer del personaje (qué partes hay sueltas) para saber si viene de otro lado.
   - Con el regalo 200 o 1000 (usá el test project): ¿la nube y la corona quedan pegadas?
2. **Playtest normal:** no tiene que aparecer ningún botón "(prueba Studio)". Con `test.project.json` sí.
3. **Teletransportador del Lounge → "Lobby":** te lleva al lobby y "Volver al checkpoint" te devuelve donde estabas.
4. **Cumbre 100:** subí limpio y verificá Win +1. Después teletransportate al mundo 10 (nivel 90) y subí a 100: **no** tiene que sumar Win. Hacé rebirth y subí de 0 a 100: sí suma.
5. **Mundos 7, 8 y 9 (niveles 61-90):** ¿se leen bien las plataformas con los materiales nuevos? Neon Space con tapas Neon puede encandilar con bloom. Si molesta, sacá la línea `[9]` de `CAPS` en `Scenery.luau`.
6. **AutoTest completo** (`test.project.json`): no lo pude correr. Ahí están los presupuestos de partes por torre (≤ 7200), luces, fps, etc. **El conteo real de partes en torres altas no está medido.**

## Pendiente

- **Subir los íconos** (`tools/icons/upload_assets.py`). Hasta entonces el HUD sigue con emojis.
- **No medí partes ni rendimiento de las torres 2-10** sin Studio. Lo cubre el AutoTest.
- **Crear los productos/pases/badges** y pegar los IDs en `Config.luau`. Con IDs en 0, Skip no se vende.
- **Detalles menores que no toqué:**
  - El evento `Win` de la torre 1 igual se dispara en una cumbre que ya no paga. Muestra el panel con el mismo total de wins.
  - Las monedas por nivel se vuelven a pagar al re-subir después de teletransportarte y reconectar. Es lo mismo que pasa con rebirth.
- `SkyTowerObby.rbxlx`, dentro de la carpeta del juego, es un build viejo. No lo regeneré.
