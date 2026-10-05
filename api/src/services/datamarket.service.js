// SERVICIO: valida la entrada (formato) y orquesta el repositorio.
// Las reglas de negocio fuertes (stock, cliente activo, atomicidad)
// las garantiza la base de datos; aquí solo se filtra lo evidente
// para responder rápido con un mensaje claro.
const repo = require('../repositories/datamarket.repository');

class ErrorApi extends Error {
  constructor(status, mensaje) {
    super(mensaje);
    this.status = status;
  }
}

function idValido(valor, nombre) {
  const n = Number(valor);
  if (!Number.isInteger(n) || n <= 0) {
    throw new ErrorApi(400, `${nombre} debe ser un número entero positivo`);
  }
  return n;
}

function idOpcional(valor, nombre) {
  return valor === undefined ? null : idValido(valor, nombre);
}

async function listarProductos(categoria) {
  return repo.listarProductos(idOpcional(categoria, 'categoria'));
}

async function obtenerProducto(id) {
  const producto = await repo.obtenerProducto(idValido(id, 'id'));
  if (!producto) throw new ErrorApi(404, `El producto ${id} no existe`);
  return producto;
}

async function inventarioBajo() {
  return repo.inventarioBajo();
}

async function inventarioDeProducto(productoId) {
  const inv = await repo.inventarioDeProducto(idValido(productoId, 'productoId'));
  if (!inv) throw new ErrorApi(404, `El producto ${productoId} no tiene inventario`);
  return inv;
}

async function crearPedido(body) {
  const { cliente_id, items, metodo_pago } = body || {};
  const clienteId = idValido(cliente_id, 'cliente_id');

  if (!Array.isArray(items) || items.length === 0) {
    throw new ErrorApi(400, 'items debe ser una lista con al menos un producto');
  }
  const itemsLimpios = items.map((it, i) => ({
    producto_id: idValido(it?.producto_id, `items[${i}].producto_id`),
    cantidad: idValido(it?.cantidad, `items[${i}].cantidad`),
  }));

  if (typeof metodo_pago !== 'string') {
    throw new ErrorApi(400, 'metodo_pago es obligatorio (TARJETA, PSE, EFECTIVO o TRANSFERENCIA)');
  }

  const pedidoId = await repo.crearPedido(clienteId, itemsLimpios, metodo_pago.toUpperCase());
  return repo.obtenerPedido(pedidoId);
}

async function listarPedidos(clienteId) {
  return repo.listarPedidos(idOpcional(clienteId, 'cliente_id'));
}

async function obtenerPedido(id) {
  const pedido = await repo.obtenerPedido(idValido(id, 'id'));
  if (!pedido) throw new ErrorApi(404, `El pedido ${id} no existe`);
  return pedido;
}

module.exports = {
  ErrorApi,
  listarProductos,
  obtenerProducto,
  inventarioBajo,
  inventarioDeProducto,
  crearPedido,
  listarPedidos,
  obtenerPedido,
};
