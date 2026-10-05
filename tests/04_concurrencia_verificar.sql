-- =====================================================
-- tests/04_concurrencia_verificar.sql
-- Paso 7: resultado de cada escenario.
-- Ejecutar DESPUÉS de que ambas sesiones terminen.
--
-- Correcto:     1 pedido  y stock 0
-- Sobreventa:   2 pedidos y stock 0  (se vendió 1 unidad dos veces)
-- =====================================================
SET search_path TO datamarket;

SELECT
  (SELECT stock FROM inventario WHERE producto_id = 3)                         AS stock_final,
  (SELECT count(*) FROM pedidos WHERE cliente_id IN (101, 102) AND total = 0)  AS pedidos_creados,
  CASE WHEN (SELECT count(*) FROM pedidos
             WHERE cliente_id IN (101, 102) AND total = 0) > 1
       THEN 'SOBREVENTA: inconsistencia'
       ELSE 'OK: consistente'
  END AS resultado;
