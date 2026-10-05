-- =====================================================
-- tests/07_pruebas_funciones.sql
-- Paso 10: probar funciones y procedimientos.
-- Ejecutar como postgres después de 07, 08, 10 y 11.
--
-- Las pruebas se ejecutan como usr_operador (el rol que
-- registra compras), para comprobar también los permisos.
-- =====================================================

SET search_path TO datamarket;
\set VERBOSITY default

-- Preparar: un producto con stock conocido (10) y uno inactivo
UPDATE inventario SET stock = 10 WHERE producto_id IN (1, 2);
SELECT id AS prod_inactivo,
       '[{"producto_id": ' || id || ', "cantidad": 1}]' AS prod_json_inactivo
FROM productos WHERE NOT activo ORDER BY id LIMIT 1 \gset

SELECT (SELECT count(*) FROM pedidos)        AS ini_pedidos,
       (SELECT count(*) FROM detalle_pedido) AS ini_detalles,
       (SELECT count(*) FROM pagos)          AS ini_pagos \gset

SET ROLE usr_operador;

-- =====================================================
\echo ''
\echo '================ FUNCIONES ================'

\echo '--- fn_stock_disponible(1) -> 10'
SELECT fn_stock_disponible(1) AS stock_producto_1;

\echo '--- fn_stock_disponible(999999) -> ERROR: el producto no existe'
SELECT fn_stock_disponible(999999);

-- =====================================================
\echo ''
\echo '================ sp_registrar_compra: CASO VÁLIDO ================'
\echo 'Cliente 1 compra: 2 del producto 1, 1 del producto 2 y otra vez 1 del producto 1'
\echo '(el producto 1 repetido se suma: 3 unidades en una sola línea)'

CALL sp_registrar_compra(
    1,
    '[{"producto_id": 1, "cantidad": 2},
      {"producto_id": 2, "cantidad": 1},
      {"producto_id": 1, "cantidad": 1}]',
    'TARJETA',
    NULL
);

SELECT max(id) AS pedido_ok FROM pedidos WHERE cliente_id = 1 \gset

\echo '--- Pedido creado'
SELECT id, cliente_id, estado, total,
       fn_calcular_total_pedido(id) AS total_recalculado
FROM pedidos WHERE id = :pedido_ok;

\echo '--- Detalle (precio copiado del producto)'
SELECT producto_id, cantidad, precio_unitario, subtotal
FROM detalle_pedido WHERE pedido_id = :pedido_ok ORDER BY producto_id;

\echo '--- Pago'
SELECT monto, metodo, estado FROM pagos WHERE pedido_id = :pedido_ok;

\echo '--- Stock después: producto 1 = 7, producto 2 = 9'
SELECT producto_id, stock FROM inventario WHERE producto_id IN (1, 2) ORDER BY producto_id;

SELECT (SELECT count(*) FROM pedidos)        AS ini_pedidos,
       (SELECT count(*) FROM detalle_pedido) AS ini_detalles,
       (SELECT count(*) FROM pagos)          AS ini_pagos \gset

-- =====================================================
\echo ''
\echo '================ sp_registrar_compra: CASOS INVÁLIDOS ================'
\echo '(todos deben terminar en ERROR con un mensaje claro)'

\echo ''
\echo '--- V1 Cliente inexistente'
CALL sp_registrar_compra(999999, '[{"producto_id": 1, "cantidad": 1}]', 'PSE', NULL);

\echo ''
\echo '--- V2 Sin productos'
CALL sp_registrar_compra(1, '[]', 'PSE', NULL);

\echo ''
\echo '--- V3 Cantidad 0'
CALL sp_registrar_compra(1, '[{"producto_id": 1, "cantidad": 0}]', 'PSE', NULL);

\echo ''
\echo '--- V4 Producto inexistente'
CALL sp_registrar_compra(1, '[{"producto_id": 999999, "cantidad": 1}]', 'PSE', NULL);

\echo ''
\echo '--- V5 Producto inactivo'
CALL sp_registrar_compra(1, :'prod_json_inactivo', 'PSE', NULL);

\echo ''
\echo '--- V6 Método de pago inválido'
CALL sp_registrar_compra(1, '[{"producto_id": 1, "cantidad": 1}]', 'BITCOIN', NULL);

\echo ''
\echo '--- V7 Stock insuficiente en el SEGUNDO producto'
\echo '    (el primero sí tiene stock: debe deshacerse todo igual)'
CALL sp_registrar_compra(1, '[{"producto_id": 1, "cantidad": 1},
                              {"producto_id": 2, "cantidad": 500}]', 'PSE', NULL);

\echo ''
\echo '--- Verificación: ningún caso inválido dejó datos parciales (todo en 0)'
SELECT (SELECT count(*) FROM pedidos)        - :ini_pedidos  AS dif_pedidos,
       (SELECT count(*) FROM detalle_pedido) - :ini_detalles AS dif_detalles,
       (SELECT count(*) FROM pagos)          - :ini_pagos    AS dif_pagos;
\echo '--- Stock sin cambios: producto 1 = 7, producto 2 = 9'
SELECT producto_id, stock FROM inventario WHERE producto_id IN (1, 2) ORDER BY producto_id;

-- =====================================================
\echo ''
\echo '================ sp_cancelar_pedido ================'

\echo '--- Cancelar el pedido válido: el stock vuelve a 10 y 10'
CALL sp_cancelar_pedido(:pedido_ok);
SELECT id, estado FROM pedidos WHERE id = :pedido_ok;
SELECT producto_id, stock FROM inventario WHERE producto_id IN (1, 2) ORDER BY producto_id;

\echo '--- Cancelarlo otra vez -> ERROR: ya está CANCELADO'
CALL sp_cancelar_pedido(:pedido_ok);

\echo '--- Cancelar un pedido ENTREGADO -> ERROR'
RESET ROLE;
SELECT min(id) AS pedido_entregado FROM pedidos WHERE estado = 'ENTREGADO' \gset
SET ROLE usr_operador;
CALL sp_cancelar_pedido(:pedido_entregado);

RESET ROLE;

-- =====================================================
\echo ''
\echo '================ PERMISOS ================'

SET ROLE usr_analista;
\echo '--- [PERMITIDO] Analista ejecuta el reporte por categoría (último mes)'
SELECT * FROM fn_ventas_por_categoria((current_date - 30), current_date);

\echo '--- [DENEGADO] Analista intenta registrar una compra'
CALL sp_registrar_compra(1, '[{"producto_id": 1, "cantidad": 1}]', 'PSE', NULL);
RESET ROLE;

SET ROLE usr_auditor;
\echo '--- [DENEGADO] Auditor intenta consultar stock'
SELECT fn_stock_disponible(1);
RESET ROLE;

\echo ''
\echo '--- fn_ventas_por_categoria con rango invertido -> ERROR'
SELECT * FROM fn_ventas_por_categoria(current_date, current_date - 30);
