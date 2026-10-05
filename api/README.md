# API DataMarket (Paso 14)

API REST básica en **Node.js + Express** que consume la base PostgreSQL del laboratorio.

## Arquitectura

```
CLIENTE (Postman / REST Client / navegador)
   │  HTTP + JSON
   ▼
API REST ............ src/routes/index.js        → rutas, códigos HTTP
   │
   ▼
SERVICIO ............ src/services/*.service.js  → valida formato de la entrada
   │
   ▼
REPOSITORIO ......... src/repositories/*.js      → único lugar con SQL (parametrizado)
   │
   ▼
POSTGRESQL .......... usuario usr_api (privilegios mínimos)
                      vistas, funciones y sp_registrar_compra
```

## Seguridad: privilegios mínimos

La API **no** se conecta como `postgres` ni como `usr_admin`. Usa **`usr_api`**, que hereda del rol `db_operator`:

| Puede | No puede |
|---|---|
| Leer productos, categorías, inventario, clientes, pedidos y pagos | Borrar ningún registro |
| Registrar compras (`sp_registrar_compra`) | Cambiar precios |
| Leer la vista `inventario_bajo` | Leer usuarios internos ni la auditoría |
| | Crear o modificar tablas |

Además:
- Todas las consultas son **parametrizadas** (`$1, $2`), lo que evita la inyección SQL.
- Las credenciales van en `.env`, que **no** se sube al repositorio (`.gitignore`).
- Toda operación de la API queda en la auditoría con usuario `usr_api`.

## Endpoints

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/health` | Estado y usuario de base de datos con el que se conecta |
| GET | `/api/productos?categoria=1` | Productos activos con su stock (filtro opcional) |
| GET | `/api/productos/:id` | Un producto |
| GET | `/api/inventario/:productoId` | Inventario de un producto |
| GET | `/api/inventario/bajo` | Productos por reponer (vista `inventario_bajo`) |
| POST | `/api/pedidos` | **Crear pedido**: llama a `sp_registrar_compra` |
| GET | `/api/pedidos?cliente_id=1` | Pedidos (filtro opcional, últimos 50) |
| GET | `/api/pedidos/:id` | Pedido con su detalle y pagos |

Cuerpo de `POST /api/pedidos`:

```json
{
  "cliente_id": 1,
  "items": [
    { "producto_id": 1, "cantidad": 2 },
    { "producto_id": 2, "cantidad": 1 }
  ],
  "metodo_pago": "TARJETA"
}
```

### Errores

Los errores de la base se traducen a códigos HTTP:

| Situación | Código PostgreSQL | HTTP |
|---|---|---|
| Datos con formato inválido | validación de la API | 400 |
| Método de pago inválido, sin productos | `22023` | 400 |
| Cliente o producto inexistente | `23503` / `P0002` | 404 |
| Stock insuficiente o producto inactivo | `23514` | 409 |
| Permiso denegado | `42501` | 403 |

## Ejecutar

Requisitos: Node.js 18 o superior, y el contenedor `datamarket-postgres` con la base construida (scripts `01` a `11`).

```
cd api
npm install
copy .env.example .env
npm start
```

Debe mostrar:

```
DataMarket API escuchando en http://localhost:3000
Usuario de base de datos: usr_api
```

Comprobar en el navegador: http://localhost:3000/health

## Probar

Abre `requests.http` en VS Code con la extensión **REST Client** y haz clic en *Send Request* sobre cada petición. Incluye los 4 casos mínimos del taller y 6 casos de error.

Para ver que la compra quedó auditada con el usuario de la API:

```
docker exec -it datamarket-postgres psql -U postgres -d datamarket -c "SELECT id, usuario, operacion, tabla_afectada, registro_id FROM auditoria WHERE usuario = 'usr_api' ORDER BY id;"
```
