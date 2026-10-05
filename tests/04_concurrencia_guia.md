# Paso 7 – Prueba de concurrencia

**Objetivo:** simular dos clientes comprando al mismo tiempo el **último producto en stock** (producto 3, stock = 1) y observar qué ocurre en cada nivel de aislamiento.

## Preparación

Abre **dos terminales** (CMD) en `TaskDB`. En cada una entra a psql:

```
docker exec -it datamarket-postgres psql -U postgres -d datamarket
```

Llámalas **Sesión A** y **Sesión B**. Antes de **cada** escenario, en una tercera terminal (o en cualquiera de las dos, antes de empezar):

```
docker exec -i datamarket-postgres psql -U postgres -d datamarket < tests\04_concurrencia_preparar.sql
```

Y al terminar cada escenario:

```
docker exec -i datamarket-postgres psql -U postgres -d datamarket < tests\04_concurrencia_verificar.sql
```

**Reglas:**
- Ejecuta los pasos **en el orden exacto** de la tabla, alternando entre sesiones.
- Escribe una instrucción a la vez y pulsa Enter.
- Cuando una sesión "se queda esperando" (no vuelve el prompt), es normal: está **bloqueada** esperando a la otra.
- En cada sesión, primero ejecuta: `SET search_path TO datamarket;`

La lógica simulada es la de una aplicación típica: **lee el stock, decide si hay unidades, crea el pedido y guarda el nuevo stock** (`stock = 0`, calculado con el valor que leyó).

---

## Escenario 1 – READ COMMITTED (nivel por defecto)

| Paso | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN ISOLATION LEVEL READ COMMITTED;` | |
| 2 | `SELECT stock FROM inventario WHERE producto_id = 3;` → **1** | |
| 3 | | `BEGIN ISOLATION LEVEL READ COMMITTED;` |
| 4 | | `SELECT stock FROM inventario WHERE producto_id = 3;` → **1** |
| 5 | `INSERT INTO pedidos (cliente_id) VALUES (101);` | |
| 6 | `UPDATE inventario SET stock = 0 WHERE producto_id = 3;` | |
| 7 | | `INSERT INTO pedidos (cliente_id) VALUES (102);` |
| 8 | | `UPDATE inventario SET stock = 0 WHERE producto_id = 3;` → **queda esperando** |
| 9 | `COMMIT;` | → se desbloquea, `UPDATE 1` |
| 10 | | `COMMIT;` |

**Resultado esperado:** `pedidos_creados = 2`, `stock_final = 0` → **SOBREVENTA**.

**Por qué:** en READ COMMITTED cada instrucción ve los datos confirmados *en ese momento*. Ambas sesiones leyeron stock 1 antes de que nadie confirmara, y las dos decidieron vender. El bloqueo del paso 8 solo ordena las escrituras: B escribe `stock = 0` encima del 0 de A. Esto se llama **actualización perdida (lost update)**.

---

## Escenario 2 – REPEATABLE READ

Repite **exactamente** los pasos del escenario 1, cambiando los pasos 1 y 3 por:

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
```

**Resultado esperado:** en el paso 9, cuando A hace COMMIT, la Sesión B recibe:

```
ERROR:  could not serialize access due to concurrent update
```

B debe hacer `ROLLBACK;` en el paso 10. Resultado: `pedidos_creados = 1`, `stock_final = 0` → **consistente**.

**Por qué:** en REPEATABLE READ la transacción trabaja con una "foto" de los datos tomada al inicio. Cuando B intenta modificar una fila que otra transacción cambió y confirmó después de esa foto, PostgreSQL no le permite sobrescribirla y aborta la transacción. La aplicación debe **reintentar**; al reintentar, B leerá stock 0 y no venderá.

---

## Escenario 3 – SERIALIZABLE

Igual que el escenario 1, con:

```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;
```

**Resultado esperado:** igual que REPEATABLE READ: error de serialización en B, 1 pedido, stock 0.

**Diferencia con REPEATABLE READ:** SERIALIZABLE además detecta anomalías donde las dos transacciones **no modifican la misma fila** (por ejemplo, *write skew*: dos sesiones leen el mismo conjunto de datos y cada una modifica una fila distinta basándose en lo que leyó). Garantiza que el resultado sea equivalente a ejecutar las transacciones una después de otra. A cambio, se producen más errores de serialización y la aplicación debe reintentar con más frecuencia.

---

## Escenario 4 – Solución: bloqueo explícito con `SELECT ... FOR UPDATE`

Se mantiene READ COMMITTED, pero la lectura del stock **bloquea la fila**:

| Paso | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN;` | |
| 2 | `SELECT stock FROM inventario WHERE producto_id = 3 FOR UPDATE;` → **1** | |
| 3 | | `BEGIN;` |
| 4 | | `SELECT stock FROM inventario WHERE producto_id = 3 FOR UPDATE;` → **queda esperando** |
| 5 | `INSERT INTO pedidos (cliente_id) VALUES (101);` | |
| 6 | `UPDATE inventario SET stock = 0 WHERE producto_id = 3;` | |
| 7 | `COMMIT;` | → se desbloquea y muestra **0** |
| 8 | | Como el stock es 0, **no vende**: `ROLLBACK;` |

**Resultado esperado:** `pedidos_creados = 1`, `stock_final = 0` → **consistente, y sin errores**.

**Por qué:** `FOR UPDATE` toma un bloqueo de fila. La segunda sesión no puede ni siquiera *leer para modificar* hasta que la primera termine, y cuando lo hace ve el valor ya actualizado.

---

## Otra solución: actualización condicional atómica

Sin leer antes, se descuenta solo si hay stock:

```sql
UPDATE inventario
SET stock = stock - 1
WHERE producto_id = 3 AND stock >= 1
RETURNING stock;
```

Si devuelve **0 filas**, no había stock y la aplicación cancela la compra. Funciona porque la condición y la escritura ocurren en la **misma instrucción**: la segunda sesión espera el bloqueo, vuelve a evaluar `stock >= 1` con el valor nuevo (0) y no actualiza nada.

Además, la restricción `chk_inventario_stock (stock >= 0)` es la última red de seguridad: aunque la aplicación se equivoque, la base nunca acepta stock negativo.

---

## Resumen

| Nivel / técnica | ¿Ve datos sin confirmar? | Dos compras del último producto | Costo |
|---|---|---|---|
| READ COMMITTED | No | **Sobreventa** (lost update) | Ninguno |
| REPEATABLE READ | No | Segunda falla → reintentar | Reintentos |
| SERIALIZABLE | No | Segunda falla → reintentar | Más reintentos, detecta más anomalías |
| READ COMMITTED + `FOR UPDATE` | No | Segunda espera y ve stock 0 | Espera (bloqueo) breve |
| UPDATE condicional | No | Segunda actualiza 0 filas | Ninguno |

**Decisión para DataMarket:** usar **READ COMMITTED con `SELECT ... FOR UPDATE`** (o UPDATE condicional) en el proceso de compra. Evita la sobreventa sin obligar a la aplicación a manejar reintentos por errores de serialización. Se reserva SERIALIZABLE para procesos donde varias filas distintas dependen entre sí.

> Nota: PostgreSQL no implementa READ UNCOMMITTED como un nivel distinto; si se pide, se comporta como READ COMMITTED. Por eso en ningún nivel aparecen *lecturas sucias* (dirty reads).

## Evidencia

Toma captura de ambas sesiones y del resultado de `04_concurrencia_verificar.sql` en cada escenario, y guárdalas en `screenshots/` (por ejemplo `paso7_escenario1_read_committed.png`).
