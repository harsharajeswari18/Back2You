import { pool } from '@/lib/db';
import { requireRole } from '@/lib/auth';
import { route, ok } from '@/lib/http';

export const GET = route(async (req) => {
  await requireRole(req, ['admin']);
  const [byLocation] = await pool.query('SELECT * FROM v_admin_dashboard');
  const [byStatus]   = await pool.query('SELECT status, COUNT(*) AS items FROM items GROUP BY status');
  const [recent]     = await pool.query(
    `SELECT a.audit_id, a.record_id, a.action, a.new_value, u.full_name AS changed_by, a.changed_at
       FROM audit_log a LEFT JOIN users u ON u.user_id = a.changed_by
      ORDER BY a.audit_id DESC LIMIT 15`);
  return ok({ byLocation, byStatus, recent });
});
