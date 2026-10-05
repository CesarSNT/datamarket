-- =====================================================
-- 09_triggers.sql
-- Auditoría automática con triggers (Paso 11).
-- Ejecutar conectado a la BD "datamarket", después de
-- 03_tables.sql (la tabla auditoria se crea allí).
--
-- Qué se audita (INSERT, UPDATE y DELETE):
--   productos   -> cambios de precio, activar/desactivar
--   inventario  -> movimientos de stock
--   pedidos     -> creación, cambios de estado, cancelaciones
--   pagos       -> registro y cambios de estado del dinero
--   clientes    -> datos personales
--   usuarios    -> altas, cambios de rol, desactivaciones
--
-- No se auditan:
--   categorias      -> catálogo de referencia, cambia muy poco
--   detalle_pedido  -> se crea junto con el pedido y no se modifica;
--                      el pedido (auditado) ya registra el evento
--
-- Decisiones de seguridad:
--   1. La función del trigger es SECURITY DEFINER: escribe en
--      auditoria con los permisos de su dueño. Así NINGÚN rol de
--      la aplicación necesita permiso de INSERT sobre auditoria
--      (nadie puede fabricar eventos falsos).
--   2. El usuario registrado es session_user: el usuario con el
--      que se INICIÓ SESIÓN. No cambia con SET ROLE, ni dentro
--      de la función SECURITY DEFINER.
--   3. La auditoría es de solo inserción: un trigger impide
--      UPDATE, DELETE y TRUNCATE, incluso al administrador.
--   4. No se guarda password_hash: solo se indica si cambió.
--   5. Un UPDATE que no cambia nada no genera evento.
-- =====================================================

SET search_path TO datamarket;
SET client_min_messages TO warning;   -- oculta avisos "does not exist, skipping"

-- -----------------------------------------------------
-- 1. Función genérica de auditoría
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION fn_auditoria()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = datamarket, pg_temp      -- obligatorio en SECURITY DEFINER
AS $$
DECLARE
    v_antes    JSONB;
    v_despues  JSONB;
    v_id       BIGINT;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_antes := to_jsonb(OLD);
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_despues := to_jsonb(NEW);
    END IF;

    -- UPDATE sin cambios reales: no se registra
    IF TG_OP = 'UPDATE' AND v_antes = v_despues THEN
        RETURN NULL;
    END IF;

    -- Nunca guardar contraseñas (ni siquiera cifradas)
    IF TG_TABLE_NAME = 'usuarios' THEN
        IF TG_OP = 'UPDATE'
           AND v_antes->>'password_hash' IS DISTINCT FROM v_despues->>'password_hash' THEN
            v_despues := v_despues || '{"password_cambiado": true}';
        END IF;
        v_antes   := v_antes   - 'password_hash';
        v_despues := v_despues - 'password_hash';
    END IF;

    v_id := coalesce(v_despues->>'id', v_antes->>'id')::BIGINT;

    INSERT INTO auditoria (usuario, fecha, operacion, tabla_afectada,
                           registro_id, datos_anteriores, datos_nuevos)
    VALUES (session_user, clock_timestamp(), TG_OP, TG_TABLE_NAME,
            v_id, v_antes, v_despues);

    RETURN NULL;   -- trigger AFTER: el valor de retorno se ignora
END;
$$;

COMMENT ON FUNCTION fn_auditoria() IS
  'Registra INSERT/UPDATE/DELETE en auditoria (SECURITY DEFINER, sin password_hash)';

-- -----------------------------------------------------
-- 2. Triggers sobre las tablas críticas
--    AFTER: solo se audita lo que realmente se guardó
--    (si la operación falla por una restricción, no hay evento).
--    FOR EACH ROW: un evento por cada registro afectado.
-- -----------------------------------------------------
DO $$
DECLARE
    v_tabla TEXT;
BEGIN
    FOREACH v_tabla IN ARRAY
        ARRAY['productos', 'inventario', 'pedidos', 'pagos', 'clientes', 'usuarios']
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_auditoria_%1$s ON %1$I', v_tabla);
        EXECUTE format(
            'CREATE TRIGGER trg_auditoria_%1$s
             AFTER INSERT OR UPDATE OR DELETE ON %1$I
             FOR EACH ROW EXECUTE FUNCTION fn_auditoria()', v_tabla);
    END LOOP;
END
$$;

-- -----------------------------------------------------
-- 3. Auditoría inmutable (solo inserción)
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION fn_auditoria_inmutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'La auditoría no se puede modificar ni borrar (operación % rechazada)', TG_OP
          USING ERRCODE = 'insufficient_privilege';
END;
$$;

DROP TRIGGER IF EXISTS trg_auditoria_inmutable ON auditoria;
CREATE TRIGGER trg_auditoria_inmutable
    BEFORE UPDATE OR DELETE OR TRUNCATE ON auditoria
    FOR EACH STATEMENT EXECUTE FUNCTION fn_auditoria_inmutable();

-- -----------------------------------------------------
-- 4. Índices para consultar la auditoría
--    (historial de un registro y eventos por fecha)
-- -----------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_auditoria_tabla_registro
    ON auditoria (tabla_afectada, registro_id);
CREATE INDEX IF NOT EXISTS idx_auditoria_fecha
    ON auditoria (fecha);
