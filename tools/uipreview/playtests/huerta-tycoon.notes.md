**Hallazgos reales**

1. **Regalos por minutos de sesión farmeables reentrando** (diseño, baja/media): `giftsClaimed` vive en la sesión (`src/server/Services/Session.luau:70`) y no se guarda en el perfil; `Config.PlaytimeGifts` se reclama de nuevo después de reentrar.
2. Los pases y productos de `Config.GamePasses/DevProducts` tienen `id = 0` (tienda apagada en el repo); el playtest les pone ids falsos para probar el flujo de compra. Con eso: pases y productos concedidos una vez, recibo reenviado con el mismo `PurchaseId` sin conceder dos veces y recibo tardío para un jugador que ya salió -> `NotProcessedYet`.

**Sin errores de Luau ni advertencias** en 10 min (nuevo y mid): el loop de comprar semillas, plantar todas las tiles, esperar el crecimiento, cosechar, ir al puesto de venta con el propio `Teleport.toSellStand()` del cliente y vender, comprar tiles y mejoras, y volver a entrar (perfil idéntico) funcionó siempre. Con el estado `mid` el bot llega a rebirth.

**Qué no se pudo ejercitar**: el clima y los eventos en vivo corren (sin errores) pero el bot no los usa; el Wild Patch (nodos de la zona salvaje) y los trofeos/exhibiciones no están en el bot. Auto-farm queda bloqueado en el estado `new` (se prueba que se rechaza el pedido sin Farmhand).
