# -*- coding: utf-8 -*-
"""Genera docs/imagenes/*.png (salidas reales en estilo consola) y docs/Guia_simulacion_integrada.docx."""
import os, re, textwrap
from PIL import Image, ImageDraw, ImageFont
from docx import Document
from docx.shared import Pt, Inches, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH

base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sal = os.path.join(base, "pruebas", "salidas")
docs = os.path.join(base, "docs"); img_dir = os.path.join(docs, "imagenes")
os.makedirs(img_dir, exist_ok=True)
FONT = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 17)
FONT_B = ImageFont.truetype("C:/Windows/Fonts/consolab.ttf", 17)


def limpiar(texto):
    lineas = [l.rstrip() for l in texto.splitlines()]
    out = []
    for l in lineas:
        if l.strip() in ("PL/SQL procedure successfully completed.", "Package created.", "Package body created.",
                         "Trigger created.", "Table created.", "Sequence created.", "User created.", "Grant succeeded.", "User altered."):
            out.append("> " + l.strip()); continue
        if re.match(r"^\d+ rows? (created|updated)\.$", l.strip()): continue
        out.append(l)
    # quitar lineas en blanco repetidas
    res = []
    for l in out:
        if l.strip() == "" and res and res[-1].strip() == "": continue
        res.append(l)
    return res


def render(lineas, titulo, nombre, ancho=1240):
    lineas = [sub for l in lineas for sub in (textwrap.wrap(l, 140, replace_whitespace=False, drop_whitespace=False) or [""])]
    alto = 54 + 22 * len(lineas) + 20
    im = Image.new("RGB", (ancho, alto), (24, 26, 32)); d = ImageDraw.Draw(im)
    d.rectangle([0, 0, ancho, 40], fill=(40, 44, 56))
    for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]): d.ellipse([14 + i * 22, 13, 28 + i * 22, 27], fill=c)
    d.text((90, 11), titulo, font=FONT_B, fill=(220, 224, 232))
    y = 54
    for l in lineas:
        col = (220, 224, 232)
        s = l.strip()
        if s.startswith("==") or s.startswith(">> ") or s.startswith("--- "): col = (120, 200, 255)
        elif "OK" in s and "esperado" in s: col = (120, 230, 140)
        elif "REVISAR" in s or "ERROR" in s or "ORA-" in s or "BLOQUEADA" in s or "RECHAZAD" in s or "INVALIDOS" in s: col = (255, 150, 120)
        elif s.startswith("> "): col = (150, 150, 165)
        d.text((16, y), l, font=FONT, fill=col); y += 22
    p = os.path.join(img_dir, nombre); im.save(p); return p


def trozos(lineas, n=58):
    return [lineas[i:i + n] for i in range(0, len(lineas), n)]


imgs = {}
# bloque final: simulacion y reporte
final = limpiar(open(os.path.join(sal, "10_bloque_final.txt"), encoding="utf-8").read())
i_rep = next(i for i, l in enumerate(final) if "REPORTE CONSOLIDADO" in l) - 1
sim, rep = final[:i_rep], final[i_rep:]
imgs["sim"] = [render(t, f"10_bloque_final.sql - simulacion ({k + 1}/{len(trozos(sim))})", f"10_simulacion_{k + 1}.png") for k, t in enumerate(trozos(sim))]
imgs["rep"] = [render(t, f"10_bloque_final.sql - reporte ({k + 1}/{len(trozos(rep))})", f"10_reporte_{k + 1}.png") for k, t in enumerate(trozos(rep))]
imgs["03"] = [render(limpiar(open(os.path.join(sal, "03_control_stock_receta.txt"), encoding="utf-8").read()), "03_control_stock_receta.sql - compilacion y pruebas", "03_pruebas.png")]
imgs["04"] = [render(limpiar(open(os.path.join(sal, "04_control_merma.txt"), encoding="utf-8").read()), "04_control_merma.sql - compilacion y pruebas", "04_pruebas.png")]
imgs["09"] = [render(limpiar(open(os.path.join(sal, "09_pkg_simulacion.txt"), encoding="utf-8").read()), "09_pkg_simulacion.sql - compilacion", "09_compila.png")]

# ---------------------------------------------------------------- documento
doc = Document()
st = doc.styles["Normal"]; st.font.name = "Calibri"; st.font.size = Pt(11)


def h(t, n=1): doc.add_heading(t, n)
def p(t, bold=False, it=False):
    par = doc.add_paragraph(); r = par.add_run(t); r.bold = bold; r.italic = it; return par
def code(t):
    par = doc.add_paragraph(); r = par.add_run(t); r.font.name = "Consolas"; r.font.size = Pt(9)
    par.paragraph_format.left_indent = Inches(0.2); return par
def tabla(filas, anchos=None):
    t = doc.add_table(rows=len(filas), cols=len(filas[0])); t.style = "Light Grid Accent 1"
    for i, f in enumerate(filas):
        for j, c in enumerate(f):
            cell = t.cell(i, j); cell.text = ""; r = cell.paragraphs[0].add_run(c); r.font.size = Pt(9.5); r.bold = (i == 0)
    doc.add_paragraph()
def fig(path, w=6.5):
    doc.add_picture(path, width=Inches(w)); doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER


tit = doc.add_heading("Sabores Urbanos · Simulación integrada (Evaluación parcial 2)", 0)
p("BDY1103 Taller de Base de Datos · Guía de funcionamiento, salidas reales y dónde cambiar cada cosa", it=True)
p("Módulos a cargo: Problema 3 (control de stock por receta) y Problema 4 (control de merma), más el package coordinador PKG_SIMULACION y el bloque anónimo final.")

h("1. Idea general")
p("La parcial 2 pide simular una operación completa del restaurante usando los seis packages de la parcial 1 y mostrar un reporte consolidado desde un único bloque anónimo. La regla acordada es: cada package recibe dos procedimientos públicos nuevos, proc_simular (hace su etapa) y proc_reporte (solo consulta e imprime), y un package nuevo, PKG_SIMULACION, los llama en orden. Nadie mueve su lógica al coordinador: cada módulo sigue usando sus propias funciones, procedimientos, cursores y excepciones.")
p("Ninguno de los proc_simular hace COMMIT. El bloque final ejecuta la simulación y el reporte y, si todo salió bien, confirma con COMMIT; si un paso falla, el coordinador relanza el error (RAISE) y el bloque hace ROLLBACK de todo, así nunca queda una simulación a medias.")

h("2. Orden de la simulación")
tabla([
    ["Paso", "Package", "Qué hace", "Deja"],
    ["1", "PKG_INTEGRACION_EXTERNA.proc_simular", "Registra el pedido Rappi (id externo SIM-RAP-<marca de tiempo>), agrega hamburguesa y papas", "Pedido A, $12.400, PENDIENTE"],
    ["2", "PKG_MESAS.proc_simular('ABRIR')", "Crea el pedido de salón en la mesa 3 con pollo grill y bebida; el trigger ocupa la mesa", "Pedido B, $13.700, mesa OCUPADA"],
    ["3", "PKG_STOCK_RECETA.proc_simular(A, B)", "Valida existencias y confirma A y B con sp_confirmar_pedido", "9 movimientos SALIDA, stock descontado"],
    ["4", "PKG_GESTION_KDS.proc_simular(1, A, B)", "Prioriza, entra a cocina y marca los 4 detalles LISTO; el trigger deja los pedidos LISTO", "A y B en estado 3 (LISTO)"],
    ["5", "PKG_MERMA.proc_simular(1)", "Registra 50 GR de lechuga por deterioro y calcula el KPI del día", "1 movimiento MERMA"],
    ["6", "PKG_FACTURACION.proc_simular(A, B)", "Pagos (app delivery / débito), boletas y DTE ACEPTADA", "2 pagos, 2 boletas"],
    ["7", "PKG_MESAS.proc_simular('CERRAR')", "Entrega y cierre del pedido B; el trigger libera la mesa", "B ENTREGADO, mesa 3 LIBRE"],
])
p("Después PKG_SIMULACION.proc_generar_reporte(A, B) llama al proc_reporte de los seis y termina con un resumen comparado contra lo esperado (2 pedidos, 4 detalles listos, 9 salidas, al menos 1 merma, 2 pagos, 2 boletas, 1 mesa liberada).")

h("3. Mi parte: qué cambió y por qué")
h("3.1 pkg_stock_receta (03_control_stock_receta.sql)", 2)
p("Procedimientos nuevos:", bold=True)
tabla([
    ["Componente", "Tipo", "Para qué"],
    ["proc_simular(p_id_pedido_a, p_id_pedido_b)", "público", "Muestra los insumos que necesita cada pedido y su stock, confirma A y luego B, y cuenta las salidas (9)."],
    ["proc_reporte(p_id_pedido_a, p_id_pedido_b)", "público", "Lista las salidas de los dos pedidos valorizadas en pesos y las existencias finales del local, avisando si algo quedó bajo el mínimo."],
    ["pr_simular_pedido(p_id_pedido)", "privado", "Hace la etapa de un pedido; proc_simular lo llama dos veces. Demuestra componente privado del cuerpo."],
    ["ex_pedido_ya_confirmado", "excepción", "Se lanza si el pedido ya tiene movimientos SALIDA: no se descuenta dos veces."],
    ["fn_insumos_bajo_minimo()", "función SIN parámetros", "Cuenta los insumos bajo su stock mínimo en toda la cadena. Se usa en PL/SQL, dentro de un SELECT y desde el trigger."],
    ["proc_alerta_stock_minimo", "procedimiento SIN parámetros", "Lista los insumos bajo mínimo de todos los locales (cursor sin parámetros)."],
    ["trg_alerta_stock_minimo", "trigger de SENTENCIA", "AFTER UPDATE OF cantidad_actual ON STOCK_LOCAL, sin FOR EACH ROW: tras cada descuento avisa cuántos insumos quedaron bajo el mínimo. Al ser de sentencia puede leer STOCK_LOCAL sin problema de tabla mutante."],
])
p("Corrección a sp_confirmar_pedido:", bold=True)
p("Antes descontaba insumo por insumo y recién al final avisaba los faltantes, así que un pedido rechazado dejaba stock descontado a medias (se arreglaba con ROLLBACK desde afuera). Ahora trabaja en tres pasos: (1) recorre pedido → recetas y suma lo requerido por insumo en una tabla indexada por id_insumo (TABLE OF NUMBER INDEX BY PLS_INTEGER), (2) valida cada insumo contra el stock y junta los faltantes en el VARRAY t_faltantes, (3) solo si no falta nada descuenta línea por línea y registra cada SALIDA. Además rechaza confirmar dos veces el mismo pedido.")
code("""-- PASO 1: sumar lo requerido por insumo sin tocar nada
IF v_requerido.EXISTS(rec.id_insumo) THEN
    v_requerido(rec.id_insumo) := v_requerido(rec.id_insumo) + rec.cantidad_requerida * det.cantidad;
ELSE
    v_requerido(rec.id_insumo) := rec.cantidad_requerida * det.cantidad;
END IF;
-- PASO 2: validar todo (v_faltantes es el VARRAY)
IF NOT fn_stock_disponible(v_id_local, v_consumo.id_insumo, v_consumo.requerido) THEN
    v_faltantes.EXTEND; v_faltantes(v_faltantes.LAST) := ...;
END IF;
IF v_faltantes.COUNT > 0 THEN RAISE ex_stock_insuficiente; END IF;
-- PASO 3: recién aquí UPDATE STOCK_LOCAL e INSERT INTO MOVIMIENTO_STOCK""")

h("3.2 pkg_merma (04_control_merma.sql)", 2)
tabla([
    ["Componente", "Tipo", "Para qué"],
    ["proc_simular(p_id_local)", "público", "Lee el stock de lechuga, llama a sp_registrar_merma (50 GR, 'Deterioro durante almacenamiento'), comprueba que bajó exactamente 50, que quedó el movimiento MERMA de hoy y muestra costo y KPI del día con fn_costo_movimientos y fn_porcentaje_merma."],
    ["proc_reporte(p_id_local)", "público", "Cursor con parámetro con las mermas de hoy valorizadas, KPI del día con la meta, y llama a sp_reporte_merma del día para comparar los nueve locales."],
    ["c_insumo_sim, c_cantidad_sim, c_motivo_sim", "constantes privadas", "Datos de la simulación acordados por el grupo. Si cambian, se cambian aquí."],
    ["fn_meta_merma()", "función SIN parámetros", "Devuelve la meta (4 %). Reemplaza el literal 4 en los reportes y se puede usar en SQL: SELECT pkg_merma.fn_meta_merma() FROM dual."],
    ["proc_reporte_hoy", "procedimiento SIN parámetros", "Reporte de merma de hoy de todos los locales."],
    ["fn_porcentaje_merma dentro de un SELECT", "función en SQL", "proc_reporte muestra los 3 locales con más merma del día llamando a la función desde la sentencia SQL (ORDER BY kpi DESC FETCH FIRST 3 ROWS ONLY)."],
    ["trg_merma_con_motivo", "trigger de FILA", "BEFORE INSERT ON MOVIMIENTO_STOCK FOR EACH ROW: una MERMA sin motivo se rechaza (ORA-20042) y si la fecha viene vacía la completa con SYSDATE. Es de fila porque lee y corrige :NEW de cada registro."],
])
p("También se corrigió el formato del KPI cuando un local no tuvo consumo: antes imprimía '%' solo; ahora imprime 'sin consumo' (NVL2 en vez de NVL).")

h("3.3 PKG_SIMULACION (09_pkg_simulacion.sql)", 2)
tabla([
    ["Componente", "Tipo", "Para qué"],
    ["proc_simular(p_id_delivery OUT, p_id_salon OUT)", "público", "Llama a los siete pasos en orden y devuelve los IDs. Si algo falla imprime en qué paso y relanza."],
    ["proc_generar_reporte(p_id_delivery, p_id_salon)", "público", "Seis secciones (una por package) y el resumen. Cada sección va en su propio BEGIN/EXCEPTION para que un error en un módulo no corte el resto del reporte."],
    ["c_local, c_canal_rappi, c_cliente, c_mesa, c_garzon", "constantes privadas", "Datos comunes: local 1, canal 3 (Rappi), cliente 1, mesa 3, empleado 1."],
    ["pr_titulo, pr_paso, pr_seccion, pr_resumen", "privados", "Formato de la salida. pr_resumen compara obtenido vs esperado y marca OK o REVISAR."],
    ["proc_ejecutar", "público SIN parámetros", "Llama a proc_simular y proc_generar_reporte en una sola llamada (alternativa del bloque final)."],
])

h("3.4 Bloque anónimo final (10_bloque_final.sql)", 2)
code("""DECLARE
    v_delivery PEDIDO.id_pedido%TYPE;
    v_salon    PEDIDO.id_pedido%TYPE;
BEGIN
    PKG_SIMULACION.proc_simular(v_delivery, v_salon);
    PKG_SIMULACION.proc_generar_reporte(v_delivery, v_salon);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Simulacion deshecha (ROLLBACK): ' || SQLERRM);
        RAISE;
END;
/""")

h("4. Cómo ejecutarlo en SQL Developer")
for s in [
    "Conectarse como SYS y ejecutar 00_creacion_usuario.sql (solo la primera vez).",
    "Conectarse como SABORES_ADMIN / Sabores2026.",
    "Abrir cada script y ejecutarlo con «Ejecutar script» (F5), en orden: 01, 02, 03, 04, 05, 06, 07, 08, 09 y 10. Cada archivo trae SET SERVEROUTPUT ON, así que la salida aparece en la pestaña Salida de script.",
    "Si la pestaña Salida DBMS está cerrada: Ver → Salida DBMS y el botón + para la conexión.",
    "El 10 se puede ejecutar varias veces: cada vez crea dos pedidos nuevos con un id externo distinto. La mesa 3 queda libre al final, así que la siguiente corrida la vuelve a usar.",
]:
    doc.add_paragraph(s, style="List Number")
p("Se necesita Oracle 23ai (las tablas usan BOOLEAN). Las salidas de este documento se obtuvieron en Oracle Database Free 23ai corriendo en Docker, con SQL*Plus.", it=True)

h("5. Salidas reales")
h("5.1 Compilación y pruebas de pkg_stock_receta", 2)
p("La prueba 2 muestra la corrección: con el pan casi en cero, el pedido se bloquea sin descontar carne, queso, lechuga ni tomate; además el trigger de sentencia avisa 'ALERTA DE STOCK: 1 insumo bajo el mínimo' justo después del UPDATE que dejó el pan en 0,001. La prueba 4 rechaza la doble confirmación y la prueba 5 ejecuta el procedimiento sin parámetros.")
for im in imgs["03"]: fig(im)
h("5.2 Compilación y pruebas de pkg_merma", 2)
p("La prueba 6 muestra el trigger de fila rechazando una merma sin motivo (ORA-20042) y la prueba 7 usa la función sin parámetros dentro de un SELECT y el procedimiento sin parámetros.")
for im in imgs["04"]: fig(im)
h("5.3 Compilación de PKG_SIMULACION", 2)
for im in imgs["09"]: fig(im)
h("5.4 Bloque final: simulación", 2)
for im in imgs["sim"]: fig(im)
h("5.5 Bloque final: reporte consolidado y resumen", 2)
p("La línea 'Mermas registradas hoy' muestra 2 porque la prueba 1 del script 04 también registra una merma el mismo día; por eso el resumen pide 'al menos 1'. En un esquema recién poblado, sin correr las pruebas de los módulos, saldría 1.")
for im in imgs["rep"]: fig(im)

h("6. Dónde cambiar cada cosa")
tabla([
    ["Si quiero cambiar…", "Archivo", "Dónde exactamente"],
    ["El local, el canal, el cliente, la mesa o el garzón de la simulación", "09_pkg_simulacion.sql", "Constantes c_local, c_canal_rappi, c_cliente, c_mesa, c_garzon al inicio del PACKAGE BODY"],
    ["El insumo, la cantidad o el motivo de la merma", "04_control_merma.sql", "Constantes c_insumo_sim, c_cantidad_sim, c_motivo_sim al inicio del PACKAGE BODY de pkg_merma"],
    ["Los productos del pedido delivery", "05_integracion_externa.sql", "proc_simular de PKG_INTEGRACION_EXTERNA (hoy productos 1 y 4); ajustar también el total esperado 12.400"],
    ["Los productos del pedido de salón", "06_rotacion_mesas.sql", "proc_simular de pkg_mesas, etapa ABRIR (hoy productos 2 y 5); ajustar el total esperado 13.700"],
    ["Los valores esperados del resumen", "09_pkg_simulacion.sql", "Las llamadas pr_resumen(...) al final de proc_generar_reporte"],
    ["El orden de los pasos", "09_pkg_simulacion.sql", "proc_simular: cada paso es una línea v_paso := n; pr_paso(...); PKG_X.proc_simular(...)"],
    ["Qué imprime el reporte de stock", "03_control_stock_receta.sql", "proc_reporte: cursores c_salidas y c_stock"],
    ["Qué imprime el reporte de merma", "04_control_merma.sql", "proc_reporte: cursor c_mermas_hoy y la llamada a sp_reporte_merma"],
    ["Que el bloque final no confirme (para probar sin guardar)", "10_bloque_final.sql", "Cambiar COMMIT por ROLLBACK después de proc_generar_reporte"],
    ["Permitir confirmar un pedido ya confirmado", "03_control_stock_receta.sql", "Quitar el bloque 'SELECT COUNT(*) ... tipo = SALIDA' de sp_confirmar_pedido (no recomendado)"],
])

h("7. Preguntas que pueden hacer y cómo responderlas")
for q, a in [
    ("¿Por qué proc_simular no hace COMMIT?", "Porque la transacción es de toda la simulación. Si el paso 6 falla, los pasos 1 a 5 también deben deshacerse. El único COMMIT está en el bloque anónimo final; en el EXCEPTION hay ROLLBACK y RAISE."),
    ("¿Qué componentes PL/SQL usa tu parte?", "RECORD (t_consumo_rec, t_kpi_rec), VARRAY (t_faltantes, t_kpi_tab), tabla indexada INDEX BY PLS_INTEGER (v_requerido), cursores con parámetros (c_receta, c_necesidad, c_movimientos, c_salidas, c_stock, c_mermas_hoy) y sin parámetros (c_detalles, c_locales), funciones, procedimientos públicos y privados, excepciones de usuario (ex_stock_insuficiente, ex_pedido_ya_confirmado, ex_cantidad_invalida…) y predefinidas (NO_DATA_FOUND), RAISE_APPLICATION_ERROR, FOR UPDATE, SQL%ROWCOUNT no, pero SYSDATE y TRUNC para el período del día."),
    ("¿Qué diferencia hay entre componentes públicos y privados?", "Los públicos están declarados en la especificación (PACKAGE) y se pueden llamar desde afuera, por ejemplo desde PKG_SIMULACION. Los privados solo existen en el cuerpo (PACKAGE BODY): pr_simular_pedido, fn_stock_actual, las constantes de la merma, pr_titulo/pr_paso/pr_resumen. Hay que declararlos antes de usarlos dentro del cuerpo."),
    ("¿Por qué validar todo antes de descontar?", "Porque un pedido con dos productos puede tener stock para el primero y no para el segundo. Si descuento a medida que reviso, el rechazo deja el stock del primero descontado. Validando primero, el procedimiento nunca deja el stock inconsistente aunque quien lo llame no haga ROLLBACK."),
    ("¿Por qué una tabla indexada y no solo el cursor?", "Porque el mismo insumo puede aparecer en varios productos del pedido (las papas van en el pollo grill y en las papas fritas). Sumando por id_insumo valido contra el stock la necesidad total, no cada línea por separado."),
    ("¿Cómo sabe el reporte que los datos son de esta ejecución?", "Filtra por los IDs que devolvió proc_simular (A y B). Las métricas por período (rotación de mesas, KPI de merma) son del día y se indica que pueden incluir datos previos."),
    ("¿Dónde están tus triggers y por qué uno es de fila y otro de sentencia?", "trg_merma_con_motivo es BEFORE INSERT ... FOR EACH ROW sobre MOVIMIENTO_STOCK: necesita mirar :NEW.tipo y :NEW.motivo de cada fila y puede corregir :NEW.fecha_hora, cosa que solo se puede hacer a nivel de fila. trg_alerta_stock_minimo es AFTER UPDATE OF cantidad_actual ON STOCK_LOCAL sin FOR EACH ROW: la alerta es una por operación (un pedido descuenta varios insumos en varios UPDATE, pero cada sentencia dispara una sola vez) y como es de sentencia puede consultar la misma tabla STOCK_LOCAL sin error de tabla mutante. Los dos se ven funcionando en las salidas: 'ALERTA DE STOCK: 1 insumo bajo el minimo' y 'ORA-20042: Toda merma debe registrarse con un motivo'."),
    ("¿Cuáles son tus procedimientos y funciones con y sin parámetros, y dónde se usan en SQL?", "Con parámetros: sp_confirmar_pedido, sp_registrar_merma, fn_stock_disponible, fn_costo_movimientos, fn_porcentaje_merma, proc_simular/proc_reporte. Sin parámetros: fn_insumos_bajo_minimo, fn_meta_merma, proc_alerta_stock_minimo, proc_reporte_hoy y PKG_SIMULACION.proc_ejecutar. En sentencias SQL: SELECT pkg_merma.fn_meta_merma() FROM dual, SELECT pkg_stock_receta.fn_insumos_bajo_minimo() FROM dual y el SELECT de proc_reporte que ordena los locales por pkg_merma.fn_porcentaje_merma(...). Una función se puede usar en SQL si no hace DML ni COMMIT, por eso las de cálculo sí y sp_registrar_merma no."),
    ("¿Qué pasa si un compañero todavía no tiene su proc_simular?", "PKG_SIMULACION no compila hasta que los seis packages tengan proc_simular y proc_reporte con las firmas de FIRMAS.md. Para probar en local se usó pruebas/companeros_provisional.sql, una versión provisional de los otros cuatro packages."),
    ("¿Por qué el KPI de merma sale tan alto (24,73 %)?", "Porque el consumo del día son solo los dos pedidos de la simulación (unos $12.900 de insumos) y la merma incluye los 250 GR de carne de la prueba 1 del módulo ($3.000) más los 50 GR de lechuga ($200). Con un día real de ventas el porcentaje baja."),
]:
    p(q, bold=True); p(a)

h("8. Estado del grupo")
p("En el repositorio ya están listos: 03 (stock), 04 (merma), 09 (coordinador), 10 (bloque final), FIRMAS.md y README.md. Los scripts 05 a 08 están tal como se entregaron en la parcial 1: cada compañero agrega a su package proc_simular y proc_reporte con la firma de FIRMAS.md, sin COMMIT, y relanzando errores con RAISE. Cuando los cuatro estén, se ejecuta 09 y 10 y debería salir la misma salida de la sección 5.")

out = os.path.join(docs, "Guia_simulacion_integrada.docx"); doc.save(out)
print("ok", out, sum(len(v) for v in imgs.values()), "imagenes")
