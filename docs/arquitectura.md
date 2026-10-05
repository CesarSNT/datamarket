# Arquitectura – DataMarket S.A.S.

## 1. Contexto

DataMarket es una plataforma de pedidos: los clientes compran productos de un catálogo, el sistema descuenta inventario, registra pagos y guarda auditoría de los cambios críticos. Este laboratorio implementa la **capa de datos** completa en PostgreSQL y una **API básica** que la consume.

## 2. Vista general

```
┌──────────────────────────┐
│  CLIENTE                 │  Postman / REST Client / navegador
└────────────┬─────────────┘
             │ HTTP + JSON
┌────────────▼─────────────┐
│  API REST (Node/Express) │  api/src/routes        → rutas y códigos HTTP
│  ─ SERVICIO              │  api/src/services      → validación de formato
│  ─ REPOSITORIO           │  api/src/repositories  → SQL parametrizado
└────────────┬─────────────┘
             │ usuario usr_api (privilegios mínimos)
┌────────────▼──────────────────────────────────────────────┐
│  POSTGRESQL 16 (contenedor Docker: datamarket-postgres)    │
│                                                            │
│  Base: datamarket · Esquema: datamarket                    │
│  ├─ Tablas + restricciones (PK, FK, UNIQUE, CHECK)         │
│  ├─ Índices                                                │
│  ├─ Vistas de negocio                                      │
│  ├─ Funciones y procedimientos (lógica de compra)          │
│  ├─ Triggers de auditoría                                  │
│  └─ Roles y permisos                                       │
│                                                            │
│  Volumen persistente: postgres_data                        │
└────────────┬───────────────────────────────────────────────┘
             │ pg_dump -F c
┌────────────▼─────────────┐
│  backup/datamarket.backup│  fuera del contenedor y de su volumen
└──────────────────────────┘
```

## 3. Componentes

| Componente | Tecnología | Ubicación | Responsabilidad |
|---|---|---|---|
| Entorno | Docker Compose | `docker/docker-compose.yml` | Levantar PostgreSQL 16 igual en cualquier máquina |
| Base de datos | PostgreSQL 16 | `database/01` a `11` | Datos, integridad, lógica crítica, seguridad y auditoría |
| API | Node.js 18+, Express, `pg` | `api/` | Exponer consultas y la creación de pedidos por HTTP |
| Pruebas | SQL + guías | `tests/` | Demostrar cada decisión con ejecución |
| Respaldo | `pg_dump` / `pg_restore` | `backup/` | Recuperar el servicio ante un incidente |
| Documentación | Markdown + PlantUML | `docs/`, `screenshots/` | Diseño, decisiones y evidencias |

## 4. Modelo de datos

9 tablas en el esquema `datamarket`. Diagramas en `docs/01_modelo_conceptual`, `docs/02_modelo_logico` y `docs/03_modelo_fisico`; detalle de columnas en `docs/diccionario-datos.md`.

```
categorias 1──N productos 1──1 inventario
                    │
                    N
clientes 1──N pedidos 1──N detalle_pedido
                 │
                 1──N pagos

usuarios          (usuarios internos del sistema)
auditoria         (eventos de cualquier tabla crítica; sin FK)
```

## 5. Distribución de responsabilidades

El principio es: **lo que protege la consistencia de los datos vive en la base**; lo que tiene que ver con presentación y formato vive en la API.

| Responsabilidad | Dónde | Por qué |
|---|---|---|
| Integridad (FK, UNIQUE, CHECK, NOT NULL) | Base | Ninguna aplicación puede saltársela |
| Compra atómica y anti-sobreventa | Base (`sp_registrar_compra`) | Una sola transacción con bloqueo de fila, junto a los datos |
| Totales y subtotales | Base (columna generada, función) | Un solo cálculo, sin descuadres |
| Auditoría | Base (triggers) | Registra cambios hechos desde cualquier cliente, incluso psql |
| Control de acceso a datos | Base (roles) | El permiso acompaña al dato, no al código |
| Validación de formato (tipos, campos vacíos) | API | Respuesta rápida y mensaje claro al usuario |
| Traducción de errores a HTTP | API | 400 / 404 / 409 / 403 según el código de PostgreSQL |
| Paginación y filtros de consulta | API | Presentación |

## 6. Flujo crítico: crear un pedido

```
POST /api/pedidos
  │
  ├─ API (servicio): ¿cliente_id e items válidos? ── no ──► 400
  │
  └─ CALL sp_registrar_compra(cliente, items, método)    ← una transacción
        1. Valida parámetros, método de pago y cliente activo
        2. Consolida productos repetidos
        3. SELECT ... FOR UPDATE sobre inventario          ← bloqueo anti-sobreventa
        4. Valida que cada producto exista, esté activo y tenga stock
        5. INSERT pedido
        6. INSERT detalle (precio copiado del producto)
        7. UPDATE inventario (descuenta)
        8. Calcula total → estado PAGADO
        9. INSERT pago APROBADO
        └─ Cualquier fallo → RAISE EXCEPTION → se deshace TODO
  │
  ├─ Triggers registran en auditoria: pedido, inventario y pago (usuario usr_api)
  └─ 201 con el pedido completo │ 409 sin stock │ 404 cliente o producto inexistente
```

## 7. Seguridad

**Modelo de roles.** Los permisos se otorgan a roles de grupo sin login, y los usuarios de login heredan de un grupo:

| Grupo | Usuario | Uso |
|---|---|---|
| `db_admin` | `usr_admin` | Administración (no es superusuario) |
| `db_developer` | `usr_dev` | Desarrollo: CRUD y creación de objetos; auditoría solo lectura |
| `db_analyst` | `usr_analista` | Reportes: solo lectura; sin usuarios ni auditoría |
| `db_operator` | `usr_operador`, **`usr_api`** | Operación: compras y stock; nunca borra |
| `db_auditor` | `usr_auditor` | Solo lectura de la auditoría |

Otras medidas:
- Se revoca a `PUBLIC` todo acceso por defecto, incluido `EXECUTE` sobre funciones y procedimientos.
- Las vistas exponen solo las columnas necesarias; por ejemplo, `resumen_compras_cliente` oculta email, teléfono y dirección.
- La auditoría es **inmutable**: un trigger rechaza UPDATE, DELETE y TRUNCATE, incluso para el administrador.
- La API usa consultas parametrizadas y guarda sus credenciales en `.env`, fuera del repositorio.

## 8. Respaldo y recuperación

| Aspecto | Decisión |
|---|---|
| Herramienta | `pg_dump -F c` (formato comprimido, restauración selectiva con `pg_restore`) |
| Ubicación | `backup/` del proyecto, fuera del contenedor y de su volumen |
| Qué no incluye | Roles (son del servidor) y configuración de la base (`search_path`, `CONNECT`) |
| Complemento | `10_roles.sql` y `tests/09_post_restauracion.sql` |
| Prueba de recuperación | Incidente controlado sobre `datamarket_restaurada` y restauración verificada |
| Procedimiento | `tests/09_backup_restauracion.md` |

## 9. Despliegue local

```
docker compose -f docker/docker-compose.yml up -d     → PostgreSQL en localhost:5440 (5432 dentro del contenedor)
database\01 … 11  (en orden)                            → estructura, seguridad y datos
cd api && npm install && npm start                      → API en http://localhost:3000
```

Pasos detallados en el `README.md` principal.
