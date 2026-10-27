-- ====================================================================
-- PKG_SIMULACION - coordinador de la simulacion integrada (evaluacion parcial 2)
-- Sabores Urbanos - BDY1103 Taller de Base de Datos
-- --------------------------------------------------------------------
-- Llama en orden al proc_simular de los seis packages del grupo y luego
-- arma el reporte consolidado con el proc_reporte de cada uno.
-- Este package NO repite la logica de los modulos: solo coordina.
--
-- Requiere que los seis packages tengan proc_simular y proc_reporte con las
-- firmas acordadas en FIRMAS.md. Ningun proc_simular hace COMMIT: la
-- transaccion completa la confirma o deshace el bloque anonimo final.
-- ====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED

CREATE OR REPLACE PACKAGE PKG_SIMULACION AS

    -- Ejecuta la operacion completa y devuelve los dos pedidos creados.
    PROCEDURE proc_simular (
        p_id_delivery OUT PEDIDO.id_pedido%TYPE,
        p_id_salon    OUT PEDIDO.id_pedido%TYPE
    );

    -- Muestra el resultado de la simulacion. Solo consulta.
    PROCEDURE proc_generar_reporte (
        p_id_delivery IN PEDIDO.id_pedido%TYPE,
        p_id_salon    IN PEDIDO.id_pedido%TYPE
    );

    -- Procedimiento SIN parametros: simula y reporta de una sola llamada.
    PROCEDURE proc_ejecutar;

END PKG_SIMULACION;
/

CREATE OR REPLACE PACKAGE BODY PKG_SIMULACION AS

    -- datos comunes acordados por el grupo (datos de prueba, no IDs de pedidos)
    c_local       CONSTANT LOCAL.id_local%TYPE       := 1;   -- Costanera
    c_canal_rappi CONSTANT CANAL_VENTA.id_canal%TYPE := 3;   -- Rappi
    c_cliente     CONSTANT CLIENTE.id_cliente%TYPE   := 1;
    c_mesa        CONSTANT MESA.id_mesa%TYPE         := 3;   -- mesa 3, capacidad 2
    c_garzon      CONSTANT EMPLEADO.id_empleado%TYPE := 1;   -- Sofia Rojas, garzon

    -- ---------------- componentes privados (solo se usan dentro del cuerpo) ----------------

    -- titulo de seccion
    PROCEDURE pr_titulo (p_texto IN VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '==================================================');
        DBMS_OUTPUT.PUT_LINE('  ' || p_texto);
        DBMS_OUTPUT.PUT_LINE('==================================================');
    END pr_titulo;

    -- encabezado de cada paso de la simulacion
    PROCEDURE pr_paso (p_numero IN PLS_INTEGER, p_texto IN VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '>> Paso ' || p_numero || ': ' || p_texto);
    END pr_paso;

    -- linea del resumen final: compara lo obtenido con lo esperado
    -- p_minimo = TRUE: basta con alcanzar lo esperado (sirve cuando el dia ya traia datos)
    PROCEDURE pr_resumen (p_concepto IN VARCHAR2, p_obtenido IN NUMBER, p_esperado IN NUMBER,
                          p_minimo IN BOOLEAN DEFAULT FALSE) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('  ' || RPAD(p_concepto, 34) || LPAD(p_obtenido, 4) ||
                             '  (esperado ' || CASE WHEN p_minimo THEN 'al menos ' END || p_esperado || ')' ||
                             CASE WHEN p_obtenido = p_esperado OR (p_minimo AND p_obtenido > p_esperado)
                                  THEN '  OK' ELSE '  REVISAR' END);
    END pr_resumen;

    -- ejecuta una seccion del reporte sin que un error en un modulo corte el resto
    PROCEDURE pr_seccion (p_nombre IN VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ' || p_nombre || ' ---');
    END pr_seccion;

    -- ---------------- componentes publicos ----------------

    PROCEDURE proc_simular (
        p_id_delivery OUT PEDIDO.id_pedido%TYPE,
        p_id_salon    OUT PEDIDO.id_pedido%TYPE
    ) IS
        v_paso PLS_INTEGER := 0;
    BEGIN
        pr_titulo('SIMULACION DE OPERACION - Sabores Urbanos, local ' || c_local ||
                  ' - ' || TO_CHAR(SYSDATE, 'DD-MM-YYYY HH24:MI'));

        v_paso := 1; pr_paso(v_paso, 'Integracion externa: pedido delivery (Rappi)');
        PKG_INTEGRACION_EXTERNA.proc_simular(c_local, c_canal_rappi, c_cliente, p_id_delivery);

        v_paso := 2; pr_paso(v_paso, 'Mesas: apertura del pedido de salon');
        p_id_salon := NULL;
        PKG_MESAS.proc_simular('ABRIR', c_local, c_mesa, c_garzon, p_id_salon);

        v_paso := 3; pr_paso(v_paso, 'Stock por receta: confirmacion de ambos pedidos');
        PKG_STOCK_RECETA.proc_simular(p_id_delivery, p_id_salon);

        v_paso := 4; pr_paso(v_paso, 'KDS: preparacion en cocina');
        PKG_GESTION_KDS.proc_simular(c_local, p_id_delivery, p_id_salon);

        v_paso := 5; pr_paso(v_paso, 'Merma: perdida de insumo');
        PKG_MERMA.proc_simular(c_local);

        v_paso := 6; pr_paso(v_paso, 'Facturacion: pagos, boletas y DTE');
        PKG_FACTURACION.proc_simular(p_id_delivery, p_id_salon);

        v_paso := 7; pr_paso(v_paso, 'Mesas: cierre de la atencion de salon');
        PKG_MESAS.proc_simular('CERRAR', c_local, c_mesa, c_garzon, p_id_salon);

        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Simulacion completa. Pedido delivery ' || p_id_delivery ||
                             ' | pedido salon ' || p_id_salon);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE(CHR(10) || 'SIMULACION DETENIDA en el paso ' || v_paso ||
                                 ': ' || SQLERRM);
            RAISE;   -- el bloque final hace ROLLBACK de todo
    END proc_simular;

    PROCEDURE proc_generar_reporte (
        p_id_delivery IN PEDIDO.id_pedido%TYPE,
        p_id_salon    IN PEDIDO.id_pedido%TYPE
    ) IS
        v_pedidos  PLS_INTEGER;
        v_listos   PLS_INTEGER;
        v_salidas  PLS_INTEGER;
        v_mermas   PLS_INTEGER;
        v_pagos    PLS_INTEGER;
        v_boletas  PLS_INTEGER;
        v_liberada PLS_INTEGER;
    BEGIN
        pr_titulo('REPORTE CONSOLIDADO - pedidos ' || p_id_delivery || ' (delivery) y ' ||
                  p_id_salon || ' (salon)');

        -- cada seccion la imprime su propio package; si una falla, sigo con la siguiente
        pr_seccion('1. INTEGRACION EXTERNA');
        BEGIN PKG_INTEGRACION_EXTERNA.proc_reporte(p_id_delivery);
        EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('  Seccion no disponible: ' || SQLERRM); END;

        pr_seccion('2. MESAS');
        BEGIN PKG_MESAS.proc_reporte(p_id_salon);
        EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('  Seccion no disponible: ' || SQLERRM); END;

        pr_seccion('3. STOCK POR RECETA');
        BEGIN PKG_STOCK_RECETA.proc_reporte(p_id_delivery, p_id_salon);
        EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('  Seccion no disponible: ' || SQLERRM); END;

        pr_seccion('4. KDS');
        BEGIN PKG_GESTION_KDS.proc_reporte(p_id_delivery, p_id_salon);
        EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('  Seccion no disponible: ' || SQLERRM); END;

        pr_seccion('5. MERMA');
        BEGIN PKG_MERMA.proc_reporte(c_local);
        EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('  Seccion no disponible: ' || SQLERRM); END;

        pr_seccion('6. FACTURACION');
        BEGIN PKG_FACTURACION.proc_reporte(p_id_delivery, p_id_salon);
        EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('  Seccion no disponible: ' || SQLERRM); END;

        -- resumen: consultas simples filtradas por los IDs de esta ejecucion
        pr_seccion('RESUMEN DE LA SIMULACION');

        SELECT COUNT(*) INTO v_pedidos
          FROM PEDIDO WHERE id_pedido IN (p_id_delivery, p_id_salon);

        SELECT COUNT(*) INTO v_listos
          FROM DETALLE_PEDIDO
         WHERE id_pedido IN (p_id_delivery, p_id_salon) AND estado_kds = 'LISTO';

        SELECT COUNT(*) INTO v_salidas
          FROM MOVIMIENTO_STOCK
         WHERE id_pedido IN (p_id_delivery, p_id_salon) AND tipo = 'SALIDA';

        SELECT COUNT(*) INTO v_mermas
          FROM MOVIMIENTO_STOCK
         WHERE id_local = c_local AND tipo = 'MERMA' AND fecha_hora >= TRUNC(SYSDATE);

        SELECT COUNT(*) INTO v_pagos
          FROM PAGO WHERE id_pedido IN (p_id_delivery, p_id_salon);

        SELECT COUNT(*) INTO v_boletas
          FROM BOLETA
         WHERE id_pedido IN (p_id_delivery, p_id_salon) AND estado_dte = 'ACEPTADA';

        SELECT CASE WHEN m.ocupada THEN 0 ELSE 1 END INTO v_liberada
          FROM MESA m
          JOIN PEDIDO p ON p.id_mesa = m.id_mesa
         WHERE p.id_pedido = p_id_salon;

        pr_resumen('Pedidos creados',            v_pedidos, 2);
        pr_resumen('Detalles LISTO en cocina',   v_listos,  4);
        pr_resumen('Salidas de stock',           v_salidas, 9);
        pr_resumen('Mermas registradas hoy',     v_mermas,  1, TRUE);
        pr_resumen('Pagos registrados',          v_pagos,   2);
        pr_resumen('Boletas ACEPTADAS',          v_boletas, 2);
        pr_resumen('Mesa de salon liberada',     v_liberada, 1);

        IF v_mermas > 1 THEN
            DBMS_OUTPUT.PUT_LINE('  (el local ' || c_local || ' ya tenia mermas hoy, por ejemplo las de las' ||
                                 ' pruebas del modulo; la de esta simulacion es una de ellas)');
        END IF;
    END proc_generar_reporte;

    PROCEDURE proc_ejecutar IS
        v_delivery PEDIDO.id_pedido%TYPE;
        v_salon    PEDIDO.id_pedido%TYPE;
    BEGIN
        proc_simular(v_delivery, v_salon);
        proc_generar_reporte(v_delivery, v_salon);
    END proc_ejecutar;

END PKG_SIMULACION;
/
