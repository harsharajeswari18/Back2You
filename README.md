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

## Vector matching (Qdrant)
- **What is embedded:** item title + description + category name.
- **Model:** `all-MiniLM-L6-v2` (384 dimensions) via Transformers.js, run inside Node (downloads ~25 MB on first use).
- **Storage:** Qdrant collection `found_items`, cosine distance, point id = MySQL `item_id`,
  payload = category_id, location_id, color, found_ts. Item status stays in MySQL only.
- **Retrieval:** embed the claimant's description -> Qdrant top-50 by cosine -> keep items that are
  still open in MySQL -> re-rank: 0.65 cosine + 0.12 category + 0.10 location + 0.08 colour + 0.05 time.

### Run it
1. Start Qdrant: `docker compose up -d qdrant`  (or use a free Qdrant Cloud cluster: set `QDRANT_URL` and `QDRANT_API_KEY` in `.env`)
2. `npm install`
3. `npm run index-items`   (embeds all items into Qdrant; re-run any time)
4. `npm run eval-match`    (top-1 / top-3 / top-5 / MRR, vector-only vs hybrid)
5. `POST /api/match` with `{"description": "...", "category_id": 2, "color": "blue", "lost_at": "2026-10-10 08:00:00"}`
