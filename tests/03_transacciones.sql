-- =====================================================
-- tests/03_transacciones.sql
-- Paso 6: el proceso de compra como UNA unidad lógica.
--   crear pedido -> insertar detalle -> descontar inventario
--   -> registrar pago
-- Ejecutar como postgres después de 11_seed.sql.
--
-- Caso A: compra exitosa            -> COMMIT
-- Caso B: error a mitad de la compra -> ROLLBACK automático
--         (stock insuficiente viola chk_inventario_stock)
-- Caso C: pago rechazado            -> ROLLBACK manual
-- En B y C se comprueba que NO quedan datos parciales.
-- =====================================================

SET search_path TO datamarket;

-- Productos que se usarán en las pruebas
SELECT 1 AS prod_a, 2 AS prod_b \gset
SELECT producto_id AS prod_bajo, stock AS stock_bajo
FROM inventario WHERE stock BETWEEN 1 AND 4
ORDER BY producto_id LIMIT 1 \gset

\echo ''
\echo '================ ESTADO INICIAL ================'
SELECT (SELECT count(*) FROM pedidos)        AS pedidos,
       (SELECT count(*) FROM detalle_pedido) AS detalles,
       (SELECT count(*) FROM pagos)          AS pagos;
SELECT producto_id, stock FROM inventario
WHERE producto_id IN (:prod_a, :prod_b, :prod_bajo) ORDER BY producto_id;

-- Guardar los conteos para compararlos después
SELECT (SELECT count(*) FROM pedidos)        AS ini_pedidos,
       (SELECT count(*) FROM detalle_pedido) AS ini_detalles,
       (SELECT count(*) FROM pagos)          AS ini_pagos \gset


-- =====================================================
\echo ''
\echo '================ CASO A: COMPRA EXITOSA (COMMIT) ================'
\echo 'Cliente 1 compra 2 unidades del producto A y 1 del producto B'

BEGIN;

-- 1. Crear pedido
INSERT INTO pedidos (cliente_id) VALUES (1)
RETURNING id AS pedido_a \gset
\echo 'Pedido creado:' :pedido_a

-- 2. Insertar detalle (el precio se copia del producto)
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
SELECT :pedido_a, id, CASE id WHEN :prod_a THEN 2 ELSE 1 END, precio
FROM productos WHERE id IN (:prod_a, :prod_b);

-- 3. Descontar inventario
UPDATE inventario SET stock = stock - 2, ultima_actualizacion = now()
WHERE producto_id = :prod_a;
UPDATE inventario SET stock = stock - 1, ultima_actualizacion = now()
WHERE producto_id = :prod_b;

-- 4. Calcular total del pedido
UPDATE pedidos
SET total = (SELECT sum(subtotal) FROM detalle_pedido WHERE pedido_id = :pedido_a)
WHERE id = :pedido_a;

-- 5. Registrar pago y marcar el pedido como pagado
INSERT INTO pagos (pedido_id, monto, metodo, estado)
SELECT id, total, 'TARJETA', 'APROBADO' FROM pedidos WHERE id = :pedido_a;
UPDATE pedidos SET estado = 'PAGADO' WHERE id = :pedido_a;

COMMIT;

\echo '--- Resultado: el pedido quedó completo'
SELECT p.id, p.estado, p.total,
       (SELECT count(*) FROM detalle_pedido d WHERE d.pedido_id = p.id) AS lineas,
       (SELECT estado FROM pagos pa WHERE pa.pedido_id = p.id) AS pago
FROM pedidos p WHERE p.id = :pedido_a;
SELECT producto_id, stock FROM inventario
WHERE producto_id IN (:prod_a, :prod_b) ORDER BY producto_id;

-- Conteos después del caso A (base para comparar B y C)
SELECT (SELECT count(*) FROM pedidos)        AS ini_pedidos,
       (SELECT count(*) FROM detalle_pedido) AS ini_detalles,
       (SELECT count(*) FROM pagos)          AS ini_pagos \gset


-- =====================================================
\echo ''
\echo '================ CASO B: ERROR A MITAD DE LA COMPRA ================'
\echo 'Se piden 100 unidades de un producto con stock' :stock_bajo
\echo 'El paso 3 (descontar inventario) viola chk_inventario_stock'

BEGIN;

-- 1. Crear pedido  (OK)
INSERT INTO pedidos (cliente_id) VALUES (2)
RETURNING id AS pedido_b \gset

-- 2. Insertar detalle (OK)
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
SELECT :pedido_b, id, 100, precio FROM productos WHERE id = :prod_bajo;

-- 3. Descontar inventario -> ERROR: el stock quedaría negativo
UPDATE inventario SET stock = stock - 100 WHERE producto_id = :prod_bajo;

-- 4. Cualquier instrucción posterior también falla:
--    la transacción quedó abortada
INSERT INTO pagos (pedido_id, monto, metodo, estado)
VALUES (:pedido_b, 1000, 'PSE', 'APROBADO');

ROLLBACK;

\echo '--- Verificación: NO debe quedar el pedido, ni su detalle, ni el pago'
SELECT count(*) AS pedido_b_existe FROM pedidos WHERE id = :pedido_b;
SELECT count(*) AS detalle_b_existe FROM detalle_pedido WHERE pedido_id = :pedido_b;
SELECT (SELECT count(*) FROM pedidos)        - :ini_pedidos  AS dif_pedidos,
       (SELECT count(*) FROM detalle_pedido) - :ini_detalles AS dif_detalles,
       (SELECT count(*) FROM pagos)          - :ini_pagos    AS dif_pagos;
SELECT producto_id, stock AS stock_sin_cambios FROM inventario WHERE producto_id = :prod_bajo;


-- =====================================================
\echo ''
\echo '================ CASO C: PAGO RECHAZADO (ROLLBACK MANUAL) ================'
\echo 'Todo se ejecuta bien, pero la pasarela rechaza el pago:'
\echo 'la aplicación decide deshacer la compra.'

BEGIN;

INSERT INTO pedidos (cliente_id) VALUES (3)
RETURNING id AS pedido_c \gset

INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
SELECT :pedido_c, id, 1, precio FROM productos WHERE id = :prod_a;

UPDATE inventario SET stock = stock - 1 WHERE producto_id = :prod_a;

\echo '--- Dentro de la transacción el stock ya bajó:'
SELECT producto_id, stock AS stock_dentro_tx FROM inventario WHERE producto_id = :prod_a;

-- La pasarela responde "RECHAZADO" -> se deshace todo
ROLLBACK;

\echo '--- Verificación: todo vuelve al estado anterior'
SELECT count(*) AS pedido_c_existe FROM pedidos WHERE id = :pedido_c;
SELECT (SELECT count(*) FROM pedidos)        - :ini_pedidos  AS dif_pedidos,
       (SELECT count(*) FROM detalle_pedido) - :ini_detalles AS dif_detalles,
       (SELECT count(*) FROM pagos)          - :ini_pagos    AS dif_pagos;
SELECT producto_id, stock AS stock_restaurado FROM inventario WHERE producto_id = :prod_a;

\echo ''
\echo 'Nota: el ID del pedido rechazado se consumió de la secuencia aunque'
\echo 'hubo ROLLBACK. Las secuencias no son transaccionales (es normal que'
\echo 'queden "huecos" en los IDs).'
