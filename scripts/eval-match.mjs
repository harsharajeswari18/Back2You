// Match-quality evaluation on the seeded lost/found pairs (claims 1..150 -> items 1..150).
//   vector-only : cosine similarity of the claim text only
//   hybrid      : cosine + category / location / colour / time re-ranking
// The form fields a claimant may fill in are simulated: location is given for 70% of
// claims and colour for 50% (they are optional in real life). Category is always given.
// Run: npm run eval-match
import mysql from 'mysql2/promise';
import { searchSimilar } from '../lib/vector.mjs';
import { rerank, summarize } from '../lib/match.mjs';

const conn = await mysql.createConnection({
  host: process.env.DB_HOST, port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER, password: process.env.DB_PASSWORD, database: process.env.DB_NAME,
});
const [claims] = await conn.query(
  `SELECT c.claim_id, c.item_id AS truth, c.description, c.lost_location_id,
          UNIX_TIMESTAMP(c.lost_at) AS lost_ts, i.category_id, i.color
     FROM claims c JOIN items i ON i.item_id = c.item_id
    WHERE c.claim_id <= 150 ORDER BY c.claim_id`);
const [items] = await conn.query(
  `SELECT item_id, category_id, location_id, color, UNIX_TIMESTAMP(found_at) AS found_ts FROM items`);
const byId = new Map(items.map((i) => [i.item_id, { ...i, found_ts: Number(i.found_ts) }]));

const rank = (list, truth) => {
  const i = list.findIndex((x) => x.item_id === truth);
  return i < 0 ? Infinity : i + 1;
};
const ranksV = [], ranksH = [];
for (const c of claims) {
  const hits = await searchSimilar(c.description, { limit: 50 });
  const cands = hits.map((h) => ({ ...byId.get(h.payload.item_id), vector_score: h.score }));
  ranksV.push(rank(rerank(cands, {}, 'vector'), c.truth));
  const q = {
    category_id: c.category_id,
    location_id: c.claim_id % 10 < 7 ? c.lost_location_id : null,
    color: c.claim_id % 2 === 0 ? c.color : null,
    lost_ts: Number(c.lost_ts),
  };
  ranksH.push(rank(rerank(cands, q, 'hybrid'), c.truth));
}
const f = (x) => (x * 100).toFixed(1) + '%';
const V = summarize(ranksV, claims.length), H = summarize(ranksH, claims.length);
console.log(`Evaluated ${claims.length} lost/found pairs (embedder: ${process.env.EMBEDDER || 'all-MiniLM-L6-v2'})`);
console.table({
  'vector-only': { 'top-1': f(V.top1), 'top-3': f(V.top3), 'top-5': f(V.top5), MRR: V.mrr.toFixed(3) },
  hybrid:        { 'top-1': f(H.top1), 'top-3': f(H.top3), 'top-5': f(H.top5), MRR: H.mrr.toFixed(3) },
});
await conn.end();
