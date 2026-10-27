
/*
=====================================================================
1. LOCALES
=====================================================================
*/
INSERT INTO LOCAL VALUES (seq_local.NEXTVAL,'Sabores Urbanos Costanera','Costanera Center','Providencia','Av. Andrés Bello 2425','226000101',TRUE);
INSERT INTO LOCAL VALUES (seq_local.NEXTVAL,'Sabores Urbanos Parque Arauco','Parque Arauco','Las Condes','Av. Presidente Kennedy 5413','226000102',TRUE);
INSERT INTO LOCAL VALUES (seq_local.NEXTVAL,'Sabores Urbanos Plaza Egaña','Mallplaza Egaña','La Reina','Av. Larraín 5862','226000103',TRUE);
INSERT INTO LOCAL VALUES (seq_local.NEXTVAL,'Sabores Urbanos Vespucio','Mallplaza Vespucio','La Florida','Av. Vicuña Mackenna 7110','226000104',TRUE);
INSERT INTO LOCAL VALUES (seq_local.NEXTVAL,'Sabores Urbanos Plaza Oeste','Mallplaza Oeste','Cerrillos','Av. Américo Vespucio 1501','226000105',TRUE);
INSERT INTO LOCAL VALUES (seq_local.NEXTVAL,'Sabores Urbanos Plaza Norte','Mallplaza Norte','Huechuraba','Av. Américo Vespucio 1737','226000106',TRUE);
INSERT INTO LOCAL VALUES (seq_local.NEXTVAL,'Sabores Urbanos Alto Las Condes','Alto Las Condes','Las Condes','Av. Presidente Kennedy 9001','226000107',TRUE);
INSERT INTO LOCAL VALUES (seq_local.NEXTVAL,'Sabores Urbanos Florida Center','Florida Center','La Florida','Av. Vicuña Mackenna 6100','226000108',TRUE);
INSERT INTO LOCAL VALUES (seq_local.NEXTVAL,'Sabores Urbanos Tobalaba','Mallplaza Tobalaba','Puente Alto','Av. Camilo Henríquez 3296','226000109',TRUE);

/*
=====================================================================
2. CATEGORÍAS E INSUMOS
=====================================================================
*/
INSERT INTO CATEGORIA VALUES (seq_categoria.NEXTVAL,'Hamburguesas');
INSERT INTO CATEGORIA VALUES (seq_categoria.NEXTVAL,'Platos principales');
INSERT INTO CATEGORIA VALUES (seq_categoria.NEXTVAL,'Ensaladas y acompañamientos');
INSERT INTO CATEGORIA VALUES (seq_categoria.NEXTVAL,'Bebidas y convenios');

INSERT INTO INSUMO VALUES (seq_insumo.NEXTVAL,'Pan de hamburguesa','UN',350);
INSERT INTO INSUMO VALUES (seq_insumo.NEXTVAL,'Carne de vacuno','GR',12);
INSERT INTO INSUMO VALUES (seq_insumo.NEXTVAL,'Pechuga de pollo','GR',8);
INSERT INTO INSUMO VALUES (seq_insumo.NEXTVAL,'Queso cheddar','GR',10);
INSERT INTO INSUMO VALUES (seq_insumo.NEXTVAL,'Lechuga','GR',4);
INSERT INTO INSUMO VALUES (seq_insumo.NEXTVAL,'Tomate','GR',5);
INSERT INTO INSUMO VALUES (seq_insumo.NEXTVAL,'Papa','GR',2);
INSERT INTO INSUMO VALUES (seq_insumo.NEXTVAL,'Bebida cola 500 ml','UN',850);

/*
=====================================================================
3. CANALES, MEDIOS DE PAGO Y ESTADOS
=====================================================================
*/
INSERT INTO CANAL_VENTA VALUES (1,'GARZON','PRESENCIAL',0,FALSE,TRUE);
INSERT INTO CANAL_VENTA VALUES (2,'TOTEM','PRESENCIAL',0,FALSE,TRUE);
INSERT INTO CANAL_VENTA VALUES (3,'RAPPI','DELIVERY',27.5,TRUE,TRUE);
INSERT INTO CANAL_VENTA VALUES (4,'UBER_EATS','DELIVERY',29,TRUE,TRUE);
INSERT INTO CANAL_VENTA VALUES (5,'JUST_EAT','DELIVERY',25,TRUE,TRUE);

INSERT INTO MEDIO_PAGO VALUES (1,'EFECTIVO');
INSERT INTO MEDIO_PAGO VALUES (2,'DEBITO');
INSERT INTO MEDIO_PAGO VALUES (3,'CREDITO');
INSERT INTO MEDIO_PAGO VALUES (4,'TRANSFERENCIA');
INSERT INTO MEDIO_PAGO VALUES (5,'APP_DELIVERY');

INSERT INTO ESTADO_PEDIDO VALUES (1,'PENDIENTE');
INSERT INTO ESTADO_PEDIDO VALUES (2,'EN_PREPARACION');
INSERT INTO ESTADO_PEDIDO VALUES (3,'LISTO');
INSERT INTO ESTADO_PEDIDO VALUES (4,'ENTREGADO');
INSERT INTO ESTADO_PEDIDO VALUES (5,'ANULADO');

/*
=====================================================================
4. EMPLEADOS Y MESAS
=====================================================================
*/
INSERT INTO EMPLEADO VALUES (seq_empleado.NEXTVAL,'21000001-1','Sofía','Rojas','GARZON',TRUNC(SYSDATE)-400,TRUE,1);
INSERT INTO EMPLEADO VALUES (seq_empleado.NEXTVAL,'21000002-2','Mateo','Díaz','COCINERO',TRUNC(SYSDATE)-350,TRUE,1);
INSERT INTO EMPLEADO VALUES (seq_empleado.NEXTVAL,'21000003-3','Valentina','Soto','COCINERO',TRUNC(SYSDATE)-300,TRUE,1);
INSERT INTO EMPLEADO VALUES (seq_empleado.NEXTVAL,'21000004-4','Diego','Pérez','CAJERO',TRUNC(SYSDATE)-250,TRUE,1);
INSERT INTO EMPLEADO VALUES (seq_empleado.NEXTVAL,'21000005-5','Camila','González','ADMIN',TRUNC(SYSDATE)-500,TRUE,1);

INSERT INTO MESA VALUES (seq_mesa.NEXTVAL,1,4,FALSE,1);
INSERT INTO MESA VALUES (seq_mesa.NEXTVAL,2,4,FALSE,1);
INSERT INTO MESA VALUES (seq_mesa.NEXTVAL,3,2,FALSE,1);
INSERT INTO MESA VALUES (seq_mesa.NEXTVAL,4,6,FALSE,1);

/*
=====================================================================
5. PRODUCTOS
=====================================================================
*/
INSERT INTO PRODUCTO VALUES (seq_producto.NEXTVAL,'Hamburguesa Clásica','Hamburguesa de vacuno con queso, lechuga y tomate',8500,8,TRUE,TRUE,1);
INSERT INTO PRODUCTO VALUES (seq_producto.NEXTVAL,'Pollo Grill con Papas','Pechuga de pollo grillada con papas',11500,13,TRUE,TRUE,2);
INSERT INTO PRODUCTO VALUES (seq_producto.NEXTVAL,'Ensalada de Pollo','Ensalada de pollo con lechuga y tomate',9900,7,TRUE,TRUE,3);
INSERT INTO PRODUCTO VALUES (seq_producto.NEXTVAL,'Papas Fritas','Porción individual de papas fritas',3900,5,TRUE,TRUE,3);
INSERT INTO PRODUCTO VALUES (seq_producto.NEXTVAL,'Bebida Cola 500 ml','Bebida individual de 500 ml',2200,1,TRUE,TRUE,4);
INSERT INTO PRODUCTO VALUES (seq_producto.NEXTVAL,'Colación Convenio Pollo','Colación de pollo con ensalada para convenio institucional',7500,10,FALSE,TRUE,4);

/*
=====================================================================
6. RECETAS
=====================================================================
*/
INSERT INTO RECETA VALUES (1,1,1);
INSERT INTO RECETA VALUES (1,2,180);
INSERT INTO RECETA VALUES (1,4,30);
INSERT INTO RECETA VALUES (1,5,25);
INSERT INTO RECETA VALUES (1,6,40);
INSERT INTO RECETA VALUES (2,3,220);
INSERT INTO RECETA VALUES (2,7,250);
INSERT INTO RECETA VALUES (3,3,150);
INSERT INTO RECETA VALUES (3,5,100);
INSERT INTO RECETA VALUES (3,6,80);
INSERT INTO RECETA VALUES (4,7,250);
INSERT INTO RECETA VALUES (5,8,1);
INSERT INTO RECETA VALUES (6,3,180);
INSERT INTO RECETA VALUES (6,5,80);
INSERT INTO RECETA VALUES (6,6,60);

/*
=====================================================================
7. STOCK
=====================================================================
*/
INSERT INTO STOCK_LOCAL VALUES (1,1,30,10,SYSDATE);
INSERT INTO STOCK_LOCAL VALUES (1,2,8000,1500,SYSDATE);
INSERT INTO STOCK_LOCAL VALUES (1,3,6000,1200,SYSDATE);
INSERT INTO STOCK_LOCAL VALUES (1,4,3000,500,SYSDATE);
INSERT INTO STOCK_LOCAL VALUES (1,5,4000,800,SYSDATE);
INSERT INTO STOCK_LOCAL VALUES (1,6,4000,800,SYSDATE);
INSERT INTO STOCK_LOCAL VALUES (1,7,12000,2500,SYSDATE);
INSERT INTO STOCK_LOCAL VALUES (1,8,50,10,SYSDATE);

/*
=====================================================================
8. CLIENTES
=====================================================================
*/
INSERT INTO CLIENTE VALUES (seq_cliente.NEXTVAL,'18000001-1','Daniela Muñoz','912345678','daniela.munoz@correo.cl','Providencia, Santiago');
INSERT INTO CLIENTE VALUES (seq_cliente.NEXTVAL,'18000002-2','Andrés Silva','923456789','andres.silva@correo.cl','Las Condes, Santiago');

/*
=====================================================================
9. PEDIDOS HISTÓRICOS
=====================================================================
*/
INSERT INTO PEDIDO VALUES (seq_pedido.NEXTVAL,TRUNC(SYSDATE)-10+12/24,TRUNC(SYSDATE)-10+12/24+18/1440,TRUNC(SYSDATE)-10+13/24,NULL,NULL,12400,1,1,1,1,1,4);
INSERT INTO PEDIDO VALUES (seq_pedido.NEXTVAL,TRUNC(SYSDATE)-7+13/24,TRUNC(SYSDATE)-7+13/24+14/1440,TRUNC(SYSDATE)-7+13/24+20/1440,'RAP-001','Pedido recibido desde Rappi',13700,1,NULL,NULL,3,2,4);
INSERT INTO PEDIDO VALUES (seq_pedido.NEXTVAL,TRUNC(SYSDATE)-5+14/24,TRUNC(SYSDATE)-5+14/24+12/1440,TRUNC(SYSDATE)-5+14/24+17/1440,NULL,'Pedido realizado en tótem',7500,1,NULL,NULL,2,1,4);
INSERT INTO PEDIDO VALUES (seq_pedido.NEXTVAL,TRUNC(SYSDATE)-2+12/24+30/1440,TRUNC(SYSDATE)-2+12/24+46/1440,TRUNC(SYSDATE)-2+13/24+20/1440,NULL,NULL,12100,1,2,1,1,NULL,4);

/*
=====================================================================
10. DETALLES DE PEDIDO
=====================================================================
*/
INSERT INTO DETALLE_PEDIDO VALUES (seq_detalle_pedido.NEXTVAL,1,8500,8500,NULL,'LISTO',TRUNC(SYSDATE)-10+12/24+2/1440,TRUNC(SYSDATE)-10+12/24+10/1440,1,1);
INSERT INTO DETALLE_PEDIDO VALUES (seq_detalle_pedido.NEXTVAL,1,3900,3900,NULL,'LISTO',TRUNC(SYSDATE)-10+12/24+3/1440,TRUNC(SYSDATE)-10+12/24+8/1440,1,4);
INSERT INTO DETALLE_PEDIDO VALUES (seq_detalle_pedido.NEXTVAL,1,11500,11500,NULL,'LISTO',TRUNC(SYSDATE)-7+13/24+1/1440,TRUNC(SYSDATE)-7+13/24+12/1440,2,2);
INSERT INTO DETALLE_PEDIDO VALUES (seq_detalle_pedido.NEXTVAL,1,2200,2200,NULL,'LISTO',TRUNC(SYSDATE)-7+13/24+1/1440,TRUNC(SYSDATE)-7+13/24+2/1440,2,5);
INSERT INTO DETALLE_PEDIDO VALUES (seq_detalle_pedido.NEXTVAL,1,7500,7500,NULL,'LISTO',TRUNC(SYSDATE)-5+14/24+1/1440,TRUNC(SYSDATE)-5+14/24+10/1440,3,6);
INSERT INTO DETALLE_PEDIDO VALUES (seq_detalle_pedido.NEXTVAL,1,9900,9900,NULL,'LISTO',TRUNC(SYSDATE)-2+12/24+32/1440,TRUNC(SYSDATE)-2+12/24+42/1440,4,3);
INSERT INTO DETALLE_PEDIDO VALUES (seq_detalle_pedido.NEXTVAL,1,2200,2200,NULL,'LISTO',TRUNC(SYSDATE)-2+12/24+31/1440,TRUNC(SYSDATE)-2+12/24+33/1440,4,5);

/*
=====================================================================
11. BOLETAS Y PAGOS
=====================================================================
*/
INSERT INTO BOLETA VALUES (seq_boleta.NEXTVAL,1001,'AFECTA',TRUNC(SYSDATE)-10+13/24,10420,1980,12400,'ACEPTADA',1);
INSERT INTO BOLETA VALUES (seq_boleta.NEXTVAL,1002,'AFECTA',TRUNC(SYSDATE)-7+13/24+20/1440,11513,2187,13700,'ACEPTADA',2);
INSERT INTO BOLETA VALUES (seq_boleta.NEXTVAL,5001,'EXENTA',TRUNC(SYSDATE)-5+14/24+17/1440,7500,0,7500,'ACEPTADA',3);
INSERT INTO BOLETA VALUES (seq_boleta.NEXTVAL,1003,'AFECTA',TRUNC(SYSDATE)-2+13/24+20/1440,10168,1932,12100,'ACEPTADA',4);

INSERT INTO PAGO VALUES (seq_pago.NEXTVAL,12400,TRUNC(SYSDATE)-10+13/24,1,2);
INSERT INTO PAGO VALUES (seq_pago.NEXTVAL,13700,TRUNC(SYSDATE)-7+13/24+1/1440,2,5);
INSERT INTO PAGO VALUES (seq_pago.NEXTVAL,7500,TRUNC(SYSDATE)-5+14/24+17/1440,3,2);
INSERT INTO PAGO VALUES (seq_pago.NEXTVAL,12100,TRUNC(SYSDATE)-2+13/24+20/1440,4,1);

/*
=====================================================================
12. MOVIMIENTOS DE STOCK
=====================================================================
*/
INSERT INTO MOVIMIENTO_STOCK VALUES (seq_movimiento_stock.NEXTVAL,'SALIDA',180,TRUNC(SYSDATE)-10+12/24+10/1440,'Consumo de carne por venta',1,2,1);
INSERT INTO MOVIMIENTO_STOCK VALUES (seq_movimiento_stock.NEXTVAL,'SALIDA',220,TRUNC(SYSDATE)-7+13/24+12/1440,'Consumo de pollo por venta',1,3,2);
INSERT INTO MOVIMIENTO_STOCK VALUES (seq_movimiento_stock.NEXTVAL,'MERMA',150,TRUNC(SYSDATE)-4,'Papas descartadas por mala calidad',1,7,NULL);
INSERT INTO MOVIMIENTO_STOCK VALUES (seq_movimiento_stock.NEXTVAL,'MERMA',80,TRUNC(SYSDATE)-3,'Tomates dañados durante almacenamiento',1,6,NULL);

/*
=====================================================================
13. AJUSTES Y CONFIRMACIÓN
=====================================================================
*/
UPDATE MESA SET ocupada = FALSE;
COMMIT;

/*
=====================================================================
14. VALIDACIONES
=====================================================================
*/
SELECT COUNT(*) AS locales FROM LOCAL;
SELECT COUNT(*) AS empleados FROM EMPLEADO;
SELECT COUNT(*) AS mesas FROM MESA;
SELECT COUNT(*) AS productos FROM PRODUCTO;
SELECT COUNT(*) AS insumos FROM INSUMO;
SELECT COUNT(*) AS recetas FROM RECETA;
SELECT COUNT(*) AS stock FROM STOCK_LOCAL;
SELECT COUNT(*) AS clientes FROM CLIENTE;
SELECT COUNT(*) AS pedidos FROM PEDIDO;
SELECT COUNT(*) AS detalles FROM DETALLE_PEDIDO;
SELECT COUNT(*) AS boletas FROM BOLETA;
SELECT COUNT(*) AS pagos FROM PAGO;
SELECT COUNT(*) AS movimientos_stock FROM MOVIMIENTO_STOCK;

SELECT id_pedido,total,id_canal,id_estado,id_externo_delivery
FROM PEDIDO
ORDER BY id_pedido;
