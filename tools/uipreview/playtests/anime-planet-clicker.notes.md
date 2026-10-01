**Hallazgos reales**

1. **Regalos por minutos de sesión farmeables reentrando** (diseño, baja/media): `State.giftsClaimed` es por sesión (`src/server/Services/State.luau:42`) y no está en el perfil; `Config.Gifts` se puede volver a reclamar después de salir y entrar (el bot lo comprueba).
2. Los pases/productos de `Config` tienen `id = 0` (tienda apagada en el repo); el playtest les pone ids falsos solo para probar el flujo de compra. Con eso: recibos concedidos una sola vez aunque se reenvíen, y la compra cancelada no cambia nada.
3. Los paquetes "minutos de minado" (`StardustSmall/Medium/Large`, 30/180/720 min) se pagan con el ingreso ideal por segundo (`Formulas.income`); para un jugador de 5 minutos con pico de titanio los tres paquetes valen ~14 millones de stardust, que es lo que el bot mina en ~10 horas reales... pero coincide con su ritmo real de minado (≈15-19 mil por minuto) × 930 min, así que no hay inconsistencia: solo es una compra que salta mucho el progreso (herramientas de la galaxia 2: 170 mil, 18 millones). Para revisar si es lo deseado en la economía.

**Sin errores de Luau ni advertencias** en 10 min (nuevo y mid). El perfil se guardó y se recargó idéntico (incluido un dron de carga en vuelo al salir: `Mining.forget` lo aterriza antes de guardar).

**Qué se probó**: tutorial completo (minar, romper el núcleo, vender caminando al Refinery, abrir cápsula, comprar herramienta, activar Auto Mine), minado con `Miner.simulate` (el mismo camino que un click), cápsulas, mejoras, regalos, misiones, todas las ventanas, ajustes de auto, idiomas, compras, rejoin. Rebirth y galaxias lejanas no se alcanzan en 10 min.
