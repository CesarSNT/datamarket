-- =====================================================
-- tests/02_pruebas_permisos.sql
-- Paso 5: probar permisos PERMITIDOS y DENEGADOS por rol.
-- Ejecutar como postgres después de 10_roles.sql y 11_seed.sql.
--
-- Se usa SET ROLE para actuar como cada usuario.
-- [PERMITIDO] debe funcionar.
-- [DENEGADO]  debe terminar en "ERROR: permission denied".
-- Las operaciones de escritura se hacen dentro de
-- BEGIN ... ROLLBACK para no modificar los datos.
-- =====================================================

SET search_path TO datamarket;

-- =====================================================
\echo ''
\echo '################ ANALISTA (usr_analista) ################'
SET ROLE usr_analista;
SELECT current_user;

\echo '--- [PERMITIDO] Consultar pedidos'
SELECT count(*) AS pedidos FROM pedidos;

\echo '--- [PERMITIDO] Consultar ventas por estado'
SELECT estado, count(*) FROM pedidos GROUP BY estado ORDER BY estado;

\echo '--- [DENEGADO] Eliminar un pedido'
DELETE FROM pedidos WHERE id = 1;

\echo '--- [DENEGADO] Modificar un precio'
UPDATE productos SET precio = 1 WHERE id = 1;

\echo '--- [DENEGADO] Insertar un cliente'
INSERT INTO clientes (nombre, email) VALUES ('X', 'x@x.com');

\echo '--- [DENEGADO] Ver usuarios internos (password_hash)'
SELECT username, password_hash FROM usuarios;

\echo '--- [DENEGADO] Ver auditoría'
SELECT count(*) FROM auditoria;

RESET ROLE;

-- =====================================================
\echo ''
\echo '################ AUDITOR (usr_auditor) ################'
SET ROLE usr_auditor;
SELECT current_user;

\echo '--- [PERMITIDO] Consultar auditoría'
SELECT count(*) AS eventos_auditoria FROM auditoria;

\echo '--- [DENEGADO] Consultar clientes'
SELECT count(*) FROM clientes;

\echo '--- [DENEGADO] Borrar registros de auditoría'
DELETE FROM auditoria;

\echo '--- [DENEGADO] Crear una tabla (administrar la base)'
CREATE TABLE datamarket.tabla_auditor (id int);

RESET ROLE;

-- =====================================================
\echo ''
\echo '################ OPERADOR (usr_operador) ################'
SET ROLE usr_operador;
SELECT current_user;

\echo '--- [PERMITIDO] Crear un pedido (se deshace con ROLLBACK)'
BEGIN;
INSERT INTO pedidos (cliente_id) VALUES (1) RETURNING id, estado;
ROLLBACK;

\echo '--- [PERMITIDO] Actualizar stock (se deshace con ROLLBACK)'
BEGIN;
UPDATE inventario SET stock = stock - 1 WHERE producto_id = 1 RETURNING producto_id, stock;
ROLLBACK;

\echo '--- [DENEGADO] Cambiar el precio de un producto'
UPDATE productos SET precio = 1 WHERE id = 1;

\echo '--- [DENEGADO] Cambiar el email de un cliente (columna no autorizada)'
UPDATE clientes SET email = 'otro@correo.com' WHERE id = 1;

\echo '--- [DENEGADO] Eliminar un pago'
DELETE FROM pagos WHERE id = 1;

RESET ROLE;

-- =====================================================
\echo ''
\echo '################ DEVELOPER (usr_dev) ################'
SET ROLE usr_dev;
SELECT current_user;

\echo '--- [PERMITIDO] Modificar datos (se deshace con ROLLBACK)'
BEGIN;
UPDATE productos SET precio = precio WHERE id = 1 RETURNING id, precio;
ROLLBACK;

\echo '--- [PERMITIDO] Crear y borrar una tabla de prueba'
CREATE TABLE datamarket.tmp_dev (id int);
DROP TABLE datamarket.tmp_dev;

\echo '--- [DENEGADO] Alterar la auditoría'
DELETE FROM auditoria;

RESET ROLE;

-- =====================================================
\echo ''
\echo '################ ADMIN (usr_admin) ################'
SET ROLE usr_admin;
SELECT current_user;

\echo '--- [PERMITIDO] Consultar usuarios internos'
SELECT username, rol FROM usuarios ORDER BY id;

\echo '--- [PERMITIDO] Consultar auditoría'
SELECT count(*) FROM auditoria;

RESET ROLE;

-- =====================================================
\echo ''
\echo '################ API (usr_api, hereda db_operator) ################'
SET ROLE usr_api;
SELECT current_user;

\echo '--- [PERMITIDO] Consultar productos e inventario'
SELECT p.id, p.nombre, p.precio, i.stock
FROM productos p JOIN inventario i ON i.producto_id = p.id
ORDER BY p.id LIMIT 3;

\echo '--- [PERMITIDO] Consultar pedidos de un cliente'
SELECT count(*) AS pedidos_cliente_1 FROM pedidos WHERE cliente_id = 1;

\echo '--- [DENEGADO] Leer usuarios internos'
SELECT username FROM usuarios;

\echo '--- [DENEGADO] Borrar pedidos'
DELETE FROM pedidos WHERE id = 1;

\echo '--- [DENEGADO] Leer la auditoría'
SELECT count(*) FROM auditoria;

\echo '--- [DENEGADO] Crear tablas'
CREATE TABLE datamarket.tabla_api (id int);

RESET ROLE;

\echo '--- La API NO es superusuario ni administra roles'
SELECT rolname, rolsuper, rolcreaterole, rolcreatedb
FROM pg_roles WHERE rolname = 'usr_api';

-- =====================================================
\echo ''
\echo '################ RESUMEN: privilegios por rol ################'
SELECT grantee AS rol, table_name AS tabla,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privilegios
FROM information_schema.role_table_grants
WHERE table_schema = 'datamarket'
  AND grantee IN ('db_developer','db_analyst','db_operator','db_auditor')
GROUP BY grantee, table_name
ORDER BY grantee, table_name;
