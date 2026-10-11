import bcrypt from 'bcryptjs';
import { NextResponse } from 'next/server';
import { pool } from '@/lib/db';
import { signToken } from '@/lib/auth';
import { route, HttpError } from '@/lib/http';

export const POST = route(async (req) => {
  const { email, password } = await req.json();
  if (!email || !password) throw new HttpError(400, 'Email and password required');
  const [rows] = await pool.execute(
    'SELECT user_id, full_name, role, password_hash FROM users WHERE email = ?', [email]);
  const u = rows[0];
  if (!u || !(await bcrypt.compare(password, u.password_hash)))
    throw new HttpError(401, 'Invalid email or password');
  const token = await signToken(u);
  const res = NextResponse.json({ user_id: u.user_id, name: u.full_name, role: u.role });
  res.cookies.set('token', token, { httpOnly: true, sameSite: 'lax', path: '/', maxAge: 8 * 3600 });
  return res;
});
