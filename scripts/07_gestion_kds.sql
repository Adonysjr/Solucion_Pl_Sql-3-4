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

/*
===============================
    SIMULACIÓN GESTION KDS
===============================
*/
DECLARE
    v_local       LOCAL.ID_LOCAL%TYPE := 1;
    v_pedido_1    PEDIDO.ID_PEDIDO%TYPE;
    v_pedido_2    PEDIDO.ID_PEDIDO%TYPE;
    v_procesados  PLS_INTEGER;

    -- cursor sin parametros: productos para generar los pedidos
    CURSOR c_productos IS
        SELECT ID_PRODUCTO, PRECIO_VENTA,
               ROW_NUMBER() OVER (ORDER BY ID_PRODUCTO) AS n
        FROM PRODUCTO
        ORDER BY ID_PRODUCTO
        FETCH FIRST 5 ROWS ONLY;

    -- cursor parametrizado: pedidos creados en la simulacion
    CURSOR c_pedidos(
        cp_pedido_1 PEDIDO.ID_PEDIDO%TYPE,
        cp_pedido_2 PEDIDO.ID_PEDIDO%TYPE
    ) IS
        SELECT ID_PEDIDO
        FROM PEDIDO
        WHERE ID_PEDIDO IN (cp_pedido_1, cp_pedido_2)
        ORDER BY ID_PEDIDO;

    -- cursor parametrizado: detalles que pueden finalizarse
    CURSOR c_detalles(cp_id_pedido PEDIDO.ID_PEDIDO%TYPE) IS
        SELECT ID_DETALLE
        FROM DETALLE_PEDIDO
        WHERE ID_PEDIDO = cp_id_pedido
          AND ESTADO_KDS = 'PREPARANDO'
        ORDER BY ID_DETALLE;

    -- cursor parametrizado: resultado final de los pedidos
    CURSOR c_resultado(
        cp_pedido_1 PEDIDO.ID_PEDIDO%TYPE,
        cp_pedido_2 PEDIDO.ID_PEDIDO%TYPE
    ) IS
        SELECT pe.ID_PEDIDO, pe.ID_ESTADO,
               COUNT(*) AS TOTAL,
               SUM(CASE WHEN d.ESTADO_KDS = 'LISTO' THEN 1 ELSE 0 END) AS LISTOS
        FROM PEDIDO pe
        JOIN DETALLE_PEDIDO d ON d.ID_PEDIDO = pe.ID_PEDIDO
        WHERE pe.ID_PEDIDO IN (cp_pedido_1, cp_pedido_2)
        GROUP BY pe.ID_PEDIDO, pe.ID_ESTADO
        ORDER BY pe.ID_PEDIDO;

BEGIN
    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('       SIMULACIÓN GESTION KDS');
    DBMS_OUTPUT.PUT_LINE('========================================');

    -- 1. crear dos pedidos con distintos tiempos de espera
    SELECT SEQ_PEDIDO.NEXTVAL INTO v_pedido_1 FROM DUAL;
    SELECT SEQ_PEDIDO.NEXTVAL INTO v_pedido_2 FROM DUAL;

    INSERT INTO PEDIDO
        (ID_PEDIDO, FECHA_HORA_CREACION, OBSERVACION, TOTAL,
         ID_LOCAL, ID_CANAL, ID_ESTADO)
    VALUES
        (v_pedido_1, SYSDATE - 20/1440, 'SIMULACION KDS 3 PLATOS',
         0, v_local, 2, 1);

    INSERT INTO PEDIDO
        (ID_PEDIDO, FECHA_HORA_CREACION, OBSERVACION, TOTAL,
         ID_LOCAL, ID_CANAL, ID_ESTADO)
    VALUES
        (v_pedido_2, SYSDATE - 10/1440, 'SIMULACION KDS 2 PLATOS',
         0, v_local, 2, 1);

    -- 2. agregar 3 platos al primero y 2 al segundo
    FOR producto IN c_productos LOOP
        INSERT INTO DETALLE_PEDIDO (
            ID_DETALLE, CANTIDAD, PRECIO_UNITARIO, SUBTOTAL,
            ESTADO_KDS, ID_PEDIDO, ID_PRODUCTO
        ) VALUES (
            SEQ_DETALLE_PEDIDO.NEXTVAL,
            1,
            producto.PRECIO_VENTA,
            producto.PRECIO_VENTA,
            'PENDIENTE',
            CASE WHEN producto.n <= 3 THEN v_pedido_1 ELSE v_pedido_2 END,
            producto.ID_PRODUCTO
        );
    END LOOP;

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- CÁLCULOS KDS ---');

    -- 3. calcular espera, preparacion y prioridad
    FOR pedido IN c_pedidos(v_pedido_1, v_pedido_2) LOOP
        DBMS_OUTPUT.PUT_LINE(
            'Pedido ' || pedido.ID_PEDIDO ||
            ' | espera: ' ||
            PKG_GESTION_KDS.fn_tiempo_espera(pedido.ID_PEDIDO) || ' min' ||
            ' | preparación: ' ||
            PKG_GESTION_KDS.fn_tiempo_preparacion_pedido(pedido.ID_PEDIDO) || ' min' ||
            ' | prioridad: ' ||
            ROUND(PKG_GESTION_KDS.fn_prioridad_kds(pedido.ID_PEDIDO), 2)
        );
    END LOOP;

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- INGRESO A COCINA ---');

    -- 4. ordenar pedidos por prioridad y capacidad
    PKG_GESTION_KDS.proc_gestionar_kds(v_local);

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- FINALIZACIÓN DE PLATOS ---');

    -- 5. recorrer pedidos y detalles mediante loops anidados
    -- se finalizan como maximo 2 detalles por pedido:
    -- pedido 1 queda 2/3 y pedido 2 queda 2/2
    FOR pedido IN c_pedidos(v_pedido_1, v_pedido_2) LOOP
        v_procesados := 0;

        FOR detalle IN c_detalles(pedido.ID_PEDIDO) LOOP
            EXIT WHEN v_procesados = 2;

            PKG_GESTION_KDS.proc_marcar_detalle_listo(
                detalle.ID_DETALLE
            );

            v_procesados := v_procesados + 1;
        END LOOP;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- RESULTADO DEL TRIGGER ---');

    -- 6. comprobar que solo el pedido completo quede LISTO
    FOR pedido IN c_resultado(v_pedido_1, v_pedido_2) LOOP
        DBMS_OUTPUT.PUT_LINE(
            'Pedido ' || pedido.ID_PEDIDO ||
            ' | platos: ' || pedido.LISTOS || '/' || pedido.TOTAL ||
            ' | estado: ' || pedido.ID_ESTADO ||
            CASE
                WHEN pedido.ID_ESTADO = 3 THEN ' -> LISTO'
                ELSE ' -> EN_PREPARACION'
            END
        );
    END LOOP;

EXCEPTION
    WHEN OTHERS THEN
        PKG_GESTION_KDS.proc_mostrar_error('SIMULACION_KDS');
        RAISE;
END;
/
