# Crop Kingdom — publicar y promocionar

## 1. Publicar (≈10 min, lo tenés que hacer vos: es tu cuenta)
1. Abrí `CropKingdom.rbxlx` en Roblox Studio → **File → Publish to Roblox** → "Create new experience".
   - Nombre: **Crop Kingdom 🌱 [WEATHER!]** · Género: Simulation · Dispositivos: todos.
2. **Game Settings → Security → Enable Studio Access to API Services = ON** (sin esto no se guarda el progreso).
3. **Game Settings → Places → Max players = 6** (hay 6 parcelas por servidor).
4. Creator Dashboard → tu experiencia → **Monetization**:
   - **Passes** (crear y poner en venta): 2x Cash (249 R$), Auto Harvest (199), Sell Anywhere (149), VIP (399), Super Luck (299), Big Basket (99).
   - **Developer Products**: Cash Pouch (49), Cash Chest (199), Instant Grow (79), Restock Shop (39), Lucky Seed Pack (99),
     **Starter Pack (15)** (oferta única de las primeras 24 h, precio de impulso: tachado 49 → −70%; contenido fijo, sin
     ítems al azar; con `id = 0` no aparece).
   - **Ítems al azar pagos** (reglas de Roblox del 26/05/2026): el Lucky Seed Pack y el pass Super Luck muestran sus
     probabilidades en el panel "Chances" y se ocultan solos en los países donde están restringidos (`PolicyService`).
     No hace falta configurar nada.
   - **Anuncios con recompensa**: creá un developer product "AdRestock" (cualquier precio, es solo la recompensa) y poné
     su ID en `Config.AdProducts`. Requisitos de Roblox: 2.000 visitantes únicos por mes, verificación de ID + 2FA y el
     cuestionario de madurez. Con `id = 0` el botón de video no aparece.
   - Copiá cada ID en `src/shared/Config.luau` (`id = 0` → el número) y volvé a construir: `tools\rojo.exe build default.project.json -o CropKingdom.rbxlx`, abrir y Publish de nuevo. (O pasame los IDs y lo hago yo.)
5. Icono y thumbnails: los genero yo con capturas del juego cuando no estés usando la PC.
6. **Grupo** (gratis): crealo y poné su ID en `Config.GroupId` → +10% de cash a miembros + regalo único al unirse (botón en "Invitar").
7. **Admins de eventos**: tu UserId en `Config.AdminUserIds` → en el chat `/event HarvestFestival 30` arranca el evento en
   todos los servidores (máx. 60 min). El Harvest Festival además corre solo cada sábado 18:00 UTC.
8. Público: **Settings → Public**. Los **Creator Rewards** son automáticos: pagan por usuarios que gastan y juegan 10+ min,
   y 35% de lo que gasten los que traés con tu share link o invitaciones (el juego ya manda `ref:<tuUserId>` y premia a los dos).

   - Primera línea de la descripción de la experiencia: **"EARNS WHILE OFFLINE 🌱"** (los cultivos crecen hasta 24 h
     con el juego cerrado). Es lo que abren los tycoons que están arriba hoy.

   - **Sonido**: el juego sale mudo. Pegá IDs de audio de Roblox en `Config.Sounds` (click, harvest, harvestRare, sell,
     error, fanfare, music) y reconstruí; con `0` ese sonido no suena. Todo pasa por `src/client/UI/Sound.luau`.
   - **Semillas por Robux** (opcional): un developer product por semilla en `Config.SeedProducts` agrega un segundo
     botón violeta en esa fila de la tienda. Con `0` no aparece.

## 2. Cómo gana plata
- Game passes y productos (70% para vos, 30% Roblox).
- Creator Rewards: 5 R$ por usuario que gasta si tu juego es de los 3 primeros que abre en el día y juega 10+ min, y 35% del gasto de los usuarios que traés con tu share link. Por eso conviene poner el share link en cada TikTok. Los regalos por tiempo de juego (5–60 min) empujan justo esas sesiones de 10+ min.
- DevEx: a partir de 30.000 R$ ganados, verificado con ID, ~US$ 0,0038/R$.

## 3. TikTok orgánico (0 pesos)
Cuenta nueva, a tu nombre, 1–3 videos por día los primeros 14 días. Formato vertical, 12–25 s, gancho en el primer segundo, texto grande en pantalla, audio en tendencia.

| # | Gancho (texto en pantalla) | Qué se ve |
|---|---|---|
| 1 | "I left my garden in a THUNDERSTORM… ⚡" | Tormenta, cultivos que se vuelven Shocked (x8), venta enorme |
| 2 | "0.1% chance… RAINBOW pumpkin 🌈" | Cosecha de mutación Rainbow, "+$" gigante |
| 3 | "Day 1 vs Day 7 in Crop Kingdom" | Parcela vacía → parcela llena de árboles y mutaciones |
| 4 | "POV: the shop restocked a MOON MELON" | Toast de stock raro, corrida a la tienda |
| 5 | "Rebirthing with $1,000,000,000" | Botón de rebirth, multiplicador |
| 6 | "Rating every seed in Crop Kingdom" | Pasar por la tienda comentando cada semilla |
| 7 | "Golden Hour = free money 🤑" | Evento Golden Hour, cultivos dorados |

**Caption base:** `this weather event is broken 😭 #roblox #robloxgame #growagarden #robloxsimulator #fyp`
**Horarios:** 18–22 h de EE.UU. (19–23 h de Argentina), cuando más juega el público de Roblox.
**Regla:** a la 1 h de subido, si tiene <300 vistas no pasa nada; repetí el gancho que mejor anduvo con otro clip.

### Otras vías gratis
- **YouTube Shorts**: los mismos videos (suele rendir más para Roblox que TikTok).
- **Roblox Talent Hub / DevForum → "Game Design Support"**: pedir feedback atrae los primeros jugadores.
- **Códigos** (`Config.Codes`): anunciá uno nuevo en cada video ("code in comments") para empujar comentarios, que es la señal que más pesa en TikTok.
- **Grupo de Roblox** (gratis): poné su ID en `Config.GroupId` → +10% de cash a los miembros = los jugadores se suman solos.

## 4. Métricas para mirar (Creator Dashboard → Analytics)
- **D1 retention** > 10% y **tiempo de sesión** > 12 min → el juego funciona, vale escalar.
- **Conversión de pagadores** > 1% → los precios están bien.
- Si D1 < 5%: hay que cambiar los primeros 5 minutos (tutorial, primeras semillas).
