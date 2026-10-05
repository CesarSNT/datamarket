-- =====================================================
-- 05_indexes.sql
-- Índices con justificación técnica (Paso 8).
-- Ejecutar conectado a la BD "datamarket".
--
-- Índices que PostgreSQL YA crea automáticamente (no se repiten):
--   - Cada PRIMARY KEY (id de todas las tablas)
--   - Cada UNIQUE: clientes(email), productos(sku), categorias(nombre),
--     inventario(producto_id), usuarios(username), usuarios(email)
--   - detalle_pedido(pedido_id, producto_id): por ser la primera columna,
--     también sirve para buscar por pedido_id solo. Por eso NO se crea
--     un índice aparte sobre detalle_pedido(pedido_id).
--
-- PostgreSQL NO crea índices sobre las claves foráneas.
-- =====================================================

SET search_path TO datamarket;

-- -----------------------------------------------------
-- 1. Pedidos de un cliente
--    Consulta: historial de compras del cliente (API, Paso 14)
--    Sin índice: Seq Scan sobre 100.000 pedidos.
--    Además, es la FK pedidos.cliente_id: sin índice, borrar o
--    validar un cliente obliga a recorrer toda la tabla pedidos.
-- -----------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_pedidos_cliente
    ON pedidos (cliente_id);

-- -----------------------------------------------------
-- 2. Pedidos por período
--    Consulta: reporte y vista de ventas por período (Paso 9).
--    Filtra por rango de fechas -> índice B-tree sobre fecha.
-- -----------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_pedidos_fecha
    ON pedidos (fecha);

-- -----------------------------------------------------
-- 3. Ventas de un producto
--    Consulta: cuántas unidades se vendieron de un producto.
--    Es la FK detalle_pedido.producto_id. El índice compuesto
--    (pedido_id, producto_id) NO sirve aquí porque producto_id
--    es la segunda columna.
-- -----------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_detalle_producto
    ON detalle_pedido (producto_id);

-- -----------------------------------------------------
-- 4. Pagos de un pedido
--    Consulta: estado de pago de un pedido (proceso de compra).
--    Es la FK pagos.pedido_id.
-- -----------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_pagos_pedido
    ON pagos (pedido_id);

-- -----------------------------------------------------
-- 5. Productos por categoría
--    Consulta: catálogo filtrado por categoría (API).
--    Es la FK productos.categoria_id.
-- -----------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_productos_categoria
    ON productos (categoria_id);

-- -----------------------------------------------------
-- Índices evaluados y NO creados
--   - inventario(stock): la tabla tiene 1.000 filas; un Seq Scan
--     es tan rápido como un índice y el índice se tendría que
--     actualizar en CADA compra (el stock cambia constantemente).
--   - pedidos(estado): solo 5 valores posibles (baja selectividad);
--     filtrar por estado devuelve demasiadas filas para que el
--     índice convenga.
-- -----------------------------------------------------

-- Actualizar estadísticas para que el planificador use los índices
ANALYZE pedidos;
ANALYZE detalle_pedido;
ANALYZE pagos;
ANALYZE productos;
