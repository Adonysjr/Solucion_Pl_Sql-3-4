-- ====================================================================
-- VERSION PROVISIONAL de los packages de los companeros, SOLO para probar
-- PKG_SIMULACION en local. Son sus packages de la parcial 1 + un proc_simular
-- y proc_reporte con las firmas de FIRMAS.md. Cada companero entrega el suyo.
-- ====================================================================

SET SERVEROUTPUT ON


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

END PKG_INTEGRACION_EXTERNA;
/

-- ============================================================
-- PAQUETE DE EXCEPCIONES DEL MÓDULO DE MESAS
-- ============================================================
CREATE OR REPLACE PACKAGE exc_mesas IS

    sin_mesas_local        EXCEPTION;
    PRAGMA EXCEPTION_INIT(sin_mesas_local, -20402);

    rango_horario_invalido EXCEPTION;
    PRAGMA EXCEPTION_INIT(rango_horario_invalido, -20403);

    mesa_no_disponible     EXCEPTION;
    PRAGMA EXCEPTION_INIT(mesa_no_disponible, -20404);

END exc_mesas;
/


-- ============================================================
-- ESPECIFICACIÓN DEL PAQUETE DE GESTIÓN DE MESAS (pkg_mesas)
-- ============================================================
CREATE OR REPLACE PACKAGE pkg_mesas IS

    -- Calcula la duración en minutos entre la apertura y cierre de un pedido
    FUNCTION fn_duracion_atencion_min (
        p_id_pedido PEDIDO.ID_PEDIDO%TYPE
    ) RETURN NUMBER;

    -- Calcula el índice de rotación (pedidos de salón / total mesas)
    FUNCTION fn_rotacion_mesas (
        p_id_local    MESA.ID_LOCAL%TYPE,
        p_fecha       DATE,
        p_hora_inicio VARCHAR2,
        p_hora_fin    VARCHAR2
    ) RETURN NUMBER;

    -- Genera el reporte impreso con promedios y métricas del local
    PROCEDURE sp_reporte_rotacion_local (
        p_id_local    MESA.ID_LOCAL%TYPE,
        p_fecha       DATE,
        p_hora_inicio VARCHAR2,
        p_hora_fin    VARCHAR2
    );


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

END pkg_mesas;
/


-- ============================================================
-- CUERPO DEL PAQUETE DE GESTIÓN DE MESAS (pkg_mesas)
-- ============================================================
CREATE OR REPLACE PACKAGE BODY pkg_mesas IS

    -- Obtiene los timestamps/fechas del pedido y retorna la diferencia en minutos
    FUNCTION fn_duracion_atencion_min (
        p_id_pedido PEDIDO.ID_PEDIDO%TYPE
    ) RETURN NUMBER IS
        v_creacion PEDIDO.FECHA_HORA_CREACION%TYPE;
        v_cierre   PEDIDO.FECHA_HORA_CIERRE%TYPE;
    BEGIN
        SELECT FECHA_HORA_CREACION, FECHA_HORA_CIERRE
        INTO v_creacion, v_cierre
        FROM PEDIDO
        WHERE ID_PEDIDO = p_id_pedido;

        -- Si el pedido sigue abierto no hay tiempo final de atención
        IF v_cierre IS NULL THEN
            RETURN NULL;
        END IF;

        -- Diferencia entre dos DATE = días; se convierte a minutos (* 24 * 60)
        RETURN ROUND((v_cierre - v_creacion) * 24 * 60, 1);

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20401, 'Pedido no encontrado: ' || p_id_pedido);
    END fn_duracion_atencion_min;


    -- Valida parámetros y obtiene la rotación de mesas para un período
    FUNCTION fn_rotacion_mesas (
        p_id_local    MESA.ID_LOCAL%TYPE,
        p_fecha       DATE,
        p_hora_inicio VARCHAR2,
        p_hora_fin    VARCHAR2
    ) RETURN NUMBER IS
        v_cantidad_mesas NUMBER;
        v_pedidos_salon  NUMBER;
    BEGIN
        -- Validación básica de rango de horas
        IF TO_DATE(p_hora_inicio, 'HH24:MI') >= TO_DATE(p_hora_fin, 'HH24:MI') THEN
            RAISE exc_mesas.rango_horario_invalido;
        END IF;

        -- Contar cuántas mesas físicas tiene el local
        SELECT COUNT(*) INTO v_cantidad_mesas
        FROM MESA
        WHERE ID_LOCAL = p_id_local;

        IF v_cantidad_mesas = 0 THEN
            RAISE exc_mesas.sin_mesas_local;
        END IF;

        -- Contar pedidos asignados a mesa dentro de la fecha y tramo horario
        SELECT COUNT(*) INTO v_pedidos_salon
        FROM PEDIDO
        WHERE ID_LOCAL = p_id_local
          AND ID_MESA IS NOT NULL
          AND TRUNC(FECHA_HORA_CREACION) = TRUNC(p_fecha)
          AND TO_CHAR(FECHA_HORA_CREACION, 'HH24:MI')
              BETWEEN p_hora_inicio AND p_hora_fin;

        -- Cálculo del indicador de rotación
        RETURN ROUND(v_pedidos_salon / v_cantidad_mesas, 2);

    EXCEPTION
        WHEN exc_mesas.sin_mesas_local THEN
            DBMS_OUTPUT.PUT_LINE('ERROR: El local ' || p_id_local || ' no tiene mesas registradas.');
            RETURN NULL;
        WHEN exc_mesas.rango_horario_invalido THEN
            DBMS_OUTPUT.PUT_LINE('ERROR: La hora de inicio debe ser menor a la hora de fin.');
            RETURN NULL;
    END fn_rotacion_mesas;


    -- Imprime el detalle mediante cursor explícito y resume los KPIs
    PROCEDURE sp_reporte_rotacion_local (
        p_id_local    MESA.ID_LOCAL%TYPE,
        p_fecha       DATE,
        p_hora_inicio VARCHAR2,
        p_hora_fin    VARCHAR2
    ) IS
        -- Cursor explícito para iterar los pedidos del tramo consultado
        CURSOR cur_pedidos_salon IS
            SELECT p.ID_PEDIDO, p.ID_MESA, m.NUMERO_MESA,
                   p.FECHA_HORA_CREACION, p.FECHA_HORA_CIERRE
            FROM PEDIDO p
            JOIN MESA m ON p.ID_MESA = m.ID_MESA
            WHERE p.ID_LOCAL = p_id_local
              AND p.ID_MESA IS NOT NULL
              AND TRUNC(p.FECHA_HORA_CREACION) = TRUNC(p_fecha)
              AND TO_CHAR(p.FECHA_HORA_CREACION, 'HH24:MI')
                  BETWEEN p_hora_inicio AND p_hora_fin
            ORDER BY p.FECHA_HORA_CREACION;

        v_duracion         NUMBER;
        v_suma_duracion    NUMBER := 0;
        v_cant_cerrados    NUMBER := 0;
        v_cantidad_pedidos NUMBER := 0;
        v_rotacion         NUMBER;

    BEGIN
        DBMS_OUTPUT.PUT_LINE('ROTACION DE MESAS - Local ' || p_id_local ||
                             ' - ' || TO_CHAR(p_fecha, 'DD-MM-YYYY') ||
                             ' (' || p_hora_inicio || ' a ' || p_hora_fin || ')');
        DBMS_OUTPUT.PUT_LINE('======================================================');

        -- Recorrido del cursor con FOR LOOP
        FOR pedido IN cur_pedidos_salon LOOP
            v_cantidad_pedidos := v_cantidad_pedidos + 1;
            v_duracion := fn_duracion_atencion_min(pedido.ID_PEDIDO);

            IF v_duracion IS NULL THEN
                DBMS_OUTPUT.PUT_LINE('Pedido ' || pedido.ID_PEDIDO || ' - Mesa ' ||
                                     pedido.NUMERO_MESA || ' - AUN NO CIERRA');
            ELSE
                DBMS_OUTPUT.PUT_LINE('Pedido ' || pedido.ID_PEDIDO || ' - Mesa ' ||
                                     pedido.NUMERO_MESA || ' - Duracion: ' ||
                                     v_duracion || ' min');
                v_suma_duracion := v_suma_duracion + v_duracion;
                v_cant_cerrados := v_cant_cerrados + 1;
            END IF;
        END LOOP;

        IF v_cantidad_pedidos = 0 THEN
            DBMS_OUTPUT.PUT_LINE('No se encontraron pedidos de salon en el periodo.');
        END IF;

        -- Consolidación llamando a la función del paquete
        v_rotacion := fn_rotacion_mesas(p_id_local, p_fecha, p_hora_inicio, p_hora_fin);

        DBMS_OUTPUT.PUT_LINE('======================================================');
        IF v_cant_cerrados > 0 THEN
            DBMS_OUTPUT.PUT_LINE('Duracion promedio de atencion: ' ||
                                 ROUND(v_suma_duracion / v_cant_cerrados, 1) || ' min');
        END IF;
        DBMS_OUTPUT.PUT_LINE('Rotacion de mesas del periodo: ' || v_rotacion);

    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error en sp_reporte_rotacion_local: ' || SQLERRM);
            RAISE;
    END sp_reporte_rotacion_local;


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

END pkg_mesas;
/


-- ============================================================
-- TRIGGERS DEL MÓDULO DE MESAS
-- ============================================================

-- Trigger para ocupar la mesa de forma automática al ingresar un pedido
CREATE OR REPLACE TRIGGER trg_ocupar_mesa
AFTER INSERT ON PEDIDO
FOR EACH ROW
WHEN (NEW.ID_MESA IS NOT NULL)
DECLARE
    v_ocupada MESA.OCUPADA%TYPE;
BEGIN
    SELECT OCUPADA INTO v_ocupada
    FROM MESA
    WHERE ID_MESA = :NEW.ID_MESA;

    -- Valida disponibilidad usando el valor del campo
    IF v_ocupada THEN
        RAISE_APPLICATION_ERROR(-20404,
            'La mesa ' || :NEW.ID_MESA || ' ya se encuentra ocupada.');
    END IF;

    -- Actualiza el estado a ocupado (BOOLEAN nativo en Oracle 23ai)
    UPDATE MESA
    SET OCUPADA = TRUE
    WHERE ID_MESA = :NEW.ID_MESA;

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error en trg_ocupar_mesa: ' || SQLERRM);
        RAISE;
END;
/


-- Trigger para liberar la mesa de forma automática al registrar la hora de cierre
CREATE OR REPLACE TRIGGER trg_liberar_mesa
AFTER UPDATE OF FECHA_HORA_CIERRE ON PEDIDO
FOR EACH ROW
WHEN (NEW.FECHA_HORA_CIERRE IS NOT NULL
      AND OLD.FECHA_HORA_CIERRE IS NULL
      AND NEW.ID_MESA IS NOT NULL)
BEGIN
    -- Actualiza el estado a libre (BOOLEAN nativo en Oracle 23ai)
    UPDATE MESA
    SET OCUPADA = FALSE
    WHERE ID_MESA = :NEW.ID_MESA;

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error en trg_liberar_mesa: ' || SQLERRM);
        RAISE;
END;
/


/*
================================
    SOLUCIÓN TIEMPOS PEDIDOS
================================
*/

CREATE OR REPLACE PACKAGE PKG_GESTION_KDS IS

    PROCEDURE proc_mostrar_error(p_origen VARCHAR2);

    FUNCTION fn_tiempo_espera(
        p_id_pedido PEDIDO.ID_PEDIDO%TYPE
    ) RETURN NUMBER;

    FUNCTION fn_tiempo_preparacion_pedido(
        p_id_pedido PEDIDO.ID_PEDIDO%TYPE
    ) RETURN NUMBER;

    FUNCTION fn_prioridad_kds(
        p_id_pedido PEDIDO.ID_PEDIDO%TYPE
    ) RETURN NUMBER;

    PROCEDURE proc_gestionar_kds(
        p_id_local LOCAL.ID_LOCAL%TYPE
    );

    PROCEDURE proc_marcar_detalle_listo(
        p_id_detalle DETALLE_PEDIDO.ID_DETALLE%TYPE
    );


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

END PKG_GESTION_KDS;
/

CREATE OR REPLACE PACKAGE BODY PKG_GESTION_KDS IS


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

FUNCTION fn_tiempo_espera(p_id_pedido PEDIDO.ID_PEDIDO%TYPE)
    RETURN NUMBER IS

    -- cursor pedido
    CURSOR c_pedido(id_ped PEDIDO.ID_PEDIDO%TYPE) IS
        SELECT FECHA_HORA_CREACION FROM PEDIDO WHERE ID_PEDIDO = id_ped;

    f_hora_creacion PEDIDO.FECHA_HORA_CREACION%TYPE;

    diff                NUMBER;
    tiempo_espera       NUMBER; -- tiempo en minutos
    ex_pedido_no_existe EXCEPTION;
BEGIN
    OPEN c_pedido(p_id_pedido);
    FETCH c_pedido INTO f_hora_creacion;

    IF c_pedido%NOTFOUND THEN
        CLOSE c_pedido;
        RAISE ex_pedido_no_existe;
    END IF;

    diff            := SYSDATE - f_hora_creacion;
    tiempo_espera   := TRUNC(diff * 24 * 60);

    CLOSE c_pedido;

    RETURN tiempo_espera;
EXCEPTION
    WHEN ex_pedido_no_existe THEN
        DBMS_OUTPUT.PUT_LINE('Error: El pedido ' || p_id_pedido || ' no existe.');
        RETURN NULL;

    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE(
            'Error: No se encontraron datos para el pedido ' || p_id_pedido || '.'
        );
        RETURN NULL;

    WHEN TOO_MANY_ROWS THEN
        DBMS_OUTPUT.PUT_LINE(
            'Error: Se encontraron multiples registros para el pedido ' || p_id_pedido || '.'
        );
        RETURN NULL;

    WHEN OTHERS THEN
        PKG_GESTION_KDS.proc_mostrar_error('FN_TIEMPO_ESPERA');
        RAISE;

END fn_tiempo_espera;

FUNCTION fn_tiempo_preparacion_pedido(p_id_pedido PEDIDO.ID_PEDIDO%TYPE)
    RETURN NUMBER IS

    CURSOR c_tiempo_prep(pedido DETALLE_PEDIDO.ID_PEDIDO%TYPE) IS
        SELECT MAX(p.tiempo_preparacion_min) FROM DETALLE_PEDIDO d
        JOIN PRODUCTO p ON p.id_producto = d.id_producto
        WHERE d.id_pedido = pedido;

    tiempo_preparacion  NUMBER;
    ex_sin_productos    EXCEPTION;
BEGIN
    OPEN c_tiempo_prep(p_id_pedido);
    fetch c_tiempo_prep INTO tiempo_preparacion;
    CLOSE c_tiempo_prep;

    -- si el resultado del fetch es NULL arrojamos excepción
    IF tiempo_preparacion IS NULL THEN
        RAISE ex_sin_productos;
    END IF;

    RETURN tiempo_preparacion;

EXCEPTION
    WHEN ex_sin_productos THEN
        DBMS_OUTPUT.PUT_LINE(
            'Error: El pedido ' || p_id_pedido || ' no tiene productos asociados.'
        );
        RETURN NULL;

    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE(
            'Error: No se encontraron datos para el pedido ' || p_id_pedido || '.'
        );
        RETURN NULL;

    WHEN TOO_MANY_ROWS THEN
        DBMS_OUTPUT.PUT_LINE(
            'Error: Se encontraron multiples registros para el pedido ' || p_id_pedido || '.'
        );
        RETURN NULL;

    WHEN OTHERS THEN
        PKG_GESTION_KDS.proc_mostrar_error('FN_TIEMPO_PREPARACION_PEDIDO');
        RAISE;
END fn_tiempo_preparacion_pedido;


FUNCTION fn_prioridad_kds(p_id_pedido PEDIDO.ID_PEDIDO%TYPE) RETURN NUMBER IS
    tiempo_espera       NUMBER;
    tiempo_prep         NUMBER;
    puntaje             NUMBER;
    suavizado           NUMBER := 5; -- suavizar curva
BEGIN
    -- 1. obtener tiempo espera (cuanto lleva esperando desde que se creo el pedido)
    tiempo_espera := PKG_GESTION_KDS.fn_tiempo_espera(p_id_pedido);

    -- 2. obtener tiempo base de preparacion (tiempo máximo de preparacion / pedido con tiempo mas alto)
    tiempo_prep := PKG_GESTION_KDS.fn_tiempo_preparacion_pedido(p_id_pedido);

    -- 3. calcular puntaje = P + (E/5)^2
    puntaje := tiempo_prep + (tiempo_espera / suavizado) ** 2;

    RETURN puntaje;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE(
            'Error: No se encontraron datos para calcular la prioridad del pedido ' ||
            p_id_pedido || '.'
        );
        RETURN NULL;

    WHEN TOO_MANY_ROWS THEN
        DBMS_OUTPUT.PUT_LINE(
            'Error: Se encontraron multiples registros al calcular la prioridad del pedido ' ||
            p_id_pedido || '.'
        );
        RETURN NULL;

    WHEN OTHERS THEN
        PKG_GESTION_KDS.proc_mostrar_error('FN_PRIORIDAD_KDS');
        RAISE;

END fn_prioridad_kds;


PROCEDURE proc_gestionar_kds(p_id_local LOCAL.ID_LOCAL%TYPE) IS
    -------- CURSORES --------
    CURSOR c_cocineros_disponibles(local LOCAL.ID_LOCAL%TYPE) IS
        SELECT COUNT(*) FROM EMPLEADO
        WHERE CARGO = 'COCINERO'
        AND ACTIVO = TRUE
        AND ID_LOCAL=local;

    CURSOR c_platos_en_prep(local LOCAL.ID_LOCAL%TYPE) IS
        SELECT NVL(SUM(dp.cantidad), 0)
        FROM PEDIDO p JOIN DETALLE_PEDIDO dp
        ON p.id_pedido = dp.id_pedido
        WHERE p.id_local = local
        AND dp.estado_kds = 'PREPARANDO';

    -- pedidos pendientes ordenados por prioridad de mayor a menor
    -- trae id_pedido, puntaje_prioridad y total de platos
    CURSOR c_pedidos_pendientes(local PEDIDO.ID_LOCAL%TYPE) IS
    SELECT  p.id_pedido,
            PKG_GESTION_KDS.fn_prioridad_kds(p.id_pedido) AS puntaje_prioridad,
            SUM(dp.cantidad) AS total_platos
            FROM PEDIDO p
            JOIN DETALLE_PEDIDO dp ON p.id_pedido = dp.id_pedido
            WHERE p.id_estado = 1
            AND dp.estado_kds = 'PENDIENTE'
            AND p.id_local = local
            GROUP BY p.id_pedido
            ORDER BY puntaje_prioridad DESC;

    -------- RECORDS --------
    TYPE r_pedidos_p IS RECORD(
        id              PEDIDO.ID_PEDIDO%TYPE,
        puntaje         NUMBER,
        total_platos    NUMBER
    );


    -------- VARIABLES --------
    local_valido            NUMBER;
    capacidad_por_cocinero  NUMBER:= 5;

    cocineros_disponibles   NUMBER;
    capacidad_cocina        NUMBER;
    platos_en_prep          NUMBER;
    capacidad_disponible    NUMBER;

    pedidos_p               r_pedidos_p;

    -------- EXCEPCIONES --------
    ex_local_invalido       EXCEPTION;
BEGIN
    -- 1. validar local
    SELECT COUNT(*) INTO local_valido FROM LOCAL
    WHERE ID_LOCAL = p_id_local AND ACTIVO = TRUE;

    IF local_valido = 0 THEN
        RAISE ex_local_invalido;
    END IF;

    -- 2. contar los cocineros activos del local
    OPEN c_cocineros_disponibles(p_id_local);
    FETCH c_cocineros_disponibles INTO cocineros_disponibles;
    CLOSE c_cocineros_disponibles;
    -- capacidad maxima de cocina
    capacidad_cocina := cocineros_disponibles * capacidad_por_cocinero;

    -- 3. contar los pedidos que ya se encuentran EN_PREPARACION
    OPEN c_platos_en_prep(p_id_local);
    FETCH c_platos_en_prep INTO platos_en_prep;
    CLOSE c_platos_en_prep;

    -- 4. calcular capacidad disponible de cocina
    capacidad_disponible := capacidad_cocina - platos_en_prep;
    DBMS_OUTPUT.PUT_LINE('Capacidad disponible: ' || capacidad_disponible);

    -- 5. obtener los pedidos PENDIENTES ordenados por FN_PRIORIDAD_KDS
    OPEN c_pedidos_pendientes(p_id_local);
    FETCH c_pedidos_pendientes INTO pedidos_p;

    -- 6. recorrer los pedidos mientras exista capacidad disponible
    LOOP
        EXIT WHEN c_pedidos_pendientes%NOTFOUND;

        DBMS_OUTPUT.PUT_LINE('ID PEDIDO:    ' || pedidos_p.id);
        DBMS_OUTPUT.PUT_LINE('PUNTAJE:      ' || pedidos_p.puntaje);
        DBMS_OUTPUT.PUT_LINE('TOTAL PLATOS: ' || pedidos_p.total_platos);


        IF pedidos_p.total_platos <= capacidad_disponible THEN
            DBMS_OUTPUT.PUT_LINE('-----------------------------');

            DBMS_OUTPUT.PUT_LINE('UPDATE pedido id: '|| pedidos_p.id || ' NUEVO ESTADO: PREPARANDO');

            -- 7. cambiar los detalles PENDIENTES seleccionados a PREPARANDO y registrar FECHA_HORA_INICIO
            UPDATE DETALLE_PEDIDO SET ESTADO_KDS = 'PREPARANDO', FECHA_HORA_INICIO = SYSDATE
            WHERE ID_PEDIDO = pedidos_p.id AND ESTADO_KDS = 'PENDIENTE';

            -- restar platos de la capacidad de cocina
            capacidad_disponible := capacidad_disponible - pedidos_p.total_platos;
            DBMS_OUTPUT.PUT_LINE('Capacidad disponible: ' || capacidad_disponible);

            -- 8. actualizar el pedido correspondiente a EN_PREPARACION.
            UPDATE PEDIDO SET ID_ESTADO = 2 WHERE ID_PEDIDO = pedidos_p.id;

        END IF;
        DBMS_OUTPUT.PUT_LINE('-----------------------------');

        FETCH c_pedidos_pendientes INTO pedidos_p;
    END LOOP;
    CLOSE c_pedidos_pendientes;

EXCEPTION
    WHEN ex_local_invalido THEN
        DBMS_OUTPUT.PUT_LINE(
            'El local ' || p_id_local || ' es invalido'
        );

    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE(
            'Error: No se encontraron datos necesarios para gestionar el KDS del local ' ||
            p_id_local || '.'
        );

    WHEN TOO_MANY_ROWS THEN
        DBMS_OUTPUT.PUT_LINE(
            'Error: Se encontraron multiples registros inesperados al gestionar el KDS del local ' ||
            p_id_local || '.'
        );

    WHEN OTHERS THEN
        PKG_GESTION_KDS.proc_mostrar_error('PROC_GESTIONAR_KDS');
        RAISE;

END proc_gestionar_kds;

PROCEDURE proc_marcar_detalle_listo(p_id_detalle DETALLE_PEDIDO.ID_DETALLE%TYPE) IS

    -------- CURSORES --------
    CURSOR c_detalle_pedido(
        detalle DETALLE_PEDIDO.ID_DETALLE%TYPE
    ) IS
        SELECT ID_PEDIDO, ESTADO_KDS
        FROM DETALLE_PEDIDO
        WHERE ID_DETALLE = detalle;

    -------- RECORDS --------
    TYPE r_detalle IS RECORD(
        id_pedido DETALLE_PEDIDO.ID_PEDIDO%TYPE,
        estado    DETALLE_PEDIDO.ESTADO_KDS%TYPE
    );

    -------- VARIABLES --------
    detalle_valido NUMBER;
    detalle        r_detalle;

    -------- EXCEPCIONES --------
    ex_detalle_invalido        EXCEPTION;
    ex_estado_detalle_invalido EXCEPTION;

BEGIN
    -- 1. validar que el detalle exista
    SELECT COUNT(*)
    INTO detalle_valido
    FROM DETALLE_PEDIDO
    WHERE ID_DETALLE = p_id_detalle;

    IF detalle_valido = 0 THEN
        RAISE ex_detalle_invalido;
    END IF;


    -- 2. obtener el pedido asociado y el estado actual del detalle
    OPEN c_detalle_pedido(p_id_detalle);
    FETCH c_detalle_pedido INTO detalle;
    CLOSE c_detalle_pedido;


    -- 3. validar que el detalle este en estado PREPARANDO
    IF detalle.estado != 'PREPARANDO' THEN
        RAISE ex_estado_detalle_invalido;
    END IF;


    -- 4. marcar el detalle como LISTO y registrar la hora de finalización
    UPDATE DETALLE_PEDIDO
    SET ESTADO_KDS = 'LISTO',
        FECHA_HORA_LISTO = SYSDATE
    WHERE ID_DETALLE = p_id_detalle;

    -- TRG_ACTUALIZAR_PEDIDO_LISTO se encarga de validar
    -- automáticamente si el pedido completo debe pasar a estado LISTO

EXCEPTION
    WHEN ex_detalle_invalido THEN
        DBMS_OUTPUT.PUT_LINE(
            'El detalle de pedido id: ' ||
            p_id_detalle ||
            ' es invalido.'
        );

    WHEN ex_estado_detalle_invalido THEN
        DBMS_OUTPUT.PUT_LINE(
            'El ESTADO_KDS para detalle de pedido id: ' ||
            p_id_detalle ||
            ' es invalido.'
        );

    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE(
            'Error: No se encontraron datos para el detalle de pedido id: ' ||
            p_id_detalle || '.'
        );

    WHEN TOO_MANY_ROWS THEN
        DBMS_OUTPUT.PUT_LINE(
            'Error: Se encontraron multiples registros para el detalle de pedido id: ' ||
            p_id_detalle || '.'
        );

    WHEN OTHERS THEN
        PKG_GESTION_KDS.proc_mostrar_error(
            'PROC_MARCAR_DETALLE_LISTO'
        );
        RAISE;

END proc_marcar_detalle_listo;


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

END PKG_GESTION_KDS;
/


CREATE OR REPLACE TRIGGER trg_actualizar_pedido_listo
AFTER UPDATE OF estado_kds ON DETALLE_PEDIDO
BEGIN
    UPDATE PEDIDO p
    -- 1. cambiar el estado del pedido a LISTO
    SET p.id_estado = 3
    -- 2. considerar solo pedidos que actualmente estén EN_PREPARACION
    WHERE p.id_estado = 2
      -- 3. validar que el pedido tenga detalles asociados
      AND EXISTS (
          SELECT 1
          FROM DETALLE_PEDIDO d
          WHERE d.id_pedido = p.id_pedido
      )

      -- 4. validar que no exista ningún detalle que aun no este LISTO
      AND NOT EXISTS (
          SELECT 1
          FROM DETALLE_PEDIDO d
          WHERE d.id_pedido = p.id_pedido
            AND d.estado_kds <> 'LISTO'
      );
END;
/


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


    -- Simulacion integrada (provisional): pagos, boletas y DTE de los dos pedidos.
    PROCEDURE proc_simular (
        p_id_pedido_a IN PEDIDO.ID_PEDIDO%TYPE,
        p_id_pedido_b IN PEDIDO.ID_PEDIDO%TYPE
    );

    PROCEDURE proc_reporte (
        p_id_pedido_a IN PEDIDO.ID_PEDIDO%TYPE,
        p_id_pedido_b IN PEDIDO.ID_PEDIDO%TYPE
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

END pkg_facturacion;
/
