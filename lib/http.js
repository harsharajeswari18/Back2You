import { NextResponse } from 'next/server';

export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export const ok = (data, status = 200) => NextResponse.json(data, { status });

// Turns database errors (triggers, CHECKs, FKs) into clean API errors.
export function errorResponse(e) {
  if (e instanceof HttpError) return ok({ error: e.message }, e.status);
  if (e?.errno === 1644) return ok({ error: e.sqlMessage }, 400);            // SIGNAL from trigger/procedure
  if (e?.errno === 3819) return ok({ error: 'Validation failed: ' + e.sqlMessage }, 400); // CHECK
  if (e?.errno === 1062) return ok({ error: 'Duplicate record' }, 409);      // UNIQUE
  if (e?.errno === 1452) return ok({ error: 'Referenced record does not exist' }, 400); // FK
  console.error(e);
  return ok({ error: 'Internal server error' }, 500);
}

export const route = (handler) => async (req, ctx) => {
  try {
    return await handler(req, ctx);
  } catch (e) {
    return errorResponse(e);
  }
};
