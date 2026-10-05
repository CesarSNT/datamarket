# Diccionario de datos – DataMarket S.A.S.

**Motor:** PostgreSQL 16  
**Base de datos:** `datamarket`  
**Esquema:** `datamarket`  
**Modelos relacionados:** `01_modelo_conceptual.puml`, `02_modelo_logico.puml`, `03_modelo_fisico.puml`

## Convenciones

| Símbolo / término | Significado |
|---|---|
| **PK** | Clave primaria |
| **FK** | Clave foránea |
| **UK** | Restricción `UNIQUE` |
| **Nulo = No** | Columna `NOT NULL` |
| **Default** | Valor asignado si no se envía uno |
| **RESTRICT** | `ON DELETE RESTRICT`: no se puede borrar el registro padre si tiene hijos |
| **CASCADE** | `ON DELETE CASCADE`: al borrar el padre se borran los hijos |

- Nombres de tablas y columnas en minúscula y `snake_case`.
- Todas las tablas usan `id BIGSERIAL` como clave primaria.
- Los valores monetarios usan `NUMERIC(12,2)` (nunca `FLOAT`, para evitar errores de redondeo).
- Las fechas usan `TIMESTAMPTZ` (con zona horaria), salvo en `auditoria`, que sigue la definición del taller.

---

## 1. `clientes`

**Descripción:** Personas que realizan compras en la plataforma.

| Columna | Tipo | Nulo | Clave | Default | Restricción | Descripción |
|---|---|---|---|---|---|---|
| id | BIGSERIAL | No | PK | autoincremental | — | Identificador del cliente |
| nombre | VARCHAR(150) | No | — | — | — | Nombre completo |
| email | VARCHAR(150) | No | UK | — | UNIQUE | Correo electrónico, no se repite |
| telefono | VARCHAR(20) | Sí | — | — | — | Teléfono de contacto |
| direccion | VARCHAR(255) | Sí | — | — | — | Dirección de entrega |
| fecha_registro | TIMESTAMPTZ | No | — | `now()` | — | Fecha de alta del cliente |
| activo | BOOLEAN | No | — | `true` | — | Borrado lógico: `false` = inactivo |

---

## 2. `categorias`

**Descripción:** Clasificación de los productos del catálogo.

| Columna | Tipo | Nulo | Clave | Default | Restricción | Descripción |
|---|---|---|---|---|---|---|
| id | BIGSERIAL | No | PK | autoincremental | — | Identificador de la categoría |
| nombre | VARCHAR(100) | No | UK | — | UNIQUE | Nombre de la categoría |
| descripcion | TEXT | Sí | — | — | — | Descripción de la categoría |

---

## 3. `productos`

**Descripción:** Catálogo de productos a la venta.

| Columna | Tipo | Nulo | Clave | Default | Restricción | Descripción |
|---|---|---|---|---|---|---|
| id | BIGSERIAL | No | PK | autoincremental | — | Identificador del producto |
| categoria_id | BIGINT | No | FK → `categorias.id` | — | RESTRICT | Categoría a la que pertenece |
| sku | VARCHAR(50) | No | UK | — | UNIQUE | Código interno del producto |
| nombre | VARCHAR(150) | No | — | — | — | Nombre comercial |
| descripcion | TEXT | Sí | — | — | — | Descripción del producto |
| precio | NUMERIC(12,2) | No | — | — | `CHECK (precio > 0)` | Precio de venta actual |
| activo | BOOLEAN | No | — | `true` | — | Si está disponible para la venta |
| fecha_creacion | TIMESTAMPTZ | No | — | `now()` | — | Fecha de registro del producto |

---

## 4. `inventario`

**Descripción:** Existencias de cada producto. Relación 1:1 con `productos`.

| Columna | Tipo | Nulo | Clave | Default | Restricción | Descripción |
|---|---|---|---|---|---|---|
| id | BIGSERIAL | No | PK | autoincremental | — | Identificador del registro |
| producto_id | BIGINT | No | FK → `productos.id`, UK | — | UNIQUE, RESTRICT | Producto al que corresponde (uno por producto) |
| stock | INTEGER | No | — | `0` | `CHECK (stock >= 0)` | Unidades disponibles |
| stock_minimo | INTEGER | No | — | `5` | `CHECK (stock_minimo >= 0)` | Umbral para alertar inventario bajo |
| ultima_actualizacion | TIMESTAMPTZ | No | — | `now()` | — | Último cambio de stock |

---

## 5. `pedidos`

**Descripción:** Compras realizadas por los clientes.

| Columna | Tipo | Nulo | Clave | Default | Restricción | Descripción |
|---|---|---|---|---|---|---|
| id | BIGSERIAL | No | PK | autoincremental | — | Identificador del pedido |
| cliente_id | BIGINT | No | FK → `clientes.id` | — | RESTRICT | Cliente que realiza el pedido |
| fecha | TIMESTAMPTZ | No | — | `now()` | — | Fecha y hora del pedido |
| estado | VARCHAR(20) | No | — | `'PENDIENTE'` | `CHECK (estado IN ('PENDIENTE','PAGADO','ENVIADO','ENTREGADO','CANCELADO'))` | Estado del pedido |
| total | NUMERIC(12,2) | No | — | `0` | `CHECK (total >= 0)` | Suma de los subtotales del detalle |

---

## 6. `detalle_pedido`

**Descripción:** Productos incluidos en cada pedido. Resuelve la relación N:M entre `pedidos` y `productos`.

| Columna | Tipo | Nulo | Clave | Default | Restricción | Descripción |
|---|---|---|---|---|---|---|
| id | BIGSERIAL | No | PK | autoincremental | — | Identificador de la línea |
| pedido_id | BIGINT | No | FK → `pedidos.id` | — | CASCADE | Pedido al que pertenece |
| producto_id | BIGINT | No | FK → `productos.id` | — | RESTRICT | Producto comprado |
| cantidad | INTEGER | No | — | — | `CHECK (cantidad > 0)` | Unidades compradas |
| precio_unitario | NUMERIC(12,2) | No | — | — | `CHECK (precio_unitario > 0)` | Precio copiado del producto al momento de la compra |
| subtotal | NUMERIC(12,2) | No | — | calculado | `GENERATED ALWAYS AS (cantidad * precio_unitario) STORED` | Cantidad × precio unitario |

**Restricción compuesta:** `UNIQUE (pedido_id, producto_id)`: un producto aparece una sola vez por pedido.

---

## 7. `pagos`

**Descripción:** Pagos asociados a un pedido. Un pedido puede tener varios intentos de pago.

| Columna | Tipo | Nulo | Clave | Default | Restricción | Descripción |
|---|---|---|---|---|---|---|
| id | BIGSERIAL | No | PK | autoincremental | — | Identificador del pago |
| pedido_id | BIGINT | No | FK → `pedidos.id` | — | RESTRICT | Pedido que se paga |
| monto | NUMERIC(12,2) | No | — | — | `CHECK (monto > 0)` | Valor pagado |
| metodo | VARCHAR(20) | No | — | — | `CHECK (metodo IN ('TARJETA','PSE','EFECTIVO','TRANSFERENCIA'))` | Medio de pago |
| estado | VARCHAR(20) | No | — | `'PENDIENTE'` | `CHECK (estado IN ('PENDIENTE','APROBADO','RECHAZADO'))` | Estado del pago |
| fecha | TIMESTAMPTZ | No | — | `now()` | — | Fecha del pago |

---

## 8. `usuarios`

**Descripción:** Usuarios internos del sistema (empleados que usan el backoffice o la API).

| Columna | Tipo | Nulo | Clave | Default | Restricción | Descripción |
|---|---|---|---|---|---|---|
| id | BIGSERIAL | No | PK | autoincremental | — | Identificador del usuario |
| username | VARCHAR(50) | No | UK | — | UNIQUE | Nombre de usuario |
| email | VARCHAR(150) | No | UK | — | UNIQUE | Correo corporativo |
| password_hash | VARCHAR(255) | No | — | — | — | Contraseña cifrada (nunca en texto plano) |
| rol | VARCHAR(20) | No | — | — | `CHECK (rol IN ('ADMIN','DEVELOPER','ANALYST','OPERATOR','AUDITOR'))` | Rol funcional del usuario |
| activo | BOOLEAN | No | — | `true` | — | Si puede acceder al sistema |
| fecha_creacion | TIMESTAMPTZ | No | — | `now()` | — | Fecha de alta |

> Estos roles describen la función del usuario en la aplicación. Los permisos reales en PostgreSQL se definen con los roles `db_admin`, `db_developer`, `db_analyst`, `db_operator` y `db_auditor` (Paso 5).

---

## 9. `auditoria`

**Descripción:** Registro de cambios sobre datos críticos. Se llena automáticamente mediante triggers (Paso 11).

| Columna | Tipo | Nulo | Clave | Default | Restricción | Descripción |
|---|---|---|---|---|---|---|
| id | BIGSERIAL | No | PK | autoincremental | — | Identificador del evento |
| usuario | TEXT | Sí | — | `current_user` | — | Usuario de base de datos que hizo el cambio |
| fecha | TIMESTAMP | No | — | `CURRENT_TIMESTAMP` | — | Momento del cambio |
| operacion | TEXT | No | — | — | `CHECK (operacion IN ('INSERT','UPDATE','DELETE'))` | Tipo de operación |
| tabla_afectada | TEXT | No | — | — | — | Tabla donde ocurrió el cambio |
| registro_id | BIGINT | Sí | — | — | — | `id` del registro modificado |
| datos_anteriores | JSONB | Sí | — | — | — | Valores antes del cambio (NULL en INSERT) |
| datos_nuevos | JSONB | Sí | — | — | — | Valores después del cambio (NULL en DELETE) |

> No tiene claves foráneas porque registra cambios de cualquier tabla, y debe conservar el evento aunque el registro original se elimine.

---

## Resumen de relaciones

| Tabla padre | Tabla hija | Cardinalidad | FK | ON DELETE |
|---|---|---|---|---|
| categorias | productos | 1:N | `productos.categoria_id` | RESTRICT |
| productos | inventario | 1:1 | `inventario.producto_id` (UNIQUE) | RESTRICT |
| clientes | pedidos | 1:N | `pedidos.cliente_id` | RESTRICT |
| pedidos | detalle_pedido | 1:N | `detalle_pedido.pedido_id` | CASCADE |
| productos | detalle_pedido | 1:N | `detalle_pedido.producto_id` | RESTRICT |
| pedidos | pagos | 1:N | `pagos.pedido_id` | RESTRICT |

---

## Reglas de negocio y restricción que las garantiza

| # | Regla de negocio | Implementación en la base |
|---|---|---|
| RN-01 | El precio de un producto debe ser mayor que 0 | `CHECK (precio > 0)` en `productos` |
| RN-02 | El stock nunca puede ser negativo | `CHECK (stock >= 0)` en `inventario` |
| RN-03 | La cantidad comprada debe ser mayor que 0 | `CHECK (cantidad > 0)` en `detalle_pedido` |
| RN-04 | El email del cliente no se repite | `UNIQUE (email)` en `clientes` |
| RN-05 | El SKU del producto no se repite | `UNIQUE (sku)` en `productos` |
| RN-06 | No existe un pedido sin cliente válido | FK `pedidos.cliente_id` + `NOT NULL` |
| RN-07 | Cada producto tiene un único registro de inventario | `UNIQUE (producto_id)` en `inventario` |
| RN-08 | Un producto aparece una sola vez por pedido | `UNIQUE (pedido_id, producto_id)` en `detalle_pedido` |
| RN-09 | El precio del pedido no cambia si luego cambia el del producto | `precio_unitario` se copia en `detalle_pedido` al comprar |
| RN-10 | El subtotal siempre es cantidad × precio | Columna generada `subtotal` |
| RN-11 | Los estados de pedido y pago solo toman valores válidos | `CHECK (estado IN (...))` |
| RN-12 | No se puede borrar un cliente o producto con historial de pedidos | FKs con `ON DELETE RESTRICT` + borrado lógico (`activo`) |
| RN-13 | Al eliminar un pedido se eliminan sus líneas de detalle | FK `detalle_pedido.pedido_id` con `ON DELETE CASCADE` |
| RN-14 | Los cambios en datos críticos quedan registrados | Triggers que insertan en `auditoria` (Paso 11) |