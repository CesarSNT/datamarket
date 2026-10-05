# Evidencias de ejecución – DataMarket S.A.S.

Capturas del laboratorio, ordenadas por paso del taller. Cada sección indica **qué se ejecutó, qué muestra la captura y qué demuestra**.

- **Entorno:** Windows 11 · Docker Desktop · contenedor `datamarket-postgres` (PostgreSQL 16.15) · VS Code.
- **Fecha de ejecución:** 4 de octubre de 2026.
- **Ejecución final:** las capturas principales de los pasos 3, 5, 6, 9, 10 y 11 corresponden a la **reconstrucción completa** de la base (scripts `01` a `11` en orden) con la versión definitiva de los scripts.
- **Historial:** las carpetas `historial/` guardan la primera ejecución, hecha mientras se construía cada paso. Se conservan como evidencia del proceso.

> **Nota sobre el orden de los mensajes.** En la consola de Windows, `psql` escribe los resultados por la salida estándar y los `ERROR` por la salida de errores. Al mostrarse juntos, a veces un `ERROR` aparece **debajo del título de la prueba siguiente** (por ejemplo, el error de P07 bajo el título de P08). No es una falla: cada prueba produjo el error que le corresponde. El detalle (`DETAIL`) de cada error identifica la restricción.

## Índice

| Paso | Tema | Carpeta |
|---|---|---|
| 0 | Entorno con Docker | `paso00_entorno/` |
| 1 | Diseño del modelo | `paso01_diseno/` |
| 2 | Creación de la base y el esquema | `paso02_creacion/` |
| 3 | Tablas e integridad | `paso03_integridad/` |
| 4 | Datos de prueba | `paso04_datos/` |
| 5 | Seguridad y roles | `paso05_seguridad/` |
| 6 | Transacciones | `paso06_transacciones/` |
| 7 | Concurrencia | `paso07_concurrencia/` |
| 8 | Optimización (EXPLAIN ANALYZE e índices) | `paso08_rendimiento/` |
| 9 | Vistas | `paso09_vistas/` |
| 10 | Funciones y procedimientos | `paso10_funciones/` |
| 11 | Auditoría | `paso11_auditoria/` |
| 12 | Backup | `paso12_backup/` |
| 13 | Incidente y recuperación | `paso13_restauracion/` |
| 14 | API REST | `paso14_api/` |
| Reto | Diagnóstico de salud de la base | `reto_diagnostico/` |
| — | Evidencias opcionales | ver final del documento |

---

## Paso 0 – Entorno con Docker

**1. Archivo `docker/docker-compose.yml`.** Servicio `postgres` con imagen `postgres:16`, contenedor `datamarket-postgres`, base `datamarket`, puerto `5432` y volumen persistente `postgres_data` (en la captura; luego se cambió a `5440:5432`, ver Paso 14).

![docker-compose.yml](paso00_entorno/01_docker_compose_yml.png)

**2. Levantar el entorno:** `docker compose -f docker/docker-compose.yml up -d`. Se descarga la imagen y se crean la red, el volumen y el contenedor.

![docker compose up](paso00_entorno/02_docker_compose_up.png)

**3. Verificación con `docker ps`.** `datamarket-postgres` en estado **Up**, publicado en `0.0.0.0:5432->5432/tcp` (configuración inicial; hoy `5440`).

![docker ps](paso00_entorno/03_docker_ps.png)

---

## Paso 1 – Diseño del modelo

**1. Modelo conceptual en PlantUML** (`docs/01_modelo_conceptual/01_modelo_conceptual.puml`), en notación Chen. Los modelos lógico y físico están en las carpetas vecinas.

![Modelo conceptual en PlantUML](paso01_diseno/01_modelo_conceptual_puml.png)

**2. Diagrama conceptual generado.** Entidades, atributos y relaciones con cardinalidad. La relación M:N `CONTIENE` entre PEDIDO y PRODUCTO lleva sus propios atributos (cantidad, precio_unitario, subtotal).

![Diagrama conceptual](paso01_diseno/02_modelo_conceptual_diagrama.png)

**3. Diccionario de datos** (`docs/diccionario-datos.md`): convenciones y una tabla por cada entidad, con tipo, nulos, clave, default, restricción y descripción.

![Diccionario de datos](paso01_diseno/03_diccionario_datos.png)

---

## Paso 2 – Creación de la base de datos

**1. Script `01_database.sql`.** Borra y crea la base `datamarket` en UTF-8, para poder reconstruirla desde cero.

![01_database.sql](paso02_creacion/01_script_01_database.png)

**2. Script `02_schema.sql`.** Crea el esquema `datamarket` y fija el `search_path`.

![02_schema.sql](paso02_creacion/02_script_02_schema.png)

**3. Ejecución.** `DROP DATABASE`, `CREATE DATABASE`, `CREATE SCHEMA` y `ALTER DATABASE` sin errores.

![Ejecución 01 y 02](paso02_creacion/03_ejecucion_01_02.png)

**4. Verificación en psql.**
- `\l`: la base `datamarket` existe con codificación UTF8.
- `\dn`: el esquema `datamarket` existe.
- `SHOW search_path`: devuelve `datamarket, public`.

![Verificación de base y esquema](paso02_creacion/04_verificacion_base_esquema.png)

---

## Paso 3 – Tablas e integridad

**1 y 2. Scripts.** `03_tables.sql` crea las 9 tablas (PK, tipos, NOT NULL, DEFAULT); `04_constraints.sql` agrega las FK, UNIQUE y CHECK con nombre.

![03_tables.sql](paso03_integridad/01_script_03_tables.png)
![04_constraints.sql](paso03_integridad/02_script_04_constraints.png)

**3 y 4. Ejecución.** 9 `CREATE TABLE` y 11 `COMMENT`; 9 `ALTER TABLE` con las restricciones.

![Ejecución 03_tables](paso03_integridad/03_ejecucion_03_tables.png)
![Ejecución 04_constraints](paso03_integridad/04_ejecucion_04_constraints.png)

**5 a 7. Pruebas de integridad** (`tests/01_pruebas_integridad.sql`, ejecución final).

Resultado:
- El subtotal se calcula solo: 2 × 10.000 = **20.000**.
- **Las 12 operaciones inválidas fueron rechazadas**, cada una por su restricción: `fk_pedidos_cliente`, `chk_productos_precio`, `uq_clientes_email`, `uq_productos_sku`, `chk_inventario_stock`, `chk_detalle_cantidad`, `uq_inventario_producto`, `uq_detalle_pedido_producto`, `chk_pedidos_estado`, columna generada `subtotal`, borrado de cliente con pedidos (RESTRICT) y nombre NULL.
- **P13 (CASCADE):** al borrar el pedido, `detalles_restantes = 0`.
- La limpieza elimina los datos de prueba (IDs 9900001).

![Pruebas de integridad, parte 1](paso03_integridad/05_pruebas_integridad_parte1.png)
![Pruebas de integridad, parte 2](paso03_integridad/06_pruebas_integridad_parte2.png)
![Limpieza](paso03_integridad/07_pruebas_integridad_limpieza.png)

<details>
<summary>Historial: primera versión de las pruebas (IDs 900, antes de cargar datos)</summary>

![Script v1](paso03_integridad/historial/01_script_pruebas_v1.png)
![Pruebas v1, parte 1](paso03_integridad/historial/02_pruebas_v1_parte1.png)
![Pruebas v1, parte 2](paso03_integridad/historial/03_pruebas_v1_parte2.png)

La versión 1 usaba IDs fijos (900). Se reemplazó por IDs altos (9900001) porque, con los datos del Paso 4 cargados, la limpieza podía borrar registros reales.
</details>

---

## Paso 4 – Datos de prueba

**1. Script `11_seed.sql`.** Datos base con nombre y volumen masivo generado con `generate_series()`. Es reproducible gracias a `setseed(0.42)`.

![11_seed.sql](paso04_datos/01_script_11_seed.png)

**2. Ejecución y conteo.**

| Tabla | Registros |
|---|---|
| usuarios | 5 |
| categorias | 8 |
| productos | 1.000 |
| inventario | 1.000 |
| clientes | 10.000 |
| pedidos | 100.000 |
| detalle_pedido | 249.728 |
| pagos | 108.375 |

![Ejecución del seed](paso04_datos/02_ejecucion_seed_conteos.png)

---

## Paso 5 – Seguridad y roles

**1 a 3. Scripts y ejecución.** `10_roles.sql` crea los roles de grupo (`db_*`) y los usuarios de login (`usr_*`), cierra el acceso a PUBLIC y otorga privilegios mínimos.

![10_roles.sql](paso05_seguridad/01_script_10_roles.png)
![02_pruebas_permisos.sql](paso05_seguridad/02_script_pruebas_permisos.png)
![Ejecución 10_roles](paso05_seguridad/03_ejecucion_10_roles.png)

**4 a 6. Pruebas de permisos** (`tests/02_pruebas_permisos.sql`, ejecución final).

| Rol | Permitido ✅ | Denegado (`permission denied`) ✅ |
|---|---|---|
| Analista | Consultar pedidos (100.000) y ventas por estado | Borrar pedidos, modificar precios, insertar clientes, ver `usuarios`, ver `auditoria` |
| Auditor | Consultar la auditoría | Ver clientes, borrar auditoría, crear tablas |
| Operador | Crear pedido y descontar stock (revertidos con ROLLBACK) | Cambiar precio, cambiar email, borrar pagos |
| Developer | Modificar datos, crear y borrar tablas | Alterar la auditoría |
| Admin | Ver usuarios internos y auditoría | — |
| **API (`usr_api`)** | Consultar productos, inventario y pedidos | Leer usuarios, borrar pedidos, leer auditoría, crear tablas. **No es superusuario** (`rolsuper = f`) |

La tabla resumen al final muestra los privilegios de cada rol por tabla y vista.

![Analista y auditor](paso05_seguridad/04_permisos_analista_auditor.png)
![Operador, developer y admin](paso05_seguridad/05_permisos_operador_developer_admin.png)
![API y resumen de privilegios](paso05_seguridad/06_permisos_api_y_resumen.png)

<details>
<summary>Historial: primera ejecución de permisos (antes de agregar vistas y usr_api)</summary>

![Analista v1](paso05_seguridad/historial/01_permisos_v1_analista.png)
![Auditor y operador v1](paso05_seguridad/historial/02_permisos_v1_auditor_operador.png)
![Developer y admin v1](paso05_seguridad/historial/03_permisos_v1_developer_admin.png)
![Resumen v1](paso05_seguridad/historial/04_permisos_v1_resumen.png)
</details>

---

## Paso 6 – Transacciones

**1. Script `tests/03_transacciones.sql`.** El proceso de compra (pedido → detalle → inventario → pago) como una sola unidad.

![Script de transacciones](paso06_transacciones/01_script_transacciones.png)

**2. Casos A y B.**
- **Caso A, compra exitosa (COMMIT):** pedido 100003 en estado **PAGADO**, total **7.550.000**, 2 líneas y pago APROBADO. Stock del producto 1: 57 → 55; producto 2: 70 → 69.
- **Caso B, error a mitad (ROLLBACK):** se piden 100 unidades con stock 4. El paso 3 viola `chk_inventario_stock` y la transacción queda abortada (`current transaction is aborted`). Verificación: `pedido_b_existe = 0`, `detalle_b_existe = 0`, diferencias **0 / 0 / 0**, stock sin cambios (4).

![Casos A y B](paso06_transacciones/02_casos_A_y_B.png)

**3. Caso C, pago rechazado (ROLLBACK manual).** Dentro de la transacción el stock bajó a 54; tras el ROLLBACK vuelve a **55** y no queda ningún dato parcial.

![Caso C](paso06_transacciones/03_caso_C.png)

<details>
<summary>Historial: primera ejecución</summary>

![Transacciones v1, parte 1](paso06_transacciones/historial/01_transacciones_v1_parte1.png)
![Transacciones v1, parte 2](paso06_transacciones/historial/02_transacciones_v1_parte2.png)
</details>

---

## Paso 7 – Concurrencia

**1. Dos sesiones simultáneas en READ COMMITTED.** Izquierda: sesión A; derecha: sesión B. El producto 3 empieza con stock = 1 (`04_concurrencia_preparar.sql`). Ambas sesiones leen **stock 1**, crean su pedido y escriben `stock = 0`.

![Dos sesiones](paso07_concurrencia/01_dos_sesiones_read_committed.png)

**2. Resultado.** `stock = 0` con **3 pedidos creados** para una sola unidad: **sobreventa** (*lost update*). En READ COMMITTED cada sesión decidió vender basándose en un valor que la otra ya estaba cambiando.

![Resultado de sobreventa](paso07_concurrencia/02_resultado_sobreventa.png)

> En esta ejecución, la sesión B insertó dos veces el pedido del cliente 102, por eso aparecen 3 pedidos en lugar de 2. La conclusión es la misma: se vendió más de lo disponible.
>
> **Solución aplicada:** bloquear la fila con `SELECT ... FOR UPDATE` antes de validar el stock. Está implementada en `sp_registrar_compra` (Paso 10). Los escenarios REPEATABLE READ, SERIALIZABLE y FOR UPDATE se documentan en `tests/04_concurrencia_guia.md`.

---

## Paso 8 – Optimización

**Antes (sin índices):** `tests/05_quitar_indices.sql` + `tests/05_rendimiento.sql`.

![Sin índices – Q1](paso08_rendimiento/01_sin_indices_Q1.png)
![Sin índices – Q2](paso08_rendimiento/02_sin_indices_Q2.png)
![Sin índices – Q3 y Q4](paso08_rendimiento/03_sin_indices_Q3_Q4.png)

**Creación de índices:** `database/05_indexes.sql` crea 5 índices y actualiza estadísticas.

![Creación de índices](paso08_rendimiento/04_creacion_indices.png)

**Después (con índices):**

![Índices existentes](paso08_rendimiento/05_con_indices_lista.png)
![Con índices – Q2 y Q3](paso08_rendimiento/06_con_indices_Q2_Q3.png)
![Con índices – Q4](paso08_rendimiento/07_con_indices_Q4.png)

### Resultados medidos

| Consulta | Antes | Después | Mejora | Cambio en el plan |
|---|---|---|---|---|
| Q1 Pedidos del cliente 1000 | 5,921 ms · costo 2987 · descarta 99.991 filas | 0,834 ms · costo 42 | ~70× en costo | Seq Scan → Bitmap Index Scan `idx_pedidos_cliente` |
| Q2 Ventas última semana | 16,529 ms · costo 3805 | 1,589 ms · costo 1605 | ~10× | Seq Scan → Bitmap Index Scan `idx_pedidos_fecha` |
| Q3 Ventas del producto 500 | 12,412 ms · costo 5167 | 1,182 ms · costo 731 | ~10× | Parallel Seq Scan → Bitmap Index Scan `idx_detalle_producto` |
| Q4 Detalle de un pedido (JOIN de 5 tablas) | 7,039 ms · costo 2481 | 0,141 ms · costo 62 | ~50× | Seq Scan en `pagos` (descarta 108.375 filas) → Index Scan `idx_pagos_pedido` |

**Ejecución final (después de recrear el contenedor en el puerto 5440).** Repetición de `05_rendimiento.sql` con los índices creados. Todas las consultas usan su índice; Q1 pasa de un costo de 2987 a 42.

![Final – Q1 y Q2](paso08_rendimiento/08_final_con_indices_Q1_Q2.png)
![Final – Q3 y Q4](paso08_rendimiento/09_final_con_indices_Q3_Q4.png)

> **Sobre los tiempos de esta ejecución.** Q2 (27,9 ms) y Q3 (15,2 ms) tardaron más que en la medición anterior (1,6 ms y 1,2 ms). La causa es que se ejecutaron justo después de recrear el contenedor: la memoria caché estaba vacía y las páginas se leyeron desde disco (*cold cache*). El **plan y el costo estimado no cambian** (Index Scan, costo 1645 frente a 3805 en Q2 y 731 frente a 5167 en Q3); por eso el costo y el tipo de recorrido son la medida más confiable, y los tiempos se comparan con la caché "caliente".

**Consulta de mayor costo:** Q3. Sin índice en `detalle_pedido.producto_id`, PostgreSQL recorrió las ~250.000 líneas de detalle con dos procesos en paralelo para quedarse con 249. El índice compuesto `(pedido_id, producto_id)` no sirve aquí porque `producto_id` es su segunda columna.

---

## Paso 9 – Vistas

**1. Creación de vistas y permisos.** `06_views.sql` crea `ventas_por_periodo`, `inventario_bajo` y `resumen_compras_cliente`; luego `10_roles.sql` otorga el acceso.

![Creación de vistas](paso09_vistas/01_ejecucion_06_views_y_roles.png)

**2 y 3. Pruebas de vistas** (`tests/06_pruebas_vistas.sql`, ejecución final).
- El **analista** consulta las tres vistas: ventas de los últimos 6 meses, inventario bajo y top 5 de clientes.
- `SELECT email` sobre `resumen_compras_cliente` → `column "email" does not exist`: **la vista oculta los datos de contacto**.
- DELETE sobre una vista → rechazado (vista de solo lectura).
- El **operador** ve `inventario_bajo` (**109** productos por reponer), pero se le **deniega** `ventas_por_periodo`.
- Al **auditor** se le deniega `resumen_compras_cliente`.
- **Coherencia:** total de la vista = total de las tablas = **466.547.763.500,00**.

![Pruebas de vistas, parte 1](paso09_vistas/02_pruebas_vistas_parte1.png)
![Pruebas de vistas, parte 2](paso09_vistas/03_pruebas_vistas_parte2.png)

<details>
<summary>Historial: primera ejecución</summary>

![Vistas v1](paso09_vistas/historial/01_pruebas_vistas_v1.png)
</details>

---

## Paso 10 – Funciones y procedimientos

**0. Ejecución de los scripts.** `07_functions.sql` (3 funciones), `08_procedures.sql` (2 procedimientos) y `09_triggers.sql` (función de auditoría, triggers sobre las 6 tablas críticas, trigger de inmutabilidad e índices de auditoría), sin errores.

![Ejecución 07, 08 y 09](paso10_funciones/00_ejecucion_07_08_09.png)

**1. Funciones y compra válida** (`tests/07_pruebas_funciones.sql`, ejecutado como `usr_operador`).
- `fn_stock_disponible(1)` = 10; con el producto 999999 → error controlado.
- `sp_registrar_compra`: pedido **100006 PAGADO**, total **10.750.000**. El producto 1, repetido en el JSON, se consolidó en una sola línea de 3 unidades.

![Funciones y compra válida](paso10_funciones/01_funciones_compra_valida.png)

**2. Compras inválidas y cancelación.**
- **7 casos inválidos rechazados con mensaje claro:** cliente inexistente, sin productos, cantidad 0, producto inexistente, producto inactivo (50), método de pago `BITCOIN` y stock insuficiente en el segundo producto.
- Verificación: diferencias **0 / 0 / 0** y stock sin cambios (7 y 9). **Ningún caso dejó datos parciales.**
- `sp_cancelar_pedido`: el pedido pasa a CANCELADO y el stock vuelve a **10 y 10**.

![Casos inválidos y cancelación](paso10_funciones/02_compra_invalidos_cancelacion.png)

**3. Reglas de cancelación y permisos.**
- Cancelar dos veces, o cancelar un pedido ENTREGADO → rechazado.
- El analista ejecuta `fn_ventas_por_categoria` (8 categorías), pero **no** puede ejecutar `sp_registrar_compra`.
- El auditor **no** puede ejecutar `fn_stock_disponible`.
- Un rango de fechas invertido → error controlado.

![Cancelación y permisos](paso10_funciones/03_cancelacion_permisos.png)

---

## Paso 11 – Auditoría

**1. Acciones** (`tests/08_pruebas_auditoria.sql`). Cada usuario **inicia sesión** con `\connect`:
- `usr_dev` cambia un precio, crea y borra un cliente, y hace un UPDATE sin cambios.
- `usr_operador` registra una compra.
- `postgres` cambia una contraseña.

![Acciones auditadas](paso11_auditoria/01_acciones.png)

**2. Consulta del auditor y protección de la auditoría.**
- **8 eventos registrados** (IDs 30 a 37) con usuario, operación, tabla, registro y fecha.
- Precio del producto 10: **980.000 → 981.000**, por `usr_dev`.
- El cliente borrado queda recuperable en `datos_anteriores` (nombre y email).
- El UPDATE sin cambios **no** generó evento (0).
- La compra dejó 4 eventos (pedido, inventario y pago); stock **10 → 9**.
- La contraseña **no se guarda**: `hash_antes_guardado = f`, `hash_nuevo_guardado = f`, `password_cambiado = true`.
- **Protección:**
  - El auditor no puede borrar eventos.
  - **Ni el administrador** puede borrarlos ni modificarlos: los bloquea el trigger `fn_auditoria_inmutable`.
  - El operador no puede insertar eventos falsos.

![Consulta del auditor y protección](paso11_auditoria/02_consulta_auditor_y_proteccion.png)

---

## Paso 12 – Backup

**1. Generación y verificación del archivo.**
- `pg_dump -F c` dentro del contenedor y `docker cp` hacia `backup\datamarket.backup`.
- **Fecha:** 4 de octubre de 2026, 21:12 (Bogotá) · 02:12:43 UTC.
- **Tamaño:** **7.092.621 bytes (~7,1 MB)**, comprimido con gzip, para una base de 82 MB.
- `pg_restore -l` lee el archivo sin errores: formato CUSTOM, 169 entradas, generado con pg_dump 16.15. Eso prueba que el backup es válido y restaurable.

![dir backup y pg_restore -l](paso12_backup/01_dir_backup_y_pg_restore_lista.png)

**2 a 4. Contenido del backup.** La lista incluye el esquema, las 9 tablas con sus datos, las 3 vistas, las 7 funciones y procedimientos, los permisos (ACL), los 23 índices, las restricciones y los 7 triggers.

![pg_restore -l parte 2](paso12_backup/02_pg_restore_lista_parte2.png)
![pg_restore -l parte 3](paso12_backup/03_pg_restore_lista_parte3.png)
![pg_restore -l parte 4](paso12_backup/04_pg_restore_lista_parte4.png)

**5. Huella de la base original** (`tests/09_verificar_backup.sql` sobre `datamarket`). Es la referencia contra la que se compara la restauración.

![Huella original](paso12_backup/05_huella_original.png)

**Procedimiento:**
```
docker exec datamarket-postgres pg_dump -U postgres -d datamarket -F c -f /tmp/datamarket.backup
docker cp datamarket-postgres:/tmp/datamarket.backup backup\datamarket.backup
dir backup
docker exec datamarket-postgres pg_restore -l /tmp/datamarket.backup
```

---

## Paso 13 – Incidente controlado y recuperación

**1. Base experimental e incidente.** Se crea `datamarket_restaurada` desde el archivo del proyecto, se aplica `09_post_restauracion.sql` y se simula el incidente:
- **Antes:** 100.004 pedidos, 249.735 detalles y 108.379 pagos.
- **Incidente:** `DELETE FROM pagos` sin WHERE + `TRUNCATE pedidos CASCADE`.
- **Después:** **0 / 0 / 0**. Las vistas quedan vacías (0 meses con ventas): el servicio está caído.
- La auditoría registró los **108.379 DELETE** de pagos con usuario y hora. El TRUNCATE no queda auditado; es una limitación documentada (DT-24).

![Restauración e incidente](paso13_restauracion/01_restauracion_e_incidente.png)

**2. Recuperación con tiempo medido.** DROP + CREATE de la base, `pg_restore` y post-restauración: de **21:14:59.96** a **21:15:03.21** = **3,25 segundos**.

![Recuperación](paso13_restauracion/02_recuperacion_tiempo.png)

**3. Comprobación: la base restaurada es idéntica a la original.**

| Comprobación | Original (Paso 12) | Restaurada |
|---|---|---|
| pedidos / detalle / pagos | 100.004 / 249.735 / 108.379 | 100.004 / 249.735 / 108.379 ✅ |
| clientes / productos / inventario | 10.000 / 1.000 / 1.000 | 10.000 / 1.000 / 1.000 ✅ |
| auditoría / categorías / usuarios | 38 / 8 / 5 | 38 / 8 / 5 ✅ |
| Suma de pedidos = suma del detalle | 507.695.758.400,00 | 507.695.758.400,00 ✅ |
| Suma de pagos | 549.418.574.900,00 | 549.418.574.900,00 ✅ |
| Stock total | 225.647 | 225.647 ✅ |
| Tablas / vistas / índices / rutinas / triggers / restricciones | 9 / 3 / 23 / 7 / 7 / 25 | 9 / 3 / 23 / 7 / 7 / 25 ✅ |
| Totales descuadrados, productos sin inventario, stock negativo | 0 / 0 / 0 | 0 / 0 / 0 ✅ |
| Ventas por período (últimos 3 meses) | iguales | iguales ✅ |

> El tamaño baja de 82 MB a 69 MB: la restauración reescribe las tablas sin el espacio muerto que dejan las actualizaciones y borrados (*bloat*). Los datos son idénticos.

![Verificación de la restaurada](paso13_restauracion/03_verificacion_restaurada.png)

**4. Un usuario de la aplicación trabaja en la base restaurada.** `usr_analista` consulta `ventas_por_periodo` sin errores. Esto confirma que `09_post_restauracion.sql` aplicó correctamente el `search_path` y los permisos de conexión que `pg_dump` no guarda.

![Usuario de aplicación en la restaurada](paso13_restauracion/04_usuario_app_en_restaurada.png)

---

## Paso 14 – API REST

API en Node.js + Express (`api/`), con capas rutas → servicio → repositorio, conectada a PostgreSQL con **`usr_api`** (privilegios mínimos). Las pruebas se hicieron con Postman.

**1. Arranque.** La API escucha en `http://localhost:3000` y se conecta como `usr_api`, no como `postgres` ni `usr_admin`.

![Arranque de la API](paso14_api/01_arranque_api_usr_api.png)

> El aviso `DeprecationWarning` de la librería `pg` no afecta el funcionamiento.

**2. Salud de la conexión** (`GET /health`): `"estado": "ok"`, `"usuario_bd": "usr_api"`, base `datamarket`.

![Health](paso14_api/02_health.png)

**3 y 4. Consultar productos.**
- `GET /api/productos?categoria=1` → **200**, productos activos de Tecnología con su stock.
- `GET /api/productos/3` → **200**, producto con descripción, precio, stock y stock mínimo.

![Productos por categoría](paso14_api/03_productos_por_categoria.png)
![Producto por id](paso14_api/04_producto_por_id.png)

**5 y 6. Consultar inventario.**
- `GET /api/inventario/3` → **200**, stock 269 y mínimo 5.
- `GET /api/inventario/bajo` → **200**, productos por reponer, servidos desde la vista `inventario_bajo` del Paso 9.

![Inventario de un producto](paso14_api/05_inventario_producto.png)
![Inventario bajo](paso14_api/06_inventario_bajo.png)

**7 y 8. Consultar pedidos.**
- `GET /api/pedidos?cliente_id=1` → **200**, pedidos del cliente del más reciente al más antiguo, incluidos los creados en las pruebas de los Pasos 6 y 10 (100003 PAGADO, 100006 CANCELADO).
- `GET /api/pedidos/1` → **200**, el pedido con su detalle (productos, cantidad, precio unitario copiado, subtotal) y sus pagos.

![Pedidos por cliente](paso14_api/07_pedidos_por_cliente.png)
![Detalle de un pedido](paso14_api/08_detalle_pedido.png)

**9 y 10. Manejo de errores.**
- `GET /api/pedidos/abc` → **400 Bad Request**: "id debe ser un número entero positivo". La API valida el formato antes de consultar la base.
- `GET /api/pedidos/99999999` → **404 Not Found**: "El pedido 99999999 no existe".

![Error 400](paso14_api/09_error_400_id_invalido.png)
![Error 404](paso14_api/10_error_404_pedido_inexistente.png)

**11. Crear pedido** (`POST /api/pedidos`, cliente 1: 2 unidades del producto 1 y 1 del producto 2, pago con TARJETA) → **201 Created**. Se creó el pedido **100008** en estado **PAGADO** con total **7.550.000**; el detalle conserva el precio unitario copiado del producto (3.200.000 × 2 = 6.400.000). La API no repite la lógica: llama a `sp_registrar_compra`, que valida, bloquea el stock, crea el detalle, descuenta inventario y registra el pago en una sola transacción.

![Crear pedido 201](paso14_api/11_crear_pedido_201.png)

**12. Crear pedido sin stock suficiente** (`POST /api/pedidos` pidiendo 9.999 unidades del producto 1) → **409 Conflict**: "Stock insuficiente para el producto 1: disponible 9, solicitado 9999" (código PostgreSQL `23514`). El procedimiento `sp_registrar_compra` rechazó la compra completa: el producto 2 del mismo pedido tampoco se descontó, porque la operación es atómica.

![Error 409 stock insuficiente](paso14_api/12_error_409_stock_insuficiente.png)

**13. La compra de la API quedó auditada.** Consulta a `auditoria` filtrando por `usuario = 'usr_api'`: **5 eventos** (IDs 39 a 43), todos de la compra del pedido 100008:
- `pedidos`: INSERT (creación) y UPDATE (total y estado PAGADO);
- `inventario`: dos UPDATE, de los productos 1 y 2;
- `pagos`: INSERT (pago 108379).

El evento registra **el usuario real de la conexión** (`usr_api`), lo que permite distinguir las operaciones de la API de las hechas por personas.

![Auditoría de la API](paso14_api/13_auditoria_usr_api.png)

> **Hallazgo durante la puesta en marcha.** Al principio la API respondía `password authentication failed for user "usr_api"`. La causa: los PostgreSQL 17 y 18 instalados en Windows ocupaban los puertos 5432 y 5433, así que la API se conectaba a ellos y no al contenedor (el mensaje en español delataba al servidor de Windows). Los comandos `docker exec` no se veían afectados porque entran directo al contenedor. **Solución:** publicar el contenedor en el puerto **5440** (`"5440:5432"` en `docker-compose.yml` y `DB_PORT=5440` en `api/.env`).

---

## Reto final – Diagnóstico de salud de la base

`tests/10_diagnostico.sql` revisa la base **sin modificarla** y busca los problemas típicos del reto: permisos excesivos, índices ausentes, consultas lentas, inconsistencias de datos y auditoría desactivada. Sirve para dos momentos: **antes** de corregir (evidencia del problema) y **después** (comprobación de la solución).

**1. Permisos, índices y consultas.**
- **1a a 1f, permisos:** 0 hallazgos. Ninguna tabla ni rutina está abierta a PUBLIC; ningún rol de lectura puede escribir; ningún usuario de aplicación tiene privilegios de administración. En 1d solo aparece `postgres`, que es el superusuario esperado.
- **2a a 2c, índices:** 0 hallazgos. Todas las claves foráneas tienen índice y los 5 índices del Paso 8 existen y son válidos.
- **3b y 3c:** sin consultas lentas en curso ni sesiones bloqueadas.

![Diagnóstico: permisos, índices y consultas](reto_diagnostico/01_diagnostico_permisos_indices_consultas.png)

**Sobre la sección 3a (no es una falla).** Aparecen `detalle_pedido` (28 lecturas secuenciales frente a 18 por índice) y `pagos` (15 frente a 3). Los contadores acumulan todo lo ocurrido desde que se crearon las tablas, e incluyen:
- la carga masiva de `11_seed.sql`, que recorre las tablas completas para calcular totales y pagos;
- la medición **sin índices** del Paso 8, hecha a propósito para mostrar el "antes";
- los conteos completos de las pruebas (`count(*)` sobre toda la tabla).

Con los índices ya creados, las consultas puntuales usan Index Scan, como se ve en el Paso 8. En producción esta sección se lee después de reiniciar las estadísticas (`SELECT pg_stat_reset();`) y dejar pasar un período de uso real.

**2. Datos y auditoría.**
- **4a, inconsistencias:** todo en 0. No hay totales descuadrados, pedidos sin productos, pedidos pagados sin pago aprobado, cobros de más, productos sin inventario ni stock negativo.
- **4b a 4d:** no hay pedidos descuadrados, restricciones desactivadas ni restricciones faltantes.
- **5a y 5b, auditoría:** las 6 tablas críticas tienen su trigger activo y la auditoría sigue siendo inmutable.
- **5c:** últimos eventos registrados (IDs 29 a 38), con el usuario real de cada operación.

![Diagnóstico: datos y auditoría](reto_diagnostico/02_diagnostico_datos_auditoria.png)

> **Validación del diagnóstico.** En el entorno de prueba se inyectaron 8 fallas a propósito y el script las detectó todas. Detalle en `tests/README.md`, sección T10.

---

## Evidencias opcionales

Todas las evidencias obligatorias del taller están completas. Queda, como complemento opcional:

| Paso | Qué capturar | Guía |
|---|---|---|
| 7 | Escenarios REPEATABLE READ, SERIALIZABLE y FOR UPDATE (la solución a la sobreventa) | `tests/04_concurrencia_guia.md` |
