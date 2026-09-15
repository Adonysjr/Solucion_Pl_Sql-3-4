-- Problema 4: control y reduccion de merma
-- La empresa tiene cerca de 15% de merma y quiere bajarla a menos de 4%.
-- Para eso necesito registrar las perdidas reales de insumos separadas del
-- consumo normal de las recetas, y poder calcular el KPI de merma por local
-- y periodo. El KPI se calcula en pesos (cantidad * costo_unitario) para no
-- mezclar gramos, mililitros y unidades.

SET SERVEROUTPUT ON

CREATE OR REPLACE PACKAGE pkg_merma AS

    -- Excepciones definidas por mi para los dos casos que pide el problema:
    -- cantidad invalida y stock insuficiente. Las declaro en el package para
    -- lanzarlas con RAISE y capturarlas por nombre desde el bloque anonimo.
    ex_cantidad_invalida  EXCEPTION;
    ex_stock_insuficiente EXCEPTION;

    -- Procedimiento que registra una merma: valida, descuenta el stock y
    -- guarda el movimiento con su motivo.
    PROCEDURE sp_registrar_merma (
        p_id_local  IN LOCAL.id_local%TYPE,
        p_id_insumo IN INSUMO.id_insumo%TYPE,
        p_cantidad  IN NUMBER,
        p_motivo    IN VARCHAR2
    );

    -- Funcion que suma en pesos los movimientos de un tipo (SALIDA o MERMA)
    -- de un local en un periodo. La reutilizo para el consumo y para la merma.
    FUNCTION fn_costo_movimientos (
        p_id_local IN LOCAL.id_local%TYPE,
        p_tipo     IN MOVIMIENTO_STOCK.tipo%TYPE,
        p_desde    IN DATE,
        p_hasta    IN DATE
    ) RETURN NUMBER;

    -- Funcion que calcula el KPI: costo_merma / costo_consumo * 100.
    FUNCTION fn_porcentaje_merma (
        p_id_local IN LOCAL.id_local%TYPE,
        p_desde    IN DATE,
        p_hasta    IN DATE
    ) RETURN NUMBER;

    -- Procedimiento que muestra el KPI de todos los locales en un periodo.
    PROCEDURE sp_reporte_merma (
        p_desde IN DATE,
        p_hasta IN DATE
    );

END pkg_merma;
/

CREATE OR REPLACE PACKAGE BODY pkg_merma AS

    PROCEDURE sp_registrar_merma (
        p_id_local  IN LOCAL.id_local%TYPE,
        p_id_insumo IN INSUMO.id_insumo%TYPE,
        p_cantidad  IN NUMBER,
        p_motivo    IN VARCHAR2
    ) IS
        v_stock  STOCK_LOCAL.cantidad_actual%TYPE;
        v_nombre INSUMO.nombre%TYPE;
        v_unidad INSUMO.unidad_medida%TYPE;
    BEGIN
        -- Una merma negativa o en cero no tiene sentido, la rechazo altiro.
        IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
            DBMS_OUTPUT.PUT_LINE('La cantidad de merma debe ser mayor a cero (recibido: ' ||
                                 NVL(TO_CHAR(p_cantidad), 'NULL') || ').');
            RAISE ex_cantidad_invalida;
        END IF;

        -- Saco el nombre y la unidad del insumo para los mensajes.
        SELECT nombre, unidad_medida
          INTO v_nombre, v_unidad
          FROM INSUMO
         WHERE id_insumo = p_id_insumo;

        -- Leo el stock actual del local. Uso FOR UPDATE para bloquear la fila
        -- mientras la modifico, por si otro usuario descuenta al mismo tiempo.
        SELECT cantidad_actual
          INTO v_stock
          FROM STOCK_LOCAL
         WHERE id_local  = p_id_local
           AND id_insumo = p_id_insumo
           FOR UPDATE;

        -- No puedo registrar una perdida mayor a lo que hay en stock.
        IF v_stock < p_cantidad THEN
            DBMS_OUTPUT.PUT_LINE('Stock insuficiente para registrar merma de ' || v_nombre ||
                ' en local ' || p_id_local || ': disponible ' || v_stock || ' ' || v_unidad ||
                ', merma solicitada ' || p_cantidad || '.');
            RAISE ex_stock_insuficiente;
        END IF;

        -- Descuento la cantidad perdida del stock del local.
        UPDATE STOCK_LOCAL
           SET cantidad_actual     = cantidad_actual - p_cantidad,
               fecha_actualizacion = SYSDATE
         WHERE id_local  = p_id_local
           AND id_insumo = p_id_insumo;

        -- Registro el movimiento tipo MERMA con el motivo. Va sin id_pedido
        -- porque no esta asociado a una venta.
        INSERT INTO MOVIMIENTO_STOCK
            (id_movimiento, tipo, cantidad, fecha_hora, motivo, id_local, id_insumo, id_pedido)
        VALUES
            (seq_movimiento_stock.NEXTVAL, 'MERMA', p_cantidad, SYSDATE,
             SUBSTR(p_motivo, 1, 100), p_id_local, p_id_insumo, NULL);

        DBMS_OUTPUT.PUT_LINE('Merma registrada: ' || p_cantidad || ' ' || v_unidad || ' de ' ||
                             v_nombre || ' en local ' || p_id_local || ' - motivo: ' || p_motivo);
    END sp_registrar_merma;

    FUNCTION fn_costo_movimientos (
        p_id_local IN LOCAL.id_local%TYPE,
        p_tipo     IN MOVIMIENTO_STOCK.tipo%TYPE,
        p_desde    IN DATE,
        p_hasta    IN DATE
    ) RETURN NUMBER IS
        v_total NUMBER := 0;

        -- Cursor con parametros: local, tipo de movimiento y rango de fechas.
        -- Con los parametros puedo usar el mismo cursor para sumar el consumo
        -- (SALIDA) y la merma (MERMA) sin repetir la consulta.
        CURSOR c_movimientos (
            cp_id_local LOCAL.id_local%TYPE,
            cp_tipo     MOVIMIENTO_STOCK.tipo%TYPE,
            cp_desde    DATE,
            cp_hasta    DATE
        ) IS
            SELECT m.cantidad, i.costo_unitario
              FROM MOVIMIENTO_STOCK m
              JOIN INSUMO i ON i.id_insumo = m.id_insumo
             WHERE m.id_local   = cp_id_local
               AND m.tipo       = cp_tipo
               AND m.fecha_hora >= cp_desde
               AND m.fecha_hora <  cp_hasta + 1;
    BEGIN
        -- Recorro los movimientos y voy acumulando cantidad * costo.
        FOR mov IN c_movimientos(p_id_local, p_tipo, p_desde, p_hasta) LOOP
            v_total := v_total + (mov.cantidad * mov.costo_unitario);
        END LOOP;
        RETURN v_total;
    END fn_costo_movimientos;

    FUNCTION fn_porcentaje_merma (
        p_id_local IN LOCAL.id_local%TYPE,
        p_desde    IN DATE,
        p_hasta    IN DATE
    ) RETURN NUMBER IS
        v_costo_consumo NUMBER;
        v_costo_merma   NUMBER;
    BEGIN
        v_costo_consumo := fn_costo_movimientos(p_id_local, 'SALIDA', p_desde, p_hasta);
        v_costo_merma   := fn_costo_movimientos(p_id_local, 'MERMA',  p_desde, p_hasta);

        -- Si el local no tuvo consumo en el periodo no se puede dividir,
        -- devuelvo NULL para indicar que el KPI no aplica.
        IF v_costo_consumo = 0 THEN
            RETURN NULL;
        END IF;

        RETURN ROUND(v_costo_merma / v_costo_consumo * 100, 2);
    END fn_porcentaje_merma;

    PROCEDURE sp_reporte_merma (
        p_desde IN DATE,
        p_hasta IN DATE
    ) IS
        v_consumo NUMBER;
        v_merma   NUMBER;
        v_pct     NUMBER;

        -- Cursor sin parametros que recorre los locales activos.
        CURSOR c_locales IS
            SELECT id_local, nombre
              FROM LOCAL
             WHERE activo = TRUE
             ORDER BY id_local;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('REPORTE DE MERMA ' || TO_CHAR(p_desde, 'DD-MM-YYYY') ||
                             ' al ' || TO_CHAR(p_hasta, 'DD-MM-YYYY') || ' (meta < 4%)');

        -- Por cada local calculo consumo, merma y KPI usando las funciones.
        FOR loc IN c_locales LOOP
            v_consumo := fn_costo_movimientos(loc.id_local, 'SALIDA', p_desde, p_hasta);
            v_merma   := fn_costo_movimientos(loc.id_local, 'MERMA',  p_desde, p_hasta);
            v_pct     := fn_porcentaje_merma(loc.id_local, p_desde, p_hasta);

            DBMS_OUTPUT.PUT_LINE(RPAD(loc.id_local || ' - ' || loc.nombre, 34) ||
                ' consumo $' || LPAD(TO_CHAR(v_consumo, 'FM999G999G990'), 10) ||
                ' merma $'   || LPAD(TO_CHAR(v_merma,   'FM999G999G990'), 9)  ||
                ' KPI '      || LPAD(NVL(TO_CHAR(v_pct, 'FM990D00') || '%', 'sin consumo'), 11) ||
                CASE
                    WHEN v_pct IS NULL THEN ''
                    WHEN v_pct < 4     THEN '  OK'
                    ELSE '  SOBRE META'
                END);
        END LOOP;
    END sp_reporte_merma;

END pkg_merma;
/

-- Prueba 1: merma valida. Registro 250 gramos de carne perdidos en el local 1.
BEGIN
    pkg_merma.sp_registrar_merma(1, 2, 250, 'Vencimiento en camara de frio');
    COMMIT;
EXCEPTION
    WHEN pkg_merma.ex_cantidad_invalida THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('DATOS INVALIDOS: la merma no se registra.');
    WHEN pkg_merma.ex_stock_insuficiente THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('MERMA RECHAZADA: la merma no se registra.');
END;
/

-- Prueba 2: cantidad negativa, deberia salir ex_cantidad_invalida.
BEGIN
    pkg_merma.sp_registrar_merma(1, 2, -5, 'Prueba cantidad negativa');
EXCEPTION
    WHEN pkg_merma.ex_cantidad_invalida THEN
        DBMS_OUTPUT.PUT_LINE('DATOS INVALIDOS: la merma no se registra.');
END;
/

-- Prueba 3: merma mayor al stock, deberia salir ex_stock_insuficiente.
BEGIN
    pkg_merma.sp_registrar_merma(1, 2, 999999, 'Prueba stock insuficiente');
EXCEPTION
    WHEN pkg_merma.ex_stock_insuficiente THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('MERMA RECHAZADA: la merma no se registra.');
END;
/

-- Prueba 4: KPI de un solo local en lo que va del mes.
DECLARE
    v_pct NUMBER;
BEGIN
    v_pct := pkg_merma.fn_porcentaje_merma(1, TRUNC(SYSDATE, 'MM'), SYSDATE);
    IF v_pct IS NULL THEN
        DBMS_OUTPUT.PUT_LINE('Local 1: sin consumo en el periodo, KPI no calculable.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Local 1: merma del mes = ' || v_pct || '%');
    END IF;
END;
/

-- Prueba 5: reporte de todos los locales en lo que va del mes.
BEGIN
    pkg_merma.sp_reporte_merma(TRUNC(SYSDATE, 'MM'), SYSDATE);
END;
/
