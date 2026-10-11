import bcrypt from 'bcryptjs';
import { pool } from '@/lib/db';
import { route, ok, HttpError } from '@/lib/http';

// Self-registration always creates a normal 'user'. Staff/admin are created by an admin.
export const POST = route(async (req) => {
  const { full_name, email, phone, password } = await req.json();
  if (!full_name || !email || !password || password.length < 8)
    throw new HttpError(400, 'Name, email and a password of 8+ characters are required');
  const hash = await bcrypt.hash(password, 10);
  const [r] = await pool.execute(
    "INSERT INTO users (full_name, email, phone, password_hash, role) VALUES (?,?,?,?, 'user')",
    [full_name, email, phone || null, hash]);   // CHECK constraints validate email/phone
  return ok({ user_id: r.insertId }, 201);
});
