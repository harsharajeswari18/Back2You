import { withUser } from '@/lib/db';
import { requireRole } from '@/lib/auth';
import { route, ok } from '@/lib/http';

// Owner confirms they received the item -> status 'returned'
export const POST = route(async (req, { params }) => {
  const s = await requireRole(req, ['user']);
  await withUser(s.userId, (conn) =>
    conn.query('CALL confirm_return(?,?)', [Number(params.id), s.userId]));
  return ok({ status: 'returned' });
});
