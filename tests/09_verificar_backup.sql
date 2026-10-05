-- =====================================================
-- tests/09_verificar_backup.sql
-- Pasos 12 y 13: "huella" de la base para comparar el
-- original con la restaurada.
--
-- Ejecutar en AMBAS bases y comparar los resultados:
--   -d datamarket             (original)
--   -d datamarket_restaurada  (restaurada)
-- Si la restauración es correcta, todo debe coincidir.
-- =====================================================

SET search_path TO datamarket;

\echo ''
\echo '================ Base de datos ================'
SELECT current_database() AS base,
       pg_size_pretty(pg_database_size(current_database())) AS tamano,
       to_char(now(), 'YYYY-MM-DD HH24:MI:SS') AS fecha_verificacion;

\echo ''
\echo '================ 1. Registros por tabla ================'
SELECT 'categorias'     AS tabla, count(*) AS registros FROM categorias
UNION ALL SELECT 'productos',      count(*) FROM productos
UNION ALL SELECT 'inventario',     count(*) FROM inventario
UNION ALL SELECT 'clientes',       count(*) FROM clientes
UNION ALL SELECT 'pedidos',        count(*) FROM pedidos
UNION ALL SELECT 'detalle_pedido', count(*) FROM detalle_pedido
UNION ALL SELECT 'pagos',          count(*) FROM pagos
UNION ALL SELECT 'usuarios',       count(*) FROM usuarios
UNION ALL SELECT 'auditoria',      count(*) FROM auditoria
ORDER BY 1;

\echo ''
\echo '================ 2. Totales de control (dinero y stock) ================'
SELECT (SELECT sum(total)    FROM pedidos)        AS suma_pedidos,
       (SELECT sum(subtotal) FROM detalle_pedido) AS suma_detalle,
       (SELECT sum(monto)    FROM pagos)          AS suma_pagos,
       (SELECT sum(stock)    FROM inventario)     AS stock_total;

\echo ''
\echo '================ 3. Objetos de la base ================'
SELECT
  (SELECT count(*) FROM pg_tables   WHERE schemaname = 'datamarket')          AS tablas,
  (SELECT count(*) FROM pg_views    WHERE schemaname = 'datamarket')          AS vistas,
  (SELECT count(*) FROM pg_indexes  WHERE schemaname = 'datamarket')          AS indices,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'datamarket')                                           AS funciones_y_procedimientos,
  (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'datamarket' AND NOT t.tgisinternal)                    AS triggers,
  (SELECT count(*) FROM pg_constraint co JOIN pg_namespace n ON n.oid = co.connamespace
    WHERE n.nspname = 'datamarket' AND co.contype IN ('f','c','u'))           AS restricciones;

\echo ''
\echo '================ 4. Integridad después de restaurar ================'
\echo '(todos deben ser 0)'
SELECT
  (SELECT count(*) FROM pedidos p
    WHERE p.total <> (SELECT coalesce(sum(subtotal), 0)
                      FROM detalle_pedido d WHERE d.pedido_id = p.id))        AS totales_descuadrados,
  (SELECT count(*) FROM productos pr
    WHERE NOT EXISTS (SELECT 1 FROM inventario i WHERE i.producto_id = pr.id)) AS productos_sin_inventario,
  (SELECT count(*) FROM inventario WHERE stock < 0)                           AS stock_negativo;

\echo ''
\echo '================ 5. Funciona: consulta de negocio ================'
SELECT * FROM ventas_por_periodo ORDER BY periodo DESC LIMIT 3;
