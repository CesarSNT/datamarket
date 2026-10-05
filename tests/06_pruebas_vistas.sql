-- =====================================================
-- tests/06_pruebas_vistas.sql
-- Paso 9: comprobar que las vistas devuelven datos y que
-- solo los roles adecuados pueden consultarlas.
-- Ejecutar como postgres después de 06_views.sql y 10_roles.sql.
-- =====================================================

SET search_path TO datamarket;

-- =====================================================
\echo ''
\echo '################ ANALISTA: las tres vistas ################'
SET ROLE usr_analista;

\echo '--- [PERMITIDO] Ventas de los últimos 6 meses'
SELECT * FROM ventas_por_periodo
ORDER BY periodo DESC LIMIT 6;

\echo '--- [PERMITIDO] Inventario bajo (primeros 10)'
SELECT producto_id, sku, producto, categoria, stock, stock_minimo, unidades_faltantes
FROM inventario_bajo LIMIT 10;

\echo '--- [PERMITIDO] Top 5 clientes por total comprado'
SELECT * FROM resumen_compras_cliente
ORDER BY total_comprado DESC LIMIT 5;

\echo '--- La vista NO expone datos de contacto: esta columna no existe'
SELECT email FROM resumen_compras_cliente LIMIT 1;

\echo '--- [DENEGADO] Las vistas son de solo lectura para el analista'
DELETE FROM inventario_bajo;

RESET ROLE;

-- =====================================================
\echo ''
\echo '################ OPERADOR: solo inventario_bajo ################'
SET ROLE usr_operador;

\echo '--- [PERMITIDO] Inventario bajo'
SELECT count(*) AS productos_por_reponer FROM inventario_bajo;

\echo '--- [DENEGADO] Ventas por período (información gerencial)'
SELECT * FROM ventas_por_periodo LIMIT 1;

RESET ROLE;

-- =====================================================
\echo ''
\echo '################ AUDITOR: ninguna vista de negocio ################'
SET ROLE usr_auditor;

\echo '--- [DENEGADO] Resumen de compras por cliente'
SELECT * FROM resumen_compras_cliente LIMIT 1;

RESET ROLE;

-- =====================================================
\echo ''
\echo '################ Coherencia de la vista vs. la consulta directa ################'
\echo '--- Ambos valores deben ser iguales'
SELECT
  (SELECT sum(ventas_totales) FROM ventas_por_periodo)                  AS total_vista,
  (SELECT sum(total) FROM pedidos WHERE estado <> 'CANCELADO')          AS total_tablas;
