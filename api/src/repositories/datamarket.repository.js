// REPOSITORIO: único lugar con SQL.
// Siempre consultas parametrizadas ($1, $2...) para evitar inyección SQL.
const pool = require('../db');

async function listarProductos(categoriaId) {
  const { rows } = await pool.query(
    `SELECT p.id, p.sku, p.nombre, c.nombre AS categoria, p.precio, i.stock
       FROM productos p
       JOIN categorias c ON c.id = p.categoria_id
       JOIN inventario i ON i.producto_id = p.id
      WHERE p.activo
        AND ($1::bigint IS NULL OR p.categoria_id = $1)
      ORDER BY p.id
      LIMIT 100`,
    [categoriaId ?? null]
  );
  return rows;
}

async function obtenerProducto(id) {
  const { rows } = await pool.query(
    `SELECT p.id, p.sku, p.nombre, p.descripcion, c.nombre AS categoria,
            p.precio, p.activo, i.stock, i.stock_minimo
       FROM productos p
       JOIN categorias c ON c.id = p.categoria_id
       JOIN inventario i ON i.producto_id = p.id
      WHERE p.id = $1`,
    [id]
  );
  return rows[0] || null;
}

async function inventarioBajo() {
  // Vista de negocio del Paso 9
  const { rows } = await pool.query('SELECT * FROM inventario_bajo');
  return rows;
}

async function inventarioDeProducto(productoId) {
  const { rows } = await pool.query(
    `SELECT producto_id, stock, stock_minimo, ultima_actualizacion
       FROM inventario
      WHERE producto_id = $1`,
    [productoId]
  );
  return rows[0] || null;
}

async function crearPedido(clienteId, items, metodoPago) {
  // Toda la lógica de compra (validaciones, bloqueo anti-sobreventa,
  // detalle, inventario y pago) vive en el procedimiento del Paso 10.
  const { rows } = await pool.query(
    'CALL sp_registrar_compra($1, $2::jsonb, $3, NULL)',
    [clienteId, JSON.stringify(items), metodoPago]
  );
  return rows[0].p_pedido_id;
}

async function listarPedidos(clienteId) {
  const { rows } = await pool.query(
    `SELECT id, cliente_id, fecha, estado, total
       FROM pedidos
      WHERE ($1::bigint IS NULL OR cliente_id = $1)
      ORDER BY id DESC
      LIMIT 50`,
    [clienteId ?? null]
  );
  return rows;
}

async function obtenerPedido(id) {
  const pedido = await pool.query(
    'SELECT id, cliente_id, fecha, estado, total FROM pedidos WHERE id = $1',
    [id]
  );
  if (pedido.rowCount === 0) return null;

  const detalle = await pool.query(
    `SELECT d.producto_id, p.nombre AS producto, d.cantidad,
            d.precio_unitario, d.subtotal
       FROM detalle_pedido d
       JOIN productos p ON p.id = d.producto_id
      WHERE d.pedido_id = $1
      ORDER BY d.producto_id`,
    [id]
  );
  const pagos = await pool.query(
    'SELECT id, monto, metodo, estado, fecha FROM pagos WHERE pedido_id = $1 ORDER BY id',
    [id]
  );
  return { ...pedido.rows[0], detalle: detalle.rows, pagos: pagos.rows };
}

module.exports = {
  listarProductos,
  obtenerProducto,
  inventarioBajo,
  inventarioDeProducto,
  crearPedido,
  listarPedidos,
  obtenerPedido,
};
