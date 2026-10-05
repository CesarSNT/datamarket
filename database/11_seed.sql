-- =====================================================
-- 11_seed.sql
-- Datos de prueba para DataMarket.
-- Ejecutar conectado a la BD "datamarket", después de
-- 03_tables.sql y 04_constraints.sql.
--
-- Contiene dos partes:
--   PARTE 1. Datos base "realistas" (categorías, productos
--            con nombre, usuarios internos y algunos clientes).
--   PARTE 2. Volumen masivo generado con generate_series()
--            para las pruebas de rendimiento (Paso 8).
--
-- Volumen aproximado resultante:
--   categorías ........      8
--   productos .........  1.000
--   clientes .......... 10.000
--   pedidos ........... 100.000
--   detalle_pedido .... ~250.000
--   pagos ............. ~105.000
--
-- Es re-ejecutable: vacía las tablas y reinicia los IDs.
-- setseed() hace que los datos aleatorios salgan iguales
-- en cada ejecución (resultados reproducibles).
-- =====================================================

SET search_path TO datamarket;

BEGIN;

-- Vaciar tablas de negocio y reiniciar las secuencias (IDs desde 1)
TRUNCATE pagos, detalle_pedido, pedidos, inventario, productos,
         categorias, clientes, usuarios
RESTART IDENTITY CASCADE;

-- La carga de datos de prueba NO se audita: generaría cientos de
-- miles de eventos que no corresponden a operaciones reales.
-- DISABLE TRIGGER USER desactiva solo los triggers creados por
-- nosotros (09_triggers.sql); las FK y CHECK siguen validándose.
-- Se reactivan antes del COMMIT.
ALTER TABLE productos  DISABLE TRIGGER USER;
ALTER TABLE inventario DISABLE TRIGGER USER;
ALTER TABLE pedidos    DISABLE TRIGGER USER;
ALTER TABLE pagos      DISABLE TRIGGER USER;
ALTER TABLE clientes   DISABLE TRIGGER USER;
ALTER TABLE usuarios   DISABLE TRIGGER USER;

-- Semilla para que random() genere siempre la misma secuencia
SELECT setseed(0.42);

-- =====================================================
-- PARTE 1. Datos base
-- =====================================================

-- Categorías
INSERT INTO categorias (nombre, descripcion) VALUES
  ('Tecnología',     'Computadores, celulares y accesorios'),
  ('Hogar',          'Artículos para el hogar y la cocina'),
  ('Deportes',       'Ropa y equipos deportivos'),
  ('Moda',           'Ropa, calzado y accesorios'),
  ('Libros',         'Libros físicos y digitales'),
  ('Juguetes',       'Juguetes y juegos de mesa'),
  ('Belleza',        'Cuidado personal y cosméticos'),
  ('Supermercado',   'Alimentos y productos de aseo');

-- Productos con nombre (los primeros 20)
INSERT INTO productos (categoria_id, sku, nombre, descripcion, precio) VALUES
  (1, 'TEC-0001', 'Portátil 14 pulgadas',      'Core i5, 16 GB RAM, 512 GB SSD', 3200000),
  (1, 'TEC-0002', 'Celular gama media',        '128 GB, cámara 50 MP',            1150000),
  (1, 'TEC-0003', 'Audífonos inalámbricos',    'Bluetooth con cancelación de ruido', 280000),
  (1, 'TEC-0004', 'Mouse ergonómico',          'Inalámbrico, 6 botones',            95000),
  (2, 'HOG-0001', 'Cafetera de goteo',         '12 tazas',                         189000),
  (2, 'HOG-0002', 'Juego de ollas',            'Acero inoxidable, 5 piezas',       345000),
  (2, 'HOG-0003', 'Lámpara de escritorio LED', 'Luz cálida y fría',                 79000),
  (3, 'DEP-0001', 'Balón de fútbol',           'Tamaño 5',                          85000),
  (3, 'DEP-0002', 'Mancuernas 10 kg',          'Par, recubiertas en neopreno',     160000),
  (3, 'DEP-0003', 'Bicicleta estática',        'Resistencia magnética',            980000),
  (4, 'MOD-0001', 'Tenis para correr',         'Suela amortiguada',                320000),
  (4, 'MOD-0002', 'Chaqueta impermeable',      'Unisex',                           210000),
  (5, 'LIB-0001', 'Cien años de soledad',      'Gabriel García Márquez',            65000),
  (5, 'LIB-0002', 'Fundamentos de bases de datos', 'Texto universitario',          150000),
  (6, 'JUG-0001', 'Rompecabezas 1000 piezas',  'Paisaje',                           55000),
  (6, 'JUG-0002', 'Juego de mesa de estrategia', '2 a 6 jugadores',                140000),
  (7, 'BEL-0001', 'Protector solar FPS 50',    '120 ml',                            48000),
  (7, 'BEL-0002', 'Kit de cuidado facial',     'Limpiador, tónico e hidratante',   125000),
  (8, 'SUP-0001', 'Café molido 500 g',         'Origen Huila',                      28000),
  (8, 'SUP-0002', 'Aceite de oliva 1 L',       'Extra virgen',                      42000);

-- Usuarios internos (uno por rol funcional)
-- password_hash: valor de EJEMPLO, no corresponde a una contraseña real
INSERT INTO usuarios (username, email, password_hash, rol) VALUES
  ('admin',     'admin@datamarket.com',     '$2b$10$ejemplo.hash.no.real.admin.......', 'ADMIN'),
  ('dev01',     'dev01@datamarket.com',     '$2b$10$ejemplo.hash.no.real.dev01.......', 'DEVELOPER'),
  ('analista01','analista01@datamarket.com','$2b$10$ejemplo.hash.no.real.analista..', 'ANALYST'),
  ('operador01','operador01@datamarket.com','$2b$10$ejemplo.hash.no.real.operador..', 'OPERATOR'),
  ('auditor01', 'auditor01@datamarket.com', '$2b$10$ejemplo.hash.no.real.auditor...', 'AUDITOR');

-- Algunos clientes con nombre (los primeros 5)
INSERT INTO clientes (nombre, email, telefono, direccion, fecha_registro) VALUES
  ('Laura Gómez',     'laura.gomez@correo.com',     '3001234567', 'Calle 80 # 15-20, Bogotá',   now() - interval '700 days'),
  ('Andrés Martínez', 'andres.martinez@correo.com', '3109876543', 'Carrera 7 # 45-10, Bogotá',  now() - interval '650 days'),
  ('Camila Rodríguez','camila.rodriguez@correo.com','3204567890', 'Calle 10 # 40-30, Medellín', now() - interval '600 days'),
  ('Julián Torres',   'julian.torres@correo.com',   '3157654321', 'Avenida 6N # 25-50, Cali',   now() - interval '500 days'),
  ('Valentina Ruiz',  'valentina.ruiz@correo.com',  '3012223344', 'Calle 72 # 50-12, Barranquilla', now() - interval '400 days');

-- =====================================================
-- PARTE 2. Volumen masivo (para rendimiento)
-- =====================================================

-- Productos 21 a 1.000, repartidos en las 8 categorías.
-- Precio entre 10.000 y 2.000.000, redondeado a centenas.
INSERT INTO productos (categoria_id, sku, nombre, precio, fecha_creacion)
SELECT
  (g % 8) + 1,
  'GEN-' || lpad(g::text, 5, '0'),
  'Producto generado ' || g,
  round((10000 + random() * 1990000) / 100) * 100,
  now() - (random() * interval '730 days')
FROM generate_series(21, 1000) AS g;

-- Unos pocos productos inactivos (descontinuados)
UPDATE productos SET activo = false WHERE id % 50 = 0;

-- Inventario: un registro por producto (relación 1:1).
-- ~10% de los productos queda con stock por debajo del mínimo
-- para que la vista "inventario_bajo" (Paso 9) devuelva datos.
INSERT INTO inventario (producto_id, stock, stock_minimo)
SELECT
  p.id,
  CASE WHEN random() < 0.10
       THEN floor(random() * 5)::int          -- 0 a 4: inventario bajo
       ELSE 5 + floor(random() * 500)::int    -- 5 a 504: inventario normal
  END,
  5
FROM productos p;

-- Clientes 6 a 10.000, registrados en los últimos 2 años
INSERT INTO clientes (nombre, email, telefono, direccion, fecha_registro)
SELECT
  'Cliente ' || g,
  'cliente' || g || '@correo.com',
  '3' || lpad((floor(random() * 1000000000))::text, 9, '0'),
  'Dirección generada ' || g,
  now() - (random() * interval '730 days')
FROM generate_series(6, 10000) AS g;

-- Pedidos: 100.000 repartidos aleatoriamente entre los clientes,
-- con fechas en los últimos 2 años y distribución de estados:
--   PENDIENTE 10%, PAGADO 15%, ENVIADO 15%, ENTREGADO 52%, CANCELADO 8%
INSERT INTO pedidos (cliente_id, fecha, estado)
SELECT
  1 + floor(random() * 10000)::int,
  now() - (random() * interval '730 days'),
  CASE
    WHEN r < 0.10 THEN 'PENDIENTE'
    WHEN r < 0.25 THEN 'PAGADO'
    WHEN r < 0.40 THEN 'ENVIADO'
    WHEN r < 0.92 THEN 'ENTREGADO'
    ELSE 'CANCELADO'
  END
FROM (SELECT random() AS r FROM generate_series(1, 100000)) AS t;

-- Detalle: entre 1 y 4 productos DISTINTOS por pedido.
-- La fórmula ((pedido*7 + n*131) % 1000) + 1 da productos diferentes
-- para n = 1..4, cumpliendo UNIQUE (pedido_id, producto_id).
-- precio_unitario se copia del precio del producto (RN-09).
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
SELECT
  pe.id,
  pr.id,
  1 + floor(random() * 3)::int,      -- cantidad 1 a 3
  pr.precio
FROM (
  -- Cantidad de líneas (1 a 4) calculada POR PEDIDO
  SELECT id, 1 + floor(random() * 4)::int AS lineas FROM pedidos
) AS pe
CROSS JOIN LATERAL generate_series(1, pe.lineas) AS n
JOIN productos pr ON pr.id = ((pe.id * 7 + n * 131) % 1000) + 1;

-- Total del pedido = suma de sus subtotales
UPDATE pedidos pe
SET total = d.suma
FROM (
  SELECT pedido_id, sum(subtotal) AS suma
  FROM detalle_pedido
  GROUP BY pedido_id
) AS d
WHERE d.pedido_id = pe.id;

-- Pagos:
--  - Pedidos PAGADO / ENVIADO / ENTREGADO: un pago APROBADO por el total.
--  - ~20% de ellos tuvo antes un intento RECHAZADO (por eso pagos es 1:N).
--  - Pedidos PENDIENTE: un pago PENDIENTE.
--  - Pedidos CANCELADO: sin pago.
INSERT INTO pagos (pedido_id, monto, metodo, estado, fecha)
SELECT id, total,
       (ARRAY['TARJETA','PSE','EFECTIVO','TRANSFERENCIA'])[1 + floor(random() * 4)::int],
       'RECHAZADO',
       fecha + interval '5 minutes'
FROM pedidos
WHERE estado IN ('PAGADO','ENVIADO','ENTREGADO') AND random() < 0.20;

INSERT INTO pagos (pedido_id, monto, metodo, estado, fecha)
SELECT id, total,
       (ARRAY['TARJETA','PSE','EFECTIVO','TRANSFERENCIA'])[1 + floor(random() * 4)::int],
       CASE WHEN estado = 'PENDIENTE' THEN 'PENDIENTE' ELSE 'APROBADO' END,
       fecha + interval '15 minutes'
FROM pedidos
WHERE estado <> 'CANCELADO';

-- Reactivar la auditoría
ALTER TABLE productos  ENABLE TRIGGER USER;
ALTER TABLE inventario ENABLE TRIGGER USER;
ALTER TABLE pedidos    ENABLE TRIGGER USER;
ALTER TABLE pagos      ENABLE TRIGGER USER;
ALTER TABLE clientes   ENABLE TRIGGER USER;
ALTER TABLE usuarios   ENABLE TRIGGER USER;

COMMIT;

-- Actualizar estadísticas para que el planificador (EXPLAIN) conozca el volumen
ANALYZE;

-- =====================================================
-- Verificación: cantidad de registros por tabla
-- =====================================================
SELECT 'categorias'     AS tabla, count(*) AS registros FROM categorias
UNION ALL SELECT 'productos',      count(*) FROM productos
UNION ALL SELECT 'inventario',     count(*) FROM inventario
UNION ALL SELECT 'clientes',       count(*) FROM clientes
UNION ALL SELECT 'pedidos',        count(*) FROM pedidos
UNION ALL SELECT 'detalle_pedido', count(*) FROM detalle_pedido
UNION ALL SELECT 'pagos',          count(*) FROM pagos
UNION ALL SELECT 'usuarios',       count(*) FROM usuarios;
