-- =====================================================
-- 08_procedures.sql
-- Procedimientos de negocio (Paso 10).
-- Ejecutar conectado a la BD "datamarket".
--
-- PROCEDIMIENTO = ejecuta un proceso que MODIFICA datos.
-- Se invoca con CALL.
--
-- Atomicidad: un CALL es una sola transacción. Si cualquier
-- validación falla, RAISE EXCEPTION aborta TODO y no queda
-- ningún dato parcial (lo mismo que se probó en el Paso 6).
-- Los procedimientos no hacen COMMIT internamente, para que
-- quien los llama (por ejemplo la API) pueda incluirlos en
-- una transacción mayor si lo necesita.
-- =====================================================

SET search_path TO datamarket;

-- -----------------------------------------------------
-- 1. sp_registrar_compra
--    Proceso de compra completo:
--      validar -> bloquear stock -> crear pedido -> detalle
--      -> descontar inventario -> total -> pago -> PAGADO
--
--    Parámetros:
--      p_cliente_id  cliente que compra
--      p_items       JSON con los productos, por ejemplo:
--                    '[{"producto_id": 1, "cantidad": 2},
--                      {"producto_id": 7, "cantidad": 1}]'
--      p_metodo      TARJETA | PSE | EFECTIVO | TRANSFERENCIA
--      p_pedido_id   (salida) id del pedido creado
--
--    Concurrencia (Paso 7): las filas de inventario se bloquean
--    con SELECT ... FOR UPDATE antes de validar el stock, en
--    orden de producto_id para evitar interbloqueos (deadlocks)
--    cuando dos compras piden los mismos productos.
-- -----------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_compra(
    IN  p_cliente_id BIGINT,
    IN  p_items      JSONB,
    IN  p_metodo     VARCHAR,
    OUT p_pedido_id  BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_items      JSONB;              -- ítems normalizados
    v_item       RECORD;
    v_total      NUMERIC(12,2);
BEGIN
    -- ---------- Validaciones de parámetros ----------
    IF p_items IS NULL
       OR jsonb_typeof(p_items) <> 'array'
       OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'La compra debe incluir al menos un producto'
              USING ERRCODE = 'invalid_parameter_value',
                    HINT = 'Formato: [{"producto_id": 1, "cantidad": 2}]';
    END IF;

    IF p_metodo IS NULL
       OR p_metodo NOT IN ('TARJETA','PSE','EFECTIVO','TRANSFERENCIA') THEN
        RAISE EXCEPTION 'Método de pago inválido: %', p_metodo
              USING ERRCODE = 'invalid_parameter_value',
                    HINT = 'Use TARJETA, PSE, EFECTIVO o TRANSFERENCIA';
    END IF;

    -- ---------- Validar cliente ----------
    PERFORM 1 FROM clientes WHERE id = p_cliente_id AND activo;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El cliente % no existe o está inactivo', p_cliente_id
              USING ERRCODE = 'foreign_key_violation';
    END IF;

    -- ---------- Normalizar los ítems ----------
    -- Si el mismo producto viene dos veces, se suman las cantidades
    -- (detalle_pedido tiene UNIQUE (pedido_id, producto_id)).
    -- El resultado se guarda en v_items y se lee con
    -- jsonb_to_recordset(v_items) en los pasos siguientes.
    SELECT jsonb_agg(jsonb_build_object('producto_id', producto_id,
                                        'cantidad',    cantidad))
    INTO v_items
    FROM (
        SELECT (e->>'producto_id')::BIGINT       AS producto_id,
               sum((e->>'cantidad')::INTEGER)    AS cantidad
        FROM jsonb_array_elements(p_items) AS e
        GROUP BY (e->>'producto_id')::BIGINT
    ) AS x;

    IF EXISTS (SELECT 1
               FROM jsonb_to_recordset(v_items) AS t(producto_id BIGINT, cantidad INTEGER)
               WHERE t.producto_id IS NULL OR t.cantidad IS NULL OR t.cantidad <= 0) THEN
        RAISE EXCEPTION 'Cada producto debe tener producto_id y una cantidad mayor que 0'
              USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- ---------- Bloquear filas de inventario ----------
    -- Bloqueo de fila (anti-sobreventa), en orden de producto_id.
    -- Si otra compra tiene bloqueado alguno de estos productos,
    -- esta espera hasta que la otra termine.
    PERFORM 1
    FROM inventario
    WHERE producto_id IN (SELECT t.producto_id
                          FROM jsonb_to_recordset(v_items) AS t(producto_id BIGINT, cantidad INTEGER))
    ORDER BY producto_id
    FOR UPDATE;

    -- ---------- Validar productos y stock (ya bloqueado) ----------
    FOR v_item IN
        SELECT t.producto_id, t.cantidad, pr.activo, i.stock
        FROM jsonb_to_recordset(v_items) AS t(producto_id BIGINT, cantidad INTEGER)
        LEFT JOIN productos  pr ON pr.id = t.producto_id
        LEFT JOIN inventario i  ON i.producto_id = t.producto_id
        ORDER BY t.producto_id
    LOOP
        IF v_item.activo IS NULL THEN
            RAISE EXCEPTION 'El producto % no existe', v_item.producto_id
                  USING ERRCODE = 'foreign_key_violation';
        END IF;

        IF NOT v_item.activo THEN
            RAISE EXCEPTION 'El producto % está inactivo y no se puede vender', v_item.producto_id
                  USING ERRCODE = 'check_violation';
        END IF;

        IF v_item.stock < v_item.cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente para el producto %: disponible %, solicitado %',
                  v_item.producto_id, v_item.stock, v_item.cantidad
                  USING ERRCODE = 'check_violation';
        END IF;
    END LOOP;

    -- ---------- Crear pedido ----------
    INSERT INTO pedidos (cliente_id)
    VALUES (p_cliente_id)
    RETURNING id INTO p_pedido_id;

    -- ---------- Detalle (precio copiado del producto) ----------
    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
    SELECT p_pedido_id, t.producto_id, t.cantidad, pr.precio
    FROM jsonb_to_recordset(v_items) AS t(producto_id BIGINT, cantidad INTEGER)
    JOIN productos pr ON pr.id = t.producto_id;

    -- ---------- Descontar inventario ----------
    UPDATE inventario i
    SET stock = i.stock - t.cantidad,
        ultima_actualizacion = now()
    FROM jsonb_to_recordset(v_items) AS t(producto_id BIGINT, cantidad INTEGER)
    WHERE i.producto_id = t.producto_id;

    -- ---------- Total ----------
    v_total := fn_calcular_total_pedido(p_pedido_id);

    UPDATE pedidos
    SET total  = v_total,
        estado = 'PAGADO'
    WHERE id = p_pedido_id;

    -- ---------- Pago ----------
    INSERT INTO pagos (pedido_id, monto, metodo, estado)
    VALUES (p_pedido_id, v_total, p_metodo, 'APROBADO');

    RAISE NOTICE 'Compra registrada: pedido %, total %', p_pedido_id, v_total;
END;
$$;

COMMENT ON PROCEDURE sp_registrar_compra(BIGINT, JSONB, VARCHAR, BIGINT) IS
  'Compra completa y atómica: valida, bloquea stock, crea pedido, detalle y pago';

-- -----------------------------------------------------
-- 2. sp_cancelar_pedido
--    Cancela un pedido y DEVUELVE las unidades al inventario.
--    Solo se pueden cancelar pedidos PENDIENTE o PAGADO
--    (un pedido ENVIADO o ENTREGADO ya salió de bodega).
-- -----------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cancelar_pedido(
    IN p_pedido_id BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado VARCHAR(20);
BEGIN
    -- Bloquear el pedido para que nadie lo modifique a la vez
    SELECT estado INTO v_estado
    FROM pedidos
    WHERE id = p_pedido_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El pedido % no existe', p_pedido_id
              USING ERRCODE = 'no_data_found';
    END IF;

    IF v_estado NOT IN ('PENDIENTE', 'PAGADO') THEN
        RAISE EXCEPTION 'No se puede cancelar el pedido %: está en estado %',
              p_pedido_id, v_estado
              USING ERRCODE = 'check_violation',
                    HINT = 'Solo se cancelan pedidos PENDIENTE o PAGADO';
    END IF;

    -- Devolver unidades al inventario
    UPDATE inventario i
    SET stock = i.stock + d.cantidad,
        ultima_actualizacion = now()
    FROM detalle_pedido d
    WHERE d.pedido_id = p_pedido_id
      AND i.producto_id = d.producto_id;

    UPDATE pedidos SET estado = 'CANCELADO' WHERE id = p_pedido_id;

    RAISE NOTICE 'Pedido % cancelado; inventario restituido', p_pedido_id;
END;
$$;

COMMENT ON PROCEDURE sp_cancelar_pedido(BIGINT) IS
  'Cancela un pedido PENDIENTE o PAGADO y devuelve el stock';
