-- =====================================================
-- tests/09_incidente.sql
-- Paso 13: INCIDENTE CONTROLADO sobre la base EXPERIMENTAL.
--
-- Simula dos errores humanos frecuentes:
--   1. Un DELETE sin WHERE sobre pagos.
--   2. Un TRUNCATE ... CASCADE sobre pedidos, que arrastra
--      detalle_pedido.
--
-- PROTECCIÓN: solo se ejecuta en "datamarket_restaurada".
-- Si se intenta sobre "datamarket", se detiene sin hacer nada.
-- =====================================================

\set ON_ERROR_STOP on

DO $$
BEGIN
    IF current_database() <> 'datamarket_restaurada' THEN
        RAISE EXCEPTION 'PROTECCIÓN: el incidente solo se simula en datamarket_restaurada (estás en %)',
              current_database();
    END IF;
END
$$;

SET search_path TO datamarket;

\echo ''
\echo '================ ANTES DEL INCIDENTE ================'
SELECT (SELECT count(*) FROM pedidos)        AS pedidos,
       (SELECT count(*) FROM detalle_pedido) AS detalles,
       (SELECT count(*) FROM pagos)          AS pagos;

\echo ''
\echo '================ INCIDENTE ================'
\echo '1. DELETE sin WHERE sobre pagos'
DELETE FROM pagos;

\echo '2. TRUNCATE pedidos CASCADE (borra también detalle_pedido)'
TRUNCATE pedidos CASCADE;

\echo ''
\echo '================ DESPUÉS DEL INCIDENTE ================'
SELECT (SELECT count(*) FROM pedidos)        AS pedidos,
       (SELECT count(*) FROM detalle_pedido) AS detalles,
       (SELECT count(*) FROM pagos)          AS pagos;

\echo ''
\echo '--- Las vistas de negocio quedan vacías: el servicio está caído'
SELECT count(*) AS meses_con_ventas FROM ventas_por_periodo;

\echo ''
\echo '--- La auditoría registró el DELETE fila por fila (quién y cuándo)'
SELECT usuario, operacion, tabla_afectada, count(*) AS eventos
FROM auditoria
WHERE tabla_afectada = 'pagos' AND operacion = 'DELETE'
GROUP BY usuario, operacion, tabla_afectada;

\echo ''
\echo 'Nota: TRUNCATE no dispara triggers por fila, por eso NO aparece en la'
\echo 'auditoría. Es una limitación a documentar: para auditarlo haría falta'
\echo 'un trigger BEFORE TRUNCATE o quitar el privilegio TRUNCATE a todos'
\echo 'los roles (en este proyecto solo lo tiene db_admin).'
