-- =====================================================
-- tests/05_quitar_indices.sql
-- Paso 8: elimina los índices de 05_indexes.sql para medir
-- las consultas SIN índices ("antes").
-- =====================================================
SET search_path TO datamarket;

DROP INDEX IF EXISTS idx_pedidos_cliente;
DROP INDEX IF EXISTS idx_pedidos_fecha;
DROP INDEX IF EXISTS idx_detalle_producto;
DROP INDEX IF EXISTS idx_pagos_pedido;
DROP INDEX IF EXISTS idx_productos_categoria;

ANALYZE;

\echo 'Índices eliminados. Ahora ejecuta tests/05_rendimiento.sql (ANTES).'
