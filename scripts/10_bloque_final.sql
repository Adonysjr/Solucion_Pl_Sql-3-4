-- ====================================================================
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
