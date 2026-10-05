// Capa de conexión: un pool de conexiones a PostgreSQL.
// Las credenciales vienen del archivo .env (usuario usr_api).
require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT || 5432),
  database: process.env.DB_NAME || 'datamarket',
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max: 10,
});

// Cada conexión trabaja en el esquema datamarket
pool.on('connect', (client) => client.query('SET search_path TO datamarket'));

module.exports = pool;
