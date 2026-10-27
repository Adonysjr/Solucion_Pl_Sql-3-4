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
========================================
    SIMULACIÓN ROTACIÓN DE MESAS
========================================
*/
DECLARE
    v_local       MESA.ID_LOCAL%TYPE := 1;
    v_fecha       DATE := TRUNC(SYSDATE);
    v_garzon      EMPLEADO.ID_EMPLEADO%TYPE;
    v_mesa_1      MESA.ID_MESA%TYPE;
    v_mesa_2      MESA.ID_MESA%TYPE;
    v_mesa_3      MESA.ID_MESA%TYPE;
    v_pedido_1    PEDIDO.ID_PEDIDO%TYPE;
    v_pedido_2    PEDIDO.ID_PEDIDO%TYPE;
    v_pedido_3    PEDIDO.ID_PEDIDO%TYPE;
    v_cant_mesas  PLS_INTEGER := 0;
    v_rotacion    NUMBER;
    v_local_vacio LOCAL.ID_LOCAL%TYPE;

    -- cursor parametrizado: mesas libres de un local
    CURSOR c_mesas_libres(cp_id_local MESA.ID_LOCAL%TYPE) IS
        SELECT ID_MESA, NUMERO_MESA
        FROM MESA
        WHERE ID_LOCAL = cp_id_local
          AND OCUPADA = FALSE
        ORDER BY NUMERO_MESA;

    -- cursor parametrizado: pedidos creados en la simulación
    CURSOR c_pedidos(
        cp_pedido_1 PEDIDO.ID_PEDIDO%TYPE,
        cp_pedido_2 PEDIDO.ID_PEDIDO%TYPE,
        cp_pedido_3 PEDIDO.ID_PEDIDO%TYPE
    ) IS
        SELECT ID_PEDIDO, ID_MESA
        FROM PEDIDO
        WHERE ID_PEDIDO IN (cp_pedido_1, cp_pedido_2, cp_pedido_3)
        ORDER BY ID_PEDIDO;

    -- cursor parametrizado: estado de una mesa
    CURSOR c_mesa(cp_id_mesa MESA.ID_MESA%TYPE) IS
        SELECT NUMERO_MESA, OCUPADA
        FROM MESA
        WHERE ID_MESA = cp_id_mesa;

BEGIN
    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('     SIMULACIÓN ROTACIÓN DE MESAS');
    DBMS_OUTPUT.PUT_LINE('========================================');

    -- 1. tomar tres mesas libres del local
    FOR mesa IN c_mesas_libres(v_local) LOOP
        v_cant_mesas := v_cant_mesas + 1;
        IF v_cant_mesas = 1 THEN
            v_mesa_1 := mesa.ID_MESA;
        ELSIF v_cant_mesas = 2 THEN
            v_mesa_2 := mesa.ID_MESA;
        ELSE
            v_mesa_3 := mesa.ID_MESA;
            EXIT;
        END IF;
    END LOOP;

    IF v_cant_mesas < 3 THEN
        DBMS_OUTPUT.PUT_LINE('Se necesitan al menos 3 mesas libres en el local ' || v_local || '.');
        RETURN;
    END IF;

    SELECT MIN(ID_EMPLEADO)
    INTO v_garzon
    FROM EMPLEADO
    WHERE ID_LOCAL = v_local
      AND CARGO = 'GARZON';

    -- 2. abrir tres pedidos de salón en horario de almuerzo
    --    trg_ocupar_mesa marca cada mesa como ocupada
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- APERTURA DE PEDIDOS (trg_ocupar_mesa) ---');

    INSERT INTO PEDIDO
        (ID_PEDIDO, FECHA_HORA_CREACION, OBSERVACION, TOTAL,
         ID_LOCAL, ID_MESA, ID_EMPLEADO, ID_CANAL, ID_ESTADO)
    VALUES
        (SEQ_PEDIDO.NEXTVAL, v_fecha + 12/24 + 5/1440, 'SIMULACION ROTACION', 8500,
         v_local, v_mesa_1, v_garzon, 1, 1)
    RETURNING ID_PEDIDO INTO v_pedido_1;

    INSERT INTO PEDIDO
        (ID_PEDIDO, FECHA_HORA_CREACION, OBSERVACION, TOTAL,
         ID_LOCAL, ID_MESA, ID_EMPLEADO, ID_CANAL, ID_ESTADO)
    VALUES
        (SEQ_PEDIDO.NEXTVAL, v_fecha + 12/24 + 30/1440, 'SIMULACION ROTACION', 11500,
         v_local, v_mesa_2, v_garzon, 1, 1)
    RETURNING ID_PEDIDO INTO v_pedido_2;

    INSERT INTO PEDIDO
        (ID_PEDIDO, FECHA_HORA_CREACION, OBSERVACION, TOTAL,
         ID_LOCAL, ID_MESA, ID_EMPLEADO, ID_CANAL, ID_ESTADO)
    VALUES
        (SEQ_PEDIDO.NEXTVAL, v_fecha + 13/24 + 10/1440, 'SIMULACION ROTACION', 9900,
         v_local, v_mesa_3, v_garzon, 1, 1)
    RETURNING ID_PEDIDO INTO v_pedido_3;

    -- recorrer pedidos y el estado de su mesa (loops anidados)
    FOR pedido IN c_pedidos(v_pedido_1, v_pedido_2, v_pedido_3) LOOP
        FOR mesa IN c_mesa(pedido.ID_MESA) LOOP
            DBMS_OUTPUT.PUT_LINE(
                'Pedido ' || pedido.ID_PEDIDO || ' -> Mesa ' || mesa.NUMERO_MESA || ': ' ||
                CASE WHEN mesa.OCUPADA THEN 'OCUPADA' ELSE 'LIBRE' END
            );
        END LOOP;
    END LOOP;

    -- 3. intentar abrir otro pedido en una mesa ocupada
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- PRUEBA: MESA OCUPADA ---');
    BEGIN
        INSERT INTO PEDIDO
            (ID_PEDIDO, FECHA_HORA_CREACION, TOTAL, ID_LOCAL, ID_MESA, ID_CANAL, ID_ESTADO)
        VALUES
            (SEQ_PEDIDO.NEXTVAL, v_fecha + 13/24, 5000, v_local, v_mesa_1, 1, 1);
    EXCEPTION
        WHEN exc_mesas.mesa_no_disponible THEN
            DBMS_OUTPUT.PUT_LINE('-> Rechazado: la mesa ya tiene un pedido abierto.');
    END;

    -- 4. cerrar dos pedidos: trg_liberar_mesa deja libres sus mesas
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- CIERRE DE PEDIDOS (trg_liberar_mesa) ---');

    UPDATE PEDIDO
    SET FECHA_HORA_CIERRE = FECHA_HORA_CREACION + 50/1440,
        ID_ESTADO = 4
    WHERE ID_PEDIDO = v_pedido_1;

    UPDATE PEDIDO
    SET FECHA_HORA_CIERRE = FECHA_HORA_CREACION + 35/1440,
        ID_ESTADO = 4
    WHERE ID_PEDIDO = v_pedido_2;

    FOR pedido IN c_pedidos(v_pedido_1, v_pedido_2, v_pedido_3) LOOP
        FOR mesa IN c_mesa(pedido.ID_MESA) LOOP
            DBMS_OUTPUT.PUT_LINE(
                'Pedido ' || pedido.ID_PEDIDO ||
                ' | duración: ' ||
                NVL(TO_CHAR(pkg_mesas.fn_duracion_atencion_min(pedido.ID_PEDIDO)), 'abierto') ||
                ' | Mesa ' || mesa.NUMERO_MESA || ': ' ||
                CASE WHEN mesa.OCUPADA THEN 'OCUPADA' ELSE 'LIBRE' END
            );
        END LOOP;
    END LOOP;

    -- 5. reporte de rotación del almuerzo
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- REPORTE DE ROTACIÓN ---');
    pkg_mesas.sp_reporte_rotacion_local(v_local, v_fecha, '12:00', '15:00');

    -- 6. rango horario invalido
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- PRUEBA: RANGO HORARIO INVÁLIDO ---');
    v_rotacion := pkg_mesas.fn_rotacion_mesas(v_local, v_fecha, '15:00', '12:00');
    DBMS_OUTPUT.PUT_LINE('Resultado: ' || NVL(TO_CHAR(v_rotacion), 'sin cálculo'));

    -- 7. local sin mesas registradas
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- PRUEBA: LOCAL SIN MESAS ---');
    SELECT MIN(l.ID_LOCAL)
    INTO v_local_vacio
    FROM LOCAL l
    WHERE NOT EXISTS (SELECT 1 FROM MESA m WHERE m.ID_LOCAL = l.ID_LOCAL);

    IF v_local_vacio IS NOT NULL THEN
        v_rotacion := pkg_mesas.fn_rotacion_mesas(v_local_vacio, v_fecha, '12:00', '15:00');
        DBMS_OUTPUT.PUT_LINE('Resultado: ' || NVL(TO_CHAR(v_rotacion), 'sin cálculo'));
    ELSE
        DBMS_OUTPUT.PUT_LINE('Todos los locales tienen mesas registradas.');
    END IF;

    -- 8. cerrar el último pedido para dejar la mesa libre
    UPDATE PEDIDO
    SET FECHA_HORA_CIERRE = FECHA_HORA_CREACION + 45/1440,
        ID_ESTADO = 4
    WHERE ID_PEDIDO = v_pedido_3;

    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Pedido ' || v_pedido_3 || ' cerrado: su mesa queda libre.');

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error inesperado en la simulación: ' || SQLERRM);
        RAISE;
END;
/
