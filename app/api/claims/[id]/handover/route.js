import { withUser } from '@/lib/db';
import { requireRole } from '@/lib/auth';
import { route, ok } from '@/lib/http';

export const POST = route(async (req, { params }) => {
  const s = await requireRole(req, ['staff', 'admin']);
  const { proof_type, proof_ref } = await req.json();
  await withUser(s.userId, (conn) =>
    conn.query('CALL perform_handover(?,?,?,?)',
      [Number(params.id), s.userId, proof_type, proof_ref]));
  return ok({ status: 'handed_over' });
});
