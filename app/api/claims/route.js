import { pool, withUser } from '@/lib/db';
import { requireRole } from '@/lib/auth';
import { route, ok } from '@/lib/http';

// Users see their own claims; staff/admin see all pending claims.
export const GET = route(async (req) => {
  const s = await requireRole(req);
  const staff = ['staff', 'admin'].includes(s.role);
  const [rows] = await pool.query(
    `SELECT c.claim_id, c.item_id, i.title, c.description, c.status, c.created_at
       FROM claims c JOIN items i ON i.item_id = c.item_id
      WHERE ${staff ? "c.status = 'pending'" : 'c.claimant_id = ?'}
      ORDER BY c.created_at DESC LIMIT 200`,
    staff ? [] : [s.userId]);
  return ok(rows);
});

export const POST = route(async (req) => {
  const s = await requireRole(req, ['user']);
  const b = await req.json();
  const id = await withUser(s.userId, async (conn) => {
    await conn.query('CALL submit_claim(?,?,?,?,?,@claim)', [
      b.item_id, s.userId, b.description, b.lost_at, b.lost_location_id || null]);
    const [[row]] = await conn.query('SELECT @claim AS id');
    return row.id;
  });
  return ok({ claim_id: id }, 201);
});
