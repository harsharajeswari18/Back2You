// Embeds every item in MySQL and upserts it into Qdrant. Safe to re-run.
// Run: npm run index-items
import mysql from 'mysql2/promise';
import { indexItems } from '../lib/vector.mjs';

const conn = await mysql.createConnection({
  host: process.env.DB_HOST, port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER, password: process.env.DB_PASSWORD, database: process.env.DB_NAME,
});
const [items] = await conn.query(
  `SELECT i.item_id, i.title, i.description, i.color, i.category_id, i.location_id,
          UNIX_TIMESTAMP(i.found_at) AS found_ts, c.name AS category
     FROM items i JOIN categories c ON c.category_id = i.category_id`);
console.log(`Embedding ${items.length} items (first run downloads the model)...`);
const t0 = Date.now();
await indexItems(items);
await conn.query('UPDATE items SET vector_id = CAST(item_id AS CHAR)');
console.log(`Indexed ${items.length} items in ${((Date.now() - t0) / 1000).toFixed(1)}s`);
await conn.end();
