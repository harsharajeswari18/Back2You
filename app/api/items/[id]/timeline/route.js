import { pool } from '@/lib/db';
import { requireRole } from '@/lib/auth';
import { route, ok } from '@/lib/http';

export const GET = route(async (req, { params }) => {
  await requireRole(req);
  const [rows] = await pool.execute(
    'SELECT moved_at, from_person, to_person, note FROM v_item_timeline WHERE item_id = ? ORDER BY moved_at',
    [Number(params.id)]);
  return ok(rows);
});
