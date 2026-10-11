// Gives every seeded user the password "Password123" (demo only).
// Run: npm run set-passwords
import bcrypt from 'bcryptjs';
import mysql from 'mysql2/promise';

const conn = await mysql.createConnection({
  host: process.env.DB_HOST, port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER, password: process.env.DB_PASSWORD, database: process.env.DB_NAME,
});
const hash = await bcrypt.hash('Password123', 10);
const [r] = await conn.query('UPDATE users SET password_hash = ?', [hash]);
console.log(`Updated ${r.affectedRows} users.`);
console.log('Demo logins (password Password123):');
console.log('  admin  user1@back2you.test');
console.log('  staff  user3@back2you.test');
console.log('  user   user11@back2you.test');
await conn.end();
