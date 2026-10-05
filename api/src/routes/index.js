// RUTAS (capa REST): reciben la petición HTTP, llaman al servicio
// y devuelven JSON. No contienen SQL ni reglas de negocio.
const { Router } = require('express');
const servicio = require('../services/datamarket.service');

const router = Router();

// Envuelve los handlers async para enviar los errores al middleware
const h = (fn) => (req, res, next) => fn(req, res).catch(next);

// ---------- Productos ----------
router.get('/productos', h(async (req, res) => {
  res.json(await servicio.listarProductos(req.query.categoria));
}));

router.get('/productos/:id', h(async (req, res) => {
  res.json(await servicio.obtenerProducto(req.params.id));
}));

// ---------- Inventario ----------
router.get('/inventario/bajo', h(async (req, res) => {
  res.json(await servicio.inventarioBajo());
}));

router.get('/inventario/:productoId', h(async (req, res) => {
  res.json(await servicio.inventarioDeProducto(req.params.productoId));
}));

// ---------- Pedidos ----------
router.post('/pedidos', h(async (req, res) => {
  res.status(201).json(await servicio.crearPedido(req.body));
}));

router.get('/pedidos', h(async (req, res) => {
  res.json(await servicio.listarPedidos(req.query.cliente_id));
}));

router.get('/pedidos/:id', h(async (req, res) => {
  res.json(await servicio.obtenerPedido(req.params.id));
}));

module.exports = router;
