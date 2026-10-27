-- ============================================================
-- PAQUETE DE EXCEPCIONES DEL MÓDULO DE FACTURACIÓN (exc_facturacion)
-- Debe compilarse antes que pkg_facturacion, porque este lo usa.
-- ============================================================
CREATE OR REPLACE PACKAGE exc_facturacion IS

    pedido_sin_detalles EXCEPTION;
    PRAGMA EXCEPTION_INIT(pedido_sin_detalles, -20301);

    total_no_coincide   EXCEPTION;
    PRAGMA EXCEPTION_INIT(total_no_coincide, -20302);

    pago_incompleto     EXCEPTION;
    PRAGMA EXCEPTION_INIT(pago_incompleto, -20303);

    boleta_ya_emitida   EXCEPTION;
    PRAGMA EXCEPTION_INIT(boleta_ya_emitida, -20304);

    estado_dte_invalido EXCEPTION;
    PRAGMA EXCEPTION_INIT(estado_dte_invalido, -20305);

END exc_facturacion;
/


-- ============================================================
-- ESPECIFICACIÓN DEL PAQUETE DE FACTURACIÓN (pkg_facturacion)
-- ============================================================
CREATE OR REPLACE PACKAGE pkg_facturacion IS

    -- 1. RECORD CON ATRIBUTOS ANCLADOS A LAS COLUMNAS DE LA TABLA BOLETA (%TYPE)
    TYPE t_resumen_boleta IS RECORD (
        monto_afecto BOLETA.NETO%TYPE,
        monto_exento BOLETA.NETO%TYPE,
        neto         BOLETA.NETO%TYPE,
        iva          BOLETA.IVA%TYPE,
        total        BOLETA.TOTAL%TYPE,
        tipo_boleta  BOLETA.TIPO%TYPE
    );

    -- 2. VARRAY CON ELEMENTOS ANCLADOS AL TIPO DE LA COLUMNA ESTADO_DTE (%TYPE)
    TYPE t_estados_dte IS VARRAY(3) OF BOLETA.ESTADO_DTE%TYPE;

    -- Funciones del paquete con parámetros tipo %TYPE
    FUNCTION fn_calcular_total_detalle (p_id_pedido PEDIDO.ID_PEDIDO%TYPE) RETURN NUMBER;
    FUNCTION fn_calcular_monto_afecto (p_id_pedido PEDIDO.ID_PEDIDO%TYPE) RETURN NUMBER;
    FUNCTION fn_calcular_monto_exento (p_id_pedido PEDIDO.ID_PEDIDO%TYPE) RETURN NUMBER;
    FUNCTION fn_calcular_neto (p_id_pedido PEDIDO.ID_PEDIDO%TYPE) RETURN NUMBER;
    FUNCTION fn_calcular_iva (p_id_pedido PEDIDO.ID_PEDIDO%TYPE) RETURN NUMBER;
    FUNCTION fn_total_pagado (p_id_pedido PEDIDO.ID_PEDIDO%TYPE) RETURN NUMBER;

    -- Procedimientos almacenados con parámetros tipo %TYPE
    PROCEDURE sp_registrar_pago (
        p_id_pedido      PEDIDO.ID_PEDIDO%TYPE,
        p_monto          PAGO.MONTO%TYPE,
        p_id_medio_pago PAGO.ID_MEDIO_PAGO%TYPE
    );

    PROCEDURE sp_emitir_boleta (
        p_id_pedido PEDIDO.ID_PEDIDO%TYPE,
        p_id_boleta OUT BOLETA.ID_BOLETA%TYPE
    );

    PROCEDURE sp_actualizar_estado_dte (
        p_id_boleta    BOLETA.ID_BOLETA%TYPE,
        p_nuevo_estado BOLETA.ESTADO_DTE%TYPE
    );

END pkg_facturacion;
/

-- ============================================================
-- CUERPO DEL PAQUETE DE FACTURACIÓN (pkg_facturacion)
-- ============================================================
CREATE OR REPLACE PACKAGE BODY pkg_facturacion IS

    -- Calcula la suma de los subtotales usando tipo %TYPE para la variable local
    FUNCTION fn_calcular_total_detalle (p_id_pedido PEDIDO.ID_PEDIDO%TYPE) RETURN NUMBER IS
        v_total DETALLE_PEDIDO.SUBTOTAL%TYPE;
    BEGIN
        SELECT NVL(SUM(SUBTOTAL), 0) INTO v_total
        FROM DETALLE_PEDIDO
        WHERE ID_PEDIDO = p_id_pedido;
        RETURN v_total;
    END fn_calcular_total_detalle;

    -- Suma productos con IVA (AFECTO_IVA = TRUE)
    FUNCTION fn_calcular_monto_afecto (p_id_pedido PEDIDO.ID_PEDIDO%TYPE) RETURN NUMBER IS
        v_monto DETALLE_PEDIDO.SUBTOTAL%TYPE;
    BEGIN
        SELECT NVL(SUM(dp.SUBTOTAL), 0) INTO v_monto
        FROM DETALLE_PEDIDO dp
        JOIN PRODUCTO pr ON dp.ID_PRODUCTO = pr.ID_PRODUCTO
        WHERE dp.ID_PEDIDO = p_id_pedido
          AND pr.AFECTO_IVA = TRUE;
        RETURN v_monto;
    END fn_calcular_monto_afecto;

    -- Suma productos exentos (AFECTO_IVA = FALSE)
    FUNCTION fn_calcular_monto_exento (p_id_pedido PEDIDO.ID_PEDIDO%TYPE) RETURN NUMBER IS
        v_monto DETALLE_PEDIDO.SUBTOTAL%TYPE;
    BEGIN
        SELECT NVL(SUM(dp.SUBTOTAL), 0) INTO v_monto
        FROM DETALLE_PEDIDO dp
        JOIN PRODUCTO pr ON dp.ID_PRODUCTO = pr.ID_PRODUCTO
        WHERE dp.ID_PEDIDO = p_id_pedido
          AND pr.AFECTO_IVA = FALSE;
        RETURN v_monto;
    END fn_calcular_monto_exento;

    -- Calcula la base imponible sin IVA
    FUNCTION fn_calcular_neto (p_id_pedido PEDIDO.ID_PEDIDO%TYPE) RETURN NUMBER IS
        v_afecto      BOLETA.NETO%TYPE;
        v_exento      BOLETA.NETO%TYPE;
        v_neto_afecto BOLETA.NETO%TYPE;
    BEGIN
        v_afecto      := fn_calcular_monto_afecto(p_id_pedido);
        v_exento      := fn_calcular_monto_exento(p_id_pedido);
        v_neto_afecto := ROUND(v_afecto / 1.19, 0);
        RETURN v_neto_afecto + v_exento;
    END fn_calcular_neto;

    -- Calcula el 19% correspondiente al impuesto
    FUNCTION fn_calcular_iva (p_id_pedido PEDIDO.ID_PEDIDO%TYPE) RETURN NUMBER IS
        v_afecto      BOLETA.IVA%TYPE;
        v_neto_afecto BOLETA.IVA%TYPE;
    BEGIN
        v_afecto      := fn_calcular_monto_afecto(p_id_pedido);
        v_neto_afecto := ROUND(v_afecto / 1.19, 0);
        RETURN v_afecto - v_neto_afecto;
    END fn_calcular_iva;

    -- Obten el total acumulado de pagos registrados
    FUNCTION fn_total_pagado (p_id_pedido PEDIDO.ID_PEDIDO%TYPE) RETURN NUMBER IS
        v_total PAGO.MONTO%TYPE;
    BEGIN
        SELECT NVL(SUM(MONTO), 0) INTO v_total
        FROM PAGO
        WHERE ID_PEDIDO = p_id_pedido;
        RETURN v_total;
    END fn_total_pagado;

    -- Registra los abonos asegurando un monto mayor a cero
    PROCEDURE sp_registrar_pago (
        p_id_pedido      PEDIDO.ID_PEDIDO%TYPE,
        p_monto          PAGO.MONTO%TYPE,
        p_id_medio_pago PAGO.ID_MEDIO_PAGO%TYPE
    ) IS
    BEGIN
        IF p_monto IS NULL OR p_monto <= 0 THEN
            RAISE_APPLICATION_ERROR(-20310, 'El monto del pago debe ser mayor a 0.');
        END IF;

        INSERT INTO PAGO (ID_PAGO, MONTO, FECHA_HORA, ID_PEDIDO, ID_MEDIO_PAGO)
        VALUES (SEQ_PAGO.NEXTVAL, p_monto, SYSTIMESTAMP, p_id_pedido, p_id_medio_pago);

        DBMS_OUTPUT.PUT_LINE('Pago registrado: $' || p_monto || ' - Pedido ' || p_id_pedido);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error en sp_registrar_pago: ' || SQLERRM);
            RAISE;
    END sp_registrar_pago;

    -- Genera la boleta asignando los datos procesados mediante el RECORD
    PROCEDURE sp_emitir_boleta (
        p_id_pedido PEDIDO.ID_PEDIDO%TYPE,
        p_id_boleta OUT BOLETA.ID_BOLETA%TYPE
    ) IS
        v_total_detalle DETALLE_PEDIDO.SUBTOTAL%TYPE;
        v_total_pedido  PEDIDO.TOTAL%TYPE;
        v_total_pagado  PAGO.MONTO%TYPE;
        v_existe_boleta NUMBER;
        
        -- Variable estructurada del tipo RECORD definido con %TYPE
        v_resumen       t_resumen_boleta;
    BEGIN
        -- Validar existencia del pedido
        SELECT TOTAL INTO v_total_pedido
        FROM PEDIDO
        WHERE ID_PEDIDO = p_id_pedido;

        -- Validar que no esté vacío
        v_total_detalle := fn_calcular_total_detalle(p_id_pedido);
        IF v_total_detalle = 0 THEN
            RAISE exc_facturacion.pedido_sin_detalles;
        END IF;

        -- Validar consistencia del total
        IF v_total_pedido != v_total_detalle THEN
            RAISE exc_facturacion.total_no_coincide;
        END IF;

        -- Validar boleta única
        SELECT COUNT(*) INTO v_existe_boleta
        FROM BOLETA
        WHERE ID_PEDIDO = p_id_pedido;

        IF v_existe_boleta > 0 THEN
            RAISE exc_facturacion.boleta_ya_emitida;
        END IF;

        -- Validar cuadratura exacta del pago
        v_total_pagado := fn_total_pagado(p_id_pedido);
        IF v_total_pagado != v_total_pedido THEN
            RAISE exc_facturacion.pago_incompleto;
        END IF;

        -- Asignación directa a los campos del RECORD (garantizado sin error por %TYPE)
        v_resumen.monto_afecto := fn_calcular_monto_afecto(p_id_pedido);
        v_resumen.monto_exento := fn_calcular_monto_exento(p_id_pedido);

        IF v_resumen.monto_afecto > 0 THEN
            v_resumen.tipo_boleta := 'AFECTA';
        ELSE
            v_resumen.tipo_boleta := 'EXENTA';
        END IF;

        v_resumen.neto  := fn_calcular_neto(p_id_pedido);
        v_resumen.iva   := fn_calcular_iva(p_id_pedido);
        v_resumen.total := v_resumen.neto + v_resumen.iva;

        SELECT SEQ_BOLETA.NEXTVAL INTO p_id_boleta FROM DUAL;

        INSERT INTO BOLETA (ID_BOLETA, FOLIO_SII, TIPO, FECHA_EMISION,
                            NETO, IVA, TOTAL, ESTADO_DTE, ID_PEDIDO)
        VALUES (p_id_boleta, p_id_boleta, v_resumen.tipo_boleta, SYSTIMESTAMP,
                v_resumen.neto, v_resumen.iva, v_resumen.total, 'PENDIENTE', p_id_pedido);

        DBMS_OUTPUT.PUT_LINE('Boleta ' || p_id_boleta || ' emitida (' || v_resumen.tipo_boleta ||
                             ') - Neto: $' || v_resumen.neto || ' IVA: $' || v_resumen.iva ||
                             ' Total: $' || v_resumen.total);

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('ERROR: El pedido ' || p_id_pedido || ' no existe.');
            RAISE_APPLICATION_ERROR(-20306, 'Pedido no encontrado: ' || p_id_pedido);
        WHEN exc_facturacion.pedido_sin_detalles THEN
            DBMS_OUTPUT.PUT_LINE('ERROR: El pedido ' || p_id_pedido || ' no tiene detalles.');
            RAISE;
        WHEN exc_facturacion.total_no_coincide THEN
            DBMS_OUTPUT.PUT_LINE('ERROR: PEDIDO.TOTAL (' || v_total_pedido ||
                                 ') no coincide con DETALLE_PEDIDO (' || v_total_detalle || ').');
            RAISE;
        WHEN exc_facturacion.boleta_ya_emitida THEN
            DBMS_OUTPUT.PUT_LINE('ERROR: Ya existe una boleta para el pedido ' || p_id_pedido);
            RAISE;
        WHEN exc_facturacion.pago_incompleto THEN
            DBMS_OUTPUT.PUT_LINE('ERROR: El pago no cubre el total. Pagado: $' ||
                                 v_total_pagado || ' / Requerido: $' || v_total_pedido);
            RAISE;
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error inesperado en sp_emitir_boleta: ' || SQLERRM);
            RAISE;
    END sp_emitir_boleta;

    -- Actualiza el estado operando con la colección VARRAY anclada a %TYPE
    PROCEDURE sp_actualizar_estado_dte (
        p_id_boleta    BOLETA.ID_BOLETA%TYPE,
        p_nuevo_estado BOLETA.ESTADO_DTE%TYPE
    ) IS
        v_estados_permitidos t_estados_dte := t_estados_dte('PENDIENTE', 'ACEPTADA', 'RECHAZADA');
        v_es_valido          BOOLEAN := FALSE;
    BEGIN
        FOR i IN 1..v_estados_permitidos.COUNT LOOP
            IF p_nuevo_estado = v_estados_permitidos(i) THEN
                v_es_valido := TRUE;
                EXIT;
            END IF;
        END LOOP;

        IF NOT v_es_valido THEN
            RAISE exc_facturacion.estado_dte_invalido;
        END IF;

        UPDATE BOLETA
        SET ESTADO_DTE = p_nuevo_estado
        WHERE ID_BOLETA = p_id_boleta;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20311, 'Boleta no encontrada: ' || p_id_boleta);
        END IF;

        DBMS_OUTPUT.PUT_LINE('Boleta ' || p_id_boleta || ' -> estado DTE: ' || p_nuevo_estado);

    EXCEPTION
        WHEN exc_facturacion.estado_dte_invalido THEN
            DBMS_OUTPUT.PUT_LINE('ERROR: Estado DTE invalido. Use PENDIENTE, ACEPTADA o RECHAZADA.');
            RAISE;
        WHEN OTHERS THEN
            RAISE;
    END sp_actualizar_estado_dte;

END pkg_facturacion;
/

/*
========================================
    SIMULACIÓN BOLETAS Y FACTURAS
========================================
*/
DECLARE
    v_local        LOCAL.ID_LOCAL%TYPE := 1;
    v_pedido       PEDIDO.ID_PEDIDO%TYPE;
    v_pedido_vacio PEDIDO.ID_PEDIDO%TYPE;
    v_boleta       BOLETA.ID_BOLETA%TYPE;
    v_boleta_aux   BOLETA.ID_BOLETA%TYPE;
    v_total        PEDIDO.TOTAL%TYPE;
    v_abono        PAGO.MONTO%TYPE;

    -- cursor sin parametros: un producto afecto a IVA y uno exento
    CURSOR c_productos IS
        SELECT ID_PRODUCTO, NOMBRE, PRECIO_VENTA, 'AFECTO' AS TIPO_IVA
        FROM PRODUCTO
        WHERE ID_PRODUCTO = (SELECT MIN(ID_PRODUCTO) FROM PRODUCTO
                             WHERE AFECTO_IVA = TRUE AND ACTIVO = TRUE)
        UNION ALL
        SELECT ID_PRODUCTO, NOMBRE, PRECIO_VENTA, 'EXENTO' AS TIPO_IVA
        FROM PRODUCTO
        WHERE ID_PRODUCTO = (SELECT MIN(ID_PRODUCTO) FROM PRODUCTO
                             WHERE AFECTO_IVA = FALSE AND ACTIVO = TRUE);

    -- cursor parametrizado: pagos registrados para un pedido
    CURSOR c_pagos(cp_id_pedido PEDIDO.ID_PEDIDO%TYPE) IS
        SELECT p.MONTO, m.NOMBRE AS MEDIO
        FROM PAGO p
        JOIN MEDIO_PAGO m ON m.ID_MEDIO_PAGO = p.ID_MEDIO_PAGO
        WHERE p.ID_PEDIDO = cp_id_pedido
        ORDER BY p.ID_PAGO;

    -- cursor parametrizado: boleta emitida para un pedido
    CURSOR c_boleta(cp_id_pedido PEDIDO.ID_PEDIDO%TYPE) IS
        SELECT ID_BOLETA, TIPO, NETO, IVA, TOTAL, ESTADO_DTE
        FROM BOLETA
        WHERE ID_PEDIDO = cp_id_pedido;

BEGIN
    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('     SIMULACIÓN BOLETAS Y FACTURAS');
    DBMS_OUTPUT.PUT_LINE('========================================');

    -- 1. crear un pedido con un producto afecto y uno exento
    SELECT SEQ_PEDIDO.NEXTVAL INTO v_pedido FROM DUAL;

    INSERT INTO PEDIDO
        (ID_PEDIDO, FECHA_HORA_CREACION, OBSERVACION, TOTAL,
         ID_LOCAL, ID_CANAL, ID_ESTADO)
    VALUES
        (v_pedido, SYSDATE, 'SIMULACION BOLETA', 0, v_local, 2, 4);

    FOR producto IN c_productos LOOP
        INSERT INTO DETALLE_PEDIDO (
            ID_DETALLE, CANTIDAD, PRECIO_UNITARIO, SUBTOTAL,
            ESTADO_KDS, ID_PEDIDO, ID_PRODUCTO
        ) VALUES (
            SEQ_DETALLE_PEDIDO.NEXTVAL, 1, producto.PRECIO_VENTA, producto.PRECIO_VENTA,
            'PENDIENTE', v_pedido, producto.ID_PRODUCTO
        );
        DBMS_OUTPUT.PUT_LINE('  + ' || producto.NOMBRE || ' (' || producto.TIPO_IVA ||
                             ') $' || producto.PRECIO_VENTA);
    END LOOP;

    v_total := pkg_facturacion.fn_calcular_total_detalle(v_pedido);
    UPDATE PEDIDO SET TOTAL = v_total WHERE ID_PEDIDO = v_pedido;

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- CÁLCULOS DEL PEDIDO ' || v_pedido || ' ---');
    DBMS_OUTPUT.PUT_LINE('Total: $'  || v_total ||
                         ' | Afecto: $' || pkg_facturacion.fn_calcular_monto_afecto(v_pedido) ||
                         ' | Exento: $' || pkg_facturacion.fn_calcular_monto_exento(v_pedido));
    DBMS_OUTPUT.PUT_LINE('Neto: $' || pkg_facturacion.fn_calcular_neto(v_pedido) ||
                         ' | IVA: $' || pkg_facturacion.fn_calcular_iva(v_pedido));

    -- 2. pagar solo una parte e intentar emitir: debe rechazarse
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- PRUEBA: PAGO INCOMPLETO ---');
    v_abono := ROUND(v_total / 2);
    pkg_facturacion.sp_registrar_pago(v_pedido, v_abono, 2);

    BEGIN
        pkg_facturacion.sp_emitir_boleta(v_pedido, v_boleta);
    EXCEPTION
        WHEN exc_facturacion.pago_incompleto THEN
            DBMS_OUTPUT.PUT_LINE('-> Boleta no emitida: falta completar el pago.');
    END;

    -- 3. completar el pago y emitir la boleta
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- PRUEBA: PAGO COMPLETO Y EMISIÓN ---');
    pkg_facturacion.sp_registrar_pago(v_pedido, v_total - v_abono, 1);

    FOR pago IN c_pagos(v_pedido) LOOP
        DBMS_OUTPUT.PUT_LINE('  Pago $' || pago.MONTO || ' con ' || pago.MEDIO);
    END LOOP;

    pkg_facturacion.sp_emitir_boleta(v_pedido, v_boleta);

    -- 4. intentar emitir otra boleta para el mismo pedido
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- PRUEBA: BOLETA DUPLICADA ---');
    BEGIN
        pkg_facturacion.sp_emitir_boleta(v_pedido, v_boleta_aux);
    EXCEPTION
        WHEN exc_facturacion.boleta_ya_emitida THEN
            DBMS_OUTPUT.PUT_LINE('-> Rechazada: el pedido ya tiene boleta.');
    END;

    -- 5. actualizar el estado DTE con un valor valido y uno invalido
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- PRUEBA: ESTADO DTE ---');
    pkg_facturacion.sp_actualizar_estado_dte(v_boleta, 'ACEPTADA');

    BEGIN
        pkg_facturacion.sp_actualizar_estado_dte(v_boleta, 'ANULADA');
    EXCEPTION
        WHEN exc_facturacion.estado_dte_invalido THEN
            DBMS_OUTPUT.PUT_LINE('-> Rechazado: ANULADA no es un estado DTE permitido.');
    END;

    -- 6. registrar un pago con monto cero
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- PRUEBA: PAGO CON MONTO CERO ---');
    BEGIN
        pkg_facturacion.sp_registrar_pago(v_pedido, 0, 1);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20310 THEN
                DBMS_OUTPUT.PUT_LINE('-> Rechazado: el monto debe ser mayor a cero.');
            ELSE
                RAISE;
            END IF;
    END;

    -- 7. emitir boleta para un pedido sin detalles
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- PRUEBA: PEDIDO SIN DETALLES ---');
    SELECT SEQ_PEDIDO.NEXTVAL INTO v_pedido_vacio FROM DUAL;

    INSERT INTO PEDIDO
        (ID_PEDIDO, FECHA_HORA_CREACION, OBSERVACION, TOTAL,
         ID_LOCAL, ID_CANAL, ID_ESTADO)
    VALUES
        (v_pedido_vacio, SYSDATE, 'SIMULACION PEDIDO VACIO', 0, v_local, 2, 5);

    BEGIN
        pkg_facturacion.sp_emitir_boleta(v_pedido_vacio, v_boleta_aux);
    EXCEPTION
        WHEN exc_facturacion.pedido_sin_detalles THEN
            DBMS_OUTPUT.PUT_LINE('-> Rechazado: el pedido no tiene productos.');
    END;

    -- 8. emitir boleta para un pedido que no existe
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- PRUEBA: PEDIDO INEXISTENTE ---');
    BEGIN
        pkg_facturacion.sp_emitir_boleta(999999, v_boleta_aux);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20306 THEN
                DBMS_OUTPUT.PUT_LINE('-> Rechazado: el pedido 999999 no existe.');
            ELSE
                RAISE;
            END IF;
    END;

    -- 9. resultado final de la boleta emitida
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- BOLETA FINAL ---');
    FOR boleta IN c_boleta(v_pedido) LOOP
        DBMS_OUTPUT.PUT_LINE(
            'Boleta ' || boleta.ID_BOLETA ||
            ' | ' || boleta.TIPO ||
            ' | Neto: $' || boleta.NETO ||
            ' | IVA: $' || boleta.IVA ||
            ' | Total: $' || boleta.TOTAL ||
            ' | DTE: ' || boleta.ESTADO_DTE
        );
    END LOOP;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error inesperado en la simulación: ' || SQLERRM);
        RAISE;
END;
/
