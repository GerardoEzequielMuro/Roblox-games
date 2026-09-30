# Spin Showdown: lanzamiento

Lo que sigue solo lo puede hacer Gerar (son sus cuentas). Nada de esto está hecho todavía.

## 1. Publicar

1. Abrir `SpinShowdown.rbxlx` en Studio → **File → Publish to Roblox As…** → experiencia nueva.
2. **Game Settings → Security → Enable Studio Access to API Services = ON**. Sin esto no guarda
   progreso (el juego anda igual y avisa que no guarda).
3. **Game Settings → Basic Info**: nombre "Spin Showdown" (alternativas: "Wheel of Splat",
   "Last Spin Standing"). Género: Party & Casual. Jugadores máximos: **16**.
4. Cuestionario de madurez: marcar violencia caricaturesca leve. **No** marcar apuestas: no hay
   contenido de apuestas ni decorado de casino (ver "Policy" en `DESIGN.md`).
5. Descripción sugerida (en inglés):
   > Spin the wheel, zap your friends, be the last one standing! Pick a target, play a card,
   > hit the BRAKE at the right moment. Classic, Chaos, Teams and 1v1 duels. Bots fill the
   > table so there is always a match. Codes: SHOWDOWN, WELCOME.

## 2. Tienda (Creator Dashboard → Monetization)

Crear cada uno, copiar el ID y pegarlo en `src/shared/Config.luau` (`Config.Passes` /
`Config.Products`, campo `id`). Después `rojo build` y volver a publicar. Con ID 0 el ítem
no se puede comprar.

| Pass | R$ |
|---|---|
| VIP | 299 |
| Double Coins | 199 |
| Legend Skins | 199 |
| Finisher Pack | 149 |
| Emote Pack | 99 |
| Auto Charge | 99 |

| Producto | R$ |
|---|---|
| Coin bag (1.000) | 49 |
| Coin sack (2.500) | 99 |
| Coin vault (7.500) | 249 |
| Coin mountain (18.000) | 499 |
| Coin treasury (40.000) | 999 |
| Season pass: Premium (producto, se compra una vez por temporada) | 399 |
| Season tier skip (producto) | 39 |
| Starter Pack | 49 |
| Server party | 25 |

No agregar cajas, giros pagos ni boosts de suerte sin leer "Policy" en `DESIGN.md`: eso
convierte al juego en "paid random items" y exige probabilidades en pantalla y `PolicyService`.

## 3. Otros datos para `Config.luau`

- `Config.AdminUserIds = { <tu UserId> }` para usar `/event DoubleXP 30` en el chat.
- `Config.GroupId = <id del grupo>` para el regalo por unirse al grupo (400 monedas).
- `Config.Audio`: IDs de música (`lobby`, `match`, `sudden`, `win`) y efectos. Tienen que ser
  audios tuyos o con licencia para Roblox. Hoy solo suenan los que trae el cliente (tics,
  golpes); la música está en silencio.

## 4. Lo que no pude hacer sin assets

- Ícono y thumbnails (hay que subirlos). Ideas: la rueda desde arriba con el puntero sobre
  💀, tres avatares con cara de susto, fondo violeta con luces. En el thumbnail, el momento
  del martillo.
- Música y sonidos propios.

## 5. Primer día

1. Jugar una partida completa desde el celular (el layout táctil está probado solo con la
   simulación de Studio).
2. Entrar con una segunda cuenta para probar un duelo por desafío y una mesa privada con
   código: en Studio eso se probó con un jugador suplente, no con dos clientes reales.
3. Revisar que el progreso se guarde al salir y volver.
4. Probar una compra de cada pass y producto.

## 6. Ideas de videos (TikTok / Shorts)

1. **"Frené en el último pixel"**: primer plano de la rueda arrastrándose hacia 💀 y
   quedándose en el casillero de al lado. Texto: "casi".
2. **"1 vida contra 4"**: remontada en muerte súbita, con el borde rojo.
3. **Los 8 finishers** en 15 segundos, uno atrás del otro, y "¿cuál es el mejor?".
4. **Carta Pass en el momento justo**: pasarle el giro a un amigo y que le salga Backfire.
5. **"Le hice Doom a mi mejor amigo"**: reacción a cámara + el OVNI llevándoselo.
6. **Blackout**: ronda con los casilleros ocultos, nadie sabe qué va a salir.
7. **Código nuevo** en cada video (`Config.Codes`): trae comentarios y gente al juego.

Poner el share link del juego en cada video (Creator Rewards paga por los usuarios nuevos que
entran por ahí).

## 7. Sin verificar (necesita el juego publicado)

DataStores reales, tablas de ranking entre servidores, compras, referidos entre servidores,
eventos entre servidores (`MessagingService`), invitaciones, notificaciones, touch en un
celular real, dos clientes reales en la misma mesa. Las traducciones a 11 idiomas conviene
que las lea un nativo.
