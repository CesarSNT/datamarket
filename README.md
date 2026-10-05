# Laboratorio DBA – DataMarket S.A.S.

Base de datos PostgreSQL para una plataforma de pedidos, con integridad, seguridad por roles, transacciones, control de concurrencia, optimización, vistas, lógica en procedimientos, auditoría, backup/restauración y una API REST básica.

**Stack:** PostgreSQL 16 · Docker · Node.js + Express · PlantUML

## Estructura

```
TaskDB/
├── README.md                    ← este archivo
├── docs/
│   ├── arquitectura.md          ← componentes, capas, flujo de compra, seguridad
│   ├── decisiones-tecnicas.md   ← 29 decisiones justificadas + preguntas de reflexión
│   ├── diccionario-datos.md     ← tablas, columnas, restricciones y reglas de negocio
│   ├── 01_modelo_conceptual/    ← .puml + .png
│   ├── 02_modelo_logico/
│   └── 03_modelo_fisico/
├── database/                    ← se ejecutan EN ORDEN (01 → 11)
│   ├── 01_database.sql          ← crea la base (desde cero)
│   ├── 02_schema.sql            ← esquema datamarket + search_path
│   ├── 03_tables.sql            ← 9 tablas (PK, tipos, NOT NULL, DEFAULT)
│   ├── 04_constraints.sql       ← FK, UNIQUE, CHECK
│   ├── 05_indexes.sql           ← índices justificados
│   ├── 06_views.sql             ← vistas de negocio
│   ├── 07_functions.sql         ← funciones de consulta
│   ├── 08_procedures.sql        ← compra y cancelación (atómicas)
│   ├── 09_triggers.sql          ← auditoría
│   ├── 10_roles.sql             ← roles con privilegios mínimos
│   └── 11_seed.sql              ← datos de prueba (100.000 pedidos)
├── api/                         ← API REST (Node.js + Express)
├── tests/                       ← pruebas + plan de pruebas (tests/README.md)
├── backup/                      ← respaldo generado con pg_dump
├── docker/
│   └── docker-compose.yml
└── screenshots/                 ← evidencias por paso (screenshots/README.md)
```

## Requisitos

- Docker Desktop (con WSL2 en Windows)
- Node.js 18 o superior (solo para la API)
- VS Code con las extensiones PlantUML y REST Client (opcional)

> Todos los comandos se ejecutan en **CMD**, desde la carpeta raíz del proyecto.

---

## 1. Levantar PostgreSQL

```
docker compose -f docker/docker-compose.yml up -d
docker ps
```

`datamarket-postgres` debe aparecer en estado **Up** con `0.0.0.0:5440->5432/tcp`.

> **Puerto 5440.** En este equipo los PostgreSQL 17 y 18 de Windows ocupan los puertos 5432 y 5433, así que el contenedor se publica en el **5440**. Los comandos `docker exec` no se ven afectados (entran directo al contenedor); el puerto solo importa para conexiones externas: API, pgAdmin, DBeaver (`localhost:5440`, base `datamarket`).

## 2. Construir la base desde cero

Ejecutar en este orden:

```
docker exec -i datamarket-postgres psql -U postgres -d postgres   < database\01_database.sql
docker exec -i datamarket-postgres psql -U postgres -d datamarket < database\02_schema.sql
docker exec -i datamarket-postgres psql -U postgres -d datamarket < database\03_tables.sql
docker exec -i datamarket-postgres psql -U postgres -d datamarket < database\04_constraints.sql
docker exec -i datamarket-postgres psql -U postgres -d datamarket < database\05_indexes.sql
docker exec -i datamarket-postgres psql -U postgres -d datamarket < database\06_views.sql
docker exec -i datamarket-postgres psql -U postgres -d datamarket < database\07_functions.sql
docker exec -i datamarket-postgres psql -U postgres -d datamarket < database\08_procedures.sql
docker exec -i datamarket-postgres psql -U postgres -d datamarket < database\09_triggers.sql
docker exec -i datamarket-postgres psql -U postgres -d datamarket < database\10_roles.sql
docker exec -i datamarket-postgres psql -U postgres -d datamarket < database\11_seed.sql
```

- `01` **borra** la base `datamarket` si existe, así que todo se reconstruye limpio.
- Los roles son del servidor y se conservan entre reconstrucciones; `10_roles.sql` se puede ejecutar varias veces.
- `11_seed.sql` tarda unos segundos y al final muestra el conteo por tabla.

## 3. Ejecutar las pruebas

```
docker exec -i datamarket-postgres psql -U postgres -d datamarket < tests\01_pruebas_integridad.sql
docker exec -i datamarket-postgres psql -U postgres -d datamarket < tests\02_pruebas_permisos.sql
docker exec -i datamarket-postgres psql -U postgres -d datamarket < tests\03_transacciones.sql
docker exec -i datamarket-postgres psql -U postgres -d datamarket < tests\06_pruebas_vistas.sql
docker exec -i datamarket-postgres psql -U postgres -d datamarket < tests\07_pruebas_funciones.sql
docker exec -i datamarket-postgres psql -U postgres -d datamarket < tests\08_pruebas_auditoria.sql
docker exec -i datamarket-postgres psql -U postgres -d datamarket < tests\10_diagnostico.sql
```

Las pruebas que requieren pasos manuales tienen su propia guía:

| Prueba | Guía |
|---|---|
| Concurrencia (dos sesiones simultáneas) | `tests/04_concurrencia_guia.md` |
| Rendimiento antes/después de índices | `tests/README.md`, sección T5 |
| Backup, incidente y restauración | `tests/09_backup_restauracion.md` |

> Los `ERROR` que aparecen en las pruebas son **esperados**: demuestran que la base bloqueó una operación inválida. El plan completo (objetivo, preparación, acción, resultado esperado y obtenido) está en **`tests/README.md`**.

## 4. Backup y restauración

Resumen (detalle en `tests/09_backup_restauracion.md`):

```
docker exec datamarket-postgres pg_dump -U postgres -d datamarket -F c -f /tmp/datamarket.backup
docker cp datamarket-postgres:/tmp/datamarket.backup backup\datamarket.backup
```

La restauración se prueba sobre una base experimental (`datamarket_restaurada`); la base principal no se toca.

## 5. Ejecutar la API

```
cd api
npm install
copy .env.example .env
npm start
```

- API en http://localhost:3000, conectada con **`usr_api`** (privilegios mínimos, nunca el administrador).
- Pruebas: abrir `api/requests.http` con la extensión REST Client.
- Endpoints y detalles en `api/README.md`.

| Operación mínima del taller | Endpoint |
|---|---|
| Consultar productos | `GET /api/productos` |
| Consultar inventario | `GET /api/inventario/:productoId` · `GET /api/inventario/bajo` |
| Crear un pedido | `POST /api/pedidos` |
| Consultar pedidos | `GET /api/pedidos?cliente_id=1` · `GET /api/pedidos/:id` |

---

## Usuarios de base de datos (laboratorio)

| Usuario | Grupo | Uso | Contraseña |
|---|---|---|---|
| `postgres` | superusuario | Construcción y administración del servidor | `postgres` |
| `usr_admin` | `db_admin` | Administración de objetos | `Admin2026!` |
| `usr_dev` | `db_developer` | Desarrollo | `Dev2026!` |
| `usr_analista` | `db_analyst` | Reportes (solo lectura) | `Analista2026!` |
| `usr_operador` | `db_operator` | Operación (compras, stock) | `Operador2026!` |
| `usr_auditor` | `db_auditor` | Consulta de auditoría | `Auditor2026!` |
| `usr_api` | `db_operator` | Conexión de la API | `Api2026!` |

> Contraseñas **solo para el laboratorio**. En producción se manejan con variables de entorno o un gestor de secretos.

## Checklist del taller

| Requisito | Dónde se demuestra |
|---|---|
| El proyecto puede levantarse desde cero | Secciones 1 y 2 · `screenshots/paso00_entorno` |
| La base se reconstruye ejecutando los scripts en orden | `database/01` a `11` |
| Las restricciones impiden datos inválidos | `tests/01_pruebas_integridad.sql` · `screenshots/paso03_integridad` |
| Los roles tienen privilegios diferenciados | `tests/02_pruebas_permisos.sql` · `screenshots/paso05_seguridad` |
| Las operaciones críticas usan transacciones | `tests/03_transacciones.sql`, `sp_registrar_compra` · `screenshots/paso06_transacciones` |
| Se probó concurrencia | `tests/04_concurrencia_guia.md` · `screenshots/paso07_concurrencia` |
| Se analizaron consultas con EXPLAIN ANALYZE | `tests/05_rendimiento.sql` · `screenshots/paso08_rendimiento` |
| Los índices tienen justificación | `database/05_indexes.sql` · `docs/decisiones-tecnicas.md` (DT-20, DT-21) |
| Existen vistas de negocio | `database/06_views.sql` · `screenshots/paso09_vistas` |
| Existe auditoría | `database/09_triggers.sql` · `screenshots/paso11_auditoria` |
| Se generó un backup | `backup/datamarket.backup` · `tests/09_backup_restauracion.md` |
| Se realizó una restauración | `tests/09_incidente.sql`, `tests/09_verificar_backup.sql` |
| La API usa privilegios mínimos | `api/` (`usr_api`) · `tests/02_pruebas_permisos.sql` (sección API) |
| Las pruebas tienen evidencia | `tests/README.md` · `screenshots/README.md` |
| El README explica cómo ejecutar todo | Este archivo |

## Documentación

- **`docs/arquitectura.md`**: vista general, capas, flujo de compra, seguridad y respaldo.
- **`docs/decisiones-tecnicas.md`**: 29 decisiones con alternativas y justificación, y las 10 preguntas de reflexión.
- **`docs/diccionario-datos.md`**: tablas, columnas y reglas de negocio (RN-01 a RN-14).
- **`tests/README.md`**: plan de pruebas del Paso 15.
- **`screenshots/README.md`**: evidencias de ejecución por paso.
- **`tests/10_diagnostico.sql`**: chequeo de salud para el reto final (permisos, índices, consultas lentas, inconsistencias, auditoría).
