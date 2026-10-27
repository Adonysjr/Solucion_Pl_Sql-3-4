-- ---------------------------------------------------------------------
-- 0. ELIMINAR MODELO EXISTENTE
-- ---------------------------------------------------------------------

DECLARE
    PROCEDURE drop_table_if_exists(p_table_name VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE
            'DROP TABLE ' || p_table_name || ' CASCADE CONSTRAINTS PURGE';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -942 THEN
                RAISE;
            END IF;
    END;

    PROCEDURE drop_sequence_if_exists(p_sequence_name VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE
            'DROP SEQUENCE ' || p_sequence_name;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -2289 THEN
                RAISE;
            END IF;
    END;
BEGIN
    -- Tablas transaccionales e hijas.
    drop_table_if_exists('MOVIMIENTO_STOCK');
    drop_table_if_exists('PAGO');
    drop_table_if_exists('BOLETA');
    drop_table_if_exists('DETALLE_PEDIDO');
    drop_table_if_exists('PEDIDO');

    -- Tablas intermedias.
    drop_table_if_exists('STOCK_LOCAL');
    drop_table_if_exists('RECETA');

    -- Tablas con FK a maestras.
    drop_table_if_exists('PRODUCTO');
    drop_table_if_exists('MESA');
    drop_table_if_exists('EMPLEADO');

    -- Tablas maestras.
    drop_table_if_exists('CLIENTE');
    drop_table_if_exists('ESTADO_PEDIDO');
    drop_table_if_exists('MEDIO_PAGO');
    drop_table_if_exists('CANAL_VENTA');
    drop_table_if_exists('INSUMO');
    drop_table_if_exists('CATEGORIA');
    drop_table_if_exists('LOCAL');

    -- Secuencias.
    drop_sequence_if_exists('SEQ_MOVIMIENTO_STOCK');
    drop_sequence_if_exists('SEQ_PAGO');
    drop_sequence_if_exists('SEQ_BOLETA');
    drop_sequence_if_exists('SEQ_DETALLE_PEDIDO');
    drop_sequence_if_exists('SEQ_PEDIDO');
    drop_sequence_if_exists('SEQ_CLIENTE');
    drop_sequence_if_exists('SEQ_INSUMO');
    drop_sequence_if_exists('SEQ_PRODUCTO');
    drop_sequence_if_exists('SEQ_CATEGORIA');
    drop_sequence_if_exists('SEQ_MESA');
    drop_sequence_if_exists('SEQ_EMPLEADO');
    drop_sequence_if_exists('SEQ_LOCAL');

    DBMS_OUTPUT.PUT_LINE('Modelo anterior eliminado correctamente.');
END;
/

-- ---------------------------------------------------------------------
-- 1. TABLAS MAESTRAS (sin FK)
-- ---------------------------------------------------------------------

CREATE TABLE LOCAL (
    id_local          NUMBER(3)      NOT NULL,
    nombre            VARCHAR2(60)   NOT NULL,
    centro_comercial  VARCHAR2(60)   NOT NULL,
    comuna            VARCHAR2(40)   NOT NULL,
    direccion         VARCHAR2(120)  NOT NULL,
    telefono          VARCHAR2(15),
    activo            BOOLEAN        DEFAULT TRUE NOT NULL,

    CONSTRAINT pk_local PRIMARY KEY (id_local),
    CONSTRAINT uk_local_nom UNIQUE (nombre)
);

CREATE TABLE CATEGORIA (
    id_categoria  NUMBER(3)     NOT NULL,
    nombre        VARCHAR2(40)  NOT NULL,

    CONSTRAINT pk_categoria PRIMARY KEY (id_categoria),
    CONSTRAINT uk_categoria_nom UNIQUE (nombre)
);

CREATE TABLE INSUMO (
    id_insumo       NUMBER(5)      NOT NULL,
    nombre          VARCHAR2(60)   NOT NULL,
    unidad_medida   VARCHAR2(5)    NOT NULL,
    costo_unitario  NUMBER(10,2)   NOT NULL,

    CONSTRAINT pk_insumo PRIMARY KEY (id_insumo),
    CONSTRAINT uk_insumo_nom UNIQUE (nombre),
    CONSTRAINT ck_insumo_um CHECK (unidad_medida IN ('KG','GR','LT','ML','UN')),
    CONSTRAINT ck_insumo_cos CHECK (costo_unitario >= 0)
);

CREATE TABLE CANAL_VENTA (
    id_canal              NUMBER(2)     NOT NULL,
    nombre                VARCHAR2(30)  NOT NULL,
    tipo                  VARCHAR2(10)  NOT NULL,
    comision_pct          NUMBER(5,2)   DEFAULT 0 NOT NULL,
    requiere_integracion  BOOLEAN       DEFAULT FALSE NOT NULL,
    activo                BOOLEAN       DEFAULT TRUE NOT NULL,

    CONSTRAINT pk_canal_venta PRIMARY KEY (id_canal),
    CONSTRAINT uk_canal_venta_nom UNIQUE (nombre),
    CONSTRAINT ck_canal_tipo CHECK (tipo IN ('PRESENCIAL','DELIVERY')),
    CONSTRAINT ck_canal_com CHECK (comision_pct BETWEEN 0 AND 100)
);

CREATE TABLE MEDIO_PAGO (
    id_medio_pago  NUMBER(2)     NOT NULL,
    nombre         VARCHAR2(30)  NOT NULL,

    CONSTRAINT pk_medio_pago PRIMARY KEY (id_medio_pago),
    CONSTRAINT uk_medio_pago_nom UNIQUE (nombre)
);

CREATE TABLE ESTADO_PEDIDO (
    id_estado  NUMBER(2)     NOT NULL,
    nombre     VARCHAR2(20)  NOT NULL,

    CONSTRAINT pk_estado_pedido PRIMARY KEY (id_estado),
    CONSTRAINT uk_estado_pedido_nom UNIQUE (nombre)
);

CREATE TABLE CLIENTE (
    id_cliente  NUMBER(8)      NOT NULL,
    rut         VARCHAR2(12),
    nombre      VARCHAR2(80)   NOT NULL,
    telefono    VARCHAR2(15),
    email       VARCHAR2(80),
    direccion   VARCHAR2(150),

    CONSTRAINT pk_cliente PRIMARY KEY (id_cliente),
    CONSTRAINT uk_cliente_rut UNIQUE (rut)
);

-- ---------------------------------------------------------------------
-- 2. TABLAS CON FK A MAESTRAS
-- ---------------------------------------------------------------------

CREATE TABLE EMPLEADO (
    id_empleado    NUMBER(6)     NOT NULL,
    rut            VARCHAR2(12)  NOT NULL,
    nombre         VARCHAR2(40)  NOT NULL,
    apellido       VARCHAR2(40)  NOT NULL,
    cargo          VARCHAR2(20)  NOT NULL,
    fecha_ingreso  DATE          DEFAULT SYSDATE NOT NULL,
    activo         BOOLEAN       DEFAULT TRUE NOT NULL,
    id_local       NUMBER(3)     NOT NULL,

    CONSTRAINT pk_empleado PRIMARY KEY (id_empleado),
    CONSTRAINT uk_empleado_rut UNIQUE (rut),
    CONSTRAINT ck_empleado_cargo CHECK (cargo IN ('GARZON','COCINERO','CAJERO','ADMIN')),
    CONSTRAINT fk_empleado_local FOREIGN KEY (id_local) REFERENCES LOCAL (id_local)
);

CREATE TABLE MESA (
    id_mesa      NUMBER(5)    NOT NULL,
    numero_mesa  NUMBER(3)    NOT NULL,
    capacidad    NUMBER(2)    NOT NULL,
    ocupada      BOOLEAN      DEFAULT FALSE NOT NULL,
    id_local     NUMBER(3)    NOT NULL,

    CONSTRAINT pk_mesa PRIMARY KEY (id_mesa),
    CONSTRAINT uk_mesa_num UNIQUE (id_local, numero_mesa),
    CONSTRAINT ck_mesa_cap CHECK (capacidad > 0),
    CONSTRAINT fk_mesa_local FOREIGN KEY (id_local) REFERENCES LOCAL (id_local)
);

CREATE TABLE PRODUCTO (
    id_producto             NUMBER(5)      NOT NULL,
    nombre                  VARCHAR2(60)   NOT NULL,
    descripcion             VARCHAR2(200),
    precio_venta            NUMBER(8)      NOT NULL,
    tiempo_preparacion_min  NUMBER(3)      NOT NULL,
    afecto_iva              BOOLEAN        DEFAULT TRUE NOT NULL,
    activo                  BOOLEAN        DEFAULT TRUE NOT NULL,
    id_categoria            NUMBER(3)      NOT NULL,

    CONSTRAINT pk_producto PRIMARY KEY (id_producto),
    CONSTRAINT uk_producto_nom UNIQUE (nombre),
    CONSTRAINT ck_producto_precio CHECK (precio_venta > 0),
    CONSTRAINT ck_producto_tiempo CHECK (tiempo_preparacion_min > 0),
    CONSTRAINT fk_producto_categoria FOREIGN KEY (id_categoria) REFERENCES CATEGORIA (id_categoria)
);

-- ---------------------------------------------------------------------
-- 3. TABLAS INTERMEDIAS N:M
-- ---------------------------------------------------------------------

CREATE TABLE RECETA (
    id_producto         NUMBER(5)     NOT NULL,
    id_insumo           NUMBER(5)     NOT NULL,
    cantidad_requerida  NUMBER(10,3)  NOT NULL,

    CONSTRAINT pk_receta PRIMARY KEY (id_producto, id_insumo),
    CONSTRAINT ck_receta_cant CHECK (cantidad_requerida > 0),
    CONSTRAINT fk_receta_producto FOREIGN KEY (id_producto) REFERENCES PRODUCTO (id_producto),
    CONSTRAINT fk_receta_insumo FOREIGN KEY (id_insumo) REFERENCES INSUMO (id_insumo)
);

CREATE TABLE STOCK_LOCAL (
    id_local             NUMBER(3)     NOT NULL,
    id_insumo            NUMBER(5)     NOT NULL,
    cantidad_actual      NUMBER(10,3)  DEFAULT 0 NOT NULL,
    stock_minimo         NUMBER(10,3)  DEFAULT 0 NOT NULL,
    fecha_actualizacion  DATE          DEFAULT SYSDATE NOT NULL,

    CONSTRAINT pk_stock_local PRIMARY KEY (id_local, id_insumo),
    CONSTRAINT ck_stock_local_cant CHECK (cantidad_actual >= 0),
    CONSTRAINT ck_stock_local_min CHECK (stock_minimo >= 0),
    CONSTRAINT fk_stock_local_local FOREIGN KEY (id_local) REFERENCES LOCAL (id_local),
    CONSTRAINT fk_stock_local_insumo FOREIGN KEY (id_insumo) REFERENCES INSUMO (id_insumo)
);

-- ---------------------------------------------------------------------
-- 4. TABLAS TRANSACCIONALES
-- ---------------------------------------------------------------------

CREATE TABLE PEDIDO (
    id_pedido            NUMBER(10)     NOT NULL,
    fecha_hora_creacion  DATE           DEFAULT SYSDATE NOT NULL,
    fecha_hora_entrega   DATE,
    fecha_hora_cierre    DATE,
    id_externo_delivery  VARCHAR2(50),
    observacion          VARCHAR2(200),
    total                NUMBER(10)     DEFAULT 0 NOT NULL,
    id_local             NUMBER(3)      NOT NULL,
    id_mesa              NUMBER(5),                 -- NULL si delivery / totem
    id_empleado          NUMBER(6),                 -- NULL si totem / app
    id_canal             NUMBER(2)      NOT NULL,
    id_cliente           NUMBER(8),                 -- puede ser NULL en salon
    id_estado            NUMBER(2)      DEFAULT 1 NOT NULL,

    CONSTRAINT pk_pedido PRIMARY KEY (id_pedido),
    CONSTRAINT ck_pedido_total CHECK (total >= 0),
    CONSTRAINT ck_pedido_entrega CHECK (
        fecha_hora_entrega IS NULL OR fecha_hora_entrega >= fecha_hora_creacion
    ),
    CONSTRAINT ck_pedido_cierre CHECK (
        fecha_hora_cierre IS NULL OR fecha_hora_cierre >= fecha_hora_creacion
    ),
    CONSTRAINT fk_pedido_local FOREIGN KEY (id_local) REFERENCES LOCAL (id_local),
    CONSTRAINT fk_pedido_mesa FOREIGN KEY (id_mesa) REFERENCES MESA (id_mesa),
    CONSTRAINT fk_pedido_empleado FOREIGN KEY (id_empleado) REFERENCES EMPLEADO (id_empleado),
    CONSTRAINT fk_pedido_canal FOREIGN KEY (id_canal) REFERENCES CANAL_VENTA (id_canal),
    CONSTRAINT fk_pedido_cliente FOREIGN KEY (id_cliente) REFERENCES CLIENTE (id_cliente),
    CONSTRAINT fk_pedido_estado FOREIGN KEY (id_estado) REFERENCES ESTADO_PEDIDO (id_estado)
);

-- ---------------------------------------------------------------------
-- UNICIDAD DE PEDIDOS DELIVERY
-- ---------------------------------------------------------------------
CREATE UNIQUE INDEX uk_pedido_delivery
ON PEDIDO (
    CASE
        WHEN id_externo_delivery IS NOT NULL THEN id_canal
    END,
    CASE
        WHEN id_externo_delivery IS NOT NULL THEN id_externo_delivery
    END
);

CREATE TABLE DETALLE_PEDIDO (
    id_detalle        NUMBER(12)    NOT NULL,
    cantidad          NUMBER(3)     NOT NULL,
    precio_unitario   NUMBER(8)     NOT NULL,
    subtotal          NUMBER(10)    NOT NULL,
    observacion       VARCHAR2(100),
    estado_kds        VARCHAR2(15)  DEFAULT 'PENDIENTE' NOT NULL,
    fecha_hora_inicio DATE,
    fecha_hora_listo  DATE,
    id_pedido         NUMBER(10)    NOT NULL,
    id_producto       NUMBER(5)     NOT NULL,

    CONSTRAINT pk_detalle_pedido PRIMARY KEY (id_detalle),
    CONSTRAINT ck_detalle_cant CHECK (cantidad > 0),
    CONSTRAINT ck_detalle_precio CHECK (precio_unitario > 0),
    CONSTRAINT ck_detalle_subtotal CHECK (subtotal > 0),
    CONSTRAINT ck_detalle_kds CHECK (estado_kds IN ('PENDIENTE','PREPARANDO','LISTO')),
    CONSTRAINT ck_detalle_fechas CHECK (
        fecha_hora_listo IS NULL
        OR (fecha_hora_inicio IS NOT NULL AND fecha_hora_listo >= fecha_hora_inicio)
    ),
    CONSTRAINT fk_detalle_pedido FOREIGN KEY (id_pedido)
        REFERENCES PEDIDO (id_pedido) ON DELETE CASCADE,
    CONSTRAINT fk_detalle_producto FOREIGN KEY (id_producto)
        REFERENCES PRODUCTO (id_producto)
);

CREATE TABLE BOLETA (
    id_boleta      NUMBER(10)    NOT NULL,
    folio_sii      NUMBER(12)    NOT NULL,
    tipo           VARCHAR2(7)   NOT NULL,
    fecha_emision  DATE          DEFAULT SYSDATE NOT NULL,
    neto           NUMBER(10)    NOT NULL,
    iva            NUMBER(10)    NOT NULL,
    total          NUMBER(10)    NOT NULL,
    estado_dte     VARCHAR2(10)  DEFAULT 'PENDIENTE' NOT NULL,
    id_pedido      NUMBER(10)    NOT NULL,

    CONSTRAINT pk_boleta PRIMARY KEY (id_boleta),
    CONSTRAINT uk_boleta_folio UNIQUE (tipo, folio_sii),
    CONSTRAINT uk_boleta_pedido UNIQUE (id_pedido),
    CONSTRAINT ck_boleta_tipo CHECK (tipo IN ('EXENTA','AFECTA')),
    CONSTRAINT ck_boleta_dte CHECK (estado_dte IN ('PENDIENTE','ACEPTADA','RECHAZADA')),
    CONSTRAINT ck_boleta_montos CHECK (neto >= 0 AND iva >= 0 AND total > 0),
    CONSTRAINT fk_boleta_pedido FOREIGN KEY (id_pedido) REFERENCES PEDIDO (id_pedido)
);

CREATE TABLE PAGO (
    id_pago        NUMBER(10)  NOT NULL,
    monto          NUMBER(10)  NOT NULL,
    fecha_hora     DATE        DEFAULT SYSDATE NOT NULL,
    id_pedido      NUMBER(10)  NOT NULL,
    id_medio_pago  NUMBER(2)   NOT NULL,

    CONSTRAINT pk_pago PRIMARY KEY (id_pago),
    CONSTRAINT ck_pago_monto CHECK (monto > 0),
    CONSTRAINT fk_pago_pedido FOREIGN KEY (id_pedido) REFERENCES PEDIDO (id_pedido),
    CONSTRAINT fk_pago_medio_pago FOREIGN KEY (id_medio_pago) REFERENCES MEDIO_PAGO (id_medio_pago)
);

CREATE TABLE MOVIMIENTO_STOCK (
    id_movimiento  NUMBER(12)     NOT NULL,
    tipo           VARCHAR2(8)    NOT NULL,
    cantidad       NUMBER(10,3)   NOT NULL,
    fecha_hora     DATE           DEFAULT SYSDATE NOT NULL,
    motivo         VARCHAR2(100),
    id_local       NUMBER(3)      NOT NULL,
    id_insumo      NUMBER(5)      NOT NULL,
    id_pedido      NUMBER(10),                    -- NULL si es merma / entrada / ajuste

    CONSTRAINT pk_movimiento_stock PRIMARY KEY (id_movimiento),
    CONSTRAINT ck_movimiento_tipo CHECK (tipo IN ('ENTRADA','SALIDA','MERMA','AJUSTE')),
    CONSTRAINT ck_movimiento_cant CHECK (cantidad > 0),
    CONSTRAINT fk_movimiento_local FOREIGN KEY (id_local) REFERENCES LOCAL (id_local),
    CONSTRAINT fk_movimiento_insumo FOREIGN KEY (id_insumo) REFERENCES INSUMO (id_insumo),
    CONSTRAINT fk_movimiento_pedido FOREIGN KEY (id_pedido) REFERENCES PEDIDO (id_pedido)
);

-- ---------------------------------------------------------------------
-- 5. SECUENCIAS (para INSERT desde PL/SQL)
-- ---------------------------------------------------------------------

CREATE SEQUENCE seq_local            START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_empleado         START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_mesa             START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_categoria        START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_producto         START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_insumo           START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_cliente          START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_pedido           START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_detalle_pedido   START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_boleta           START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_pago             START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE seq_movimiento_stock START WITH 1 INCREMENT BY 1;
