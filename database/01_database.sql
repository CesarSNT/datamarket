-- =====================================================
-- 01_database.sql
-- Crea la base de datos DataMarket desde cero.
-- IMPORTANTE: ejecutar conectado a la BD "postgres",
-- no a "datamarket" (no se puede borrar la BD en uso).
-- =====================================================

DROP DATABASE IF EXISTS datamarket WITH (FORCE);

CREATE DATABASE datamarket
    WITH ENCODING = 'UTF8'
         TEMPLATE = template0;

COMMENT ON DATABASE datamarket IS 'Plataforma de pedidos - DataMarket S.A.S.';