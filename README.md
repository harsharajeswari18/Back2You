# Back2You - Lost Item Return & Ownership Management

Next.js + MySQL 8 + Qdrant. The item lifecycle (registered -> claimed -> verified
-> handed_over -> returned) is enforced INSIDE MySQL by triggers and stored procedures.

## Setup
1. `cp .env.example .env` and set DB_PASSWORD / JWT_SECRET
2. `docker compose up -d`   (MySQL with schema, procedures and seed data; Qdrant)
   - or load `database/01_schema.sql`, `02_procedures.sql`, `03_seed.sql` into your own MySQL
3. `npm install`
4. `npm run set-passwords`   (demo password `Password123` for all seeded users)
5. `npm run dev` -> http://localhost:3000

Demo logins: admin `user1@back2you.test`, staff `user3@back2you.test`, user `user11@back2you.test`.

## API (all JSON, JWT cookie auth)
| Method | Path | Role |
|---|---|---|
| POST | /api/auth/login, /register, /logout | public |
| GET / POST | /api/items | any / any |
| GET | /api/items/:id/timeline | any |
| POST | /api/items/:id/return | user |
| GET / POST | /api/claims | any / user |
| POST | /api/claims/:id/verify | staff, admin |
| POST | /api/claims/:id/handover | staff, admin |
| GET | /api/admin/dashboard | admin |

`database/queries_and_tests.sql` holds the report queries, demos and negative tests.
