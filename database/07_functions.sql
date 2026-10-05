-- =====================================================
-- 07_functions.sql
-- Funciones de negocio (Paso 10).
-- Ejecutar conectado a la BD "datamarket".
--
-- FUNCIÓN = devuelve un valor o una tabla y se usa dentro
-- de consultas (SELECT fn(...)). No debe modificar datos.
-- Los procesos que modifican datos están en 08_procedures.sql.
-- =====================================================

SET search_path TO datamarket;

-- -----------------------------------------------------
-- 1. fn_stock_disponible
--    Devuelve el stock actual de un producto.
--    Error si el producto no existe.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION fn_stock_disponible(p_producto_id BIGINT)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_stock INTEGER;
BEGIN
    SELECT stock INTO v_stock
    FROM inventario
    WHERE producto_id = p_producto_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El producto % no existe o no tiene inventario', p_producto_id
              USING ERRCODE = 'no_data_found';
    END IF;

    RETURN v_stock;
END;
$$;

COMMENT ON FUNCTION fn_stock_disponible(BIGINT) IS
  'Stock actual de un producto. Error si no existe.';

-- -----------------------------------------------------
-- 2. fn_calcular_total_pedido
--    Suma los subtotales del detalle de un pedido.
--    Sirve para validar que pedidos.total sea correcto.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION fn_calcular_total_pedido(p_pedido_id BIGINT)
RETURNS NUMERIC(12,2)
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce(sum(subtotal), 0)::NUMERIC(12,2)
    FROM detalle_pedido
    WHERE pedido_id = p_pedido_id;
$$;

COMMENT ON FUNCTION fn_calcular_total_pedido(BIGINT) IS
  'Total de un pedido calculado desde su detalle';

-- -----------------------------------------------------
-- 3. fn_ventas_por_categoria
--    Reporte de ventas por categoría en un rango de fechas.
--    Devuelve una TABLA. Valida que el rango sea coherente.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION fn_ventas_por_categoria(
    p_desde DATE,
    p_hasta DATE
)
RETURNS TABLE (
    categoria       VARCHAR,
    pedidos         BIGINT,
    unidades        BIGINT,
    ventas          NUMERIC
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF p_desde IS NULL OR p_hasta IS NULL THEN
        RAISE EXCEPTION 'Las fechas desde y hasta son obligatorias'
              USING ERRCODE = 'invalid_parameter_value';
    END IF;

    IF p_desde > p_hasta THEN
        RAISE EXCEPTION 'Rango inválido: % es posterior a %', p_desde, p_hasta
              USING ERRCODE = 'invalid_parameter_value';
    END IF;

    RETURN QUERY
    SELECT c.nombre,
           count(DISTINCT pe.id),
           sum(d.cantidad)::BIGINT,
           sum(d.subtotal)
    FROM pedidos pe
    JOIN detalle_pedido d ON d.pedido_id = pe.id
    JOIN productos pr     ON pr.id = d.producto_id
    JOIN categorias c     ON c.id = pr.categoria_id
    WHERE pe.estado <> 'CANCELADO'
      AND pe.fecha >= p_desde
      AND pe.fecha <  p_hasta + 1          -- incluye todo el día "hasta"
    GROUP BY c.nombre
    ORDER BY sum(d.subtotal) DESC;
END;
$$;

COMMENT ON FUNCTION fn_ventas_por_categoria(DATE, DATE) IS
  'Pedidos, unidades y ventas por categoría entre dos fechas (sin cancelados)';
