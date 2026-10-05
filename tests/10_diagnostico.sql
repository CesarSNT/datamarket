-- =====================================================
-- tests/10_diagnostico.sql
-- Reto final – Incidente de producción.
-- Chequeo de salud de la base: DETECTA (no corrige) los
-- problemas típicos del reto y deja evidencia.
--
-- Ejecutar como postgres:
--   - ANTES de corregir  -> evidencia del problema
--   - DESPUÉS de corregir -> comprobación de la solución
-- En una base sana, cada sección debe devolver 0 filas
-- (salvo la 5, que es informativa).
-- =====================================================

SET search_path TO datamarket;

-- =====================================================
\echo ''
\echo '================ 1. PERMISOS EXCESIVOS ================'

\echo '--- 1a. Privilegios sobre tablas otorgados a PUBLIC (todos los roles)'
SELECT table_name AS tabla, privilege_type AS privilegio
FROM information_schema.role_table_grants
WHERE table_schema = 'datamarket' AND grantee = 'PUBLIC'
ORDER BY 1, 2;

\echo '--- 1b. Roles de solo lectura con privilegios de escritura'
\echo '        (analista y auditor no deben escribir; operador no debe borrar)'
SELECT grantee AS rol, table_name AS tabla, privilege_type AS privilegio
FROM information_schema.role_table_grants
WHERE table_schema = 'datamarket'
  AND (   (grantee IN ('db_analyst','db_auditor')
           AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE'))
       OR (grantee = 'db_operator'
           AND privilege_type IN ('DELETE','TRUNCATE')))
ORDER BY 1, 2, 3;

\echo '--- 1c. Acceso indebido a datos sensibles (usuarios y auditoría)'
SELECT grantee AS rol, table_name AS tabla, privilege_type AS privilegio
FROM information_schema.role_table_grants
WHERE table_schema = 'datamarket'
  AND (   (table_name = 'usuarios'  AND grantee IN ('db_analyst','db_operator','db_auditor'))
       OR (table_name = 'auditoria' AND grantee IN ('db_analyst','db_operator')))
ORDER BY 1, 2, 3;

\echo '--- 1d. Usuarios de login con privilegios de superusuario o administración'
\echo '        (solo postgres debería aparecer)'
SELECT rolname AS rol, rolsuper AS superusuario, rolcreaterole AS crea_roles,
       rolcreatedb AS crea_bases, rolbypassrls AS ignora_rls
FROM pg_roles
WHERE rolcanlogin
  AND (rolsuper OR rolcreatedb OR rolbypassrls
       OR (rolcreaterole AND rolname <> 'usr_admin'))
ORDER BY 1;

\echo '--- 1e. Usuarios de aplicación miembros de un grupo distinto al esperado'
SELECT m.rolname AS usuario, g.rolname AS grupo
FROM pg_auth_members am
JOIN pg_roles m ON m.oid = am.member
JOIN pg_roles g ON g.oid = am.roleid
WHERE m.rolname LIKE 'usr\_%'
  AND (m.rolname, g.rolname) NOT IN (
        ('usr_admin','db_admin'), ('usr_dev','db_developer'),
        ('usr_analista','db_analyst'), ('usr_operador','db_operator'),
        ('usr_auditor','db_auditor'), ('usr_api','db_operator'))
ORDER BY 1;

\echo '--- 1f. Funciones y procedimientos que PUBLIC puede ejecutar'
SELECT p.proname AS rutina,
       CASE p.prokind WHEN 'p' THEN 'procedimiento' ELSE 'función' END AS tipo
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'datamarket'
  AND p.prorettype <> 'trigger'::regtype
  AND has_function_privilege('public', p.oid, 'EXECUTE')
ORDER BY 1;

-- =====================================================
\echo ''
\echo '================ 2. ÍNDICES AUSENTES ================'

\echo '--- 2a. Claves foráneas SIN índice (lentitud en JOIN y al borrar el padre)'
SELECT c.conrelid::regclass AS tabla,
       a.attname            AS columna_fk,
       c.conname            AS restriccion
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
WHERE c.contype = 'f'
  AND c.connamespace = 'datamarket'::regnamespace
  AND NOT EXISTS (
        SELECT 1 FROM pg_index i
        WHERE i.indrelid = c.conrelid
          AND i.indkey[0] = c.conkey[1])     -- índice que EMPIEZA por la columna FK
ORDER BY 1, 2;

\echo '--- 2b. Índices esperados que no existen'
SELECT esperado AS indice_faltante
FROM unnest(ARRAY['idx_pedidos_cliente','idx_pedidos_fecha','idx_detalle_producto',
                  'idx_pagos_pedido','idx_productos_categoria']) AS esperado
WHERE NOT EXISTS (SELECT 1 FROM pg_indexes
                  WHERE schemaname = 'datamarket' AND indexname = esperado);

\echo '--- 2c. Índices inválidos (por ejemplo, un CREATE INDEX CONCURRENTLY que falló)'
SELECT indexrelid::regclass AS indice
FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid
WHERE c.relnamespace = 'datamarket'::regnamespace AND NOT i.indisvalid;

-- =====================================================
\echo ''
\echo '================ 3. CONSULTAS LENTAS ================'

\echo '--- 3a. Tablas grandes leídas mayormente con Seq Scan (posible índice faltante)'
\echo '        Contadores desde el último reinicio de estadísticas'
SELECT relname AS tabla, n_live_tup AS filas,
       seq_scan, idx_scan,
       seq_tup_read AS filas_leidas_secuencialmente
FROM pg_stat_user_tables
WHERE schemaname = 'datamarket'
  AND n_live_tup > 10000
  AND seq_scan > coalesce(idx_scan, 0)
ORDER BY seq_tup_read DESC;

\echo '--- 3b. Consultas ejecutándose hace más de 5 segundos'
SELECT pid, usename AS usuario, state AS estado,
       now() - query_start AS duracion, left(query, 80) AS consulta
FROM pg_stat_activity
WHERE datname = current_database()
  AND state <> 'idle'
  AND pid <> pg_backend_pid()
  AND now() - query_start > interval '5 seconds'
ORDER BY duracion DESC;

\echo '--- 3c. Sesiones bloqueadas y quién las bloquea'
SELECT bloqueada.pid AS pid_bloqueada, bloqueada.usename AS usuario_bloqueado,
       left(bloqueada.query, 60) AS consulta_bloqueada,
       bloqueadora.pid AS pid_bloqueadora, bloqueadora.usename AS usuario_bloqueador,
       left(bloqueadora.query, 60) AS consulta_bloqueadora
FROM pg_stat_activity bloqueada
JOIN LATERAL unnest(pg_blocking_pids(bloqueada.pid)) AS b(pid) ON true
JOIN pg_stat_activity bloqueadora ON bloqueadora.pid = b.pid;

-- =====================================================
\echo ''
\echo '================ 4. INCONSISTENCIAS DE DATOS ================'

\echo '--- 4a. Resumen (todos deben ser 0)'
SELECT
  (SELECT count(*) FROM pedidos p
    WHERE p.total <> (SELECT coalesce(sum(subtotal), 0)
                      FROM detalle_pedido d WHERE d.pedido_id = p.id))         AS total_pedido_descuadrado,
  (SELECT count(*) FROM pedidos p
    WHERE p.estado NOT IN ('CANCELADO')
      AND NOT EXISTS (SELECT 1 FROM detalle_pedido d WHERE d.pedido_id = p.id)) AS pedidos_sin_productos,
  (SELECT count(*) FROM pedidos p
    WHERE p.estado IN ('PAGADO','ENVIADO','ENTREGADO')
      AND NOT EXISTS (SELECT 1 FROM pagos pa
                      WHERE pa.pedido_id = p.id AND pa.estado = 'APROBADO'))    AS pagados_sin_pago_aprobado,
  (SELECT count(*) FROM pedidos p
    WHERE (SELECT coalesce(sum(monto), 0) FROM pagos pa
           WHERE pa.pedido_id = p.id AND pa.estado = 'APROBADO') > p.total)     AS cobrado_de_mas,
  (SELECT count(*) FROM productos pr
    WHERE NOT EXISTS (SELECT 1 FROM inventario i WHERE i.producto_id = pr.id))  AS productos_sin_inventario,
  (SELECT count(*) FROM inventario WHERE stock < 0)                            AS stock_negativo;

\echo '--- 4b. Detalle de pedidos descuadrados (máximo 10)'
SELECT p.id AS pedido, p.total AS total_registrado,
       (SELECT coalesce(sum(subtotal), 0) FROM detalle_pedido d
        WHERE d.pedido_id = p.id) AS total_real
FROM pedidos p
WHERE p.total <> (SELECT coalesce(sum(subtotal), 0)
                  FROM detalle_pedido d WHERE d.pedido_id = p.id)
LIMIT 10;

\echo '--- 4c. Restricciones desactivadas o no validadas (NOT VALID)'
SELECT conrelid::regclass AS tabla, conname AS restriccion
FROM pg_constraint
WHERE connamespace = 'datamarket'::regnamespace AND NOT convalidated;

\echo '--- 4d. Restricciones esperadas que no existen'
SELECT esperada AS restriccion_faltante
FROM unnest(ARRAY['chk_inventario_stock','chk_productos_precio','chk_detalle_cantidad',
                  'fk_pedidos_cliente','fk_detalle_pedido','fk_detalle_producto',
                  'uq_clientes_email','uq_productos_sku','uq_inventario_producto']) AS esperada
WHERE NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE connamespace = 'datamarket'::regnamespace AND conname = esperada);

-- =====================================================
\echo ''
\echo '================ 5. AUDITORÍA ================'

\echo '--- 5a. Tablas críticas SIN trigger de auditoría activo'
SELECT t AS tabla_sin_auditoria
FROM unnest(ARRAY['productos','inventario','pedidos','pagos','clientes','usuarios']) AS t
WHERE NOT EXISTS (
        SELECT 1 FROM pg_trigger tg
        JOIN pg_class c ON c.oid = tg.tgrelid
        WHERE c.relnamespace = 'datamarket'::regnamespace
          AND c.relname = t
          AND tg.tgfoid = 'datamarket.fn_auditoria'::regproc
          AND tg.tgenabled <> 'D');           -- 'D' = desactivado

\echo '--- 5b. La auditoría ya no es inmutable'
SELECT 'trg_auditoria_inmutable ausente o desactivado' AS problema
WHERE NOT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgname = 'trg_auditoria_inmutable' AND tgenabled <> 'D');

\echo '--- 5c. Informativo: últimos 10 eventos de auditoría'
SELECT id, usuario, operacion, tabla_afectada, registro_id,
       to_char(fecha, 'YYYY-MM-DD HH24:MI:SS') AS fecha
FROM auditoria ORDER BY id DESC LIMIT 10;

-- =====================================================
\echo ''
\echo '================ 6. BACKUP ================'
\echo 'Un backup que "no se puede restaurar" se diagnostica fuera de SQL:'
\echo '  docker exec datamarket-postgres pg_restore -l /tmp/datamarket.backup'
\echo 'Si el archivo está dañado o no es formato custom, pg_restore -l falla.'
\echo 'Ver tests/09_backup_restauracion.md.'
