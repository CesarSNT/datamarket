-- =====================================================
-- tests/04_concurrencia_preparar.sql
-- Paso 7: deja el producto 3 con stock = 1 y borra los
-- pedidos de pruebas anteriores.
-- Ejecutar ANTES de cada escenario de 04_concurrencia_guia.md
-- =====================================================
SET search_path TO datamarket;

-- Pedidos de prueba: clientes 101 y 102 con total = 0
-- (los pedidos del seed siempre tienen total > 0)
DELETE FROM pedidos WHERE cliente_id IN (101, 102) AND total = 0;

UPDATE inventario SET stock = 1 WHERE producto_id = 3;

SELECT producto_id, stock AS stock_inicial FROM inventario WHERE producto_id = 3;
