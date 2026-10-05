-- =====================================================
-- 04_constraints.sql
-- Agrega las reglas de integridad: FOREIGN KEY, UNIQUE y CHECK.
-- Cada restricción tiene nombre para que el error sea
-- fácil de identificar (y para poder eliminarla si hace falta).
-- Convención: fk_<tabla>_<columna>, uq_<tabla>_<columna>,
--             chk_<tabla>_<columna>
-- Ejecutar conectado a la BD "datamarket".
-- =====================================================

SET search_path TO datamarket;

-- -----------------------------------------------------
-- categorias
-- -----------------------------------------------------
ALTER TABLE categorias
    ADD CONSTRAINT uq_categorias_nombre UNIQUE (nombre);

-- -----------------------------------------------------
-- productos
-- -----------------------------------------------------
ALTER TABLE productos
    ADD CONSTRAINT fk_productos_categoria
        FOREIGN KEY (categoria_id) REFERENCES categorias (id)
        ON DELETE RESTRICT,
    ADD CONSTRAINT uq_productos_sku    UNIQUE (sku),
    ADD CONSTRAINT chk_productos_precio CHECK (precio > 0);          -- RN-01

-- -----------------------------------------------------
-- inventario
-- -----------------------------------------------------
ALTER TABLE inventario
    ADD CONSTRAINT fk_inventario_producto
        FOREIGN KEY (producto_id) REFERENCES productos (id)
        ON DELETE RESTRICT,
    ADD CONSTRAINT uq_inventario_producto   UNIQUE (producto_id),   -- RN-07 (1:1)
    ADD CONSTRAINT chk_inventario_stock     CHECK (stock >= 0),     -- RN-02
    ADD CONSTRAINT chk_inventario_stock_min CHECK (stock_minimo >= 0);

-- -----------------------------------------------------
-- clientes
-- -----------------------------------------------------
ALTER TABLE clientes
    ADD CONSTRAINT uq_clientes_email UNIQUE (email);                 -- RN-04

-- -----------------------------------------------------
-- pedidos
-- -----------------------------------------------------
ALTER TABLE pedidos
    ADD CONSTRAINT fk_pedidos_cliente
        FOREIGN KEY (cliente_id) REFERENCES clientes (id)
        ON DELETE RESTRICT,                                          -- RN-06, RN-12
    ADD CONSTRAINT chk_pedidos_estado
        CHECK (estado IN ('PENDIENTE','PAGADO','ENVIADO','ENTREGADO','CANCELADO')),  -- RN-11
    ADD CONSTRAINT chk_pedidos_total CHECK (total >= 0);

-- -----------------------------------------------------
-- detalle_pedido
-- -----------------------------------------------------
ALTER TABLE detalle_pedido
    ADD CONSTRAINT fk_detalle_pedido
        FOREIGN KEY (pedido_id) REFERENCES pedidos (id)
        ON DELETE CASCADE,                                           -- RN-13
    ADD CONSTRAINT fk_detalle_producto
        FOREIGN KEY (producto_id) REFERENCES productos (id)
        ON DELETE RESTRICT,                                          -- RN-12
    ADD CONSTRAINT uq_detalle_pedido_producto UNIQUE (pedido_id, producto_id),  -- RN-08
    ADD CONSTRAINT chk_detalle_cantidad CHECK (cantidad > 0),        -- RN-03
    ADD CONSTRAINT chk_detalle_precio   CHECK (precio_unitario > 0);

-- -----------------------------------------------------
-- pagos
-- -----------------------------------------------------
ALTER TABLE pagos
    ADD CONSTRAINT fk_pagos_pedido
        FOREIGN KEY (pedido_id) REFERENCES pedidos (id)
        ON DELETE RESTRICT,
    ADD CONSTRAINT chk_pagos_monto  CHECK (monto > 0),
    ADD CONSTRAINT chk_pagos_metodo
        CHECK (metodo IN ('TARJETA','PSE','EFECTIVO','TRANSFERENCIA')),
    ADD CONSTRAINT chk_pagos_estado
        CHECK (estado IN ('PENDIENTE','APROBADO','RECHAZADO'));      -- RN-11

-- -----------------------------------------------------
-- usuarios
-- -----------------------------------------------------
ALTER TABLE usuarios
    ADD CONSTRAINT uq_usuarios_username UNIQUE (username),
    ADD CONSTRAINT uq_usuarios_email    UNIQUE (email),
    ADD CONSTRAINT chk_usuarios_rol
        CHECK (rol IN ('ADMIN','DEVELOPER','ANALYST','OPERATOR','AUDITOR'));

-- -----------------------------------------------------
-- auditoria (sin FK: registra cambios de cualquier tabla)
-- -----------------------------------------------------
ALTER TABLE auditoria
    ADD CONSTRAINT chk_auditoria_operacion
        CHECK (operacion IN ('INSERT','UPDATE','DELETE'));
