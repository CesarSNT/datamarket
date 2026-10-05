# Plan de pruebas – DataMarket (Paso 15)

Cada prueba indica **objetivo, preparación, acción, resultado esperado y resultado obtenido**, como pide el taller.

- **Resultado obtenido:** lo registrado en la ejecución sobre Docker (PostgreSQL 16.15). Las capturas de cada prueba están en `screenshots/`, organizadas por paso; el documento `screenshots/README.md` explica cada una.
- Las pruebas que dicen **ERROR esperado** son correctas cuando fallan: demuestran que la base bloqueó una operación inválida.

## Cómo ejecutar cualquier prueba

En CMD, desde la carpeta `TaskDB`:

```
docker exec -i datamarket-postgres psql -U postgres -d datamarket < tests\NOMBRE_DEL_ARCHIVO.sql
```

Requisito: base construida y con datos (`database\01` a `database\11`).

---

## Resumen

| # | Área | Archivo | Pruebas | Resultado |
|---|---|---|---|---|
| T1 | Integridad referencial y restricciones | `01_pruebas_integridad.sql` | 13 | ✅ 12 rechazos esperados + CASCADE correcto |
| T2 | Permisos por rol | `02_pruebas_permisos.sql` | 27 | ✅ Permitidos funcionan, 16 denegados |
| T3 | Transacciones | `03_transacciones.sql` | 3 casos | ✅ COMMIT completo, 2 ROLLBACK sin datos parciales |
| T4 | Concurrencia | `04_concurrencia_guia.md` | 4 escenarios | ✅ Sobreventa en READ COMMITTED; resuelta con FOR UPDATE |
| T5 | Rendimiento | `05_rendimiento.sql` | 4 consultas | ✅ Mejoras de ~10× a ~50× |
| T6 | Vistas | `06_pruebas_vistas.sql` | 9 | ✅ Datos correctos y acceso restringido |
| T7 | Funciones y procedimientos | `07_pruebas_funciones.sql` | 17 | ✅ Compra atómica y 13 validaciones |
| T8 | Auditoría | `08_pruebas_auditoria.sql` | 9 | ✅ Registra quién, cuándo y qué; inmutable |
| T9 | Backup / restauración | `09_backup_restauracion.md` | 4 etapas | ✅ Backup de 7,1 MB; restauración idéntica en 3,25 s |
| T10 | Diagnóstico (reto final) | `10_diagnostico.sql` | 19 chequeos | ✅ Base sana en Docker: 0 hallazgos; 8 fallas inyectadas detectadas (entorno de prueba) |

---

## T1 – Integridad referencial y restricciones

| Campo | Detalle |
|---|---|
| **Objetivo** | Comprobar que la base rechaza datos que violan las reglas de negocio RN-01 a RN-13 (ver `docs/diccionario-datos.md`). |
| **Preparación** | El script crea una categoría, producto, inventario, cliente y pedido de prueba con IDs altos (9900001) para no tocar los datos reales. |
| **Acción** | 12 operaciones inválidas + 1 borrado en cascada. |
| **Limpieza** | El script borra sus datos de prueba al final. |

| Prueba | Acción | Esperado | Obtenido |
|---|---|---|---|
| P01 | Pedido con cliente inexistente | ERROR `fk_pedidos_cliente` | ✅ ERROR fk_pedidos_cliente |
| P02 | Producto con precio −500 | ERROR `chk_productos_precio` | ✅ ERROR chk_productos_precio |
| P03 | Email de cliente duplicado | ERROR `uq_clientes_email` | ✅ ERROR uq_clientes_email |
| P04 | SKU duplicado | ERROR `uq_productos_sku` | ✅ ERROR uq_productos_sku |
| P05 | Stock = −1 | ERROR `chk_inventario_stock` | ✅ ERROR chk_inventario_stock |
| P06 | Cantidad 0 en detalle | ERROR `chk_detalle_cantidad` | ✅ ERROR chk_detalle_cantidad |
| P07 | Segundo inventario del mismo producto | ERROR `uq_inventario_producto` | ✅ ERROR uq_inventario_producto |
| P08 | Mismo producto dos veces en un pedido | ERROR `uq_detalle_pedido_producto` | ✅ ERROR uq_detalle_pedido_producto |
| P09 | Estado de pedido 'PERDIDO' | ERROR `chk_pedidos_estado` | ✅ ERROR chk_pedidos_estado |
| P10 | Escribir el subtotal a mano | ERROR columna generada | ✅ ERROR cannot insert a non-DEFAULT value |
| P11 | Borrar cliente con pedidos | ERROR `fk_pedidos_cliente` (RESTRICT) | ✅ ERROR fk_pedidos_cliente |
| P12 | Cliente con nombre NULL | ERROR not-null | ✅ ERROR not-null constraint |
| P13 | Borrar pedido con detalle | Detalle borrado en cascada (0 filas) | ✅ detalles_restantes = 0 |

**Evidencia:** [`screenshots/paso03_integridad/`](../screenshots/paso03_integridad/)

---

## T2 – Permisos por rol

| Campo | Detalle |
|---|---|
| **Objetivo** | Verificar privilegios mínimos: cada rol puede hacer solo lo que su función requiere. |
| **Preparación** | `10_roles.sql` ejecutado. El script usa `SET ROLE` para actuar como cada usuario. Las escrituras permitidas se hacen dentro de `BEGIN ... ROLLBACK` (no modifican datos). |
| **Acción** | Operaciones permitidas y prohibidas para analista, auditor, operador, developer, admin y API. |

| Rol | Acción | Esperado | Obtenido |
|---|---|---|---|
| Analista | Consultar pedidos y ventas por estado | Permitido | ✅ 100.000 pedidos |
| Analista | DELETE pedido / UPDATE precio / INSERT cliente | Denegado | ✅ permission denied (×3) |
| Analista | Leer `usuarios` y `auditoria` | Denegado | ✅ permission denied (×2) |
| Auditor | Consultar auditoría | Permitido | ✅ |
| Auditor | Leer clientes / borrar auditoría / crear tabla | Denegado | ✅ permission denied (×3) |
| Operador | Crear pedido / descontar stock | Permitido | ✅ (revertido con ROLLBACK) |
| Operador | Cambiar precio / cambiar email / borrar pago | Denegado | ✅ permission denied (×3) |
| Developer | Modificar datos / crear y borrar tabla | Permitido | ✅ |
| Developer | Borrar auditoría | Denegado | ✅ permission denied |
| Admin | Leer usuarios y auditoría | Permitido | ✅ |
| API (`usr_api`) | Leer productos, inventario y pedidos | Permitido | ✅ |
| API (`usr_api`) | Leer usuarios / borrar pedidos / leer auditoría / crear tablas | Denegado | ✅ permission denied (×4) |
| API (`usr_api`) | Atributos del rol | No superusuario | ✅ rolsuper = f, rolcreaterole = f |

**Evidencia:** [`screenshots/paso05_seguridad/`](../screenshots/paso05_seguridad/)

---

## T3 – Transacciones

| Campo | Detalle |
|---|---|
| **Objetivo** | Demostrar que la compra (pedido → detalle → inventario → pago) es atómica: todo o nada. |
| **Preparación** | Datos de `11_seed.sql`. El script guarda los conteos iniciales para compararlos. |
| **Acción** | A: compra válida + COMMIT. B: compra de 100 unidades con stock 4 (falla en el paso 3). C: compra válida + ROLLBACK manual (pago rechazado). |

| Caso | Esperado | Obtenido |
|---|---|---|
| A | Pedido PAGADO, 2 líneas, pago APROBADO, stock descontado | ✅ Total 7.550.000, stock 57→55 y 70→69 |
| B | ERROR en inventario; luego "transaction is aborted"; 0 filas nuevas | ✅ dif_pedidos = dif_detalles = dif_pagos = 0; stock sin cambios |
| C | Dentro de la transacción el stock baja; tras ROLLBACK vuelve | ✅ 54 dentro → 55 después; 0 filas nuevas |

**Evidencia:** [`screenshots/paso06_transacciones/`](../screenshots/paso06_transacciones/)

---

## T4 – Concurrencia

| Campo | Detalle |
|---|---|
| **Objetivo** | Observar el comportamiento de dos compras simultáneas del último producto en cada nivel de aislamiento. |
| **Preparación** | `04_concurrencia_preparar.sql` (producto 3 con stock = 1). Dos sesiones psql abiertas. |
| **Acción** | Pasos alternados entre sesiones según `04_concurrencia_guia.md`. Verificación con `04_concurrencia_verificar.sql`. |

| Escenario | Esperado | Obtenido |
|---|---|---|
| READ COMMITTED | Sobreventa: 2 pedidos con 1 unidad | ✅ Sobreventa (ejecución manual: 3 pedidos, stock 0) |
| REPEATABLE READ | Sesión B: `could not serialize access`; 1 pedido | ✅ (verificado en entorno de prueba) |
| SERIALIZABLE | Igual que REPEATABLE READ | ✅ (verificado en entorno de prueba) |
| READ COMMITTED + FOR UPDATE | B espera, ve stock 0 y no vende; 1 pedido | ✅ (verificado en entorno de prueba) |

**Solución aplicada:** `sp_registrar_compra` bloquea las filas de inventario con `SELECT ... FOR UPDATE` antes de validar el stock.

**Evidencia:** [`screenshots/paso07_concurrencia/`](../screenshots/paso07_concurrencia/)

---

## T5 – Rendimiento

| Campo | Detalle |
|---|---|
| **Objetivo** | Medir el efecto de los índices con `EXPLAIN ANALYZE` sobre 100.000 pedidos y ~250.000 líneas de detalle. |
| **Preparación** | `05_quitar_indices.sql` (estado "antes"). |
| **Acción** | `05_rendimiento.sql` → `database\05_indexes.sql` → `05_rendimiento.sql`. |

| Consulta | Esperado | Antes | Después | Plan |
|---|---|---|---|---|
| Q1 Pedidos del cliente 1000 | Pasa de Seq Scan a índice | 5,921 ms | 0,834 ms | Seq Scan → Bitmap Index Scan `idx_pedidos_cliente` |
| Q2 Ventas última semana | Usa `idx_pedidos_fecha` | 16,529 ms | 1,589 ms | Seq Scan → Bitmap Index Scan |
| Q3 Ventas del producto 500 | Usa `idx_detalle_producto` | 12,412 ms | 1,182 ms | Parallel Seq Scan → Bitmap Index Scan |
| Q4 Detalle de un pedido (JOIN 5 tablas) | Pagos por índice | 7,039 ms | 0,141 ms | Seq Scan en pagos → Index Scan `idx_pagos_pedido` |

**Evidencia:** [`screenshots/paso08_rendimiento/`](../screenshots/paso08_rendimiento/)

---

## T6 – Vistas

| Campo | Detalle |
|---|---|
| **Objetivo** | Comprobar que las vistas devuelven datos correctos y limitan la exposición de tablas. |
| **Preparación** | `06_views.sql` y `10_roles.sql` ejecutados. |
| **Acción** | Consultas como analista, operador y auditor. |

| Prueba | Esperado | Obtenido |
|---|---|---|
| Analista consulta las 3 vistas | Datos | ✅ |
| `SELECT email` sobre `resumen_compras_cliente` | ERROR: columna no existe (datos personales ocultos) | ✅ column "email" does not exist |
| Analista hace DELETE sobre una vista | ERROR | ✅ cannot delete from view |
| Operador consulta `inventario_bajo` | Permitido | ✅ ~109 productos por reponer |
| Operador consulta `ventas_por_periodo` | Denegado | ✅ permission denied |
| Auditor consulta `resumen_compras_cliente` | Denegado | ✅ permission denied |
| Total de la vista = total de las tablas | Iguales | ✅ |

**Evidencia:** [`screenshots/paso09_vistas/`](../screenshots/paso09_vistas/)

---

## T7 – Funciones y procedimientos

| Campo | Detalle |
|---|---|
| **Objetivo** | Validar que la lógica de compra centralizada en la base es atómica, valida entradas y respeta permisos. |
| **Preparación** | Stock de los productos 1 y 2 fijado en 10. Se ejecuta como `usr_operador`. |
| **Acción** | Compra válida, 7 compras inválidas, cancelaciones y pruebas de permisos. |

| Prueba | Esperado | Obtenido |
|---|---|---|
| Compra válida (producto 1 repetido en el JSON) | Pedido PAGADO, cantidades sumadas, stock 10→7 y 10→9 | ✅ |
| V1 cliente inexistente | ERROR claro | ✅ "El cliente 999999 no existe o está inactivo" |
| V2 sin productos | ERROR | ✅ |
| V3 cantidad 0 | ERROR | ✅ |
| V4 producto inexistente | ERROR | ✅ |
| V5 producto inactivo | ERROR | ✅ |
| V6 método de pago inválido | ERROR | ✅ |
| V7 stock insuficiente en el 2.º producto | ERROR y nada guardado | ✅ diferencias = 0, stock sin cambios |
| Cancelar pedido PAGADO | Estado CANCELADO, stock restituido | ✅ stock vuelve a 10 y 10 |
| Cancelar dos veces / cancelar ENTREGADO | ERROR | ✅ |
| Analista ejecuta `fn_ventas_por_categoria` | Permitido | ✅ 8 categorías |
| Analista ejecuta `sp_registrar_compra` | Denegado | ✅ permission denied for procedure |
| Auditor ejecuta `fn_stock_disponible` | Denegado | ✅ permission denied for function |
| Rango de fechas invertido | ERROR | ✅ |

**Evidencia:** [`screenshots/paso10_funciones/`](../screenshots/paso10_funciones/)

---

## T8 – Auditoría

| Campo | Detalle |
|---|---|
| **Objetivo** | Comprobar que se registra quién modificó datos críticos, cuándo y qué cambió, y que la auditoría no se puede alterar. |
| **Preparación** | `09_triggers.sql` ejecutado. El script inicia sesión como cada usuario con `\connect`. |
| **Acción** | UPDATE de precio, INSERT y DELETE de cliente, UPDATE sin cambios, compra con el procedimiento, cambio de contraseña e intentos de alterar la auditoría. |

| Prueba | Esperado | Obtenido |
|---|---|---|
| UPDATE de precio por `usr_dev` | Evento con precio antes/después | ✅ 980000.00 → 981000.00, usuario usr_dev |
| DELETE de cliente | El registro borrado queda en `datos_anteriores` | ✅ nombre y email recuperables |
| UPDATE sin cambios | Sin evento | ✅ 0 eventos |
| Compra por `usr_operador` | Eventos en pedidos, inventario y pagos | ✅ 4 eventos; stock 57→56 |
| Cambio de contraseña | No se guarda el hash; solo `password_cambiado` | ✅ |
| Auditor borra eventos | Denegado | ✅ permission denied |
| Admin borra / modifica eventos | Denegado por trigger | ✅ "La auditoría no se puede modificar ni borrar" |
| Operador inserta un evento falso | Denegado | ✅ permission denied |

**Evidencia:** [`screenshots/paso11_auditoria/`](../screenshots/paso11_auditoria/)

---

## T9 – Backup y restauración

| Campo | Detalle |
|---|---|
| **Objetivo** | Generar un respaldo, simular un incidente sobre una base experimental y recuperar el servicio. |
| **Preparación** | Base `datamarket` con datos. |
| **Acción** | Ver `09_backup_restauracion.md`: `pg_dump` → restaurar en `datamarket_restaurada` → `09_incidente.sql` → restaurar otra vez → `09_verificar_backup.sql`. |

| Prueba | Esperado | Obtenido |
|---|---|---|
| Backup generado | Archivo en `backup\` | ✅ `datamarket.backup`, 7.092.621 bytes (~7,1 MB) de una base de 82 MB; 4-oct-2026 21:12 |
| Archivo válido | `pg_restore -l` lista el contenido | ✅ Formato CUSTOM, 169 entradas, pg_dump 16.15 |
| Incidente sobre la base principal | Bloqueado por protección del script | ✅ Verificado en entorno de prueba ("PROTECCIÓN: ... estás en datamarket") |
| Incidente sobre la experimental | pedidos, detalles y pagos en 0 | ✅ 100.004 / 249.735 / 108.379 → 0 / 0 / 0; 108.379 DELETE auditados |
| Restauración | Conteos, totales y objetos iguales al original | ✅ Idénticos: 9 tablas, 3 vistas, 23 índices, 7 rutinas, 7 triggers, 25 restricciones; mismos totales de dinero y stock |
| Tiempo de recuperación | Medido | ✅ **3,25 s** (21:14:59.96 → 21:15:03.21) |
| Usuario de aplicación en la base restaurada | Funciona tras `09_post_restauracion.sql` | ✅ `usr_analista` consulta `ventas_por_periodo` |

**Evidencia:** [`screenshots/paso12_backup/`](../screenshots/paso12_backup/) y [`screenshots/paso13_restauracion/`](../screenshots/paso13_restauracion/)

---

## T10 – Diagnóstico (preparación del reto final)

| Campo | Detalle |
|---|---|
| **Objetivo** | Detectar los problemas típicos del reto: permisos excesivos, índices ausentes, consultas lentas, inconsistencias, auditoría desactivada. |
| **Preparación** | Ninguna. Solo lectura. |
| **Acción** | `10_diagnostico.sql` sobre la base sana; luego se inyectaron 8 fallas y se repitió. |

| Falla inyectada | Sección que la detecta | Obtenido |
|---|---|---|
| `GRANT SELECT ON usuarios TO PUBLIC` | 1a | ✅ |
| `GRANT DELETE ON pedidos TO db_analyst` | 1b | ✅ |
| `ALTER ROLE usr_dev SUPERUSER` | 1d | ✅ |
| `GRANT EXECUTE ... sp_cancelar_pedido TO PUBLIC` | 1f | ✅ |
| `DROP INDEX idx_pedidos_cliente` | 2a y 2b | ✅ |
| Total de un pedido alterado | 4a y 4b | ✅ pedido 7: 414401 vs 414400 |
| `DROP CONSTRAINT chk_inventario_stock` | 4d | ✅ |
| Trigger de auditoría de inventario desactivado | 5a | ✅ |

**Evidencia:** [`screenshots/reto_diagnostico/`](../screenshots/reto_diagnostico/). En Docker la base sana dio 0 hallazgos en todas las secciones; la 3a muestra lecturas secuenciales acumuladas por la carga de datos y por la medición sin índices del Paso 8 (ver la explicación en `screenshots/README.md`).
