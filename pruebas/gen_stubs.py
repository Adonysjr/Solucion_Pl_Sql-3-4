# -*- coding: utf-8 -*-
"""Genera pruebas/companeros_provisional.sql: los cuatro packages de los companeros
(tal como estan en la entrega de la parcial 1) + un proc_simular y proc_reporte
PROVISIONALES con las firmas de FIRMAS.md, para poder probar PKG_SIMULACION localmente.
Cada companero entrega su propia version; esto NO reemplaza su trabajo."""
import os, re, sys
src = sys.argv[1]      # carpeta soluciones de la entrega (zip adonys_maceo)
out = sys.argv[2]

def leer(n): return open(os.path.join(src, n), encoding="utf-8").read()

def recortar(texto, fin_pkg):
    """Deja solo hasta el final del PACKAGE BODY (quita la simulacion/demos de abajo)."""
    i = texto.rfind(fin_pkg)
    assert i > 0, fin_pkg
    j = texto.find("/", i)
    return texto[: j + 1] + "\n"

def inyectar(texto, fin_pkg, spec, body):
    """Mete `spec` antes del END de la especificacion y `body` antes del END del cuerpo."""
    partes = texto.split(fin_pkg)
    assert len(partes) == 3, (fin_pkg, len(partes))
    return partes[0] + spec + fin_pkg + partes[1] + body + fin_pkg + partes[2]

# ---------------------------------------------------------------- INTEGRACION
INT_SPEC = """
    -- Simulacion integrada (provisional): registra el pedido delivery de la simulacion.
    PROCEDURE proc_simular(
        p_id_local   IN  LOCAL.ID_LOCAL%TYPE,
        p_id_canal   IN  CANAL_VENTA.ID_CANAL%TYPE,
        p_id_cliente IN  CLIENTE.ID_CLIENTE%TYPE,
        p_id_pedido  OUT PEDIDO.ID_PEDIDO%TYPE
    );

    PROCEDURE proc_reporte(
        p_id_pedido IN PEDIDO.ID_PEDIDO%TYPE
    );

"""
INT_BODY = """
PROCEDURE proc_simular(
    p_id_local   IN  LOCAL.ID_LOCAL%TYPE,
    p_id_canal   IN  CANAL_VENTA.ID_CANAL%TYPE,
    p_id_cliente IN  CLIENTE.ID_CLIENTE%TYPE,
    p_id_pedido  OUT PEDIDO.ID_PEDIDO%TYPE
) IS
    v_id_externo PEDIDO.ID_EXTERNO_DELIVERY%TYPE :=
        'SIM-RAP-' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF3');
    v_items  PLS_INTEGER;
    v_total  PEDIDO.TOTAL%TYPE;
    v_estado PEDIDO.ID_ESTADO%TYPE;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- INTEGRACION EXTERNA: pedido ' || v_id_externo || ' ---');

    -- 1. validar canal y descartar duplicado con las funciones del package
    IF NOT fn_validar_canal_delivery(p_id_canal) THEN
        RAISE_APPLICATION_ERROR(-20101, 'Canal ' || p_id_canal || ' no es de delivery.');
    END IF;
    IF fn_pedido_externo_existe(p_id_canal, v_id_externo) THEN
        RAISE_APPLICATION_ERROR(-20102, 'El identificador externo ya existe.');
    END IF;

    -- 2. registrar el pedido
    proc_registrar_pedido_externo(p_id_canal, v_id_externo, p_id_local, p_id_cliente,
                                  p_id_pedido, 'SIMULACION INTEGRADA');
    IF p_id_pedido IS NULL THEN
        RAISE_APPLICATION_ERROR(-20103, 'No se pudo registrar el pedido externo.');
    END IF;

    -- 3. hamburguesa clasica (1) y papas fritas (4)
    proc_agregar_detalle_pedido(p_id_pedido, 1, 1);
    proc_agregar_detalle_pedido(p_id_pedido, 4, 1);

    -- 4. comprobar 2 detalles, total 12.400 y estado PENDIENTE
    SELECT COUNT(*) INTO v_items FROM DETALLE_PEDIDO WHERE ID_PEDIDO = p_id_pedido;
    SELECT TOTAL, ID_ESTADO INTO v_total, v_estado FROM PEDIDO WHERE ID_PEDIDO = p_id_pedido;

    DBMS_OUTPUT.PUT_LINE('Pedido ' || p_id_pedido || ' | detalles: ' || v_items ||
                         ' | total: $' || v_total || ' | estado: ' || v_estado);
    IF v_items <> 2 OR v_total <> 12400 OR v_estado <> 1 THEN
        RAISE_APPLICATION_ERROR(-20104, 'El pedido delivery no quedo como se esperaba.');
    END IF;
END proc_simular;

PROCEDURE proc_reporte(
    p_id_pedido IN PEDIDO.ID_PEDIDO%TYPE
) IS
    CURSOR c_pedido IS
        SELECT p.ID_PEDIDO, p.ID_EXTERNO_DELIVERY, c.NOMBRE AS CANAL, p.TOTAL, e.NOMBRE AS ESTADO
        FROM PEDIDO p
        JOIN CANAL_VENTA c ON c.ID_CANAL = p.ID_CANAL
        JOIN ESTADO_PEDIDO e ON e.ID_ESTADO = p.ID_ESTADO
        WHERE p.ID_PEDIDO = p_id_pedido;
    CURSOR c_detalles IS
        SELECT pr.NOMBRE, d.CANTIDAD, d.SUBTOTAL
        FROM DETALLE_PEDIDO d JOIN PRODUCTO pr ON pr.ID_PRODUCTO = d.ID_PRODUCTO
        WHERE d.ID_PEDIDO = p_id_pedido ORDER BY d.ID_DETALLE;
BEGIN
    FOR p IN c_pedido LOOP
        DBMS_OUTPUT.PUT_LINE('  Pedido ' || p.ID_PEDIDO || ' | externo ' || p.ID_EXTERNO_DELIVERY ||
                             ' | canal ' || p.CANAL || ' | total $' || p.TOTAL || ' | estado ' || p.ESTADO);
        FOR d IN c_detalles LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CANTIDAD || ' x ' || RPAD(d.NOMBRE, 24) || ' $' || d.SUBTOTAL);
        END LOOP;
    END LOOP;
END proc_reporte;

"""

# ---------------------------------------------------------------- MESAS
MES_SPEC = """
    -- Simulacion integrada (provisional): ABRIR crea el pedido de salon, CERRAR lo cierra.
    PROCEDURE proc_simular (
        p_etapa       IN     VARCHAR2,
        p_id_local    IN     LOCAL.ID_LOCAL%TYPE,
        p_id_mesa     IN     MESA.ID_MESA%TYPE,
        p_id_empleado IN     EMPLEADO.ID_EMPLEADO%TYPE,
        p_id_pedido   IN OUT PEDIDO.ID_PEDIDO%TYPE
    );

    PROCEDURE proc_reporte (
        p_id_pedido IN PEDIDO.ID_PEDIDO%TYPE
    );

"""
MES_BODY = """
    -- privado: agrega un detalle al pedido de salon y actualiza el total
    PROCEDURE pr_agregar_detalle (
        p_id_pedido   IN PEDIDO.ID_PEDIDO%TYPE,
        p_id_producto IN PRODUCTO.ID_PRODUCTO%TYPE,
        p_cantidad    IN DETALLE_PEDIDO.CANTIDAD%TYPE
    ) IS
        v_precio PRODUCTO.PRECIO_VENTA%TYPE;
    BEGIN
        SELECT PRECIO_VENTA INTO v_precio FROM PRODUCTO WHERE ID_PRODUCTO = p_id_producto AND ACTIVO = TRUE;
        INSERT INTO DETALLE_PEDIDO (ID_DETALLE, CANTIDAD, PRECIO_UNITARIO, SUBTOTAL, ESTADO_KDS, ID_PEDIDO, ID_PRODUCTO)
        VALUES (SEQ_DETALLE_PEDIDO.NEXTVAL, p_cantidad, v_precio, v_precio * p_cantidad, 'PENDIENTE', p_id_pedido, p_id_producto);
        UPDATE PEDIDO SET TOTAL = TOTAL + v_precio * p_cantidad WHERE ID_PEDIDO = p_id_pedido;
    END pr_agregar_detalle;

    PROCEDURE proc_simular (
        p_etapa       IN     VARCHAR2,
        p_id_local    IN     LOCAL.ID_LOCAL%TYPE,
        p_id_mesa     IN     MESA.ID_MESA%TYPE,
        p_id_empleado IN     EMPLEADO.ID_EMPLEADO%TYPE,
        p_id_pedido   IN OUT PEDIDO.ID_PEDIDO%TYPE
    ) IS
        v_ocupada MESA.OCUPADA%TYPE;
        v_numero  MESA.NUMERO_MESA%TYPE;
        v_total   PEDIDO.TOTAL%TYPE;
        v_mesa    PEDIDO.ID_MESA%TYPE;
    BEGIN
        SELECT OCUPADA, NUMERO_MESA INTO v_ocupada, v_numero FROM MESA WHERE ID_MESA = p_id_mesa AND ID_LOCAL = p_id_local;

        IF p_etapa = 'ABRIR' THEN
            DBMS_OUTPUT.PUT_LINE('--- MESAS: apertura en mesa ' || v_numero || ' ---');
            IF v_ocupada THEN
                RAISE exc_mesas.mesa_no_disponible;
            END IF;
            INSERT INTO PEDIDO (ID_PEDIDO, FECHA_HORA_CREACION, OBSERVACION, TOTAL, ID_LOCAL, ID_MESA, ID_EMPLEADO, ID_CANAL, ID_CLIENTE, ID_ESTADO)
            VALUES (SEQ_PEDIDO.NEXTVAL, SYSDATE, 'SIMULACION INTEGRADA', 0, p_id_local, p_id_mesa, p_id_empleado, 1, 1, 1)
            RETURNING ID_PEDIDO INTO p_id_pedido;

            pr_agregar_detalle(p_id_pedido, 2, 1);   -- pollo grill con papas
            pr_agregar_detalle(p_id_pedido, 5, 1);   -- bebida cola

            SELECT OCUPADA INTO v_ocupada FROM MESA WHERE ID_MESA = p_id_mesa;
            SELECT TOTAL INTO v_total FROM PEDIDO WHERE ID_PEDIDO = p_id_pedido;
            DBMS_OUTPUT.PUT_LINE('Pedido de salon ' || p_id_pedido || ' creado | total $' || v_total ||
                                 ' | mesa ' || v_numero || ': ' || CASE WHEN v_ocupada THEN 'OCUPADA' ELSE 'LIBRE' END);
            IF NOT v_ocupada OR v_total <> 13700 THEN
                RAISE_APPLICATION_ERROR(-20405, 'La apertura de salon no quedo como se esperaba.');
            END IF;

        ELSIF p_etapa = 'CERRAR' THEN
            DBMS_OUTPUT.PUT_LINE('--- MESAS: cierre del pedido ' || p_id_pedido || ' ---');
            SELECT ID_MESA INTO v_mesa FROM PEDIDO WHERE ID_PEDIDO = p_id_pedido;
            IF v_mesa IS NULL OR v_mesa <> p_id_mesa THEN
                RAISE_APPLICATION_ERROR(-20406, 'El pedido ' || p_id_pedido || ' no esta en la mesa ' || p_id_mesa);
            END IF;
            UPDATE PEDIDO
               SET FECHA_HORA_ENTREGA = SYSDATE, FECHA_HORA_CIERRE = SYSDATE, ID_ESTADO = 4
             WHERE ID_PEDIDO = p_id_pedido;
            SELECT OCUPADA INTO v_ocupada FROM MESA WHERE ID_MESA = p_id_mesa;
            DBMS_OUTPUT.PUT_LINE('Pedido ' || p_id_pedido || ' cerrado | duracion ' ||
                                 fn_duracion_atencion_min(p_id_pedido) || ' min | mesa ' || v_numero || ': ' ||
                                 CASE WHEN v_ocupada THEN 'OCUPADA' ELSE 'LIBRE' END);
            IF v_ocupada THEN
                RAISE_APPLICATION_ERROR(-20407, 'La mesa no se libero al cerrar.');
            END IF;
        ELSE
            RAISE_APPLICATION_ERROR(-20408, 'Etapa invalida: ' || p_etapa);
        END IF;
    END proc_simular;

    PROCEDURE proc_reporte (
        p_id_pedido IN PEDIDO.ID_PEDIDO%TYPE
    ) IS
        v_local   PEDIDO.ID_LOCAL%TYPE;
        v_numero  MESA.NUMERO_MESA%TYPE;
        v_ocupada MESA.OCUPADA%TYPE;
        v_estado  ESTADO_PEDIDO.NOMBRE%TYPE;
    BEGIN
        SELECT p.ID_LOCAL, m.NUMERO_MESA, m.OCUPADA, e.NOMBRE
          INTO v_local, v_numero, v_ocupada, v_estado
          FROM PEDIDO p JOIN MESA m ON m.ID_MESA = p.ID_MESA JOIN ESTADO_PEDIDO e ON e.ID_ESTADO = p.ID_ESTADO
         WHERE p.ID_PEDIDO = p_id_pedido;
        DBMS_OUTPUT.PUT_LINE('  Pedido ' || p_id_pedido || ' | mesa ' || v_numero || ' ' ||
                             CASE WHEN v_ocupada THEN 'OCUPADA' ELSE 'LIBRE' END ||
                             ' | estado ' || v_estado || ' | duracion ' ||
                             NVL(TO_CHAR(fn_duracion_atencion_min(p_id_pedido)), 'abierto') || ' min');
        sp_reporte_rotacion_local(v_local, TRUNC(SYSDATE), '00:00', '23:59');
    END proc_reporte;

"""

# ---------------------------------------------------------------- KDS
KDS_SPEC = """
    -- Simulacion integrada (provisional): prepara en cocina los dos pedidos.
    PROCEDURE proc_simular(
        p_id_local    IN LOCAL.ID_LOCAL%TYPE,
        p_id_pedido_a IN PEDIDO.ID_PEDIDO%TYPE,
        p_id_pedido_b IN PEDIDO.ID_PEDIDO%TYPE
    );

    PROCEDURE proc_reporte(
        p_id_pedido_a IN PEDIDO.ID_PEDIDO%TYPE,
        p_id_pedido_b IN PEDIDO.ID_PEDIDO%TYPE
    );

"""
KDS_BODY = """
PROCEDURE proc_simular(
    p_id_local    IN LOCAL.ID_LOCAL%TYPE,
    p_id_pedido_a IN PEDIDO.ID_PEDIDO%TYPE,
    p_id_pedido_b IN PEDIDO.ID_PEDIDO%TYPE
) IS
    CURSOR c_pedidos IS
        SELECT ID_PEDIDO FROM PEDIDO WHERE ID_PEDIDO IN (p_id_pedido_a, p_id_pedido_b) ORDER BY ID_PEDIDO;
    CURSOR c_detalles(cp_id_pedido PEDIDO.ID_PEDIDO%TYPE) IS
        SELECT ID_DETALLE FROM DETALLE_PEDIDO WHERE ID_PEDIDO = cp_id_pedido AND ESTADO_KDS = 'PREPARANDO' ORDER BY ID_DETALLE;
    v_preparando PLS_INTEGER;
    v_listos     PLS_INTEGER;
    v_estados    PLS_INTEGER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- KDS: cocina del local ' || p_id_local || ' ---');
    FOR p IN c_pedidos LOOP
        DBMS_OUTPUT.PUT_LINE('Pedido ' || p.ID_PEDIDO || ' | espera ' || fn_tiempo_espera(p.ID_PEDIDO) ||
                             ' min | preparacion ' || fn_tiempo_preparacion_pedido(p.ID_PEDIDO) ||
                             ' min | prioridad ' || ROUND(fn_prioridad_kds(p.ID_PEDIDO), 2));
    END LOOP;

    proc_gestionar_kds(p_id_local);

    SELECT COUNT(*) INTO v_preparando FROM DETALLE_PEDIDO
     WHERE ID_PEDIDO IN (p_id_pedido_a, p_id_pedido_b) AND ESTADO_KDS = 'PREPARANDO';
    DBMS_OUTPUT.PUT_LINE('Detalles en PREPARANDO: ' || v_preparando);
    IF v_preparando <> 4 THEN
        RAISE_APPLICATION_ERROR(-20201, 'No entraron a cocina los 4 detalles (sin capacidad?).');
    END IF;

    FOR p IN c_pedidos LOOP
        FOR d IN c_detalles(p.ID_PEDIDO) LOOP
            proc_marcar_detalle_listo(d.ID_DETALLE);
        END LOOP;
    END LOOP;

    SELECT COUNT(*) INTO v_listos FROM DETALLE_PEDIDO
     WHERE ID_PEDIDO IN (p_id_pedido_a, p_id_pedido_b) AND ESTADO_KDS = 'LISTO';
    SELECT COUNT(*) INTO v_estados FROM PEDIDO
     WHERE ID_PEDIDO IN (p_id_pedido_a, p_id_pedido_b) AND ID_ESTADO = 3;
    DBMS_OUTPUT.PUT_LINE('Detalles LISTO: ' || v_listos || ' | pedidos en estado LISTO (trigger): ' || v_estados);
    IF v_listos <> 4 OR v_estados <> 2 THEN
        RAISE_APPLICATION_ERROR(-20202, 'Los pedidos no terminaron LISTO en cocina.');
    END IF;
END proc_simular;

PROCEDURE proc_reporte(
    p_id_pedido_a IN PEDIDO.ID_PEDIDO%TYPE,
    p_id_pedido_b IN PEDIDO.ID_PEDIDO%TYPE
) IS
    CURSOR c_det IS
        SELECT d.ID_PEDIDO, pr.NOMBRE, d.ESTADO_KDS,
               TO_CHAR(d.FECHA_HORA_INICIO, 'HH24:MI:SS') AS INICIO,
               TO_CHAR(d.FECHA_HORA_LISTO, 'HH24:MI:SS')  AS LISTO,
               e.NOMBRE AS ESTADO_PEDIDO
        FROM DETALLE_PEDIDO d
        JOIN PRODUCTO pr ON pr.ID_PRODUCTO = d.ID_PRODUCTO
        JOIN PEDIDO p ON p.ID_PEDIDO = d.ID_PEDIDO
        JOIN ESTADO_PEDIDO e ON e.ID_ESTADO = p.ID_ESTADO
        WHERE d.ID_PEDIDO IN (p_id_pedido_a, p_id_pedido_b)
        ORDER BY d.ID_PEDIDO, d.ID_DETALLE;
BEGIN
    FOR d IN c_det LOOP
        DBMS_OUTPUT.PUT_LINE('  Pedido ' || d.ID_PEDIDO || ' (' || d.ESTADO_PEDIDO || ') | ' || RPAD(d.NOMBRE, 24) ||
                             ' ' || RPAD(d.ESTADO_KDS, 10) || ' inicio ' || NVL(d.INICIO, '--') || ' listo ' || NVL(d.LISTO, '--'));
    END LOOP;
END proc_reporte;

"""

# ---------------------------------------------------------------- FACTURACION
FAC_SPEC = """
    -- Simulacion integrada (provisional): pagos, boletas y DTE de los dos pedidos.
    PROCEDURE proc_simular (
        p_id_pedido_a IN PEDIDO.ID_PEDIDO%TYPE,
        p_id_pedido_b IN PEDIDO.ID_PEDIDO%TYPE
    );

    PROCEDURE proc_reporte (
        p_id_pedido_a IN PEDIDO.ID_PEDIDO%TYPE,
        p_id_pedido_b IN PEDIDO.ID_PEDIDO%TYPE
    );

"""
FAC_BODY = """
    -- privado: paga el total del pedido con un medio y emite su boleta ACEPTADA
    PROCEDURE pr_facturar (
        p_id_pedido   IN PEDIDO.ID_PEDIDO%TYPE,
        p_id_medio    IN PAGO.ID_MEDIO_PAGO%TYPE,
        p_id_boleta   OUT BOLETA.ID_BOLETA%TYPE
    ) IS
        v_total   PEDIDO.TOTAL%TYPE;
        v_detalle NUMBER;
    BEGIN
        SELECT TOTAL INTO v_total FROM PEDIDO WHERE ID_PEDIDO = p_id_pedido;
        v_detalle := fn_calcular_total_detalle(p_id_pedido);
        IF v_total <> v_detalle THEN
            RAISE exc_facturacion.total_no_coincide;
        END IF;
        sp_registrar_pago(p_id_pedido, v_total, p_id_medio);
        sp_emitir_boleta(p_id_pedido, p_id_boleta);
        sp_actualizar_estado_dte(p_id_boleta, 'ACEPTADA');
    END pr_facturar;

    PROCEDURE proc_simular (
        p_id_pedido_a IN PEDIDO.ID_PEDIDO%TYPE,
        p_id_pedido_b IN PEDIDO.ID_PEDIDO%TYPE
    ) IS
        v_boleta_a BOLETA.ID_BOLETA%TYPE;
        v_boleta_b BOLETA.ID_BOLETA%TYPE;
        v_pagos    PLS_INTEGER;
        v_boletas  PLS_INTEGER;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('--- FACTURACION: pedidos ' || p_id_pedido_a || ' y ' || p_id_pedido_b || ' ---');
        pr_facturar(p_id_pedido_a, 5, v_boleta_a);   -- app delivery
        pr_facturar(p_id_pedido_b, 2, v_boleta_b);   -- debito

        SELECT COUNT(*) INTO v_pagos FROM PAGO WHERE ID_PEDIDO IN (p_id_pedido_a, p_id_pedido_b);
        SELECT COUNT(*) INTO v_boletas FROM BOLETA WHERE ID_PEDIDO IN (p_id_pedido_a, p_id_pedido_b) AND ESTADO_DTE = 'ACEPTADA';
        DBMS_OUTPUT.PUT_LINE('Pagos: ' || v_pagos || ' | boletas ACEPTADAS: ' || v_boletas ||
                             ' (' || v_boleta_a || ', ' || v_boleta_b || ')');
        IF v_pagos <> 2 OR v_boletas <> 2 THEN
            RAISE_APPLICATION_ERROR(-20307, 'La facturacion no quedo como se esperaba.');
        END IF;
    END proc_simular;

    PROCEDURE proc_reporte (
        p_id_pedido_a IN PEDIDO.ID_PEDIDO%TYPE,
        p_id_pedido_b IN PEDIDO.ID_PEDIDO%TYPE
    ) IS
        CURSOR c_pagos IS
            SELECT p.ID_PEDIDO, p.MONTO, m.NOMBRE AS MEDIO
            FROM PAGO p JOIN MEDIO_PAGO m ON m.ID_MEDIO_PAGO = p.ID_MEDIO_PAGO
            WHERE p.ID_PEDIDO IN (p_id_pedido_a, p_id_pedido_b) ORDER BY p.ID_PAGO;
        CURSOR c_boletas IS
            SELECT ID_PEDIDO, ID_BOLETA, TIPO, NETO, IVA, TOTAL, ESTADO_DTE
            FROM BOLETA WHERE ID_PEDIDO IN (p_id_pedido_a, p_id_pedido_b) ORDER BY ID_BOLETA;
    BEGIN
        FOR p IN c_pagos LOOP
            DBMS_OUTPUT.PUT_LINE('  Pago pedido ' || p.ID_PEDIDO || ': $' || p.MONTO || ' con ' || p.MEDIO);
        END LOOP;
        FOR b IN c_boletas LOOP
            DBMS_OUTPUT.PUT_LINE('  Boleta ' || b.ID_BOLETA || ' pedido ' || b.ID_PEDIDO || ' | ' || b.TIPO ||
                                 ' | neto $' || b.NETO || ' iva $' || b.IVA || ' total $' || b.TOTAL || ' | DTE ' || b.ESTADO_DTE);
        END LOOP;
    END proc_reporte;

"""

partes = []
partes.append("-- ====================================================================\n"
              "-- VERSION PROVISIONAL de los packages de los companeros, SOLO para probar\n"
              "-- PKG_SIMULACION en local. Son sus packages de la parcial 1 + un proc_simular\n"
              "-- y proc_reporte con las firmas de FIRMAS.md. Cada companero entrega el suyo.\n"
              "-- ====================================================================\n\nSET SERVEROUTPUT ON\n\n")
t = recortar(leer("solucion_integracion_externa.sql"), "END PKG_INTEGRACION_EXTERNA;")
partes.append(inyectar(t, "END PKG_INTEGRACION_EXTERNA;", INT_SPEC, INT_BODY))
t = leer("solucion_rotacion_mesas.sql")
# mesas: dejo packages + triggers, quito la simulacion del final
i = t.find("/*\n========================================\n    SIMULACI")
t = t[:i] if i > 0 else t
partes.append(inyectar(t, "END pkg_mesas;", MES_SPEC, MES_BODY))
t = leer("solucion_tiempos_pedidos.sql")
i = t.find("/*\n===============================\n    SIMULACI")
t = t[:i] if i > 0 else t
partes.append(inyectar(t, "END PKG_GESTION_KDS;", KDS_SPEC, KDS_BODY))
t = recortar(leer("solucion_boletas_y_facturas.sql"), "END pkg_facturacion;")
partes.append(inyectar(t, "END pkg_facturacion;", FAC_SPEC, FAC_BODY))
open(out, "w", encoding="utf-8").write("\n".join(partes))
print("ok", out)
