-- =====================================================
-- tests/09_post_restauracion.sql
-- Paso 13: configuración que pg_dump NO incluye en el backup.
-- Ejecutar conectado a la base RESTAURADA, justo después
-- de pg_restore.
--
-- Hallazgo: pg_dump respalda el CONTENIDO de la base (esquema,
-- tablas, datos, permisos sobre objetos), pero NO las
-- propiedades de la base de datos en sí:
--   - ALTER DATABASE ... SET search_path   (02_schema.sql)
--   - GRANT CONNECT / REVOKE ... FROM PUBLIC (10_roles.sql)
-- Sin este paso (comprobado):
--   - Las consultas sin prefijo fallan:
--       ERROR: relation "pedidos" does not exist
--     porque search_path ya no apunta al esquema datamarket.
--   - Cualquier rol del servidor puede conectarse, porque una
--     base nueva da CONNECT a PUBLIC por defecto.
-- (Los roles tampoco van en el backup: existen a nivel de
--  servidor. En un servidor nuevo hay que ejecutar antes
--  10_roles.sql o pg_dumpall --roles-only.)
-- =====================================================

DO $$
BEGIN
    IF current_database() = 'datamarket' THEN
        RAISE EXCEPTION 'Este script es para la base RESTAURADA, no para datamarket';
    END IF;

    EXECUTE format('ALTER DATABASE %I SET search_path = datamarket, public',
                   current_database());
    EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database());
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO db_admin, db_developer, '
                   'db_analyst, db_operator, db_auditor', current_database());
    EXECUTE format('GRANT ALL ON DATABASE %I TO db_admin', current_database());

    RAISE NOTICE 'Base % configurada: search_path y permisos de conexión', current_database();
END
$$;
