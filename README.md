# Sabores Urbanos · Taller de Base de Datos (BDY1103)

Solución PL/SQL del caso **Sabores Urbanos Ltda.** Evaluación parcial 1 (seis módulos) y
evaluación parcial 2 (simulación integrada con un solo bloque anónimo).

## Orden de ejecución (SQL Developer, «Ejecutar script» F5, o SQL*Plus)

| # | Script | Qué hace | Quién lo ejecuta |
|---|---|---|---|
| 00 | `scripts/00_creacion_usuario.sql` | Crea el usuario `SABORES_ADMIN` | SYS (una sola vez) |
| 01 | `scripts/01_tablas.sql` | Borra y crea el modelo completo y las secuencias | SABORES_ADMIN |
| 02 | `scripts/02_poblacion.sql` | Datos de prueba (locales, productos, recetas, stock, pedidos históricos) | SABORES_ADMIN |
| 03 | `scripts/03_control_stock_receta.sql` | `pkg_stock_receta` + pruebas del módulo | SABORES_ADMIN |
| 04 | `scripts/04_control_merma.sql` | `pkg_merma` + pruebas del módulo | SABORES_ADMIN |
| 05 | `scripts/05_integracion_externa.sql` | `PKG_INTEGRACION_EXTERNA` + simulación del módulo | SABORES_ADMIN |
| 06 | `scripts/06_rotacion_mesas.sql` | `pkg_mesas`, triggers de mesa + simulación del módulo | SABORES_ADMIN |
| 07 | `scripts/07_gestion_kds.sql` | `PKG_GESTION_KDS`, trigger de pedido listo + simulación del módulo | SABORES_ADMIN |
| 08 | `scripts/08_facturacion.sql` | `pkg_facturacion` + simulación del módulo | SABORES_ADMIN |
| 09 | `scripts/09_pkg_simulacion.sql` | `PKG_SIMULACION`: coordinador de la simulación integrada | SABORES_ADMIN |
| 10 | `scripts/10_bloque_final.sql` | Bloque anónimo final: simula, reporta y hace COMMIT/ROLLBACK | SABORES_ADMIN |

Requiere Oracle **23ai** (las tablas usan columnas `BOOLEAN`). En SQL Developer activar la salida
de `DBMS_OUTPUT` (Ver → Salida DBMS) o simplemente ejecutar como script: cada archivo trae
`SET SERVEROUTPUT ON`.

## Evaluación parcial 2: simulación integrada

Cada package del grupo recibe dos procedimientos públicos nuevos, `proc_simular` y
`proc_reporte`, con las firmas de [FIRMAS.md](FIRMAS.md). El package nuevo `PKG_SIMULACION`
los llama en orden y el bloque `10_bloque_final.sql` ejecuta todo de una vez:

```
PKG_SIMULACION.proc_simular
  1. PKG_INTEGRACION_EXTERNA.proc_simular → pedido A (delivery Rappi, $12.400)
  2. PKG_MESAS.proc_simular('ABRIR')      → pedido B (salón, mesa 3, $13.700)
  3. PKG_STOCK_RECETA.proc_simular(A, B)  → 9 salidas de stock
  4. PKG_GESTION_KDS.proc_simular(1, A, B)→ 4 detalles LISTO, pedidos LISTO
  5. PKG_MERMA.proc_simular(1)            → 50 GR de lechuga por deterioro
  6. PKG_FACTURACION.proc_simular(A, B)   → 2 pagos, 2 boletas ACEPTADAS
  7. PKG_MESAS.proc_simular('CERRAR', B)  → mesa 3 liberada, B ENTREGADO
PKG_SIMULACION.proc_generar_reporte(A, B) → seis secciones + resumen
```

Ningún `proc_simular` hace COMMIT: el bloque final confirma todo si salió bien o deshace todo
si un paso falla.

En este repositorio los módulos 03, 04, 09 y 10 ya tienen la parte de la parcial 2. Los módulos
05 a 08 están tal como se entregaron en la parcial 1: cada compañero agrega su `proc_simular`
y `proc_reporte` siguiendo FIRMAS.md.

## Carpeta `pruebas/`

- `companeros_provisional.sql`: versión **provisional** de los packages 05 a 08 con un
  `proc_simular`/`proc_reporte` de ejemplo, solo para poder probar el coordinador antes de que
  cada compañero entregue el suyo. No reemplaza su trabajo.
- `correr_todo.sh`: ejecuta todo en orden con SQL*Plus contra una base local y guarda las salidas.
- `salidas/`: salida real de cada script en Oracle Free 23ai (Docker).
- `gen_stubs.py`: genera `companeros_provisional.sql` a partir de los scripts de la parcial 1.
