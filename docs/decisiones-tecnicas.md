# Decisiones técnicas – DataMarket S.A.S.

Cada decisión indica **qué se eligió, qué alternativas había, por qué y qué consecuencias tiene**. La evidencia de cada una está en `tests/` y `screenshots/`.

## Índice

| # | Área | Decisión |
|---|---|---|
| DT-01 | Entorno | PostgreSQL 16 en Docker |
| DT-02 | Estructura | Esquema propio `datamarket` |
| DT-03 | Tipos | `NUMERIC(12,2)` para dinero |
| DT-04 | Tipos | `BIGSERIAL` para claves primarias |
| DT-05 | Tipos | `TIMESTAMPTZ` para fechas |
| DT-06 | Tipos | `CHECK` en lugar de `ENUM` para estados |
| DT-07 | Modelo | Inventario en tabla separada de productos |
| DT-08 | Modelo | Precio copiado en `detalle_pedido` |
| DT-09 | Modelo | Subtotal como columna generada |
| DT-10 | Modelo | Pagos 1:N con pedidos |
| DT-11 | Integridad | `RESTRICT` por defecto, `CASCADE` solo en el detalle |
| DT-12 | Integridad | Borrado lógico con `activo` |
| DT-13 | Integridad | Restricciones con nombre |
| DT-14 | Seguridad | Roles de grupo + usuarios de login |
| DT-15 | Seguridad | `UPDATE` por columna para el operador |
| DT-16 | Seguridad | Revocar `EXECUTE` a PUBLIC (`ALL ROUTINES`) |
| DT-17 | Seguridad | Contraseñas solo para laboratorio |
| DT-18 | Concurrencia | READ COMMITTED + `SELECT ... FOR UPDATE` |
| DT-19 | Lógica | Compra en un procedimiento almacenado |
| DT-20 | Rendimiento | Índices sobre claves foráneas usadas en consultas |
| DT-21 | Rendimiento | Índices descartados |
| DT-22 | Vistas | Vistas que ocultan datos personales |
| DT-23 | Auditoría | Trigger genérico `SECURITY DEFINER` con `session_user` |
| DT-24 | Auditoría | Auditoría inmutable y sin contraseñas |
| DT-25 | Auditoría | La carga inicial no se audita |
| DT-26 | Respaldo | `pg_dump -F c` + script de post-restauración |
| DT-27 | API | Node.js/Express en capas, con `usr_api` |
| DT-28 | Datos de prueba | Volumen masivo reproducible |
| DT-29 | Entorno | Contenedor publicado en el puerto 5440 |

---

## Entorno y estructura

### DT-01 – PostgreSQL 16 en Docker
- **Alternativas:** PostgreSQL instalado en Windows.
- **Justificación:** el mismo entorno en cualquier máquina, levantado con un solo comando. Además, el equipo ya tenía PostgreSQL 17 y 18 locales con otras bases; el contenedor lo aísla.
- **Consecuencias:** requiere Docker Desktop abierto. Los datos persisten en el volumen `postgres_data`.

### DT-02 – Esquema propio `datamarket`
- **Alternativas:** usar el esquema `public`.
- **Justificación:** permite otorgar permisos por bloque (`GRANT ... ON ALL TABLES IN SCHEMA datamarket`) y separa los objetos de negocio de lo que crean las extensiones en `public`.
- **Consecuencias:** se configura `search_path` en la base. Ese ajuste **no** viaja en el backup (ver DT-26).

## Tipos de datos

### DT-03 – `NUMERIC(12,2)` para dinero
- **Alternativas:** `FLOAT`, `REAL`, `MONEY`.
- **Justificación:** `FLOAT` guarda aproximaciones binarias (0,1 + 0,2 ≠ 0,3), lo que produce descuadres al sumar dinero. `MONEY` depende de la configuración regional. `NUMERIC` es exacto.
- **Consecuencias:** cálculos algo más lentos que con `FLOAT`, irrelevante a esta escala. La API devuelve los montos como texto (`"7550000.00"`) para no perder precisión en JavaScript.

### DT-04 – `BIGSERIAL` para claves primarias
- **Alternativas:** `SERIAL` (entero de 4 bytes), UUID.
- **Justificación:** `SERIAL` se agota en ~2.100 millones, un límite alcanzable en pedidos o auditoría. UUID ocupa el doble y fragmenta los índices.
- **Consecuencias:** los IDs no son transaccionales: un `ROLLBACK` deja huecos en la numeración (comprobado en el Paso 6). Es normal.

### DT-05 – `TIMESTAMPTZ` para fechas
- **Justificación:** guarda el instante exacto con zona horaria. Evita errores al comparar fechas entre servidores, el contenedor (UTC) y clientes (Bogotá, UTC−5).
- **Excepción:** `auditoria.fecha` usa `TIMESTAMP`, tal como lo define el taller.

### DT-06 – `CHECK` en lugar de `ENUM` para estados
- **Alternativas:** tipo `ENUM`, tabla catálogo de estados.
- **Justificación:** agregar o quitar un valor es un simple cambio de la restricción, mientras que quitar un valor de un `ENUM` no es posible sin recrear el tipo. Con 5 estados fijos, una tabla catálogo sería excesiva.

## Modelo

### DT-07 – Inventario en tabla separada de productos (1:1)
- **Alternativas:** columna `stock` dentro de `productos`.
- **Justificación:** el catálogo cambia poco y el stock cambia en cada compra. Separarlos hace que el bloqueo `FOR UPDATE` de una compra no bloquee la fila del producto (catálogo, precios), y que la auditoría de stock no se mezcle con cambios del catálogo.
- **Consecuencias:** un JOIN adicional para mostrar productos con stock. Se garantiza el 1:1 con `UNIQUE (producto_id)`.

### DT-08 – Precio copiado en `detalle_pedido`
- **Justificación:** si un producto cambia de precio, los pedidos históricos deben conservar el precio con el que se vendieron. Calcularlo con un JOIN al precio actual falsearía los reportes.
- **Consecuencias:** el dato se repite a propósito (desnormalización controlada); es un hecho histórico, no una copia del precio actual.

### DT-09 – Subtotal como columna generada
- **Justificación:** `GENERATED ALWAYS AS (cantidad * precio_unitario) STORED` hace imposible que el subtotal no cuadre. Intentar escribirlo a mano da error (prueba P10).

### DT-10 – Pagos 1:N con pedidos
- **Justificación:** un pedido puede tener intentos rechazados antes del aprobado. Con 1:1 se perdería ese historial.

## Integridad

### DT-11 – `ON DELETE RESTRICT` por defecto y `CASCADE` solo en el detalle
- **Justificación:**
  - Borrar un cliente, producto o categoría con historial destruiría información contable, así que se impide (RESTRICT).
  - El detalle no tiene sentido sin su pedido, así que se borra con él (CASCADE).
- **Evidencia:** pruebas P11 y P13.

### DT-12 – Borrado lógico con `activo`
- **Justificación:** como RESTRICT impide borrar productos y clientes con pedidos, se desactivan. El procedimiento de compra rechaza productos inactivos y las vistas los excluyen.

### DT-13 – Restricciones con nombre
- **Justificación:** el error dice exactamente qué regla se violó (`chk_inventario_stock` en lugar de un nombre automático), y cada restricción se mapea a una regla de negocio (RN-01 a RN-14 en el diccionario). Además, el diagnóstico del reto puede detectar si falta una restricción por su nombre.

## Seguridad

### DT-14 – Roles de grupo + usuarios de login
- **Justificación:** los permisos se definen una vez por función (`db_analyst`). Dar acceso a una persona nueva es un solo `GRANT db_analyst TO nuevo_usuario`, y revocarlo, otro.

### DT-15 – `UPDATE` por columna para el operador
- **Justificación:** el operador debe poder mover stock y cambiar estados, pero no precios ni emails. `GRANT UPDATE (stock, ultima_actualizacion) ON inventario` lo permite sin abrir el resto de columnas.

### DT-16 – Revocar `EXECUTE` a PUBLIC con `ALL ROUTINES`
- **Hallazgo:** PostgreSQL otorga `EXECUTE` a PUBLIC en toda función nueva. Además, `REVOKE ... ON ALL FUNCTIONS` **no incluye procedimientos**. Antes de corregirlo, el analista podía invocar `sp_registrar_compra`; solo lo detenía la falta de permisos sobre las tablas.
- **Decisión:** `REVOKE EXECUTE ON ALL ROUTINES ... FROM PUBLIC` y privilegios por defecto para rutinas futuras. Luego se otorga `EXECUTE` explícito solo a quien lo necesita.

### DT-17 – Contraseñas solo para laboratorio
- Las contraseñas de `10_roles.sql` y `.env.example` existen para que el laboratorio sea reproducible. En producción irían en variables de entorno o en un gestor de secretos, nunca en el repositorio.

## Concurrencia y lógica

### DT-18 – READ COMMITTED + `SELECT ... FOR UPDATE`
- **Problema observado (Paso 7):** en READ COMMITTED, dos sesiones leyeron stock 1 y ambas vendieron (*lost update*).
- **Alternativas evaluadas:**
  - REPEATABLE READ / SERIALIZABLE: evitan la sobreventa abortando la segunda transacción, pero obligan a la aplicación a reintentar.
  - UPDATE condicional (`... WHERE stock >= n`): correcto, pero con varios productos por pedido complica los mensajes de error.
- **Decisión:** bloquear las filas de inventario con `FOR UPDATE` antes de validar. La segunda compra espera y luego ve el stock real.
- **Detalle:** se bloquean en orden de `producto_id` para evitar interbloqueos (*deadlocks*) entre compras con los mismos productos.
- **Respaldo:** `chk_inventario_stock (stock >= 0)` es la última barrera; aunque algo falle, la base nunca acepta stock negativo.

### DT-19 – Compra en un procedimiento almacenado
- **Justificación:**
  - **Atomicidad:** la compra completa es una transacción; si la API se cae a mitad, no quedan datos parciales.
  - **Un solo lugar para las reglas:** cualquier cliente (API, app móvil, proceso batch) usa la misma lógica.
  - **Concurrencia:** el bloqueo vive junto a los datos.
  - **Menos tráfico:** un `CALL` en lugar de 6 o 7 consultas.
  - **Seguridad:** se ejecuta con los permisos de quien lo llama (`SECURITY INVOKER`), así que el operador no gana privilegios extra.
- **Consecuencias:** la lógica en PL/pgSQL es más difícil de probar con herramientas de la aplicación; se compensa con `tests/07_pruebas_funciones.sql`. El procedimiento no hace `COMMIT` interno, para que quien lo llama pueda incluirlo en una transacción mayor.

## Rendimiento

### DT-20 – Índices sobre claves foráneas usadas en consultas
PostgreSQL crea índices para PK y UNIQUE, pero **no** para FK.

| Índice | Consulta que acelera | Antes → después (Docker) |
|---|---|---|
| `idx_pedidos_cliente` | Historial de pedidos de un cliente (API) | 5,9 ms → 0,83 ms (Seq Scan descartando 99.991 filas → Index Scan) |
| `idx_pedidos_fecha` | Ventas por período | 16,5 ms → 1,6 ms |
| `idx_detalle_producto` | Ventas de un producto | 12,4 ms → 1,2 ms |
| `idx_pagos_pedido` | Pagos de un pedido (JOIN de 5 tablas) | 7,0 ms → 0,14 ms |
| `idx_productos_categoria` | Catálogo por categoría (API) | — |

No se creó un índice sobre `detalle_pedido(pedido_id)`: el UNIQUE `(pedido_id, producto_id)` ya lo cubre porque empieza por esa columna.

### DT-21 – Índices descartados
- `inventario(stock)`: tabla pequeña (1.000 filas) cuyo stock cambia en cada compra; el índice costaría más de lo que ahorra.
- `pedidos(estado)`: solo 5 valores (baja selectividad); filtrar por estado devuelve demasiadas filas para que convenga el índice.

## Vistas

### DT-22 – Vistas que ocultan datos personales
- `resumen_compras_cliente` no expone email, teléfono ni dirección; el analista hace sus reportes sin acceso a datos de contacto.
- `inventario_bajo` se otorga también al operador, para reponer stock sin acceso a reportes de ventas.

## Auditoría

### DT-23 – Trigger genérico `SECURITY DEFINER` con `session_user`
- **Justificación:**
  - Una sola función audita las 6 tablas críticas.
  - Al ser `SECURITY DEFINER`, escribe en `auditoria` con los permisos de su dueño. **Ningún rol** de la aplicación tiene INSERT sobre `auditoria`, así que nadie puede fabricar eventos.
  - Se registra `session_user`, el usuario con el que se inició sesión, porque dentro de una función `SECURITY DEFINER` el `current_user` sería el dueño de la función.
- **Limitación:** si la API atiende a muchos usuarios finales, todos aparecen como `usr_api`. Para identificar a la persona habría que pasar su identificador con `set_config` en cada petición.

### DT-24 – Auditoría inmutable y sin contraseñas
- Un trigger `BEFORE UPDATE OR DELETE OR TRUNCATE` sobre `auditoria` rechaza cualquier alteración, **incluso del administrador**.
- `password_hash` se elimina del evento; solo queda `password_cambiado: true`.
- Un UPDATE que no cambia nada no genera evento.
- **Limitación:** `TRUNCATE` sobre las tablas auditadas no dispara triggers por fila. Por eso solo `db_admin` tiene ese privilegio.

### DT-25 – La carga inicial no se audita
- `11_seed.sql` desactiva temporalmente los triggers de usuario (`DISABLE TRIGGER USER`). Así se evitan ~320.000 eventos que no corresponden a operaciones reales. Las FK y CHECK siguen validando durante la carga.

## Respaldo

### DT-26 – `pg_dump -F c` + script de post-restauración
- **Justificación:** el formato custom es comprimido (7,1 MB para una base de 82 MB), se verifica con `pg_restore -l` y permite restaurar objetos selectivamente.
- **Hallazgos:**
  - El backup **no** incluye los roles ni la configuración de la base (`search_path`, `GRANT CONNECT`). Sin `09_post_restauracion.sql`, la aplicación recibe `relation "pedidos" does not exist`.
  - El incidente se simula sobre una base experimental y el script se niega a ejecutarse sobre `datamarket`.

## API

### DT-27 – Node.js/Express en capas, con `usr_api`
- **Capas:** rutas (HTTP) → servicio (validación de formato) → repositorio (único lugar con SQL).
- **Conexión:** `usr_api` hereda `db_operator`; no puede borrar, ni leer usuarios o auditoría, ni crear tablas (verificado en `tests/02_pruebas_permisos.sql`).
- **Crear pedido** llama a `sp_registrar_compra`; la API no duplica reglas de negocio.
- **Consultas parametrizadas** contra la inyección SQL. Los errores de PostgreSQL se traducen a HTTP: 400, 404, 409 y 403.

## Datos de prueba

### DT-28 – Volumen masivo reproducible
- 100.000 pedidos y ~250.000 líneas de detalle generados con `generate_series()`, para que `EXPLAIN ANALYZE` muestre diferencias reales.
- `setseed(0.42)` hace que los datos "aleatorios" sean idénticos en cada ejecución, de modo que las mediciones son comparables.

### DT-29 – Contenedor publicado en el puerto 5440
- **Problema detectado:** la API fallaba con `password authentication failed for user "usr_api"`. Los PostgreSQL 17 y 18 instalados en Windows ocupaban los puertos 5432 y 5433, y `localhost:5432` llegaba a esos servidores, donde `usr_api` no existe. La pista fue que el error salía en español (configuración del PostgreSQL de Windows) y no en inglés (contenedor).
- **Decisión:** publicar el contenedor como `"5440:5432"` y usar `DB_PORT=5440` en la API.
- **Consecuencias:** los comandos `docker exec` no cambian porque entran directo al contenedor; las conexiones externas (API, pgAdmin, DBeaver) usan `localhost:5440`. Lección: verificar con `netstat -ano | findstr :PUERTO` que el puerto esté libre antes de publicar un contenedor.

---

# Preguntas de reflexión técnica

**1. ¿Qué reglas deben garantizarse en la base y cuáles en la aplicación?**
En la base, todo lo que protege la consistencia:
- integridad referencial, unicidad (email, SKU), dominios (precio > 0, stock ≥ 0, estados válidos);
- atomicidad de la compra y control de concurrencia;
- control de acceso y auditoría.

La razón es que la base es el único punto por el que pasan **todos** los clientes, incluido alguien con psql. En la aplicación queda la validación de formato para responder rápido, la experiencia de usuario, la paginación y la traducción de errores. Si la aplicación olvida una validación, la base la atrapa; si la base no la tiene, nadie la atrapa.

**2. ¿Qué problema de concurrencia encontraron y cómo lo resolvieron?**
Sobreventa por *lost update*. En READ COMMITTED, dos sesiones leyeron stock 1 del mismo producto y ambas vendieron; el stock terminó en 0 con más de un pedido. Se resolvió con `SELECT ... FOR UPDATE` en orden de `producto_id` dentro de `sp_registrar_compra`, más el CHECK `stock >= 0` como última barrera. REPEATABLE READ y SERIALIZABLE también lo evitan, pero exigen reintentos en la aplicación (DT-18).

**3. ¿Qué consulta presentó mayor costo y por qué?**
Sin índices, "unidades vendidas de un producto" (costo estimado 5.167, 12,4 ms). PostgreSQL recorrió las ~250.000 filas de `detalle_pedido` con dos procesos paralelos para quedarse con 249. El índice compuesto existente no servía porque `producto_id` es su segunda columna. En tiempo real, la más lenta fue "ventas de la última semana" (16,5 ms), por el recorrido completo de 100.000 pedidos más el ordenamiento.

**4. ¿Por qué eligieron cada índice?**
Ver DT-20 y DT-21. Cada índice corresponde a una FK usada en un filtro o JOIN frecuente, y su efecto se midió con `EXPLAIN ANALYZE`. Se descartaron los que no compensaban su costo de escritura o tenían baja selectividad.

**5. ¿Qué usuario debería tener acceso a cada objeto?**
Ver la matriz de `docs/arquitectura.md`, sección 7, y la tabla resumen de `tests/02_pruebas_permisos.sql`. El principio es el mínimo privilegio:
- el analista solo lee datos de negocio;
- el operador y la API registran compras pero nunca borran;
- el auditor solo ve la auditoría;
- el developer no altera la auditoría;
- nadie, ni el administrador, puede modificar los eventos registrados.

**6. ¿Qué operaciones deben ser auditadas?**
Cambios de precio y de estado de productos; todo movimiento de stock; creación, cambios de estado y cancelación de pedidos; registro y cambio de estado de pagos; cambios en datos de clientes; altas, cambios de rol y contraseñas de usuarios internos. Es decir, todo lo que afecta dinero, inventario, datos personales o accesos. No se audita el catálogo de categorías ni el detalle (inmutable y cubierto por el evento del pedido).

**7. ¿Qué ocurriría si se pierde el servidor de base de datos?**
- Sin backup, se pierde todo el negocio: pedidos, pagos, clientes y auditoría.
- Con el backup actual:
  1. se levanta un contenedor nuevo con Docker Compose;
  2. se ejecuta `10_roles.sql`, porque los roles no viajan en el backup;
  3. se restaura con `pg_restore`;
  4. se aplica `09_post_restauracion.sql`.
- Se pierde lo ocurrido **después** del último backup. Para reducir esa pérdida haría falta archivado continuo de WAL (recuperación a un punto en el tiempo) o una réplica, y copias del backup fuera de la máquina.

**8. ¿Cuánto tiempo necesitan para recuperar el servicio con el backup realizado?**
**3,25 segundos** para restaurar la base (medido en el Paso 13: de 21:14:59.96 a 21:15:03.21), incluyendo crear la base, `pg_restore` de un backup de 7,1 MB y la post-restauración. Con la verificación (`09_verificar_backup.sql`, unos segundos más) y, en un servidor nuevo, levantar el contenedor y ejecutar `10_roles.sql`, el servicio queda disponible en **menos de 5 minutos**. El tiempo crece con el tamaño de la base, sobre todo por la recreación de índices.

**9. ¿Qué decisiones cambiarían si el sistema pasara de 1.000 a 10 millones de registros?**
- **Particionar** `pedidos`, `detalle_pedido` y `auditoria` por fecha (mensual), para consultar y archivar por períodos.
- Vistas materializadas para los reportes (`ventas_por_periodo`), actualizadas periódicamente.
- Revisar índices con `pg_stat_statements` y uso real, y considerar índices parciales (por ejemplo, solo pedidos no cancelados).
- Backups incrementales y archivado de WAL en lugar de un solo `pg_dump`.
- Réplicas de lectura para analistas, separadas de la operación.
- Pool de conexiones (PgBouncer) delante de la API.
- Cargas masivas con `COPY` y auditoría asíncrona o resumida si el volumen de eventos lo exige.

**10. ¿Qué decisiones de diseño afectan más el rendimiento y la seguridad?**
- **Rendimiento:**
  - índices sobre las FK (diferencias de 10× a 50× medidas);
  - separar inventario de productos para reducir bloqueos;
  - el procedimiento de compra (una sola llamada);
  - el costo de la auditoría por fila en cada escritura.
- **Seguridad:**
  - roles de mínimo privilegio con revocación a PUBLIC (incluido `EXECUTE`);
  - que la API no use el administrador;
  - la auditoría inmutable escrita mediante `SECURITY DEFINER`;
  - vistas que ocultan datos personales.
