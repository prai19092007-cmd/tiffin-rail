const mysql = require('mysql2');
require('dotenv').config();

// Connection settings come either from a single DATABASE_URL
// (mysql://user:password@host:3306/dbname — used by hosted MySQL providers)
// or from the individual DB_* fields in .env (local MySQL).
function buildConfig() {
  let cfg;
  if (process.env.DATABASE_URL) {
    const u = new URL(process.env.DATABASE_URL);
    cfg = {
      host: u.hostname,
      port: Number(u.port) || 3306,
      user: decodeURIComponent(u.username),
      password: decodeURIComponent(u.password),
      database: u.pathname.replace(/^\//, '')
    };
  } else {
    cfg = {
      host: process.env.DB_HOST || 'localhost',
      port: Number(process.env.DB_PORT) || 3306,
      user: process.env.DB_USER || 'root',
      password: process.env.DB_PASSWORD || '',
      database: process.env.DB_NAME || 'tiffin_rail'
    };
  }

  // Most hosted MySQL services require an encrypted connection.
  if (process.env.DB_SSL === 'true') {
    cfg.ssl = { rejectUnauthorized: false };
  }

  return {
    ...cfg,
    charset: 'utf8mb4',
    waitForConnections: true,
    connectionLimit: 10
  };
}

// Connection pool: re-uses a small set of open connections instead of
// opening a new one for every query. Use as:  const [rows] = await pool.query(sql, params)
const pool = mysql.createPool(buildConfig()).promise();

module.exports = pool;
