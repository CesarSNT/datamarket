// Punto de entrada de la API.
// Arquitectura: CLIENTE -> API REST (routes) -> SERVICIO -> REPOSITORIO -> POSTGRESQL
require('dotenv').config();
const express = require('express');
const pool = require('./db');
const rutas = require('./routes');
const { ErrorApi } = require('./services/datamarket.service');

const app = express();
app.use(express.json());

// Salud: confirma la conexión y con qué usuario se conecta la API
app.get('/health', async (req, res, next) => {
  try {
    const { rows } = await pool.query(
      'SELECT current_user AS usuario_bd, current_database() AS base, now() AS hora'
    );
    res.json({ estado: 'ok', ...rows[0] });
  } catch (err) {
    next(err);
  }
});

app.use('/api', rutas);

app.use((req, res) => res.status(404).json({ error: 'Ruta no encontrada' }));

// Traduce los errores de PostgreSQL a códigos HTTP
const ERRORES_PG = {
  '22023': 400, // invalid_parameter_value  (validaciones del procedimiento)
  '22P02': 400, // invalid_text_representation
  '23503': 404, // foreign_key_violation    (cliente o producto inexistente)
  '23514': 409, // check_violation          (stock insuficiente, producto inactivo)
  'P0002': 404, // no_data_found
  '42501': 403, // insufficient_privilege   (permiso denegado)
};

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  if (err instanceof ErrorApi) {
    return res.status(err.status).json({ error: err.message });
  }
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'El cuerpo de la petición no es un JSON válido' });
  }
  const status = ERRORES_PG[err.code];
  if (status) {
    return res.status(status).json({ error: err.message, codigo_pg: err.code });
  }
  console.error(err);
  res.status(500).json({ error: 'Error interno del servidor' });
});

const PORT = Number(process.env.PORT || 3000);
app.listen(PORT, () => {
  console.log(`DataMarket API escuchando en http://localhost:${PORT}`);
  console.log(`Usuario de base de datos: ${process.env.DB_USER}`);
});
