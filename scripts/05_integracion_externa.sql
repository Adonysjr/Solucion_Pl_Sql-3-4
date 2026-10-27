/*
======================================
    SOLUCIÓN INTEGRACION EXTERNA
======================================
*/

CREATE OR REPLACE PACKAGE PKG_INTEGRACION_EXTERNA IS

    PROCEDURE proc_mostrar_error(
        p_origen VARCHAR2
    );

    FUNCTION fn_validar_canal_delivery(
        p_id_canal CANAL_VENTA.ID_CANAL%TYPE
    ) RETURN BOOLEAN;

    FUNCTION fn_pedido_externo_existe(
        p_id_canal   CANAL_VENTA.ID_CANAL%TYPE,
        p_id_externo PEDIDO.ID_EXTERNO_DELIVERY%TYPE
    ) RETURN BOOLEAN;

    PROCEDURE proc_agregar_detalle_pedido(
        p_id_pedido   PEDIDO.ID_PEDIDO%TYPE,
        p_id_producto PRODUCTO.ID_PRODUCTO%TYPE,
        p_cantidad    DETALLE_PEDIDO.CANTIDAD%TYPE,
        p_observacion DETALLE_PEDIDO.OBSERVACION%TYPE DEFAULT NULL
    );

    PROCEDURE proc_registrar_pedido_externo(
        p_id_canal    CANAL_VENTA.ID_CANAL%TYPE,
        p_id_externo  PEDIDO.ID_EXTERNO_DELIVERY%TYPE,
        p_id_local    LOCAL.ID_LOCAL%TYPE,
        p_id_cliente  CLIENTE.ID_CLIENTE%TYPE,
        p_id_pedido   OUT PEDIDO.ID_PEDIDO%TYPE,
        p_observacion PEDIDO.OBSERVACION%TYPE DEFAULT NULL
    );

END PKG_INTEGRACION_EXTERNA;
/


CREATE OR REPLACE PACKAGE BODY PKG_INTEGRACION_EXTERNA IS

    -- procedimiento para mostrar errores
    PROCEDURE proc_mostrar_error(
        p_origen VARCHAR2
    ) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('-----------------------------');
        DBMS_OUTPUT.PUT_LINE('ERROR INESPERADO EN ' || p_origen);
        DBMS_OUTPUT.PUT_LINE('CÓDIGO: ' || SQLCODE);
        DBMS_OUTPUT.PUT_LINE('DETALLE: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('-----------------------------');
    END proc_mostrar_error;

FUNCTION fn_validar_canal_delivery(
    p_id_canal CANAL_VENTA.ID_CANAL%TYPE
) RETURN BOOLEAN IS

    canal_valido      NUMBER;
    ex_canal_invalido EXCEPTION;

BEGIN
    -- 1. validar que el canal exista, sea DELIVERY y se encuentre activo
    SELECT COUNT(*)
    INTO canal_valido
    FROM CANAL_VENTA
    WHERE ID_CANAL = p_id_canal
      AND TIPO = 'DELIVERY'
      AND ACTIVO = TRUE;

    -- 2. validar resultado
    IF canal_valido = 0 THEN
        RAISE ex_canal_invalido;
    END IF;

    -- 3. retornar canal valido
    RETURN TRUE;

EXCEPTION
    WHEN ex_canal_invalido THEN
        DBMS_OUTPUT.PUT_LINE(
            'El canal de id: ' ||
            p_id_canal ||
            ' es invalido para delivery.'
        );
        RETURN FALSE;

    WHEN NO_DATA_FOUND THEN
        PKG_INTEGRACION_EXTERNA.proc_mostrar_error(
            'FN_VALIDAR_CANAL_DELIVERY'
        );
        RETURN FALSE;

    WHEN TOO_MANY_ROWS THEN
        PKG_INTEGRACION_EXTERNA.proc_mostrar_error(
            'FN_VALIDAR_CANAL_DELIVERY'
        );
        RETURN FALSE;

    WHEN OTHERS THEN
        PKG_INTEGRACION_EXTERNA.proc_mostrar_error(
            'FN_VALIDAR_CANAL_DELIVERY'
        );
        RAISE;

END fn_validar_canal_delivery;

FUNCTION fn_pedido_externo_existe(
    p_id_canal   CANAL_VENTA.ID_CANAL%TYPE,
    p_id_externo PEDIDO.ID_EXTERNO_DELIVERY%TYPE
) RETURN BOOLEAN IS

    cantidad      NUMBER;
    pedido_existe BOOLEAN;

BEGIN
    -- 1. buscar la combinación canal + identificador externo
    SELECT COUNT(*)
    INTO cantidad
    FROM PEDIDO
    WHERE ID_CANAL = p_id_canal
      AND ID_EXTERNO_DELIVERY = p_id_externo;

    -- 2. determinar si el pedido ya existe
    pedido_existe := cantidad > 0;

    -- 3. retornar resultado
    RETURN pedido_existe;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        PKG_INTEGRACION_EXTERNA.proc_mostrar_error(
            'FN_PEDIDO_EXTERNO_EXISTE'
        );
        RETURN FALSE;

    WHEN TOO_MANY_ROWS THEN
        PKG_INTEGRACION_EXTERNA.proc_mostrar_error(
            'FN_PEDIDO_EXTERNO_EXISTE'
        );
        RETURN FALSE;

    WHEN OTHERS THEN
        PKG_INTEGRACION_EXTERNA.proc_mostrar_error(
            'FN_PEDIDO_EXTERNO_EXISTE'
        );
        RAISE;

END fn_pedido_externo_existe;

PROCEDURE proc_agregar_detalle_pedido(
    p_id_pedido   PEDIDO.ID_PEDIDO%TYPE,
    p_id_producto PRODUCTO.ID_PRODUCTO%TYPE,
    p_cantidad    DETALLE_PEDIDO.CANTIDAD%TYPE,
    p_observacion DETALLE_PEDIDO.OBSERVACION%TYPE DEFAULT NULL
) IS

    -------- CURSORES --------
    CURSOR c_producto(
        producto PRODUCTO.ID_PRODUCTO%TYPE
    ) IS
        SELECT PRECIO_VENTA
        FROM PRODUCTO
        WHERE ID_PRODUCTO = producto
          AND ACTIVO = TRUE;

    -------- VARIABLES --------
    pedido_valido      NUMBER;
    v_precio           PRODUCTO.PRECIO_VENTA%TYPE;
    v_subtotal         DETALLE_PEDIDO.SUBTOTAL%TYPE;

    -------- EXCEPCIONES --------
    ex_pedido_invalido   EXCEPTION;
    ex_producto_invalido EXCEPTION;
    ex_cantidad_invalida EXCEPTION;

BEGIN
    -- 1. validar que el pedido exista
    SELECT COUNT(*)
    INTO pedido_valido
    FROM PEDIDO
    WHERE ID_PEDIDO = p_id_pedido;

    IF pedido_valido = 0 THEN
        RAISE ex_pedido_invalido;
    END IF;


    -- 2. validar que la cantidad sea mayor a cero
    IF p_cantidad <= 0 OR p_cantidad IS NULL THEN
        RAISE ex_cantidad_invalida;
    END IF;


    -- 3. obtener el producto activo y su precio actual
    OPEN c_producto(p_id_producto);
    FETCH c_producto INTO v_precio;

    IF c_producto%NOTFOUND THEN
        CLOSE c_producto;
        RAISE ex_producto_invalido;
    END IF;

    CLOSE c_producto;

    -- 4. calcular subtotal
    v_subtotal := v_precio * p_cantidad;


    -- 5. insertar detalle en estado PENDIENTE
    INSERT INTO DETALLE_PEDIDO (
        ID_DETALLE,
        CANTIDAD,
        PRECIO_UNITARIO,
        SUBTOTAL,
        OBSERVACION,
        ESTADO_KDS,
        ID_PEDIDO,
        ID_PRODUCTO
    ) VALUES (
        SEQ_DETALLE_PEDIDO.NEXTVAL,
        p_cantidad,
        v_precio,
        v_subtotal,
        p_observacion,
        'PENDIENTE',
        p_id_pedido,
        p_id_producto
    );


    -- 6. actualizar total acumulado del pedido
    UPDATE PEDIDO
    SET TOTAL = TOTAL + v_subtotal
    WHERE ID_PEDIDO = p_id_pedido;

EXCEPTION
    WHEN ex_pedido_invalido THEN
        DBMS_OUTPUT.PUT_LINE(
            'El pedido de id: ' ||
            p_id_pedido ||
            ' es invalido.'
        );

    WHEN ex_producto_invalido THEN
        DBMS_OUTPUT.PUT_LINE(
            'El producto de id: ' ||
            p_id_producto ||
            ' no existe o se encuentra inactivo.'
        );

    WHEN ex_cantidad_invalida THEN
        DBMS_OUTPUT.PUT_LINE(
            'La cantidad ingresada debe ser mayor a cero.'
        );

    WHEN OTHERS THEN
        PKG_INTEGRACION_EXTERNA.proc_mostrar_error(
            'PROC_AGREGAR_DETALLE_PEDIDO'
        );
        RAISE;

END proc_agregar_detalle_pedido;

PROCEDURE proc_registrar_pedido_externo(
    p_id_canal    CANAL_VENTA.ID_CANAL%TYPE,
    p_id_externo  PEDIDO.ID_EXTERNO_DELIVERY%TYPE,
    p_id_local    LOCAL.ID_LOCAL%TYPE,
    p_id_cliente  CLIENTE.ID_CLIENTE%TYPE,
    p_id_pedido   OUT PEDIDO.ID_PEDIDO%TYPE,
    p_observacion PEDIDO.OBSERVACION%TYPE DEFAULT NULL
) IS

    -------- VARIABLES --------
    local_valido      NUMBER;
    cliente_valido    NUMBER;

    -------- EXCEPCIONES --------
    ex_canal_invalido     EXCEPTION;
    ex_id_externo_invalido EXCEPTION;
    ex_pedido_duplicado   EXCEPTION;
    ex_local_invalido     EXCEPTION;
    ex_cliente_invalido   EXCEPTION;

BEGIN
    -- 1. validar que el canal corresponda a DELIVERY
    IF NOT PKG_INTEGRACION_EXTERNA.fn_validar_canal_delivery(p_id_canal) THEN
        RAISE ex_canal_invalido;
    END IF;


    -- 2. validar que el identificador externo no sea nulo
    IF p_id_externo IS NULL THEN
        RAISE ex_id_externo_invalido;
    END IF;


    -- 3. validar que el pedido externo no haya sido registrado anteriormente
    IF PKG_INTEGRACION_EXTERNA.fn_pedido_externo_existe(
        p_id_canal,
        p_id_externo
    ) THEN
        RAISE ex_pedido_duplicado;
    END IF;


    -- 4. validar que el local exista y se encuentre activo
    SELECT COUNT(*)
    INTO local_valido
    FROM LOCAL
    WHERE ID_LOCAL = p_id_local
      AND ACTIVO = TRUE;

    IF local_valido = 0 THEN
        RAISE ex_local_invalido;
    END IF;


    -- 5. validar que el cliente exista
    SELECT COUNT(*)
    INTO cliente_valido
    FROM CLIENTE
    WHERE ID_CLIENTE = p_id_cliente;

    IF cliente_valido = 0 THEN
        RAISE ex_cliente_invalido;
    END IF;


    -- 6. generar identificador interno del pedido
    SELECT SEQ_PEDIDO.NEXTVAL
    INTO p_id_pedido
    FROM DUAL;


    -- 7. insertar pedido externo normalizado en estado PENDIENTE
    INSERT INTO PEDIDO (
        ID_PEDIDO,
        FECHA_HORA_CREACION,
        ID_EXTERNO_DELIVERY,
        OBSERVACION,
        TOTAL,
        ID_LOCAL,
        ID_CANAL,
        ID_CLIENTE,
        ID_ESTADO
    ) VALUES (
        p_id_pedido,
        SYSDATE,
        p_id_externo,
        p_observacion,
        0,
        p_id_local,
        p_id_canal,
        p_id_cliente,
        1
    );

    DBMS_OUTPUT.PUT_LINE(
        'Pedido externo registrado correctamente. ID: ' ||
        p_id_pedido
    );

EXCEPTION
    WHEN ex_canal_invalido THEN
        DBMS_OUTPUT.PUT_LINE(
            'El canal de id: ' ||
            p_id_canal ||
            ' no es valido para delivery.'
        );

    WHEN ex_id_externo_invalido THEN
        DBMS_OUTPUT.PUT_LINE(
            'El identificador externo del pedido es obligatorio.'
        );

    WHEN ex_pedido_duplicado THEN
        DBMS_OUTPUT.PUT_LINE(
            'El pedido externo ' ||
            p_id_externo ||
            ' ya fue registrado para el canal ' ||
            p_id_canal ||
            '.'
        );

    WHEN ex_local_invalido THEN
        DBMS_OUTPUT.PUT_LINE(
            'El local de id: ' ||
            p_id_local ||
            ' no existe o se encuentra inactivo.'
        );

    WHEN ex_cliente_invalido THEN
        DBMS_OUTPUT.PUT_LINE(
            'El cliente de id: ' ||
            p_id_cliente ||
            ' es invalido.'
        );

    WHEN NO_DATA_FOUND THEN
        PKG_INTEGRACION_EXTERNA.proc_mostrar_error(
            'PROC_REGISTRAR_PEDIDO_EXTERNO'
        );

    WHEN TOO_MANY_ROWS THEN
        PKG_INTEGRACION_EXTERNA.proc_mostrar_error(
            'PROC_REGISTRAR_PEDIDO_EXTERNO'
        );

    WHEN DUP_VAL_ON_INDEX THEN
        DBMS_OUTPUT.PUT_LINE(
            'El pedido externo ya se encuentra registrado.'
        );

    WHEN OTHERS THEN
        PKG_INTEGRACION_EXTERNA.proc_mostrar_error(
            'PROC_REGISTRAR_PEDIDO_EXTERNO'
        );
        RAISE;

END proc_registrar_pedido_externo;

END PKG_INTEGRACION_EXTERNA;
/

/*
========================================
    SIMULACIÓN INTEGRACION EXTERNA
========================================
*/
DECLARE
    v_pedido     PEDIDO.ID_PEDIDO%TYPE;
    v_duplicado  PEDIDO.ID_PEDIDO%TYPE;
    v_cliente    CLIENTE.ID_CLIENTE%TYPE;
    v_items      PLS_INTEGER;
    v_id_externo PEDIDO.ID_EXTERNO_DELIVERY%TYPE := 'SIM-RAP-DEMO-001';

    -- productos usados en la simulación
    CURSOR c_productos IS
        SELECT ID_PRODUCTO
        FROM PRODUCTO
        WHERE ACTIVO = TRUE
        ORDER BY ID_PRODUCTO
        FETCH FIRST 2 ROWS ONLY;

    -- obtiene el pedido creado
    CURSOR c_pedido(cp_id_pedido PEDIDO.ID_PEDIDO%TYPE) IS
        SELECT ID_PEDIDO, ID_EXTERNO_DELIVERY, TOTAL
        FROM PEDIDO
        WHERE ID_PEDIDO = cp_id_pedido;

    -- detalles asociados al pedido
    CURSOR c_detalles(cp_id_pedido PEDIDO.ID_PEDIDO%TYPE) IS
        SELECT ID_DETALLE
        FROM DETALLE_PEDIDO
        WHERE ID_PEDIDO = cp_id_pedido;

BEGIN
    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('     SIMULACIÓN INTEGRACIÓN EXTERNA');
    DBMS_OUTPUT.PUT_LINE('========================================');

    -- 1. obtener un cliente valido
    SELECT MIN(ID_CLIENTE)
    INTO v_cliente
    FROM CLIENTE;

    -- 2. registrar pedido externo
    PKG_INTEGRACION_EXTERNA.proc_registrar_pedido_externo(
        p_id_canal    => 3,
        p_id_externo  => v_id_externo,
        p_id_local    => 1,
        p_id_cliente  => v_cliente,
        p_id_pedido   => v_pedido,
        p_observacion => 'SIMULACIÓN: INTEGRACIÓN EXTERNA'
    );

    -- 3. agregar dos productos mediante cursor explicito
    FOR producto IN c_productos LOOP
        PKG_INTEGRACION_EXTERNA.proc_agregar_detalle_pedido(
            v_pedido,
            producto.ID_PRODUCTO,
            1
        );
    END LOOP;

    -- 4. recorrer el pedido y sus detalles mediante loops anidados
    FOR pedido IN c_pedido(v_pedido) LOOP
        v_items := 0;

        FOR detalle IN c_detalles(pedido.ID_PEDIDO) LOOP
            v_items := v_items + 1;
        END LOOP;

        DBMS_OUTPUT.PUT_LINE(
            'Pedido: ' || pedido.ID_PEDIDO ||
            ' | Externo: ' || pedido.ID_EXTERNO_DELIVERY ||
            ' | Items: ' || v_items ||
            ' | Total: $' || pedido.TOTAL
        );
    END LOOP;

    -- 5. comprobar funciones de integración
    IF PKG_INTEGRACION_EXTERNA.fn_validar_canal_delivery(3) THEN
        DBMS_OUTPUT.PUT_LINE('Canal delivery valido.');
    END IF;

    IF PKG_INTEGRACION_EXTERNA.fn_pedido_externo_existe(3, v_id_externo) THEN
        DBMS_OUTPUT.PUT_LINE('Pedido externo encontrado correctamente.');
    END IF;

    -- 6. comprobar rechazo de pedido duplicado
    DBMS_OUTPUT.PUT_LINE('--- PRUEBA DE PEDIDO DUPLICADO ---');

    PKG_INTEGRACION_EXTERNA.proc_registrar_pedido_externo(
        p_id_canal   => 3,
        p_id_externo => v_id_externo,
        p_id_local   => 1,
        p_id_cliente => v_cliente,
        p_id_pedido  => v_duplicado
    );

EXCEPTION
    WHEN OTHERS THEN
        PKG_INTEGRACION_EXTERNA.proc_mostrar_error(
            'SIMULACION_INTEGRACION_EXTERNA'
        );
        RAISE;
END;
/
