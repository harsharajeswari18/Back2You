import { SignJWT, jwtVerify } from 'jose';
import { HttpError } from '@/lib/http';

const secret = () => new TextEncoder().encode(process.env.JWT_SECRET);

export async function signToken(user) {
  return new SignJWT({ role: user.role, name: user.full_name })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(String(user.user_id))
    .setExpirationTime('8h')
    .sign(secret());
}

export async function getSession(req) {
  const bearer = req.headers.get('authorization')?.replace(/^Bearer /i, '');
  const token = req.cookies.get('token')?.value || bearer;
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, secret());
    return { userId: Number(payload.sub), role: payload.role, name: payload.name };
  } catch {
    return null;
  }
}

// Role check happens on the backend, not just in the UI.
export async function requireRole(req, roles) {
  const s = await getSession(req);
  if (!s) throw new HttpError(401, 'Login required');
  if (roles && !roles.includes(s.role)) throw new HttpError(403, 'Not allowed for your role');
  return s;
}
