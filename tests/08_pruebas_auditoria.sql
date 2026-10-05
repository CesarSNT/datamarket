-- =====================================================
-- tests/08_pruebas_auditoria.sql
-- Paso 11: comprobar que la auditoría registra quién
-- modificó datos críticos, cuándo y qué cambió.
-- Ejecutar como postgres después de 09_triggers.sql,
-- 10_roles.sql y 11_seed.sql.
--
-- Se usa \connect para INICIAR SESIÓN como cada usuario
-- (así la auditoría registra el usuario real de la sesión).
-- Dentro de Docker las conexiones locales no piden contraseña.
-- =====================================================

SET search_path TO datamarket;

-- Punto de partida: solo se mostrarán los eventos nuevos
SELECT coalesce(max(id), 0) AS audit_ini FROM auditoria \gset

-- Producto con stock suficiente para la compra de prueba
SELECT i.producto_id AS prod_compra,
       '[{"producto_id": ' || i.producto_id || ', "cantidad": 1}]' AS compra_json
FROM inventario i JOIN productos p ON p.id = i.producto_id
WHERE p.activo AND i.stock >= 5
ORDER BY i.producto_id LIMIT 1 \gset

-- =====================================================
\echo ''
\echo '================ ACCIONES (generan eventos) ================'

\connect - usr_dev
SET search_path TO datamarket;

\echo '--- A1. usr_dev cambia el precio del producto 10 (UPDATE)'
UPDATE productos SET precio = precio + 1000 WHERE id = 10;

\echo '--- A2. usr_dev crea un cliente (INSERT) y luego lo borra (DELETE)'
INSERT INTO clientes (nombre, email)
VALUES ('Cliente Auditoria', 'auditoria.prueba@correo.com')
RETURNING id AS cliente_aud \gset
DELETE FROM clientes WHERE id = :cliente_aud;

\echo '--- A3. usr_dev ejecuta un UPDATE que NO cambia nada (no debe auditarse)'
UPDATE productos SET precio = precio WHERE id = 11;

\connect - usr_operador
SET search_path TO datamarket;

\echo '--- A4. usr_operador registra una compra con el procedimiento'
CALL sp_registrar_compra(5, :'compra_json', 'PSE', NULL);

\connect - postgres
SET search_path TO datamarket;

\echo '--- A5. postgres cambia la contraseña de un usuario interno'
UPDATE usuarios SET password_hash = '$2b$10$otro.hash.de.ejemplo' WHERE username = 'dev01';

-- =====================================================
\echo ''
\echo '================ CONSULTA DEL AUDITOR ================'

\connect - usr_auditor
SET search_path TO datamarket;

\echo '--- Eventos generados por esta prueba (quién, cuándo, qué)'
SELECT id, usuario, operacion, tabla_afectada AS tabla, registro_id,
       to_char(fecha, 'YYYY-MM-DD HH24:MI:SS') AS fecha
FROM auditoria
WHERE id > :audit_ini
ORDER BY id;

\echo '--- A1: precio antes y después'
SELECT usuario, operacion,
       datos_anteriores->>'precio' AS precio_antes,
       datos_nuevos->>'precio'     AS precio_despues
FROM auditoria
WHERE id > :audit_ini AND tabla_afectada = 'productos' AND registro_id = 10;

\echo '--- A2: el cliente borrado queda guardado en datos_anteriores'
SELECT operacion, datos_anteriores->>'nombre' AS nombre_borrado,
       datos_anteriores->>'email' AS email_borrado
FROM auditoria
WHERE id > :audit_ini AND tabla_afectada = 'clientes' AND operacion = 'DELETE';

\echo '--- A3: el UPDATE sin cambios NO generó evento (debe ser 0)'
SELECT count(*) AS eventos_producto_11
FROM auditoria
WHERE id > :audit_ini AND tabla_afectada = 'productos' AND registro_id = 11;

\echo '--- A4: la compra dejó rastro en pedidos, inventario y pagos'
SELECT tabla_afectada AS tabla, operacion, count(*) AS eventos
FROM auditoria
WHERE id > :audit_ini AND usuario = 'usr_operador'
GROUP BY tabla_afectada, operacion
ORDER BY tabla_afectada, operacion;

\echo '--- A4: movimiento de stock'
SELECT datos_anteriores->>'stock' AS stock_antes,
       datos_nuevos->>'stock'     AS stock_despues
FROM auditoria
WHERE id > :audit_ini AND tabla_afectada = 'inventario' AND usuario = 'usr_operador';

\echo '--- A5: la contraseña NO se guarda; solo se indica que cambió'
SELECT datos_anteriores ? 'password_hash'      AS hash_antes_guardado,
       datos_nuevos     ? 'password_hash'      AS hash_nuevo_guardado,
       datos_nuevos->>'password_cambiado'      AS password_cambiado
FROM auditoria
WHERE id > :audit_ini AND tabla_afectada = 'usuarios';

-- =====================================================
\echo ''
\echo '================ PROTECCIÓN DE LA AUDITORÍA ================'

\echo '--- [DENEGADO] El auditor intenta borrar eventos'
DELETE FROM auditoria WHERE id > :audit_ini;

\connect - usr_admin
SET search_path TO datamarket;

\echo '--- [DENEGADO] Ni el administrador puede borrar la auditoría'
DELETE FROM auditoria WHERE id > :audit_ini;

\echo '--- [DENEGADO] Ni modificarla'
UPDATE auditoria SET usuario = 'otro' WHERE id > :audit_ini;

\connect - usr_operador
SET search_path TO datamarket;

\echo '--- [DENEGADO] El operador no puede insertar eventos falsos'
INSERT INTO auditoria (usuario, operacion, tabla_afectada)
VALUES ('nadie', 'DELETE', 'pedidos');

\connect - postgres
SET search_path TO datamarket;

-- Dejar el precio del producto 10 como estaba (también queda auditado)
UPDATE productos SET precio = precio - 1000 WHERE id = 10;
\echo ''
\echo 'Prueba terminada. El precio del producto 10 se restauró.'
