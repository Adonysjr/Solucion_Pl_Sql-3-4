#!/bin/bash
# Corre todos los scripts en orden contra el contenedor Oracle 23ai y guarda cada salida.
export NLS_LANG=.AL32UTF8
SQLPLUS="/c/app/Adoju/product/21c/dbhomeXE/bin/sqlplus"
CONN_SYS="sys/Oracle123@localhost:1522/FREEPDB1 as sysdba"
CONN="SABORES_ADMIN/Sabores2026@localhost:1522/FREEPDB1"
cd "$(dirname "$0")/.."
run() { # $1 = conexion, $2 = script, $3 = salida
  echo "=== $2"
  { echo "SET ECHO OFF FEEDBACK ON SERVEROUTPUT ON SIZE UNLIMITED LINESIZE 200 PAGESIZE 100 SQLBLANKLINES ON TAB OFF TRIMSPOOL ON"; echo "WHENEVER SQLERROR CONTINUE"; echo "@$2"; echo "EXIT"; } | "$SQLPLUS" -S "$1" > "pruebas/salidas/$3" 2>&1
  grep -n "ORA-\|PLS-\|Warning: \|compilation errors" "pruebas/salidas/$3" | head -20
}
run "$CONN_SYS" scripts/00_creacion_usuario.sql 00_creacion_usuario.txt
run "$CONN" scripts/01_tablas.sql 01_tablas.txt
run "$CONN" scripts/02_poblacion.sql 02_poblacion.txt
run "$CONN" scripts/03_control_stock_receta.sql 03_control_stock_receta.txt
run "$CONN" scripts/04_control_merma.sql 04_control_merma.txt
run "$CONN" scripts/05_integracion_externa.sql 05_integracion_externa.txt
run "$CONN" scripts/06_rotacion_mesas.sql 06_rotacion_mesas.txt
run "$CONN" scripts/07_gestion_kds.sql 07_gestion_kds.txt
run "$CONN" scripts/08_facturacion.sql 08_facturacion.txt
run "$CONN" pruebas/companeros_provisional.sql companeros_provisional.txt
run "$CONN" scripts/09_pkg_simulacion.sql 09_pkg_simulacion.txt
run "$CONN" scripts/10_bloque_final.sql 10_bloque_final.txt
