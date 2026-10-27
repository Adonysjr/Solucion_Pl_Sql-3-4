# -*- coding: utf-8 -*-
"""Parche rubrica EP2: procedimientos y funciones SIN parametros, funciones usadas en SQL,
trigger de sentencia (stock) y trigger de fila (merma). Se aplica una sola vez."""
import os
base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def patch(rel, pares, append=""):
    p = os.path.join(base, rel); s = open(p, encoding="utf-8").read()
    for a, b in pares:
        assert s.count(a) == 1, (rel, a[:70])
        s = s.replace(a, b)
    if append: s = s.rstrip() + "\n" + append
    open(p, "w", encoding="utf-8").write(s)


# ---------------- 03
A1 = """    -- Reporte del modulo: salidas de stock de los dos pedidos y existencias finales.
    -- Solo consulta, no modifica nada.
    PROCEDURE proc_reporte (
        p_id_pedido_a IN PEDIDO.id_pedido%TYPE,
        p_id_pedido_b IN PEDIDO.id_pedido%TYPE
    );
"""
B1 = A1 + """
    -- Funcion SIN parametros: cuantos insumos estan bajo su stock minimo en toda la cadena.
    -- Se puede usar en SQL: SELECT pkg_stock_receta.fn_insumos_bajo_minimo() FROM dual;
    FUNCTION fn_insumos_bajo_minimo RETURN NUMBER;

    -- Procedimiento SIN parametros: lista los insumos bajo minimo de todos los locales.
    PROCEDURE proc_alerta_stock_minimo;
"""
A2 = "END pkg_stock_receta;\n/\n\n-- ===================================================================="
B2 = """    FUNCTION fn_insumos_bajo_minimo RETURN NUMBER IS
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

-- ===================================================================="""
A3 = """                                 CASE WHEN st.cantidad_actual < st.stock_minimo THEN '  BAJO MINIMO' ELSE '' END);
        END LOOP;
    EXCEPTION"""
B3 = """                                 CASE WHEN st.cantidad_actual < st.stock_minimo THEN '  BAJO MINIMO' ELSE '' END);
        END LOOP;
        DBMS_OUTPUT.PUT_LINE('  Insumos bajo minimo en toda la cadena: ' || fn_insumos_bajo_minimo());
    EXCEPTION"""
patch("scripts/03_control_stock_receta.sql", [(A1, B1), (A2, B2), (A3, B3)], append="""
-- prueba 5 (nueva): procedimiento sin parametros con la alerta de stock minimo
BEGIN
    pkg_stock_receta.proc_alerta_stock_minimo;
END;
/
""")

# ---------------- 04
A1 = """    -- Reporte del modulo: mermas de hoy del local, KPI del dia y comparativo de locales.
    -- Solo consulta, no modifica nada.
    PROCEDURE proc_reporte (
        p_id_local IN LOCAL.id_local%TYPE
    );
"""
B1 = A1 + """
    -- Funcion SIN parametros: meta de merma de la empresa (menos de 4 %).
    -- Se usa en PL/SQL y en SQL: SELECT pkg_merma.fn_meta_merma() FROM dual;
    FUNCTION fn_meta_merma RETURN NUMBER;

    -- Procedimiento SIN parametros: reporte de merma de hoy de todos los locales.
    PROCEDURE proc_reporte_hoy;
"""
A2 = """        DBMS_OUTPUT.PUT_LINE('REPORTE DE MERMA ' || TO_CHAR(p_desde, 'DD-MM-YYYY') ||
                             ' al ' || TO_CHAR(p_hasta, 'DD-MM-YYYY') || ' (meta < 4%)');"""
B2 = """        DBMS_OUTPUT.PUT_LINE('REPORTE DE MERMA ' || TO_CHAR(p_desde, 'DD-MM-YYYY') ||
                             ' al ' || TO_CHAR(p_hasta, 'DD-MM-YYYY') || ' (meta < ' || fn_meta_merma() || '%)');"""
A3 = "                    WHEN v_kpis(i).pct_merma < 4     THEN '  OK'"
B3 = "                    WHEN v_kpis(i).pct_merma < fn_meta_merma() THEN '  OK'"
A4 = "                                 WHEN v_pct < 4     THEN ' (cumple meta < 4%)'"
B4 = "                                 WHEN v_pct < fn_meta_merma() THEN ' (cumple meta < ' || fn_meta_merma() || '%)'"
A5 = """        -- comparativo de todos los locales del dia, con el reporte que ya existia
        sp_reporte_merma(TRUNC(SYSDATE), TRUNC(SYSDATE));
    END proc_reporte;"""
B5 = """        -- la funcion del KPI usada dentro de una sentencia SQL: los 3 locales con mas merma hoy
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
    END proc_reporte_hoy;"""
A6 = "END pkg_merma;\n/\n\n-- ===================================================================="
B6 = """END pkg_merma;
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

-- ===================================================================="""
patch("scripts/04_control_merma.sql", [(A1, B1), (A2, B2), (A3, B3), (A4, B4), (A5, B5), (A6, B6)], append="""
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
""")

# ---------------- 09
A1 = """    -- Muestra el resultado de la simulacion. Solo consulta.
    PROCEDURE proc_generar_reporte (
        p_id_delivery IN PEDIDO.id_pedido%TYPE,
        p_id_salon    IN PEDIDO.id_pedido%TYPE
    );
"""
B1 = A1 + """
    -- Procedimiento SIN parametros: simula y reporta de una sola llamada.
    PROCEDURE proc_ejecutar;
"""
A2 = "END PKG_SIMULACION;\n/"
B2 = """    PROCEDURE proc_ejecutar IS
        v_delivery PEDIDO.id_pedido%TYPE;
        v_salon    PEDIDO.id_pedido%TYPE;
    BEGIN
        proc_simular(v_delivery, v_salon);
        proc_generar_reporte(v_delivery, v_salon);
    END proc_ejecutar;

END PKG_SIMULACION;
/"""
patch("scripts/09_pkg_simulacion.sql", [(A1, B1), (A2, B2)])

# ---------------- 10
open(os.path.join(base, "scripts/10_bloque_final.sql"), "w", encoding="utf-8").write("""-- ====================================================================
-- Bloque anonimo final (evaluacion parcial 2)
-- Ejecuta toda la simulacion y el reporte con una sola gestion de
-- transaccion: si todo sale bien COMMIT, si algo falla ROLLBACK completo.
-- Requisitos previos: 01 a 09 compilados sin errores.
-- ====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    v_delivery PEDIDO.id_pedido%TYPE;
    v_salon    PEDIDO.id_pedido%TYPE;
BEGIN
    -- procedimientos con parametros: la simulacion devuelve los IDs y el reporte los recibe
    PKG_SIMULACION.proc_simular(v_delivery, v_salon);
    PKG_SIMULACION.proc_generar_reporte(v_delivery, v_salon);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Transaccion confirmada (COMMIT).');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Simulacion deshecha (ROLLBACK): ' || SQLERRM);
        RAISE;
END;
/

-- Alternativa equivalente con el procedimiento SIN parametros (hace lo mismo en una llamada).
-- Descomentar para usarla en vez del bloque anterior:
-- BEGIN
--     PKG_SIMULACION.proc_ejecutar;
--     COMMIT;
-- EXCEPTION
--     WHEN OTHERS THEN
--         ROLLBACK;
--         RAISE;
-- END;
-- /
""")
print("parches ok")
