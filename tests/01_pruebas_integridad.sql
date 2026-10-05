-- =====================================================
-- tests/01_pruebas_integridad.sql
-- Paso 3: probar que la base RECHAZA datos inválidos.
-- Ejecutar después de 03_tables.sql y 04_constraints.sql.
--
-- Cada prueba inválida DEBE terminar en ERROR.
-- Si alguna se inserta sin error, la restricción falla.
-- Al final se borran los datos de preparación.
-- Usa IDs altos (9900001) para no chocar con los datos de 11_seed.sql.
-- =====================================================

SET search_path TO datamarket;
\echo '========== PREPARACIÓN: datos válidos =========='

INSERT INTO categorias (id, nombre) VALUES (9900001, 'Prueba categoria');
INSERT INTO productos (id, categoria_id, sku, nombre, precio)
VALUES (9900001, 9900001, 'SKU-PRUEBA-1', 'Producto de prueba', 10000);
INSERT INTO inventario (producto_id, stock) VALUES (9900001, 10);
INSERT INTO clientes (id, nombre, email)
VALUES (9900001, 'Cliente Prueba', 'prueba@datamarket.com');
INSERT INTO pedidos (id, cliente_id) VALUES (9900001, 9900001);
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
VALUES (9900001, 9900001, 2, 10000);

\echo ''
\echo '--- OK esperado: subtotal calculado automáticamente (2 x 10000 = 20000)'
SELECT pedido_id, cantidad, precio_unitario, subtotal
FROM detalle_pedido WHERE pedido_id = 9900001;

\echo ''
\echo '========== PRUEBAS INVÁLIDAS (todas deben dar ERROR) =========='

\echo ''
\echo '--- P01 (RN-06) Pedido con cliente inexistente -> ERROR fk_pedidos_cliente'
INSERT INTO pedidos (cliente_id) VALUES (999999);

\echo ''
\echo '--- P02 (RN-01) Producto con precio negativo -> ERROR chk_productos_precio'
INSERT INTO productos (categoria_id, sku, nombre, precio)
VALUES (9900001, 'SKU-PRUEBA-2', 'Precio negativo', -500);

\echo ''
\echo '--- P03 (RN-04) Email de cliente duplicado -> ERROR uq_clientes_email'
INSERT INTO clientes (nombre, email)
VALUES ('Otro Cliente', 'prueba@datamarket.com');

\echo ''
\echo '--- P04 (RN-05) SKU duplicado -> ERROR uq_productos_sku'
INSERT INTO productos (categoria_id, sku, nombre, precio)
VALUES (9900001, 'SKU-PRUEBA-1', 'SKU repetido', 5000);

\echo ''
\echo '--- P05 (RN-02) Stock negativo -> ERROR chk_inventario_stock'
UPDATE inventario SET stock = -1 WHERE producto_id = 9900001;

\echo ''
\echo '--- P06 (RN-03) Cantidad 0 en detalle -> ERROR chk_detalle_cantidad'
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
VALUES (9900001, 9900001, 0, 10000);

\echo ''
\echo '--- P07 (RN-07) Segundo inventario para el mismo producto -> ERROR uq_inventario_producto'
INSERT INTO inventario (producto_id, stock) VALUES (9900001, 5);

\echo ''
\echo '--- P08 (RN-08) Mismo producto dos veces en un pedido -> ERROR uq_detalle_pedido_producto'
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
VALUES (9900001, 9900001, 1, 10000);

\echo ''
\echo '--- P09 (RN-11) Estado de pedido inválido -> ERROR chk_pedidos_estado'
UPDATE pedidos SET estado = 'PERDIDO' WHERE id = 9900001;

\echo ''
\echo '--- P10 (RN-10) Escribir el subtotal a mano -> ERROR columna generada'
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
VALUES (9900001, 9900001, 1, 10000, 1);

\echo ''
\echo '--- P11 (RN-12) Borrar cliente con pedidos -> ERROR fk_pedidos_cliente'
DELETE FROM clientes WHERE id = 9900001;

\echo ''
\echo '--- P12 Campo obligatorio vacío (nombre NULL) -> ERROR not-null'
INSERT INTO clientes (nombre, email) VALUES (NULL, 'sinnombre@datamarket.com');

\echo ''
\echo '========== PRUEBA DE CASCADE (debe funcionar) =========='
\echo '--- P13 (RN-13) Borrar el pedido elimina su detalle'
DELETE FROM pedidos WHERE id = 9900001;
SELECT count(*) AS detalles_restantes FROM detalle_pedido WHERE pedido_id = 9900001;

\echo ''
\echo '========== LIMPIEZA =========='
DELETE FROM inventario WHERE producto_id = 9900001;
DELETE FROM productos  WHERE id = 9900001;
DELETE FROM categorias WHERE id = 9900001;
DELETE FROM clientes   WHERE id = 9900001;
\echo 'Datos de prueba eliminados.'
