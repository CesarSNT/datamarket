# Pasos 12 y 13 – Backup, incidente y restauración

Todos los comandos se ejecutan en **CMD**, parado en la carpeta `TaskDB`, con Docker Desktop abierto.

> `pg_dump` y `pg_restore` se ejecutan **dentro del contenedor** (`docker exec`), así no hace falta instalarlos en Windows. El archivo se copia entre el contenedor y la carpeta `backup\` con `docker cp`.

---

## Paso 12 – Backup

**1. Generar el respaldo** (formato custom `-F c`: comprimido y restaurable con `pg_restore`):

```
docker exec datamarket-postgres pg_dump -U postgres -d datamarket -F c -f /tmp/datamarket.backup
```

**2. Copiarlo a la carpeta del proyecto:**

```
docker cp datamarket-postgres:/tmp/datamarket.backup backup\datamarket.backup
```

**3. Verificar que existe (fecha y tamaño):**

```
dir backup
```

**4. Verificar que el archivo es un backup válido** (lista su contenido sin restaurarlo):

```
docker exec datamarket-postgres pg_restore -l /tmp/datamarket.backup
```

**5. Guardar la "huella" de la base original** para compararla después:

```
docker exec -i datamarket-postgres psql -U postgres -d datamarket < tests\09_verificar_backup.sql
```

📸 Captura de los pasos 3, 4 y 5.

Documentar: fecha y hora del backup, tamaño del archivo, comando utilizado.

---

## Paso 13 – Incidente controlado y recuperación

Se trabaja sobre una **base experimental** (`datamarket_restaurada`). La base principal `datamarket` **no se toca**.

### 13.1 Crear la base experimental desde el backup

```
docker exec datamarket-postgres psql -U postgres -c "DROP DATABASE IF EXISTS datamarket_restaurada WITH (FORCE);" -c "CREATE DATABASE datamarket_restaurada TEMPLATE template0;"
docker cp backup\datamarket.backup datamarket-postgres:/tmp/datamarket.backup
docker exec datamarket-postgres pg_restore -U postgres -d datamarket_restaurada /tmp/datamarket.backup
docker exec -i datamarket-postgres psql -U postgres -d datamarket_restaurada < tests\09_post_restauracion.sql
```

> El `docker cp` del segundo comando demuestra que se restaura **desde el archivo guardado en el proyecto**, no desde una copia temporal.
>
> El último comando aplica lo que `pg_dump` **no** guarda: el `search_path` de la base y los permisos de conexión. Sin él, la aplicación recibe `ERROR: relation "pedidos" does not exist`.

### 13.2 Simular el incidente

```
docker exec -i datamarket-postgres psql -U postgres -d datamarket_restaurada < tests\09_incidente.sql
```

Resultado esperado: pedidos, detalles y pagos quedan en **0**; las vistas de negocio quedan vacías.

> El script tiene una protección: si por error se ejecuta contra `datamarket`, se detiene sin borrar nada.

📸 Captura.

### 13.3 Recuperar el servicio

Anota la hora de inicio (`echo %time%`) y repite exactamente lo del 13.1:

```
echo %time%
docker exec datamarket-postgres psql -U postgres -c "DROP DATABASE IF EXISTS datamarket_restaurada WITH (FORCE);" -c "CREATE DATABASE datamarket_restaurada TEMPLATE template0;"
docker cp backup\datamarket.backup datamarket-postgres:/tmp/datamarket.backup
docker exec datamarket-postgres pg_restore -U postgres -d datamarket_restaurada /tmp/datamarket.backup
docker exec -i datamarket-postgres psql -U postgres -d datamarket_restaurada < tests\09_post_restauracion.sql
echo %time%
```

La diferencia entre las dos horas es el **tiempo de recuperación** (pregunta de reflexión 8).

### 13.4 Comprobaciones después de restaurar

**a) Comparar con la base original:**

```
docker exec -i datamarket-postgres psql -U postgres -d datamarket_restaurada < tests\09_verificar_backup.sql
```

Debe coincidir con lo obtenido en el paso 12.5: registros por tabla, totales de dinero y stock, cantidad de objetos (tablas, vistas, índices, funciones, triggers, restricciones) y 0 problemas de integridad.

**b) Un usuario de la aplicación puede trabajar en la base restaurada:**

```
docker exec -it datamarket-postgres psql -U usr_analista -d datamarket_restaurada -c "SELECT * FROM ventas_por_periodo ORDER BY periodo DESC LIMIT 3;"
```

📸 Captura de ambas.

---

## Resultados obtenidos (Docker sobre Windows, PostgreSQL 16.15)

| Medida | Valor |
|---|---|
| Fecha del backup | 4 de octubre de 2026, 21:12 (Bogotá) |
| Tamaño de la base original | 82 MB |
| Tamaño del backup (`-F c`, gzip) | 7.092.621 bytes (~7,1 MB) |
| Entradas en el backup (`pg_restore -l`) | 169 |
| Tiempo total de recuperación (13.3) | **3,25 s** |
| Tamaño de la base restaurada | 69 MB (sin espacio muerto) |
| Comparación con el original | Idéntica en registros, totales, objetos e integridad |

Evidencias en `screenshots/paso12_backup/` y `screenshots/paso13_restauracion/`.

## Hallazgos para documentar

1. **El backup no incluye la configuración de la base de datos** (`ALTER DATABASE ... SET search_path`, `GRANT CONNECT`). Por eso existe `09_post_restauracion.sql`.
2. **El backup no incluye los roles**: son del servidor, no de la base. En un servidor nuevo, antes de restaurar hay que ejecutar `10_roles.sql` (o `pg_dumpall --roles-only`).
3. **Un backup en el mismo servidor no protege contra la pérdida del servidor**: el archivo debe copiarse fuera (otro disco, nube). En este laboratorio queda en `backup\` del proyecto, fuera del contenedor y de su volumen.
4. **TRUNCATE no queda en la auditoría** (no dispara triggers por fila); el DELETE sí, fila por fila, con usuario y hora.
