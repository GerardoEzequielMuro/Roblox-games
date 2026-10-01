# CONTINUAR: traspaso para la próxima sesión de Claude Code

Este documento es para la sesión de Claude Code que retome el trabajo. Leelo entero antes de tocar nada. El detalle histórico está en `HANDOFF.md` (rondas 1 a 6) y en `docs/handoff/<juego>.md` (las 10 rondas, juego por juego).

## 1. Estado del repo

- **Repo:** `GerardoEzequielMuro/Roblox-games`. El trabajo de la sesión en la nube está en la rama **`claude/hello-iselsx`**, todavía **sin mergear a `main`**.
- **En la PC de Gerar** (`C:\work\_Personal\proyectos`):
  ```powershell
  git fetch origin
  git merge origin/claude/hello-iselsx
  ```
- **Monorepo:** los 6 juegos son carpetas de este repo. Los `.git` viejos de cada juego están en `C:\work\_Personal\_git-backups\`. Los hashes y los `git reset --hard <hash>` de `C:\work\_Personal\docs\ROBLOX-MEJORAS-NOCHE.md` **ya no aplican**.
- **Un solo commiteador:** los agentes no pueden commitear en paralelo (se pisa el `index.lock`). Que cada agente edite su carpeta y que uno solo verifique y commitee.

| Carpeta | Juego | Qué es |
|---|---|---|
| `huerta-tycoon` | Crop Kingdom | Tycoon de granja |
| `obby-sky-tower` | Sky Tower Obby | Obby de 1000 niveles en 10 torres |
| `pet-tap-simulator` | Tap Pets Simulator | Tap + huevos + mascotas |
| `anime-planet-clicker` | Planet Crackers | Picar planetas, mascotas, cápsulas, PvP |
| `ki-warriors` | Ki Warriors | Pelea y entrenamiento estilo Dragon Ball, con nombres propios |
| `ruleta-pvp` | Ruleta PvP | Party game de eliminación por rondas, **sin apuestas** |

Todos son proyectos Rojo en Luau: `src/client`, `src/server`, `src/shared`, `tests`, y `sim` en algunos.

## 2. Qué se hizo (10 rondas)

| Ronda | Qué | Dónde mirar |
|---|---|---|
| 1 | Pack de 46 íconos propios con integración en el HUD (con fallback a emoji), y bugs. El más grave: el Lobby del obby borraba el progreso. | `assets/icons`, `tools/icons/`, `src/shared/Icons.luau` |
| 2 | Precios en Robux basados en juegos reales, retención (rachas, eventos, pases de temporada) y descuentos honestos con test | `docs/research/top-juegos-y-precios.md` |
| 3 | 78 ranuras para modelos 3D (`assets/models/<ranura>.rbxm`; vacía = piezas actuales) | `docs/modelos/<juego>.md` |
| 4 | Vista previa del HUD sin Studio y HUD de celular arreglado en los 6 | `tools/uipreview/`, `docs/previews/` |
| 5 | Simuladores de ritmo de progresión y tuning. ki-warriors se terminaba en 90 min; ahora dura semanas. | `sim/pacing_sim.luau` de cada juego |
| 6 | Contenido para los baches: huevos, herramientas, cosméticos, XP del pase | `docs/handoff/<juego>.md` |
| 7 | Seguridad: unas 90 vulnerabilidades (remotes, recibos, DataStore, farmeo) | `tests/security_test.luau` |
| 8 | Primera sesión: tutoriales que no se traban, pantallas de carga, game feel | `tests/onboarding*` |
| 9 | Modo playtest: un bot juega N minutos en Roblox simulado | `docs/playtests/<juego>.md` |
| 10 | Arreglos de lo que encontró el playtest | ver la sección 4 |

## 3. Cómo verificar (hacelo después de cada cambio)

Desde la carpeta del juego:

| Chequeo | Comando |
|---|---|
| Compila | `rojo build default.project.json -o out.rbxlx` |
| Tipos (tiene que imprimir 0 errores) | `rojo sourcemap default.project.json -o sm.json`, después `luau-lsp analyze --definitions=@roblox=globalTypes.d.luau --sourcemap=sm.json src` |
| Tests puros | `luau tests\<test>.luau` y `luau sim\<sim>.luau`. Todos los que no terminan en `.server.luau` ni `.client.luau`. |
| Vista previa / playtest | desde la raíz: `python tools/uipreview/preview.py <juego> --all`, o `--playtest --minutes 10 [--state mid]` |

**Dónde están las herramientas:**
- Rojo: `huerta-tycoon\tools\rojo.exe`.
- `luau` y `luau-lsp`: https://github.com/luau-lang/luau/releases y https://github.com/JohnnyMorganz/luau-lsp/releases.
- `globalTypes.d.luau`: https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
- La vista previa necesita Lune (https://github.com/lune-org/lune/releases) y Python con `pillow cairosvg fonttools`. En la nube Lune estaba en `/tmp/tools/lune`: **revisá la ruta en `tools/uipreview/preview.py`** antes de correrla en Windows.

**Estado al cierre:** en los 6 juegos `rojo build` da OK, el chequeo de tipos da 0 errores y todos los tests puros pasan. El playtest de Studio (`tests/AutoTest*`, `test.project.json`) **nunca se corrió**, porque en la nube no hay Studio.

## 4. Lo que quedó a medio hacer (empezá por acá)

**Ronda 10, que se cortó en obby-sky-tower y ki-warriors** (commit `2385ccc`):

1. **obby-sky-tower: regalos por tiempo jugado farmeables con rejoin.**
   - `src/server/Session.luau:55` (`Session.playClaimed`) es solo de la sesión: saliendo y volviendo a entrar se cobran otra vez.
   - Ya existe el módulo puro `src/shared/PlayRewards.luau`, que guarda `{day, secs, claimed}` por día UTC, pero **no está conectado**.
   - Falta: guardarlo en el profile (`Data.luau`, con default seguro), usarlo en Session y Rewards, y agregar un test puro.
   - Así está hecho en `huerta-tycoon/src/shared/Gifts.luau` y `pet-tap-simulator/src/shared/GiftClock.luau`: copiá ese patrón.
2. **obby-sky-tower: monedas del recorrido recolectables otra vez tras rejoin.**
   - `Session.collected` (`Session.luau:54`, usado en `Obstacles.luau:147-160`) es solo de la sesión.
   - Existe `src/shared/CoinSet.luau`, pensado para codificar las recolectadas por etapa, **sin conectar**.
   - Falta: guardarlo en el profile, resetearlo solo con rebirth o run nueva, y agregar un test.
3. **ki-warriors: falta confirmar con el playtest.**
   - Ya están hechos, pero no confirmados: los regalos guardados en el profile (`State.luau`, `Rewards.luau`, `Data.luau`) y la pista del paso 13 del tutorial (requisito de 2.000 de poder con progreso, en los 12 idiomas).
   - El agente estaba haciendo que `GetState` espere a que cargue el profile.
   - Falta: correr `preview.py ki-warriors --playtest` (normal y `--state mid`) hasta que el veredicto dé ok, y agregar la sección "Ronda 10" a `docs/handoff/ki-warriors.md`.

## 5. Cosas que solo puede hacer Gerar (no las simules)

1. **Subir los íconos:**
   - Crear una API key de Open Cloud con permiso de Assets.
   - En PowerShell: `$env:ROBLOX_API_KEY`, `$env:ROBLOX_USER_ID`, y después `python tools/icons/upload_assets.py`.
   - Verificar en Studio que el ID funciona en un ImageLabel.
   - **Nunca guardes la key en un archivo del repo.**
2. **Crear los pases y productos en el Creator Dashboard.** Todos los IDs en `Config.luau` están en 0, así que hoy no se puede comprar nada.
3. **Modelos 3D:** guardarlos como `.rbxm` en `<juego>/assets/models/` según `docs/modelos/<juego>.md`.
4. **Decisiones pendientes:**
   - **Crop Kingdom:** el Starter Pack está a 15 R$ con un tachado de 49 que no es real. La investigación recomienda 29-49 R$.
   - **Tap Pets:** el pase "Secret Hunter" (1.299 R$) no se agregó porque roza el pay-to-win.
   - **ki-warriors:** nombres propios (la recomendación) o los de Dragon Ball (riesgo de DMCA). Todo está centralizado en `src/shared/Names.luau`.

## 6. Reglas aprendidas (respetalas)

- **Obby:** Gerar pidió explícitamente que sea **más difícil** y con salto más bajo. Nunca bajes la dificultad promedio. `tests/pacing_test.luau` falla si alguien lo hace más fácil.
- **Monetización:**
  - Ítems aleatorios pagos: odds en % antes de comprar, más `PolicyService.ArePaidRandomItemsRestricted`.
  - Sin estética de casino ni apuestas, sobre todo en `ruleta-pvp`.
  - Sin pay-to-win en PvP: en la arena se neutralizan los pases.
  - Todo lo pago que da poder también se gana jugando.
  - Precios tachados solo si son reales, con test.
- **No inventes asset IDs ni sound IDs.** Quedan vacíos o en 0 y el código hace no-op.
- **No uses marcas registradas** (Goku, Saiyan, etc.): usá `Names.luau`.
- **Costo:** Gerar se quejó del gasto. Para programar, agentes Sonnet; para tareas mecánicas, Haiku. Nunca 6 agentes Opus en loop. Cada ronda de 6 agentes Sonnet costó entre 10 y 20 USD aprox.
- **Studio:** cada `docs/handoff/<juego>.md` tiene listas de "Qué mirar en Studio". Lo que más valor agrega ahora es **correr el AutoTest de cada juego en Studio y arreglar lo que falle**, de a un juego. Recomendado: empezar por ki-warriors (`KiWarriors.rbxlx`).

## 7. Próximos pasos sugeridos, en orden

1. Terminar la ronda 10 (sección 4).
2. Playtest en Studio de los 6 juegos y arreglar lo que aparezca.
3. Tareas de Gerar (sección 5), sobre todo pases e íconos.
4. Más contenido después de las primeras horas, guiado por `sim/pacing_sim.luau`.
5. Publicar uno (ki-warriors o Tap Pets) y medir retención real con analíticas antes de seguir puliendo a ciegas.
