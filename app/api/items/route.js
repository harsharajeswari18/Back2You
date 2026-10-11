import { pool, withUser } from '@/lib/db';
import { requireRole } from '@/lib/auth';
import { route, ok, HttpError } from '@/lib/http';

// GET /api/items?q=black wallet&status=registered&category_id=2&location_id=8
export const GET = route(async (req) => {
  await requireRole(req);
  const p = new URL(req.url).searchParams;
  const where = [];
  const args = [];
  if (p.get('q'))           { where.push('MATCH(i.title, i.description) AGAINST(? IN NATURAL LANGUAGE MODE)'); args.push(p.get('q')); }
  if (p.get('status'))      { where.push('i.status = ?');      args.push(p.get('status')); }
  if (p.get('category_id')) { where.push('i.category_id = ?'); args.push(Number(p.get('category_id'))); }
  if (p.get('location_id')) { where.push('i.location_id = ?'); args.push(Number(p.get('location_id'))); }
  const limit = Math.min(Number(p.get('limit') || 50), 200);
  const [rows] = await pool.query(
    `SELECT i.item_id, i.title, i.color, i.status, i.found_at,
            c.name AS category, l.name AS location
       FROM items i
       JOIN categories c ON c.category_id = i.category_id
       JOIN locations  l ON l.location_id = i.location_id
      ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
      ORDER BY i.found_at DESC LIMIT ?`,
    [...args, limit]);
  return ok(rows);
});

// POST: register a found item (stored procedure register_item)
export const POST = route(async (req) => {
  const s = await requireRole(req);
  const b = await req.json();
  const custodian = ['staff', 'admin'].includes(s.role) ? s.userId : Number(b.custodian_id);
  if (!custodian) throw new HttpError(400, 'custodian_id (a staff member holding the item) is required');
  const id = await withUser(s.userId, async (conn) => {
    await conn.query('CALL register_item(?,?,?,?,?,?,?,?,@item)', [
      s.userId, custodian, b.category_id, b.location_id,
      b.title, b.description, b.color || null, b.found_at]);
    const [[row]] = await conn.query('SELECT @item AS id');
    return row.id;
  });
  return ok({ item_id: id }, 201);
});
