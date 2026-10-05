-- =====================================================
-- 10_roles.sql
-- Seguridad: roles con privilegios mínimos.
-- Ejecutar conectado a la BD "datamarket" como postgres.
--
-- Modelo: ROLES DE GRUPO (sin login) que tienen los permisos
-- + USUARIOS DE LOGIN que heredan de un grupo.
--   db_admin     -> usr_admin
--   db_developer -> usr_dev
--   db_analyst   -> usr_analista
--   db_operator  -> usr_operador
--   db_auditor   -> usr_auditor
--   db_operator  -> usr_api   (usuario de conexión de la API, Paso 14)
--
-- La API NO usa postgres ni usr_admin: hereda de db_operator,
-- que puede consultar el catálogo y registrar compras, pero no
-- borrar datos, ni ver usuarios internos, ni ver la auditoría.
--
-- Los roles existen a nivel de SERVIDOR (no se borran con la BD),
-- por eso se crean solo si no existen. El script es re-ejecutable.
--
-- Contraseñas: SOLO PARA EL LABORATORIO. En producción se
-- definen fuera del repositorio (variables de entorno / vault).
-- =====================================================

-- -----------------------------------------------------
-- 1. Crear roles de grupo (NOLOGIN) y usuarios (LOGIN)
-- -----------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('db_admin'), ('db_developer'), ('db_analyst'),
      ('db_operator'), ('db_auditor')) AS t(nombre)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r.nombre) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN', r.nombre);
    END IF;
  END LOOP;

  FOR r IN SELECT * FROM (VALUES
      ('usr_admin',    'Admin2026!',    'db_admin'),
      ('usr_dev',      'Dev2026!',      'db_developer'),
      ('usr_analista', 'Analista2026!', 'db_analyst'),
      ('usr_operador', 'Operador2026!', 'db_operator'),
      ('usr_auditor',  'Auditor2026!',  'db_auditor'),
      ('usr_api',      'Api2026!',      'db_operator')) AS t(usuario, clave, grupo)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r.usuario) THEN
      EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', r.usuario, r.clave);
    END IF;
    IF NOT pg_has_role(r.usuario, r.grupo, 'MEMBER') THEN
      EXECUTE format('GRANT %I TO %I', r.grupo, r.usuario);
    END IF;
  END LOOP;
END
$$;

-- db_admin puede crear y administrar roles, pero NO es superusuario
ALTER ROLE db_admin CREATEROLE;

-- -----------------------------------------------------
-- 2. Cerrar accesos por defecto (PUBLIC = todos los roles)
-- -----------------------------------------------------
REVOKE ALL ON DATABASE datamarket FROM PUBLIC;
REVOKE ALL ON SCHEMA public       FROM PUBLIC;
REVOKE ALL ON SCHEMA datamarket   FROM PUBLIC;

-- Todos los grupos pueden conectarse y "ver" el esquema
GRANT CONNECT ON DATABASE datamarket
  TO db_admin, db_developer, db_analyst, db_operator, db_auditor;
GRANT USAGE ON SCHEMA datamarket
  TO db_admin, db_developer, db_analyst, db_operator, db_auditor;

SET search_path TO datamarket;

-- -----------------------------------------------------
-- 3. db_admin: administración completa de los objetos
-- -----------------------------------------------------
GRANT ALL ON DATABASE datamarket TO db_admin;
GRANT ALL ON SCHEMA datamarket TO db_admin;
GRANT ALL ON ALL TABLES    IN SCHEMA datamarket TO db_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA datamarket TO db_admin;
GRANT ALL ON ALL ROUTINES IN SCHEMA datamarket TO db_admin;

-- -----------------------------------------------------
-- 4. db_developer: crea objetos y manipula datos,
--    pero NO puede alterar la auditoría
-- -----------------------------------------------------
GRANT CREATE ON SCHEMA datamarket TO db_developer;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON categorias, productos, inventario, clientes, pedidos,
     detalle_pedido, pagos, usuarios
  TO db_developer;
GRANT SELECT ON auditoria TO db_developer;          -- solo lectura
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA datamarket TO db_developer;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA datamarket TO db_developer;

-- -----------------------------------------------------
-- 5. db_analyst: SOLO LECTURA de información de negocio.
--    Sin acceso a usuarios (password_hash) ni a auditoría.
--    No puede insertar, modificar ni eliminar.
-- -----------------------------------------------------
GRANT SELECT
  ON categorias, productos, inventario, clientes, pedidos,
     detalle_pedido, pagos
  TO db_analyst;
-- Las vistas de negocio (Paso 9) se otorgan en la sección 7b

-- -----------------------------------------------------
-- 6. db_operator: opera el día a día (registrar pedidos,
--    pagos, mover inventario). NUNCA elimina registros.
--    UPDATE limitado a columnas específicas.
-- -----------------------------------------------------
GRANT SELECT
  ON categorias, productos, inventario, clientes, pedidos,
     detalle_pedido, pagos
  TO db_operator;
GRANT INSERT ON clientes, pedidos, detalle_pedido, pagos TO db_operator;
GRANT UPDATE (stock, ultima_actualizacion) ON inventario TO db_operator;
GRANT UPDATE (estado, total)               ON pedidos    TO db_operator;
GRANT UPDATE (estado)                      ON pagos      TO db_operator;
GRANT UPDATE (telefono, direccion)         ON clientes   TO db_operator;
GRANT USAGE ON SEQUENCE clientes_id_seq, pedidos_id_seq,
                        detalle_pedido_id_seq, pagos_id_seq
  TO db_operator;

-- -----------------------------------------------------
-- 7. db_auditor: consulta la auditoría y nada más
-- -----------------------------------------------------
GRANT SELECT ON auditoria TO db_auditor;

-- -----------------------------------------------------
-- 7b. Vistas de negocio (creadas en 06_views.sql)
--     La vista se ejecuta con los permisos de su dueño, así que
--     un rol puede consultarla SIN tener acceso a las tablas base.
--     db_admin ya las recibe con "ALL ON ALL TABLES" (sección 3).
-- -----------------------------------------------------
GRANT SELECT ON ventas_por_periodo, inventario_bajo, resumen_compras_cliente
  TO db_analyst, db_developer;
GRANT SELECT ON inventario_bajo TO db_operator;   -- para reponer stock

-- -----------------------------------------------------
-- 7c. Funciones y procedimientos (07_functions.sql, 08_procedures.sql)
--     Nota: "ALL FUNCTIONS" NO incluye procedimientos;
--     "ALL ROUTINES" incluye funciones y procedimientos.
--     PostgreSQL da EXECUTE a PUBLIC por defecto: se revoca y se
--     otorga solo a quien lo necesita.
--     Se ejecutan con los permisos de QUIEN LOS LLAMA
--     (SECURITY INVOKER), así que el operador solo puede hacer
--     dentro del procedimiento lo que ya tiene permitido.
-- -----------------------------------------------------
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA datamarket FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA datamarket
  REVOKE EXECUTE ON ROUTINES FROM PUBLIC;

-- Operador: registra y cancela compras, consulta stock
GRANT EXECUTE ON FUNCTION  fn_stock_disponible(BIGINT),
                           fn_calcular_total_pedido(BIGINT)
  TO db_operator;
GRANT EXECUTE ON PROCEDURE sp_registrar_compra(BIGINT, JSONB, VARCHAR, BIGINT),
                           sp_cancelar_pedido(BIGINT)
  TO db_operator;

-- Analista: solo funciones de consulta, ningún procedimiento
GRANT EXECUTE ON FUNCTION  fn_ventas_por_categoria(DATE, DATE),
                           fn_stock_disponible(BIGINT),
                           fn_calcular_total_pedido(BIGINT)
  TO db_analyst;

-- -----------------------------------------------------
-- 8. Privilegios por defecto para objetos FUTUROS
--    creados por postgres en el esquema
-- -----------------------------------------------------
ALTER DEFAULT PRIVILEGES IN SCHEMA datamarket
  GRANT ALL ON TABLES    TO db_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA datamarket
  GRANT ALL ON SEQUENCES TO db_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA datamarket
  GRANT ALL ON ROUTINES TO db_admin;
