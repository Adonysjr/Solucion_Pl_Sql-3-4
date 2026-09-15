-- Problema 3: control de stock por receta
-- La idea es que cuando se confirma un pedido, se descuenten automaticamente
-- los insumos que usa la receta de cada producto vendido. Si falta algun
-- insumo, la venta no se puede confirmar.

SET SERVEROUTPUT ON

-- Agrupo todo en un package para tener la funcion, el procedimiento y las
-- excepciones del problema en un solo lugar.
CREATE OR REPLACE PACKAGE pkg_stock_receta AS

    -- Excepciones definidas por mi. Las declaro en el package para poder
    -- lanzarlas con RAISE dentro del procedimiento y capturarlas por nombre
    -- desde el bloque anonimo que lo llama.
    ex_stock_insuficiente EXCEPTION;
    ex_pedido_no_existe   EXCEPTION;
    ex_pedido_sin_receta  EXCEPTION;

    -- Funcion que responde si hay stock suficiente de un insumo en un local.
    -- La hago funcion porque devuelve un solo valor (TRUE/FALSE) y la
    -- necesito llamar muchas veces dentro del loop.
    FUNCTION fn_stock_disponible (
        p_id_local  IN LOCAL.id_local%TYPE,
        p_id_insumo IN INSUMO.id_insumo%TYPE,
        p_cantidad  IN NUMBER
    ) RETURN BOOLEAN;

    -- Procedimiento principal: valida y descuenta el stock de un pedido.
    -- Es procedimiento porque hace cambios en las tablas (UPDATE e INSERT).
    PROCEDURE sp_confirmar_pedido (
        p_id_pedido IN PEDIDO.id_pedido%TYPE
    );

END pkg_stock_receta;
/

CREATE OR REPLACE PACKAGE BODY pkg_stock_receta AS

    FUNCTION fn_stock_disponible (
        p_id_local  IN LOCAL.id_local%TYPE,
        p_id_insumo IN INSUMO.id_insumo%TYPE,
        p_cantidad  IN NUMBER
    ) RETURN BOOLEAN IS
        v_stock STOCK_LOCAL.cantidad_actual%TYPE;
    BEGIN
        SELECT cantidad_actual
          INTO v_stock
          FROM STOCK_LOCAL
         WHERE id_local  = p_id_local
           AND id_insumo = p_id_insumo;
        RETURN v_stock >= p_cantidad;
    EXCEPTION
        -- Si el local nunca ha tenido ese insumo el SELECT no encuentra fila.
        -- NO_DATA_FOUND es una excepcion predefinida de Oracle, la capturo y
        -- lo interpreto como que no hay stock.
        WHEN NO_DATA_FOUND THEN
            RETURN FALSE;
    END fn_stock_disponible;

    PROCEDURE sp_confirmar_pedido (
        p_id_pedido IN PEDIDO.id_pedido%TYPE
    ) IS
        v_id_local  PEDIDO.id_local%TYPE;
        v_requerido NUMBER(10,3);
        v_lineas    PLS_INTEGER := 0;

        -- Cursor sin parametros: trae los productos y cantidades del pedido.
        -- Usa directamente p_id_pedido porque esta en el mismo scope.
        CURSOR c_detalles IS
            SELECT d.id_producto, p.nombre AS producto, d.cantidad
              FROM DETALLE_PEDIDO d
              JOIN PRODUCTO p ON p.id_producto = d.id_producto
             WHERE d.id_pedido = p_id_pedido;

        -- Cursor con parametro: trae la receta de un producto especifico.
        -- Lo necesito con parametro porque se abre una vez por cada detalle
        -- del pedido, con un producto distinto cada vez.
        CURSOR c_receta (cp_id_producto PRODUCTO.id_producto%TYPE) IS
            SELECT r.id_insumo, i.nombre, i.unidad_medida, r.cantidad_requerida
              FROM RECETA r
              JOIN INSUMO i ON i.id_insumo = r.id_insumo
             WHERE r.id_producto = cp_id_producto;
    BEGIN
        -- Primero verifico que el pedido exista y saco su local, que es
        -- donde se va a descontar el stock.
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

        -- Loop externo: recorre cada linea del pedido.
        FOR det IN c_detalles LOOP
            -- Loop interno: recorre cada insumo de la receta de ese producto.
            FOR rec IN c_receta(det.id_producto) LOOP
                v_lineas    := v_lineas + 1;
                -- Consumo real = lo que pide la receta por la cantidad vendida.
                v_requerido := rec.cantidad_requerida * det.cantidad;

                -- Si no alcanza el stock, lanzo mi excepcion. Como el bloque
                -- que llama hace ROLLBACK, se deshace todo lo descontado antes
                -- y el pedido queda sin confirmar.
                IF NOT fn_stock_disponible(v_id_local, rec.id_insumo, v_requerido) THEN
                    DBMS_OUTPUT.PUT_LINE('Stock insuficiente de ' || rec.nombre ||
                        ' en local ' || v_id_local || ' para ' || det.cantidad || ' x ' ||
                        det.producto || ' (requiere ' || v_requerido || ' ' || rec.unidad_medida || ').');
                    RAISE ex_stock_insuficiente;
                END IF;

                -- Hay stock: descuento del local.
                UPDATE STOCK_LOCAL
                   SET cantidad_actual     = cantidad_actual - v_requerido,
                       fecha_actualizacion = SYSDATE
                 WHERE id_local  = v_id_local
                   AND id_insumo = rec.id_insumo;

                -- Y dejo registrado el movimiento tipo SALIDA asociado al pedido.
                INSERT INTO MOVIMIENTO_STOCK
                    (id_movimiento, tipo, cantidad, fecha_hora, motivo, id_local, id_insumo, id_pedido)
                VALUES
                    (seq_movimiento_stock.NEXTVAL, 'SALIDA', v_requerido, SYSDATE,
                     'Consumo receta ' || det.producto || ' pedido ' || p_id_pedido,
                     v_id_local, rec.id_insumo, p_id_pedido);

                DBMS_OUTPUT.PUT_LINE('  ' || det.cantidad || ' x ' || RPAD(det.producto, 28) ||
                                     ' -> ' || RPAD(rec.nombre, 20) || ' -' ||
                                     v_requerido || ' ' || rec.unidad_medida);
            END LOOP;
        END LOOP;

        -- Si los loops no recorrieron nada, el pedido no tiene detalles o sus
        -- productos no tienen receta, asi que no corresponde confirmarlo.
        IF v_lineas = 0 THEN
            DBMS_OUTPUT.PUT_LINE('El pedido ' || p_id_pedido || ' no tiene detalles con receta, nada que descontar.');
            RAISE ex_pedido_sin_receta;
        END IF;

        DBMS_OUTPUT.PUT_LINE('Pedido ' || p_id_pedido || ' confirmado: ' ||
                             v_lineas || ' descuentos de insumo registrados.');
    END sp_confirmar_pedido;

END pkg_stock_receta;
/

-- Prueba 1: caso normal. Creo un pedido PENDIENTE de prueba con un producto
-- que tenga receta y lo confirmo. Deberia descontar todos los insumos.
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
    SELECT NVL(MAX(id_pedido), 0) + 1 INTO v_id_pedido FROM PEDIDO;

    INSERT INTO PEDIDO (id_pedido, fecha_hora_creacion, total, id_local, id_canal, id_estado)
    VALUES (v_id_pedido, SYSDATE, v_precio * v_cantidad, 1, 2, 1);

    INSERT INTO DETALLE_PEDIDO (id_detalle, cantidad, precio_unitario, subtotal, estado_kds, id_pedido, id_producto)
    VALUES ((SELECT NVL(MAX(id_detalle), 0) + 1 FROM DETALLE_PEDIDO),
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

-- Prueba 2: stock insuficiente. Creo otro pedido y antes de confirmarlo dejo
-- casi en cero el stock de un insumo de la receta, para forzar la excepcion.
-- Al final hago ROLLBACK, asi que esta prueba no deja nada guardado.
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
    SELECT NVL(MAX(id_pedido), 0) + 1 INTO v_id_pedido FROM PEDIDO;

    INSERT INTO PEDIDO (id_pedido, fecha_hora_creacion, total, id_local, id_canal, id_estado)
    VALUES (v_id_pedido, SYSDATE, v_precio, 1, 2, 1);

    INSERT INTO DETALLE_PEDIDO (id_detalle, cantidad, precio_unitario, subtotal, estado_kds, id_pedido, id_producto)
    VALUES ((SELECT NVL(MAX(id_detalle), 0) + 1 FROM DETALLE_PEDIDO),
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

-- Prueba 3: pedido que no existe. Deberia salir la excepcion ex_pedido_no_existe.
BEGIN
    pkg_stock_receta.sp_confirmar_pedido(999999);
EXCEPTION
    WHEN pkg_stock_receta.ex_pedido_no_existe THEN
        DBMS_OUTPUT.PUT_LINE('PEDIDO RECHAZADO: no se puede confirmar.');
END;
/
