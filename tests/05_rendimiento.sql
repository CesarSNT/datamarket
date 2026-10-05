-- =====================================================
-- tests/05_rendimiento.sql
-- Paso 8: medición con EXPLAIN ANALYZE.
-- Se ejecuta DOS veces:
--   1. ANTES:   después de tests/05_quitar_indices.sql
--   2. DESPUÉS: después de database/05_indexes.sql
--
-- Qué mirar en cada plan:
--   - Tipo de recorrido: "Seq Scan" (lee toda la tabla)
--     vs "Index Scan" / "Bitmap Index Scan" (usa índice)
--   - cost=inicio..total  -> estimación del planificador
--   - rows=               -> filas estimadas / reales
--   - Execution Time      -> tiempo real en milisegundos
--
-- Cada consulta se ejecuta una vez sin medir para "calentar"
-- la caché, así la comparación es justa.
-- =====================================================

SET search_path TO datamarket;

\echo ''
\echo 'Índices actuales sobre las tablas medidas:'
SELECT tablename AS tabla, indexname AS indice
FROM pg_indexes
WHERE schemaname = 'datamarket'
  AND tablename IN ('pedidos','detalle_pedido','pagos','productos')
ORDER BY tablename, indexname;

-- -----------------------------------------------------
\echo ''
\echo '================ Q1. Pedidos de un cliente ================'
SELECT count(*) FROM pedidos WHERE cliente_id = 1000;
EXPLAIN ANALYZE
SELECT *
FROM pedidos
WHERE cliente_id = 1000;

-- -----------------------------------------------------
\echo ''
\echo '================ Q2. Ventas de la última semana ================'
SELECT count(*) FROM pedidos WHERE fecha >= now() - interval '7 days';
EXPLAIN ANALYZE
SELECT date_trunc('day', fecha) AS dia, count(*) AS pedidos, sum(total) AS ventas
FROM pedidos
WHERE fecha >= now() - interval '7 days'
  AND estado <> 'CANCELADO'
GROUP BY 1
ORDER BY 1;

-- -----------------------------------------------------
\echo ''
\echo '================ Q3. Unidades vendidas de un producto ================'
SELECT count(*) FROM detalle_pedido WHERE producto_id = 500;
EXPLAIN ANALYZE
SELECT producto_id, sum(cantidad) AS unidades, sum(subtotal) AS ingresos
FROM detalle_pedido
WHERE producto_id = 500
GROUP BY producto_id;

-- -----------------------------------------------------
\echo ''
\echo '================ Q4. Detalle completo de un pedido (JOIN) ================'
SELECT count(*) FROM pagos WHERE pedido_id = 50000;
EXPLAIN ANALYZE
SELECT pe.id, pe.fecha, pe.estado, c.nombre AS cliente,
       pr.nombre AS producto, d.cantidad, d.subtotal,
       pa.estado AS estado_pago, pa.metodo
FROM pedidos pe
JOIN clientes c        ON c.id = pe.cliente_id
JOIN detalle_pedido d  ON d.pedido_id = pe.id
JOIN productos pr      ON pr.id = d.producto_id
LEFT JOIN pagos pa     ON pa.pedido_id = pe.id
WHERE pe.id = 50000;
