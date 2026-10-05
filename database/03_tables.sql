-- =====================================================
-- 03_tables.sql
-- Crea las tablas con: clave primaria, tipos de datos,
-- NOT NULL y DEFAULT.
-- Las FK, UNIQUE y CHECK se agregan en 04_constraints.sql.
-- Ejecutar conectado a la BD "datamarket".
-- =====================================================

SET search_path TO datamarket;

-- -----------------------------------------------------
-- Catálogo
-- -----------------------------------------------------
CREATE TABLE categorias (
    id           BIGSERIAL     PRIMARY KEY,
    nombre       VARCHAR(100)  NOT NULL,
    descripcion  TEXT
);

CREATE TABLE productos (
    id              BIGSERIAL      PRIMARY KEY,
    categoria_id    BIGINT         NOT NULL,
    sku             VARCHAR(50)    NOT NULL,
    nombre          VARCHAR(150)   NOT NULL,
    descripcion     TEXT,
    precio          NUMERIC(12,2)  NOT NULL,
    activo          BOOLEAN        NOT NULL DEFAULT true,
    fecha_creacion  TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE TABLE inventario (
    id                    BIGSERIAL    PRIMARY KEY,
    producto_id           BIGINT       NOT NULL,
    stock                 INTEGER      NOT NULL DEFAULT 0,
    stock_minimo          INTEGER      NOT NULL DEFAULT 5,
    ultima_actualizacion  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- -----------------------------------------------------
-- Clientes y pedidos
-- -----------------------------------------------------
CREATE TABLE clientes (
    id              BIGSERIAL     PRIMARY KEY,
    nombre          VARCHAR(150)  NOT NULL,
    email           VARCHAR(150)  NOT NULL,
    telefono        VARCHAR(20),
    direccion       VARCHAR(255),
    fecha_registro  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    activo          BOOLEAN       NOT NULL DEFAULT true
);

CREATE TABLE pedidos (
    id          BIGSERIAL      PRIMARY KEY,
    cliente_id  BIGINT         NOT NULL,
    fecha       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    estado      VARCHAR(20)    NOT NULL DEFAULT 'PENDIENTE',
    total       NUMERIC(12,2)  NOT NULL DEFAULT 0
);

CREATE TABLE detalle_pedido (
    id               BIGSERIAL      PRIMARY KEY,
    pedido_id        BIGINT         NOT NULL,
    producto_id      BIGINT         NOT NULL,
    cantidad         INTEGER        NOT NULL,
    precio_unitario  NUMERIC(12,2)  NOT NULL,
    -- Columna calculada: siempre cantidad * precio_unitario
    subtotal         NUMERIC(12,2)  GENERATED ALWAYS AS (cantidad * precio_unitario) STORED
);

CREATE TABLE pagos (
    id         BIGSERIAL      PRIMARY KEY,
    pedido_id  BIGINT         NOT NULL,
    monto      NUMERIC(12,2)  NOT NULL,
    metodo     VARCHAR(20)    NOT NULL,
    estado     VARCHAR(20)    NOT NULL DEFAULT 'PENDIENTE',
    fecha      TIMESTAMPTZ    NOT NULL DEFAULT now()
);

-- -----------------------------------------------------
-- Usuarios internos y auditoría
-- -----------------------------------------------------
CREATE TABLE usuarios (
    id              BIGSERIAL     PRIMARY KEY,
    username        VARCHAR(50)   NOT NULL,
    email           VARCHAR(150)  NOT NULL,
    password_hash   VARCHAR(255)  NOT NULL,
    rol             VARCHAR(20)   NOT NULL,
    activo          BOOLEAN       NOT NULL DEFAULT true,
    fecha_creacion  TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- Estructura definida en el taller (Paso 11)
CREATE TABLE auditoria (
    id                BIGSERIAL  PRIMARY KEY,
    usuario           TEXT       DEFAULT current_user,
    fecha             TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    operacion         TEXT       NOT NULL,
    tabla_afectada    TEXT       NOT NULL,
    registro_id       BIGINT,
    datos_anteriores  JSONB,
    datos_nuevos      JSONB
);

-- -----------------------------------------------------
-- Comentarios (documentación dentro de la base)
-- -----------------------------------------------------
COMMENT ON TABLE categorias     IS 'Clasificación de los productos';
COMMENT ON TABLE productos      IS 'Catálogo de productos a la venta';
COMMENT ON TABLE inventario     IS 'Existencias por producto (1:1 con productos)';
COMMENT ON TABLE clientes       IS 'Personas que compran en la plataforma';
COMMENT ON TABLE pedidos        IS 'Compras realizadas por los clientes';
COMMENT ON TABLE detalle_pedido IS 'Productos de cada pedido (resuelve N:M pedidos-productos)';
COMMENT ON TABLE pagos          IS 'Pagos asociados a un pedido';
COMMENT ON TABLE usuarios       IS 'Usuarios internos del sistema';
COMMENT ON TABLE auditoria      IS 'Registro de cambios sobre datos críticos';

COMMENT ON COLUMN detalle_pedido.precio_unitario IS 'Precio copiado del producto al momento de la compra';
COMMENT ON COLUMN usuarios.password_hash         IS 'Contraseña cifrada, nunca en texto plano';
