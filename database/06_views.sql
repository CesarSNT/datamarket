-- =====================================================
-- 06_views.sql
-- Vistas de negocio (Paso 9).
-- Ejecutar conectado a la BD "datamarket".
--
-- Objetivo:
--   1. Simplificar consultas frecuentes (JOINs y agregaciones
--      quedan escritos una sola vez).
--   2. Limitar la exposición de las tablas: un rol puede
--      consultar la vista sin tener permiso sobre las tablas
--      base, y la vista solo muestra las columnas necesarias.
--
-- Los permisos sobre las vistas se otorgan en 10_roles.sql
-- (los roles se crean después de este script).
-- =====================================================

SET search_path TO datamarket;

-- -----------------------------------------------------
-- 1. Resumen de ventas por período (mes)
--    Excluye pedidos CANCELADOS.
--    Uso: reportes gerenciales, tendencia de ventas.
-- -----------------------------------------------------
CREATE OR REPLACE VIEW ventas_por_periodo AS
SELECT
    date_trunc('month', p.fecha)::date        AS periodo,
    count(*)                                   AS pedidos,
    count(DISTINCT p.cliente_id)               AS clientes_distintos,
    sum(p.total)                               AS ventas_totales,
    round(avg(p.total), 2)                     AS ticket_promedio
FROM pedidos p
WHERE p.estado <> 'CANCELADO'
GROUP BY date_trunc('month', p.fecha)
ORDER BY periodo;

COMMENT ON VIEW ventas_por_periodo IS
  'Ventas mensuales: pedidos, clientes, total y ticket promedio (sin cancelados)';

-- -----------------------------------------------------
-- 2. Inventario bajo
--    Productos ACTIVOS cuyo stock está por debajo del mínimo.
--    Uso: reposición de inventario (operador).
-- -----------------------------------------------------
CREATE OR REPLACE VIEW inventario_bajo AS
SELECT
    pr.id                         AS producto_id,
    pr.sku,
    pr.nombre                     AS producto,
    c.nombre                      AS categoria,
    i.stock,
    i.stock_minimo,
    i.stock_minimo - i.stock      AS unidades_faltantes,
    i.ultima_actualizacion
FROM inventario i
JOIN productos  pr ON pr.id = i.producto_id
JOIN categorias c  ON c.id  = pr.categoria_id
WHERE i.stock < i.stock_minimo
  AND pr.activo
ORDER BY i.stock, pr.id;

COMMENT ON VIEW inventario_bajo IS
  'Productos activos con stock menor al stock mínimo';

-- -----------------------------------------------------
-- 3. Resumen de compras por cliente
--    No expone email, teléfono ni dirección (datos personales):
--    solo lo necesario para análisis.
--    Excluye pedidos CANCELADOS.
-- -----------------------------------------------------
CREATE OR REPLACE VIEW resumen_compras_cliente AS
SELECT
    c.id                              AS cliente_id,
    c.nombre                          AS cliente,
    count(p.id)                       AS pedidos,
    coalesce(sum(p.total), 0)         AS total_comprado,
    round(avg(p.total), 2)            AS ticket_promedio,
    max(p.fecha)                      AS ultima_compra
FROM clientes c
LEFT JOIN pedidos p
       ON p.cliente_id = c.id
      AND p.estado <> 'CANCELADO'
GROUP BY c.id, c.nombre;

COMMENT ON VIEW resumen_compras_cliente IS
  'Pedidos, total comprado y última compra por cliente (sin datos de contacto)';
