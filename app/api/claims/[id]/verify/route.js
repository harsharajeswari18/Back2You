import { withUser } from '@/lib/db';
import { requireRole } from '@/lib/auth';
import { route, ok } from '@/lib/http';

export const POST = route(async (req, { params }) => {
  const s = await requireRole(req, ['staff', 'admin']);
  const { method, notes, result } = await req.json();
  await withUser(s.userId, (conn) =>
    conn.query('CALL verify_claim(?,?,?,?,?)',
      [Number(params.id), s.userId, method, notes || null, result]));
  return ok({ claim_id: Number(params.id), result });
});
