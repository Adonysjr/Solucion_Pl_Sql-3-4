# Firmas acordadas para la simulación integrada (Evaluación parcial 2)

Cada package existente recibe **dos procedimientos públicos nuevos**, declarados en la
especificación e implementados en el cuerpo. No se mueve lógica al coordinador: cada módulo
sigue haciendo sus cálculos y validaciones con sus propios componentes.

| Package | `proc_simular` | `proc_reporte` |
|---|---|---|
| `PKG_INTEGRACION_EXTERNA` | `(p_id_local IN, p_id_canal IN, p_id_cliente IN, p_id_pedido OUT)` | `(p_id_pedido IN)` |
| `PKG_MESAS` | `(p_etapa IN VARCHAR2, p_id_local IN, p_id_mesa IN, p_id_empleado IN, p_id_pedido IN OUT)` | `(p_id_pedido IN)` |
| `PKG_STOCK_RECETA` | `(p_id_pedido_a IN, p_id_pedido_b IN)` | `(p_id_pedido_a IN, p_id_pedido_b IN)` |
| `PKG_GESTION_KDS` | `(p_id_local IN, p_id_pedido_a IN, p_id_pedido_b IN)` | `(p_id_pedido_a IN, p_id_pedido_b IN)` |
| `PKG_MERMA` | `(p_id_local IN)` | `(p_id_local IN)` |
| `PKG_FACTURACION` | `(p_id_pedido_a IN, p_id_pedido_b IN)` | `(p_id_pedido_a IN, p_id_pedido_b IN)` |

Tipos: usar `%TYPE` de la columna correspondiente (`LOCAL.id_local%TYPE`, `PEDIDO.id_pedido%TYPE`,
`CANAL_VENTA.id_canal%TYPE`, `CLIENTE.id_cliente%TYPE`, `MESA.id_mesa%TYPE`, `EMPLEADO.id_empleado%TYPE`).
`p_etapa` solo acepta `'ABRIR'` o `'CERRAR'`.

## Reglas para todos

1. **Sin `COMMIT` ni `ROLLBACK`** dentro de `proc_simular` ni de `proc_reporte`. La transacción la
   maneja el bloque anónimo final: `COMMIT` si todo sale bien, `ROLLBACK` si algo falla.
2. **Si algo sale mal, `RAISE`.** El coordinador detiene la simulación en ese paso. No capturar el
   error "para seguir": un pedido a medias es peor que ninguno.
3. `proc_reporte` **solo consulta** (`SELECT`/`DBMS_OUTPUT`). No vuelve a simular ni modifica datos.
4. Mensajes con `DBMS_OUTPUT.PUT_LINE`, sin IDs fijos de pedidos: los IDs llegan por parámetro.
5. Datos comunes: local `1`, canal Rappi `3`, cliente `1`, mesa `3` (id_mesa 3), empleado `1` (garzón).
   Pedido A (delivery): hamburguesa clásica (producto 1) + papas fritas (producto 4) = **$12.400**.
   Pedido B (salón): pollo grill (producto 2) + bebida cola (producto 5) = **$13.700**.

## Qué hace cada uno (orden de llamada en `PKG_SIMULACION.proc_simular`)

1. **Integración** registra el pedido Rappi con identificador externo nuevo
   (`'SIM-RAP-' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF3')`, nunca un literal fijo), agrega los dos
   productos, comprueba 2 detalles, total $12.400 y estado PENDIENTE, y devuelve el ID por `OUT`.
   Ojo: `proc_registrar_pedido_externo` y `proc_agregar_detalle_pedido` capturan sus errores y solo
   imprimen, así que `proc_simular` debe comprobar que el ID no quedó NULL y que el total cuadra;
   si no, `RAISE_APPLICATION_ERROR`.
2. **Mesas (`'ABRIR'`)** comprueba que la mesa está libre, inserta el pedido de salón (estado 1,
   canal 1, con `id_mesa` y `id_empleado`), deja que `trg_ocupar_mesa` la ocupe, agrega los dos
   detalles y actualiza `PEDIDO.total` (= $13.700), y devuelve el ID por `IN OUT`.
   Como `pkg_mesas` no tiene procedimiento para agregar detalles, se sugiere un **procedimiento
   privado** en el cuerpo (insert en `DETALLE_PEDIDO` + `UPDATE PEDIDO SET total`), para no depender
   de `PKG_INTEGRACION_EXTERNA`.
3. **Stock** valida existencias de todos los insumos y confirma A y luego B con `sp_confirmar_pedido`
   (9 movimientos SALIDA en total). Ya corregido: valida todo antes de descontar y rechaza doble
   confirmación.
4. **KDS** muestra espera, preparación y prioridad de A y B, ejecuta `proc_gestionar_kds(1)`,
   comprueba que los 4 detalles quedaron PREPARANDO, recorre pedido → detalles llamando
   `proc_marcar_detalle_listo` y comprueba que `trg_actualizar_pedido_listo` dejó ambos en LISTO (3).
5. **Merma** registra 50 GR de lechuga (insumo 5) por «Deterioro durante almacenamiento» y comprueba
   stock antes/después, el movimiento MERMA y el KPI del día. Listo.
6. **Facturación** verifica totales, `sp_registrar_pago` A ($12.400, medio 5) y B ($13.700, medio 2),
   `sp_emitir_boleta` por pedido guardando los IDs, `sp_actualizar_estado_dte` a ACEPTADA, y
   comprueba 2 pagos y 2 boletas.
7. **Mesas (`'CERRAR'`)** comprueba que B sigue en la mesa 3, pone `fecha_hora_entrega` y
   `fecha_hora_cierre = SYSDATE` y estado 4 (ENTREGADO), deja que `trg_liberar_mesa` libere la mesa
   y lo comprueba.

## Qué imprime cada `proc_reporte`

- Integración: ID interno y externo del pedido A, canal, detalles y total.
- Mesas: mesa del pedido B, si está ocupada o libre, duración de la atención y
  `sp_reporte_rotacion_local(1, TRUNC(SYSDATE), '00:00', '23:59')`.
- Stock: las salidas de A y B valorizadas y las existencias finales del local.
- KDS: detalles de A y B con hora de inicio y de listo, y estado final de cada pedido
  (A queda LISTO, B queda ENTREGADO por el cierre de salón).
- Merma: mermas de hoy del local, KPI del día y `sp_reporte_merma` del día para todos los locales.
- Facturación: pagos y boletas de A y B con su estado DTE.

## Orden de ejecución de los scripts

`00_creacion_usuario` (como SYS) → `01_tablas` → `02_poblacion` → `03`…`08` (los seis módulos) →
`09_pkg_simulacion` → `10_bloque_final`.
