-- Problema 4: control de merma
-- Registro las perdidas de insumos y calculo el % de merma en pesos por local.
--
-- Evaluacion parcial 2 (simulacion integrada):
--   * proc_simular: etapa de este modulo dentro de PKG_SIMULACION (registra la
--     merma de la simulacion y comprueba que bajo el stock). No hace COMMIT.
--   * proc_reporte: mermas del dia del local, KPI del dia y reporte de todos los
--     locales. Solo consulta.

SET SERVEROUTPUT ON

CREATE OR REPLACE PACKAGE pkg_merma AS

    -- excepciones mias, van en el package para poder capturarlas desde el bloque anonimo
    ex_cantidad_invalida  EXCEPTION;
    ex_stock_insuficiente EXCEPTION;

    -- record con el KPI de un local
    TYPE t_kpi_rec IS RECORD (
        id_local      LOCAL.id_local%TYPE,
        nombre_local  LOCAL.nombre%TYPE,
        costo_consumo NUMBER,
        costo_merma   NUMBER,
        pct_merma     NUMBER
    );

    -- un record por cada local, para el reporte
    TYPE t_kpi_tab IS VARRAY(20) OF t_kpi_rec;

    PROCEDURE sp_registrar_merma (
        p_id_local  IN LOCAL.id_local%TYPE,
        p_id_insumo IN INSUMO.id_insumo%TYPE,
        p_cantidad  IN NUMBER,
        p_motivo    IN VARCHAR2
    );

    FUNCTION fn_costo_movimientos (
        p_id_local IN LOCAL.id_local%TYPE,
        p_tipo     IN MOVIMIENTO_STOCK.tipo%TYPE,
        p_desde    IN DATE,
        p_hasta    IN DATE
    ) RETURN NUMBER;

    FUNCTION fn_porcentaje_merma (
        p_id_local IN LOCAL.id_local%TYPE,
        p_desde    IN DATE,
        p_hasta    IN DATE
    ) RETURN NUMBER;

    PROCEDURE sp_reporte_merma (
        p_desde IN DATE,
        p_hasta IN DATE
    );

    -- Simulacion integrada: registra 50 GR de lechuga perdidos por deterioro en el
    -- local indicado. Lo llama PKG_SIMULACION.proc_simular en el paso 5. Sin COMMIT.
    PROCEDURE proc_simular (
        p_id_local IN LOCAL.id_local%TYPE
    );

    -- Reporte del modulo: mermas de hoy del local, KPI del dia y comparativo de locales.
    -- Solo consulta, no modifica nada.
    PROCEDURE proc_reporte (
        p_id_local IN LOCAL.id_local%TYPE
    );

    -- Funcion SIN parametros: meta de merma de la empresa (menos de 4 %).
    -- Se usa en PL/SQL y en SQL: SELECT pkg_merma.fn_meta_merma() FROM dual;
    FUNCTION fn_meta_merma RETURN NUMBER;

    -- Procedimiento SIN parametros: reporte de merma de hoy de todos los locales.
    PROCEDURE proc_reporte_hoy;

END pkg_merma;
/

CREATE OR REPLACE PACKAGE BODY pkg_merma AS

    -- datos fijos de la simulacion (acordados por el grupo): insumo 5 = lechuga
    c_insumo_sim   CONSTANT INSUMO.id_insumo%TYPE := 5;
    c_cantidad_sim CONSTANT NUMBER                := 50;
    c_motivo_sim   CONSTANT VARCHAR2(100)         := 'Deterioro durante almacenamiento';

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
        IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
            DBMS_OUTPUT.PUT_LINE('La cantidad de merma debe ser mayor a cero (recibido: ' ||
                                 NVL(TO_CHAR(p_cantidad), 'NULL') || ').');
            RAISE ex_cantidad_invalida;
        END IF;

        SELECT nombre, unidad_medida
          INTO v_nombre, v_unidad
          FROM INSUMO
         WHERE id_insumo = p_id_insumo;

        SELECT cantidad_actual
          INTO v_stock
          FROM STOCK_LOCAL
         WHERE id_local  = p_id_local
           AND id_insumo = p_id_insumo
           FOR UPDATE;

        -- no se puede perder mas de lo que hay
        IF v_stock < p_cantidad THEN
            DBMS_OUTPUT.PUT_LINE('Stock insuficiente para registrar merma de ' || v_nombre ||
                ' en local ' || p_id_local || ': disponible ' || v_stock || ' ' || v_unidad ||
                ', merma solicitada ' || p_cantidad || '.');
            RAISE ex_stock_insuficiente;
        END IF;

        -- descuento y registro el movimiento MERMA
        UPDATE STOCK_LOCAL
           SET cantidad_actual     = cantidad_actual - p_cantidad,
               fecha_actualizacion = SYSDATE
         WHERE id_local  = p_id_local
           AND id_insumo = p_id_insumo;

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

        -- con parametros lo uso igual para SALIDA y para MERMA
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
        -- sumo en pesos para no mezclar GR, ML y UN
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

        -- sin consumo no se puede calcular
        IF v_costo_consumo = 0 THEN
            RETURN NULL;
        END IF;

        RETURN ROUND(v_costo_merma / v_costo_consumo * 100, 2);
    END fn_porcentaje_merma;

    PROCEDURE sp_reporte_merma (
        p_desde IN DATE,
        p_hasta IN DATE
    ) IS
        v_kpi   t_kpi_rec;
        v_kpis  t_kpi_tab := t_kpi_tab();
        v_peor  PLS_INTEGER;

        CURSOR c_locales IS
            SELECT id_local, nombre
              FROM LOCAL
             WHERE activo = TRUE
             ORDER BY id_local;
    BEGIN
        -- lleno el varray con el KPI de cada local
        FOR loc IN c_locales LOOP
            v_kpi.id_local      := loc.id_local;
            v_kpi.nombre_local  := loc.nombre;
            v_kpi.costo_consumo := fn_costo_movimientos(loc.id_local, 'SALIDA', p_desde, p_hasta);
            v_kpi.costo_merma   := fn_costo_movimientos(loc.id_local, 'MERMA',  p_desde, p_hasta);
            v_kpi.pct_merma     := fn_porcentaje_merma(loc.id_local, p_desde, p_hasta);

            v_kpis.EXTEND;
            v_kpis(v_kpis.LAST) := v_kpi;
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('REPORTE DE MERMA ' || TO_CHAR(p_desde, 'DD-MM-YYYY') ||
                             ' al ' || TO_CHAR(p_hasta, 'DD-MM-YYYY') || ' (meta < ' || fn_meta_merma() || '%)');

        -- recorro el varray, imprimo y busco el local con mas merma
        FOR i IN 1 .. v_kpis.COUNT LOOP
            DBMS_OUTPUT.PUT_LINE(RPAD(v_kpis(i).id_local || ' - ' || v_kpis(i).nombre_local, 34) ||
                ' consumo $' || LPAD(TO_CHAR(v_kpis(i).costo_consumo, 'FM999G999G990'), 10) ||
                ' merma $'   || LPAD(TO_CHAR(v_kpis(i).costo_merma,   'FM999G999G990'), 9)  ||
                ' KPI '      || LPAD(NVL2(v_kpis(i).pct_merma, TO_CHAR(v_kpis(i).pct_merma, 'FM990D00') || '%', 'sin consumo'), 11) ||
                CASE
                    WHEN v_kpis(i).pct_merma IS NULL THEN ''
                    WHEN v_kpis(i).pct_merma < fn_meta_merma() THEN '  OK'
                    ELSE '  SOBRE META'
                END);

            IF v_kpis(i).pct_merma IS NOT NULL AND
               (v_peor IS NULL OR v_kpis(i).pct_merma > v_kpis(v_peor).pct_merma) THEN
                v_peor := i;
            END IF;
        END LOOP;

        IF v_peor IS NOT NULL THEN
            DBMS_OUTPUT.PUT_LINE('Local con mayor merma: ' || v_kpis(v_peor).nombre_local ||
                                 ' (' || v_kpis(v_peor).pct_merma || '%)');
        END IF;
    END sp_reporte_merma;

    PROCEDURE proc_simular (
        p_id_local IN LOCAL.id_local%TYPE
    ) IS
        v_nombre  INSUMO.nombre%TYPE;
        v_unidad  INSUMO.unidad_medida%TYPE;
        v_antes   STOCK_LOCAL.cantidad_actual%TYPE;
        v_despues STOCK_LOCAL.cantidad_actual%TYPE;
        v_movs    PLS_INTEGER;
        v_costo   NUMBER;
        v_pct     NUMBER;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('--- MERMA: perdida de insumo en local ' || p_id_local || ' ---');

        -- 1. stock inicial del insumo (NO_DATA_FOUND si el local no lo maneja)
        SELECT i.nombre, i.unidad_medida, s.cantidad_actual
          INTO v_nombre, v_unidad, v_antes
          FROM STOCK_LOCAL s
          JOIN INSUMO i ON i.id_insumo = s.id_insumo
         WHERE s.id_local  = p_id_local
           AND s.id_insumo = c_insumo_sim;

        DBMS_OUTPUT.PUT_LINE('Stock inicial de ' || v_nombre || ': ' || v_antes || ' ' || v_unidad);

        -- 2. registro la merma con el procedimiento del modulo
        sp_registrar_merma(p_id_local, c_insumo_sim, c_cantidad_sim, c_motivo_sim);

        -- 3. compruebo que el stock bajo exactamente lo registrado
        SELECT cantidad_actual
          INTO v_despues
          FROM STOCK_LOCAL
         WHERE id_local  = p_id_local
           AND id_insumo = c_insumo_sim;

        DBMS_OUTPUT.PUT_LINE('Stock final de ' || v_nombre || ': ' || v_despues || ' ' || v_unidad ||
                             ' (bajo ' || (v_antes - v_despues) || ')');

        IF v_antes - v_despues <> c_cantidad_sim THEN
            RAISE_APPLICATION_ERROR(-20041, 'El stock no bajo lo esperado tras la merma.');
        END IF;

        -- 4. compruebo que quedo el movimiento MERMA de hoy
        SELECT COUNT(*)
          INTO v_movs
          FROM MOVIMIENTO_STOCK
         WHERE id_local   = p_id_local
           AND id_insumo  = c_insumo_sim
           AND tipo       = 'MERMA'
           AND fecha_hora >= TRUNC(SYSDATE);

        DBMS_OUTPUT.PUT_LINE('Movimientos MERMA de hoy de ' || v_nombre || ': ' || v_movs);

        -- 5. costo y KPI del dia con las funciones del modulo
        v_costo := fn_costo_movimientos(p_id_local, 'MERMA', TRUNC(SYSDATE), TRUNC(SYSDATE));
        v_pct   := fn_porcentaje_merma(p_id_local, TRUNC(SYSDATE), TRUNC(SYSDATE));

        DBMS_OUTPUT.PUT_LINE('Merma de hoy en local ' || p_id_local || ': $' ||
                             TO_CHAR(v_costo, 'FM999G999G990') || ' | KPI del dia: ' ||
                             NVL2(v_pct, TO_CHAR(v_pct, 'FM990D00') || '%', 'sin consumo'));
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('El local ' || p_id_local || ' no maneja el insumo ' ||
                                 c_insumo_sim || ': no se puede simular la merma.');
            RAISE;
        WHEN ex_cantidad_invalida OR ex_stock_insuficiente THEN
            DBMS_OUTPUT.PUT_LINE('Simulacion de merma detenida: la merma no se registro.');
            RAISE;
    END proc_simular;

    PROCEDURE proc_reporte (
        p_id_local IN LOCAL.id_local%TYPE
    ) IS
        v_cantidad PLS_INTEGER := 0;
        v_costo    NUMBER      := 0;
        v_consumo  NUMBER;
        v_pct      NUMBER;

        -- mermas de hoy del local, valorizadas
        CURSOR c_mermas_hoy (cp_id_local LOCAL.id_local%TYPE) IS
            SELECT i.nombre, m.cantidad, i.unidad_medida, m.motivo,
                   m.cantidad * i.costo_unitario AS costo,
                   TO_CHAR(m.fecha_hora, 'HH24:MI') AS hora
              FROM MOVIMIENTO_STOCK m
              JOIN INSUMO i ON i.id_insumo = m.id_insumo
             WHERE m.id_local   = cp_id_local
               AND m.tipo       = 'MERMA'
               AND m.fecha_hora >= TRUNC(SYSDATE)
             ORDER BY m.id_movimiento;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('MERMA - local ' || p_id_local || ' hoy ' || TO_CHAR(SYSDATE, 'DD-MM-YYYY'));

        FOR m IN c_mermas_hoy(p_id_local) LOOP
            v_cantidad := v_cantidad + 1;
            v_costo    := v_costo + m.costo;
            DBMS_OUTPUT.PUT_LINE('  ' || m.hora || ' ' || RPAD(m.nombre, 20) || LPAD(m.cantidad, 6) || ' ' ||
                                 RPAD(m.unidad_medida, 3) || ' $' || TO_CHAR(m.costo, 'FM999G999G990') ||
                                 ' | ' || m.motivo);
        END LOOP;

        v_consumo := fn_costo_movimientos(p_id_local, 'SALIDA', TRUNC(SYSDATE), TRUNC(SYSDATE));
        v_pct     := fn_porcentaje_merma(p_id_local, TRUNC(SYSDATE), TRUNC(SYSDATE));

        DBMS_OUTPUT.PUT_LINE('  Mermas de hoy: ' || v_cantidad || ' | $' || TO_CHAR(v_costo, 'FM999G999G990') ||
                             ' | consumo de hoy $' || TO_CHAR(v_consumo, 'FM999G999G990') ||
                             ' | KPI ' || NVL2(v_pct, TO_CHAR(v_pct, 'FM990D00') || '%', 'sin consumo') ||
                             CASE
                                 WHEN v_pct IS NULL THEN ''
                                 WHEN v_pct < fn_meta_merma() THEN ' (cumple meta < ' || fn_meta_merma() || '%)'
                                 ELSE ' (SOBRE META)'
                             END);

        -- la funcion del KPI usada dentro de una sentencia SQL: los 3 locales con mas merma hoy
        DBMS_OUTPUT.PUT_LINE('  Locales con mas merma hoy (funcion fn_porcentaje_merma dentro del SELECT):');
        FOR r IN (SELECT l.id_local, l.nombre,
                         pkg_merma.fn_porcentaje_merma(l.id_local, TRUNC(SYSDATE), TRUNC(SYSDATE)) AS kpi
                    FROM LOCAL l
                   WHERE l.activo = TRUE
                   ORDER BY kpi DESC NULLS LAST
                   FETCH FIRST 3 ROWS ONLY) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || r.id_local || ' - ' || RPAD(r.nombre, 32) ||
                                 NVL2(r.kpi, TO_CHAR(r.kpi, 'FM990D00') || '%', 'sin consumo'));
        END LOOP;

        -- comparativo de todos los locales del dia, con el reporte que ya existia
        sp_reporte_merma(TRUNC(SYSDATE), TRUNC(SYSDATE));
    END proc_reporte;

    FUNCTION fn_meta_merma RETURN NUMBER IS
    BEGIN
        RETURN 4;   -- la empresa quiere bajar de ~15 % a menos de 4 %
    END fn_meta_merma;

    PROCEDURE proc_reporte_hoy IS
    BEGIN
        sp_reporte_merma(TRUNC(SYSDATE), TRUNC(SYSDATE));
    END proc_reporte_hoy;

END pkg_merma;
/

-- ====================================================================
-- Trigger a NIVEL DE FILA: antes de insertar cada movimiento de stock
-- valida que una MERMA traiga motivo (es lo que permite separar la perdida
-- real del consumo normal) y completa la fecha si viene vacia. Es de fila
-- (FOR EACH ROW) porque necesita leer y corregir :NEW de cada registro.
-- ====================================================================
CREATE OR REPLACE TRIGGER trg_merma_con_motivo
BEFORE INSERT ON MOVIMIENTO_STOCK
FOR EACH ROW
BEGIN
    IF :NEW.tipo = 'MERMA' AND TRIM(:NEW.motivo) IS NULL THEN
        RAISE_APPLICATION_ERROR(-20042, 'Toda merma debe registrarse con un motivo.');
    END IF;
    IF :NEW.fecha_hora IS NULL THEN
        :NEW.fecha_hora := SYSDATE;
    END IF;
END;
/

-- ====================================================================
-- Pruebas del modulo (evaluacion parcial 1).
-- ====================================================================

-- prueba 1: merma normal
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

-- prueba 2: cantidad negativa
BEGIN
    pkg_merma.sp_registrar_merma(1, 2, -5, 'Prueba cantidad negativa');
EXCEPTION
    WHEN pkg_merma.ex_cantidad_invalida THEN
        DBMS_OUTPUT.PUT_LINE('DATOS INVALIDOS: la merma no se registra.');
END;
/

-- prueba 3: merma mayor al stock
BEGIN
    pkg_merma.sp_registrar_merma(1, 2, 999999, 'Prueba stock insuficiente');
EXCEPTION
    WHEN pkg_merma.ex_stock_insuficiente THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('MERMA RECHAZADA: la merma no se registra.');
END;
/

-- prueba 4: KPI del local 1 en los ultimos 30 dias
DECLARE
    v_pct NUMBER;
BEGIN
    v_pct := pkg_merma.fn_porcentaje_merma(1, TRUNC(SYSDATE) - 30, SYSDATE);
    IF v_pct IS NULL THEN
        DBMS_OUTPUT.PUT_LINE('Local 1: sin consumo en el periodo, KPI no calculable.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Local 1: merma ultimos 30 dias = ' || v_pct || '%');
    END IF;
END;
/

-- prueba 5: reporte de todos los locales en los ultimos 30 dias
BEGIN
    pkg_merma.sp_reporte_merma(TRUNC(SYSDATE) - 30, SYSDATE);
END;
/

-- prueba 6 (nueva): el trigger de fila rechaza una merma sin motivo
BEGIN
    pkg_merma.sp_registrar_merma(1, 2, 10, NULL);
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -20042 THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('MERMA RECHAZADA POR EL TRIGGER: ' || SQLERRM);
        ELSE
            RAISE;
        END IF;
END;
/

-- prueba 7 (nueva): funcion sin parametros en SQL y procedimiento sin parametros
SELECT pkg_merma.fn_meta_merma() AS meta_merma_pct FROM dual;

BEGIN
    pkg_merma.proc_reporte_hoy;
END;
/
