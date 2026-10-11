import { pool } from '@/lib/db';
import { requireRole } from '@/lib/auth';
import { route, ok, HttpError } from '@/lib/http';
import { searchSimilar } from '@/lib/vector.mjs';
import { rerank } from '@/lib/match.mjs';

// POST /api/match  { description, category_id?, location_id?, color?, lost_at?, mode?, limit? }
// 1) embed the description, 2) Qdrant cosine top-50, 3) keep items still open in MySQL,
// 4) re-rank with category / location / colour / time signals.
export const POST = route(async (req) => {
  await requireRole(req);
  const b = await req.json();
  if (!b.description || b.description.trim().length < 10)
    throw new HttpError(400, 'Describe the lost item in at least 10 characters');
  const mode = b.mode === 'vector' ? 'vector' : 'hybrid';
  const limit = Math.min(Number(b.limit || 5), 20);

  const hits = await searchSimilar(b.description, { limit: 50 });
  const ids = hits.map((h) => h.payload.item_id);
  if (!ids.length) return ok([]);

  const [rows] = await pool.query(
    `SELECT i.item_id, i.title, i.description, i.status, i.color, i.found_at,
            i.category_id, i.location_id, UNIX_TIMESTAMP(i.found_at) AS found_ts,
            c.name AS category, l.name AS location
       FROM items i
       JOIN categories c ON c.category_id = i.category_id
       JOIN locations  l ON l.location_id = i.location_id
      WHERE i.item_id IN (?) AND i.status IN ('registered','claimed')`,
    [ids]);

  const cosine = new Map(hits.map((h) => [h.payload.item_id, h.score]));
  let lostTs = null;
  if (b.lost_at) {
    const [[r]] = await pool.query('SELECT UNIX_TIMESTAMP(?) AS ts', [b.lost_at]);
    lostTs = r.ts == null ? null : Number(r.ts);
  }
  const ranked = rerank(
    rows.map((r) => ({ ...r, found_ts: Number(r.found_ts), vector_score: cosine.get(r.item_id) })),
    {
      category_id: b.category_id ? Number(b.category_id) : null,
      location_id: b.location_id ? Number(b.location_id) : null,
      color: b.color || null,
      lost_ts: lostTs,
    },
    mode,
  ).slice(0, limit);

  return ok(ranked.map((r) => ({
    item_id: r.item_id, title: r.title, description: r.description, category: r.category,
    location: r.location, found_at: r.found_at, status: r.status,
    score: Number(r.score.toFixed(4)), breakdown: r.breakdown,
  })));
});
