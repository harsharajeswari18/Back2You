import mysql from 'mysql2/promise';

const g = globalThis;
export const pool =
  g.__b2yPool ??
  mysql.createPool({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    waitForConnections: true,
    connectionLimit: 10,
    dateStrings: true,
  });
if (process.env.NODE_ENV !== 'production') g.__b2yPool = pool;

// Runs fn on ONE connection with @app_user_id set, so the audit triggers
// record who made the change. OUT params also need a single connection.
export async function withUser(userId, fn) {
  const conn = await pool.getConnection();
  try {
    await conn.query('SET @app_user_id = ?', [userId]);
    return await fn(conn);
  } finally {
    conn.release();
  }
}
