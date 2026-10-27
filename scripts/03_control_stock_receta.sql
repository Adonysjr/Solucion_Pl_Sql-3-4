-- Problema 3: control de stock por receta
-- Al confirmar un pedido descuento los insumos de la receta. Si falta algo, no se confirma.
--
-- Evaluacion parcial 2 (simulacion integrada):
--   * sp_confirmar_pedido ahora valida TODOS los insumos antes de descontar y
--     rechaza un pedido que ya fue confirmado (ya tiene salidas de stock).
--   * proc_simular: etapa de este modulo dentro de PKG_SIMULACION (confirma los
--     dos pedidos de la simulacion). No hace COMMIT: eso lo decide el bloque final.
--   * proc_reporte: solo consulta e imprime lo que dejo la simulacion.

SET SERVEROUTPUT ON

CREATE OR REPLACE PACKAGE pkg_stock_receta AS

    -- excepciones mias, van en el package para poder capturarlas desde el bloque anonimo
    ex_stock_insuficiente   EXCEPTION;
    ex_pedido_no_existe     EXCEPTION;
    ex_pedido_sin_receta    EXCEPTION;
    ex_pedido_ya_confirmado EXCEPTION;   -- nuevo: el pedido ya tiene movimientos SALIDA

    -- record con los datos del insumo que estoy revisando
    TYPE t_consumo_rec IS RECORD (
        id_insumo     INSUMO.id_insumo%TYPE,
        nombre        INSUMO.nombre%TYPE,
        unidad_medida INSUMO.unidad_medida%TYPE,
        requerido     NUMBER(10,3),
        disponible    NUMBER(10,3)
    );

    -- aqui guardo los insumos que faltan para mostrarlos todos juntos
    TYPE t_faltantes IS VARRAY(50) OF VARCHAR2(200);

    FUNCTION fn_stock_disponible (
        p_id_local  IN LOCAL.id_local%TYPE,
        p_id_insumo IN INSUMO.id_insumo%TYPE,
        p_cantidad  IN NUMBER
    ) RETURN BOOLEAN;

    PROCEDURE sp_confirmar_pedido (
        p_id_pedido IN PEDIDO.id_pedido%TYPE
    );

    -- Simulacion integrada: confirma el pedido A (delivery) y el pedido B (salon).
    -- Lo llama PKG_SIMULACION.proc_simular en el paso 3. Sin COMMIT.
    PROCEDURE proc_simular (
        p_id_pedido_a IN PEDIDO.id_pedido%TYPE,
        p_id_pedido_b IN PEDIDO.id_pedido%TYPE
    );

    -- Reporte del modulo: salidas de stock de los dos pedidos y existencias finales.
    -- Solo consulta, no modifica nada.
    PROCEDURE proc_reporte (
        p_id_pedido_a IN PEDIDO.id_pedido%TYPE,
        p_id_pedido_b IN PEDIDO.id_pedido%TYPE
    );

    -- Funcion SIN parametros: cuantos insumos estan bajo su stock minimo en toda la cadena.
    -- Se puede usar en SQL: SELECT pkg_stock_receta.fn_insumos_bajo_minimo() FROM dual;
    FUNCTION fn_insumos_bajo_minimo RETURN NUMBER;

    -- Procedimiento SIN parametros: lista los insumos bajo minimo de todos los locales.
    PROCEDURE proc_alerta_stock_minimo;

END pkg_stock_receta;
/

CREATE OR REPLACE PACKAGE BODY pkg_stock_receta AS

    -- privada: stock actual de un insumo en un local (0 si el local no lo tiene)
    FUNCTION fn_stock_actual (
        p_id_local  IN LOCAL.id_local%TYPE,
        p_id_insumo IN INSUMO.id_insumo%TYPE
    ) RETURN NUMBER IS
        v_stock STOCK_LOCAL.cantidad_actual%TYPE;
    BEGIN
        SELECT cantidad_actual
          INTO v_stock
          FROM STOCK_LOCAL
         WHERE id_local  = p_id_local
           AND id_insumo = p_id_insumo;
        RETURN v_stock;
    EXCEPTION
        -- si el local no tiene ese insumo lo tomo como stock 0
        WHEN NO_DATA_FOUND THEN
            RETURN 0;
    END fn_stock_actual;

    FUNCTION fn_stock_disponible (
        p_id_local  IN LOCAL.id_local%TYPE,
        p_id_insumo IN INSUMO.id_insumo%TYPE,
        p_cantidad  IN NUMBER
    ) RETURN BOOLEAN IS
    BEGIN
        RETURN fn_stock_actual(p_id_local, p_id_insumo) >= p_cantidad;
    END fn_stock_disponible;

    PROCEDURE sp_confirmar_pedido (
        p_id_pedido IN PEDIDO.id_pedido%TYPE
    ) IS
        v_id_local  PEDIDO.id_local%TYPE;
        v_consumo   t_consumo_rec;
        v_faltantes t_faltantes := t_faltantes();
        v_lineas    PLS_INTEGER := 0;
        v_salidas   PLS_INTEGER := 0;

        -- tabla indexada por id_insumo: suma lo que pide el pedido completo de cada
        -- insumo (un mismo insumo puede estar en varios productos del pedido)
        TYPE t_requerido_tab IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
        v_requerido t_requerido_tab;
        v_id        PLS_INTEGER;

        -- productos del pedido
        CURSOR c_detalles IS
            SELECT d.id_producto, p.nombre AS producto, d.cantidad
              FROM DETALLE_PEDIDO d
              JOIN PRODUCTO p ON p.id_producto = d.id_producto
             WHERE d.id_pedido = p_id_pedido;

        -- receta de un producto, con parametro porque cambia en cada vuelta
        CURSOR c_receta (cp_id_producto PRODUCTO.id_producto%TYPE) IS
            SELECT r.id_insumo, i.nombre, i.unidad_medida, r.cantidad_requerida
              FROM RECETA r
              JOIN INSUMO i ON i.id_insumo = r.id_insumo
             WHERE r.id_producto = cp_id_producto;
    BEGIN
        BEGIN
            SELECT id_local
              INTO v_id_local
              FROM PEDIDO
             WHERE id_pedido = p_id_pedido;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                DBMS_OUTPUT.PUT_LINE('El pedido ' || p_id_pedido || ' no existe.');
                RAISE ex_pedido_no_existe;
        END;

        -- un pedido que ya tiene salidas de stock no se confirma dos veces
        SELECT COUNT(*)
          INTO v_salidas
          FROM MOVIMIENTO_STOCK
         WHERE id_pedido = p_id_pedido
           AND tipo      = 'SALIDA';

        IF v_salidas > 0 THEN
            DBMS_OUTPUT.PUT_LINE('El pedido ' || p_id_pedido || ' ya fue confirmado: tiene ' ||
                                 v_salidas || ' salida(s) de stock registradas.');
            RAISE ex_pedido_ya_confirmado;
        END IF;

        -- PASO 1: recorro el pedido y sus recetas y sumo lo requerido por insumo (sin tocar nada)
        FOR det IN c_detalles LOOP
            FOR rec IN c_receta(det.id_producto) LOOP
                v_lineas := v_lineas + 1;
                IF v_requerido.EXISTS(rec.id_insumo) THEN
                    v_requerido(rec.id_insumo) := v_requerido(rec.id_insumo) + rec.cantidad_requerida * det.cantidad;
                ELSE
                    v_requerido(rec.id_insumo) := rec.cantidad_requerida * det.cantidad;
                END IF;
            END LOOP;
        END LOOP;

        IF v_lineas = 0 THEN
            DBMS_OUTPUT.PUT_LINE('El pedido ' || p_id_pedido || ' no tiene detalles con receta, nada que descontar.');
            RAISE ex_pedido_sin_receta;
        END IF;

        -- PASO 2: valido todos los insumos contra el stock del local antes de descontar
        v_id := v_requerido.FIRST;
        WHILE v_id IS NOT NULL LOOP
            SELECT nombre, unidad_medida
              INTO v_consumo.nombre, v_consumo.unidad_medida
              FROM INSUMO
             WHERE id_insumo = v_id;

            v_consumo.id_insumo  := v_id;
            v_consumo.requerido  := v_requerido(v_id);
            v_consumo.disponible := fn_stock_actual(v_id_local, v_id);

            -- si no alcanza lo anoto y sigo revisando el resto
            IF NOT fn_stock_disponible(v_id_local, v_consumo.id_insumo, v_consumo.requerido) THEN
                v_faltantes.EXTEND;
                v_faltantes(v_faltantes.LAST) :=
                    v_consumo.nombre || ' (requiere ' || v_consumo.requerido || ' ' ||
                    v_consumo.unidad_medida || ', hay ' || v_consumo.disponible || ')';
            END IF;

            v_id := v_requerido.NEXT(v_id);
        END LOOP;

        -- si falto algo muestro la lista y corto la venta SIN haber descontado nada
        IF v_faltantes.COUNT > 0 THEN
            DBMS_OUTPUT.PUT_LINE('Stock insuficiente en local ' || v_id_local ||
                                 ' para el pedido ' || p_id_pedido || ':');
            FOR i IN 1 .. v_faltantes.COUNT LOOP
                DBMS_OUTPUT.PUT_LINE('  - ' || v_faltantes(i));
            END LOOP;
            RAISE ex_stock_insuficiente;
        END IF;

        -- PASO 3: hay stock de todo, descuento linea por linea y registro cada SALIDA
        FOR det IN c_detalles LOOP
            FOR rec IN c_receta(det.id_producto) LOOP
                v_consumo.requerido := rec.cantidad_requerida * det.cantidad;

                UPDATE STOCK_LOCAL
                   SET cantidad_actual     = cantidad_actual - v_consumo.requerido,
                       fecha_actualizacion = SYSDATE
                 WHERE id_local  = v_id_local
                   AND id_insumo = rec.id_insumo;

                INSERT INTO MOVIMIENTO_STOCK
                    (id_movimiento, tipo, cantidad, fecha_hora, motivo, id_local, id_insumo, id_pedido)
                VALUES
                    (seq_movimiento_stock.NEXTVAL, 'SALIDA', v_consumo.requerido, SYSDATE,
                     'Consumo receta ' || det.producto || ' pedido ' || p_id_pedido,
                     v_id_local, rec.id_insumo, p_id_pedido);

                DBMS_OUTPUT.PUT_LINE('  ' || det.cantidad || ' x ' || RPAD(det.producto, 28) ||
                                     ' -> ' || RPAD(rec.nombre, 20) || ' -' ||
                                     v_consumo.requerido || ' ' || rec.unidad_medida);
            END LOOP;
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('Pedido ' || p_id_pedido || ' confirmado: ' ||
                             v_lineas || ' descuentos de insumo registrados.');
    END sp_confirmar_pedido;

    -- privada: muestra lo que necesita un pedido, lo confirma y cuenta sus salidas
    PROCEDURE pr_simular_pedido (
        p_id_pedido IN PEDIDO.id_pedido%TYPE
    ) IS
        v_detalles PLS_INTEGER;
        v_salidas  PLS_INTEGER;

        -- cursor con parametro: necesidad total de cada insumo del pedido y su stock actual
        CURSOR c_necesidad (cp_id_pedido PEDIDO.id_pedido%TYPE) IS
            SELECT i.id_insumo, i.nombre, i.unidad_medida,
                   SUM(r.cantidad_requerida * d.cantidad) AS requerido,
                   MAX(s.cantidad_actual)                  AS stock_actual
              FROM DETALLE_PEDIDO d
              JOIN PEDIDO p           ON p.id_pedido   = d.id_pedido
              JOIN RECETA r           ON r.id_producto = d.id_producto
              JOIN INSUMO i           ON i.id_insumo   = r.id_insumo
              LEFT JOIN STOCK_LOCAL s ON s.id_local    = p.id_local
                                     AND s.id_insumo   = i.id_insumo
             WHERE d.id_pedido = cp_id_pedido
             GROUP BY i.id_insumo, i.nombre, i.unidad_medida
             ORDER BY i.id_insumo;
    BEGIN
        SELECT COUNT(*)
          INTO v_detalles
          FROM DETALLE_PEDIDO
         WHERE id_pedido = p_id_pedido;

        DBMS_OUTPUT.PUT_LINE('Pedido ' || p_id_pedido || ' tiene ' || v_detalles ||
                             ' detalle(s). Insumos que necesita:');
        FOR n IN c_necesidad(p_id_pedido) LOOP
            DBMS_OUTPUT.PUT_LINE('  ' || RPAD(n.nombre, 20) || ' requiere ' ||
                                 LPAD(n.requerido, 6) || ' ' || RPAD(n.unidad_medida, 3) ||
                                 ' | stock ' || NVL(n.stock_actual, 0));
        END LOOP;

        sp_confirmar_pedido(p_id_pedido);

        SELECT COUNT(*)
          INTO v_salidas
          FROM MOVIMIENTO_STOCK
         WHERE id_pedido = p_id_pedido
           AND tipo      = 'SALIDA';

        DBMS_OUTPUT.PUT_LINE('Movimientos SALIDA registrados para el pedido ' ||
                             p_id_pedido || ': ' || v_salidas);
    END pr_simular_pedido;

    PROCEDURE proc_simular (
        p_id_pedido_a IN PEDIDO.id_pedido%TYPE,
        p_id_pedido_b IN PEDIDO.id_pedido%TYPE
    ) IS
        v_total_salidas PLS_INTEGER;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('--- STOCK POR RECETA: confirmando pedidos ' ||
                             p_id_pedido_a || ' (delivery) y ' || p_id_pedido_b || ' (salon) ---');

        pr_simular_pedido(p_id_pedido_a);
        pr_simular_pedido(p_id_pedido_b);

        SELECT COUNT(*)
          INTO v_total_salidas
          FROM MOVIMIENTO_STOCK
         WHERE id_pedido IN (p_id_pedido_a, p_id_pedido_b)
           AND tipo = 'SALIDA';

        DBMS_OUTPUT.PUT_LINE('Total de salidas de stock de la simulacion: ' || v_total_salidas);
    EXCEPTION
        WHEN ex_stock_insuficiente OR ex_pedido_no_existe
          OR ex_pedido_sin_receta OR ex_pedido_ya_confirmado THEN
            DBMS_OUTPUT.PUT_LINE('Simulacion de stock detenida: el pedido no se pudo confirmar.');
            RAISE;
    END proc_simular;

    PROCEDURE proc_reporte (
        p_id_pedido_a IN PEDIDO.id_pedido%TYPE,
        p_id_pedido_b IN PEDIDO.id_pedido%TYPE
    ) IS
        v_id_local  PEDIDO.id_local%TYPE;
        v_cantidad  PLS_INTEGER := 0;
        v_costo     NUMBER      := 0;

        -- salidas de stock de los dos pedidos, valorizadas con el costo del insumo
        CURSOR c_salidas (cp_a PEDIDO.id_pedido%TYPE, cp_b PEDIDO.id_pedido%TYPE) IS
            SELECT m.id_pedido, i.nombre, m.cantidad, i.unidad_medida,
                   m.cantidad * i.costo_unitario AS costo
              FROM MOVIMIENTO_STOCK m
              JOIN INSUMO i ON i.id_insumo = m.id_insumo
             WHERE m.tipo = 'SALIDA'
               AND m.id_pedido IN (cp_a, cp_b)
             ORDER BY m.id_pedido, m.id_movimiento;

        -- existencias actuales del local de los insumos que se consumieron
        CURSOR c_stock (cp_id_local LOCAL.id_local%TYPE,
                        cp_a PEDIDO.id_pedido%TYPE, cp_b PEDIDO.id_pedido%TYPE) IS
            SELECT i.nombre, s.cantidad_actual, s.stock_minimo, i.unidad_medida
              FROM STOCK_LOCAL s
              JOIN INSUMO i ON i.id_insumo = s.id_insumo
             WHERE s.id_local = cp_id_local
               AND s.id_insumo IN (SELECT id_insumo
                                     FROM MOVIMIENTO_STOCK
                                    WHERE id_pedido IN (cp_a, cp_b))
             ORDER BY i.id_insumo;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('STOCK POR RECETA - pedidos ' || p_id_pedido_a || ' y ' || p_id_pedido_b);

        FOR s IN c_salidas(p_id_pedido_a, p_id_pedido_b) LOOP
            v_cantidad := v_cantidad + 1;
            v_costo    := v_costo + s.costo;
            DBMS_OUTPUT.PUT_LINE('  Pedido ' || s.id_pedido || ' | ' || RPAD(s.nombre, 20) ||
                                 ' -' || LPAD(s.cantidad, 6) || ' ' || RPAD(s.unidad_medida, 3) ||
                                 ' | $' || TO_CHAR(s.costo, 'FM999G999G990'));
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('  Salidas registradas: ' || v_cantidad ||
                             ' | costo de los insumos consumidos: $' || TO_CHAR(v_costo, 'FM999G999G990'));

        SELECT id_local INTO v_id_local FROM PEDIDO WHERE id_pedido = p_id_pedido_a;

        DBMS_OUTPUT.PUT_LINE('  Existencias finales en local ' || v_id_local || ':');
        FOR st IN c_stock(v_id_local, p_id_pedido_a, p_id_pedido_b) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || RPAD(st.nombre, 20) || LPAD(st.cantidad_actual, 8) || ' ' ||
                                 RPAD(st.unidad_medida, 3) || ' (minimo ' || st.stock_minimo || ')' ||
                                 CASE WHEN st.cantidad_actual < st.stock_minimo THEN '  BAJO MINIMO' ELSE '' END);
        END LOOP;
        DBMS_OUTPUT.PUT_LINE('  Insumos bajo minimo en toda la cadena: ' || fn_insumos_bajo_minimo());
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('  No hay datos del pedido ' || p_id_pedido_a || ' para el reporte.');
    END proc_reporte;

    FUNCTION fn_insumos_bajo_minimo RETURN NUMBER IS
        v_n NUMBER;
    BEGIN
        SELECT COUNT(*)
          INTO v_n
          FROM STOCK_LOCAL
         WHERE cantidad_actual < stock_minimo;
        RETURN v_n;
    END fn_insumos_bajo_minimo;

    PROCEDURE proc_alerta_stock_minimo IS
        -- cursor sin parametros: insumos bajo minimo en toda la cadena
        CURSOR c_bajo IS
            SELECT l.nombre AS local_nombre, i.nombre AS insumo, s.cantidad_actual, s.stock_minimo, i.unidad_medida
              FROM STOCK_LOCAL s
              JOIN LOCAL  l ON l.id_local  = s.id_local
              JOIN INSUMO i ON i.id_insumo = s.id_insumo
             WHERE s.cantidad_actual < s.stock_minimo
             ORDER BY l.id_local, i.id_insumo;
    BEGIN
        -- la funcion sin parametros tambien se usa dentro de una sentencia SQL
        FOR r IN (SELECT pkg_stock_receta.fn_insumos_bajo_minimo() AS n FROM dual) LOOP
            DBMS_OUTPUT.PUT_LINE('Insumos bajo stock minimo en la cadena: ' || r.n);
        END LOOP;
        FOR b IN c_bajo LOOP
            DBMS_OUTPUT.PUT_LINE('  ' || RPAD(b.local_nombre, 34) || RPAD(b.insumo, 20) ||
                                 LPAD(b.cantidad_actual, 8) || ' ' || b.unidad_medida || ' (minimo ' || b.stock_minimo || ')');
        END LOOP;
    END proc_alerta_stock_minimo;

END pkg_stock_receta;
/

-- ====================================================================
-- Trigger a NIVEL DE SENTENCIA: despues de cualquier UPDATE del stock (una
-- confirmacion de pedido o una merma) avisa si algun insumo quedo bajo su
-- minimo. Es de sentencia (sin FOR EACH ROW) porque la alerta es una sola
-- por operacion, no una por fila, y asi puede consultar STOCK_LOCAL sin
-- el problema de la tabla mutante.
-- ====================================================================
CREATE OR REPLACE TRIGGER trg_alerta_stock_minimo
AFTER UPDATE OF cantidad_actual ON STOCK_LOCAL
DECLARE
    v_n NUMBER;
BEGIN
    v_n := pkg_stock_receta.fn_insumos_bajo_minimo();
    IF v_n > 0 THEN
        DBMS_OUTPUT.PUT_LINE('ALERTA DE STOCK: ' || v_n || ' insumo(s) bajo el minimo tras esta operacion.');
    END IF;
END;
/

-- ====================================================================
-- Pruebas del modulo (evaluacion parcial 1). Cada una confirma o deshace lo suyo.
-- ====================================================================

-- prueba 1: pedido normal, se descuenta todo
DECLARE
    v_id_pedido   PEDIDO.id_pedido%TYPE;
    v_id_producto PRODUCTO.id_producto%TYPE;
    v_precio      PRODUCTO.precio_venta%TYPE;
    v_cantidad    DETALLE_PEDIDO.cantidad%TYPE := 2;
BEGIN
    SELECT MIN(id_producto) INTO v_id_producto FROM RECETA;

    IF v_id_producto IS NULL THEN
        DBMS_OUTPUT.PUT_LINE('La tabla RECETA esta vacia: no hay nada que descontar.');
        RETURN;
    END IF;

    SELECT precio_venta INTO v_precio FROM PRODUCTO WHERE id_producto = v_id_producto;
    SELECT seq_pedido.NEXTVAL INTO v_id_pedido FROM DUAL;

    INSERT INTO PEDIDO (id_pedido, fecha_hora_creacion, total, id_local, id_canal, id_estado)
    VALUES (v_id_pedido, SYSDATE, v_precio * v_cantidad, 1, 2, 1);

    INSERT INTO DETALLE_PEDIDO (id_detalle, cantidad, precio_unitario, subtotal, estado_kds, id_pedido, id_producto)
    VALUES (seq_detalle_pedido.NEXTVAL,
            v_cantidad, v_precio, v_precio * v_cantidad, 'PENDIENTE', v_id_pedido, v_id_producto);

    DBMS_OUTPUT.PUT_LINE('=== Pedido ' || v_id_pedido || ' creado (' || v_cantidad ||
                         ' x producto ' || v_id_producto || '), confirmando ===');
    pkg_stock_receta.sp_confirmar_pedido(v_id_pedido);
    COMMIT;
EXCEPTION
    WHEN pkg_stock_receta.ex_stock_insuficiente THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('VENTA BLOQUEADA: no se confirma el pedido por falta de stock.');
    WHEN pkg_stock_receta.ex_pedido_no_existe
      OR pkg_stock_receta.ex_pedido_sin_receta THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('PEDIDO RECHAZADO: no se puede confirmar.');
END;
/

-- prueba 2: dejo un insumo casi en 0 para que falle; como se valida antes de
-- descontar, el stock de los demas insumos no se toca. Al final rollback.
DECLARE
    v_id_pedido   PEDIDO.id_pedido%TYPE;
    v_id_producto PRODUCTO.id_producto%TYPE;
    v_id_insumo   INSUMO.id_insumo%TYPE;
    v_precio      PRODUCTO.precio_venta%TYPE;
BEGIN
    SELECT MIN(id_producto) INTO v_id_producto FROM RECETA;

    IF v_id_producto IS NULL THEN
        DBMS_OUTPUT.PUT_LINE('La tabla RECETA esta vacia: no se puede simular falta de stock.');
        RETURN;
    END IF;

    SELECT MIN(id_insumo) INTO v_id_insumo FROM RECETA WHERE id_producto = v_id_producto;
    SELECT precio_venta INTO v_precio FROM PRODUCTO WHERE id_producto = v_id_producto;
    SELECT seq_pedido.NEXTVAL INTO v_id_pedido FROM DUAL;

    INSERT INTO PEDIDO (id_pedido, fecha_hora_creacion, total, id_local, id_canal, id_estado)
    VALUES (v_id_pedido, SYSDATE, v_precio, 1, 2, 1);

    INSERT INTO DETALLE_PEDIDO (id_detalle, cantidad, precio_unitario, subtotal, estado_kds, id_pedido, id_producto)
    VALUES (seq_detalle_pedido.NEXTVAL,
            1, v_precio, v_precio, 'PENDIENTE', v_id_pedido, v_id_producto);

    UPDATE STOCK_LOCAL
       SET cantidad_actual = 0.001
     WHERE id_local  = 1
       AND id_insumo = v_id_insumo;

    DBMS_OUTPUT.PUT_LINE('=== Pedido ' || v_id_pedido || ' creado con stock casi nulo del insumo ' ||
                         v_id_insumo || ', confirmando ===');
    pkg_stock_receta.sp_confirmar_pedido(v_id_pedido);
    ROLLBACK;
EXCEPTION
    WHEN pkg_stock_receta.ex_stock_insuficiente THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('VENTA BLOQUEADA: no se confirma el pedido por falta de stock.');
END;
/

-- prueba 3: pedido que no existe
BEGIN
    pkg_stock_receta.sp_confirmar_pedido(999999);
EXCEPTION
    WHEN pkg_stock_receta.ex_pedido_no_existe THEN
        DBMS_OUTPUT.PUT_LINE('PEDIDO RECHAZADO: no se puede confirmar.');
END;
/

-- prueba 4 (nueva): confirmar dos veces el mismo pedido se rechaza
DECLARE
    v_id_pedido PEDIDO.id_pedido%TYPE;
BEGIN
    SELECT MAX(id_pedido) INTO v_id_pedido
      FROM MOVIMIENTO_STOCK
     WHERE tipo = 'SALIDA' AND id_pedido IS NOT NULL;

    IF v_id_pedido IS NULL THEN
        DBMS_OUTPUT.PUT_LINE('No hay pedidos confirmados para probar la doble confirmacion.');
        RETURN;
    END IF;

    pkg_stock_receta.sp_confirmar_pedido(v_id_pedido);
EXCEPTION
    WHEN pkg_stock_receta.ex_pedido_ya_confirmado THEN
        DBMS_OUTPUT.PUT_LINE('DOBLE CONFIRMACION RECHAZADA: el pedido ' || v_id_pedido || ' ya estaba confirmado.');
END;
/

-- prueba 5 (nueva): procedimiento sin parametros con la alerta de stock minimo
BEGIN
    pkg_stock_receta.proc_alerta_stock_minimo;
END;
/
