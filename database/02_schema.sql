-- =====================================================
-- 02_schema.sql
-- Crea el esquema de la aplicación.
-- Ejecutar conectado a la BD "datamarket".
-- =====================================================

CREATE SCHEMA IF NOT EXISTS datamarket;

COMMENT ON SCHEMA datamarket IS 'Objetos de negocio de DataMarket';

-- Que todas las sesiones busquen primero en este esquema
ALTER DATABASE datamarket SET search_path = datamarket, public;